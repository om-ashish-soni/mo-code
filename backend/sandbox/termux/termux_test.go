package termux

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"mo-code/backend/sandbox"
)

// newFixturePrefix builds a minimal prefix tarball and returns the path to
// the tarball plus a prepared Backend pointing at a fresh prefix directory.
// The fixture uses /bin/sh (or /bin/bash) from the host so tests can run on
// any Linux/macOS CI machine without a real Termux bootstrap — the backend
// does not care whether the shell is bionic or glibc, only that it lives at
// $prefix/bin/sh with execute permission.
func newFixturePrefix(t *testing.T) (tarballPath string, b *Backend, cleanup func()) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("termux backend is Linux/Android only")
	}

	hostShell := findHostShell(t)

	tmp := t.TempDir()
	tarballPath = filepath.Join(tmp, "termux-prefix.tar.gz")
	writeFixtureTarball(t, tarballPath, hostShell)

	prefixDir := filepath.Join(tmp, "prefix")
	projectsDir := filepath.Join(tmp, "projects")
	if err := os.MkdirAll(projectsDir, 0o755); err != nil {
		t.Fatalf("mkdir projects: %v", err)
	}

	sb, err := Factory(context.Background(), sandbox.Config{
		Options: map[string]string{
			optPrefix:   prefixDir,
			optTarball:  tarballPath,
			optProjects: projectsDir,
			optVersion:  "test-1",
		},
	})
	if err != nil {
		t.Fatalf("Factory: %v", err)
	}
	return tarballPath, sb.(*Backend), func() { _ = os.RemoveAll(tmp) }
}

// findHostShell picks a shell to stand in for the bundled Termux shell.
// Prefer /bin/sh since every POSIX system has it.
func findHostShell(t *testing.T) string {
	t.Helper()
	for _, cand := range []string{"/bin/sh", "/bin/bash", "/usr/bin/sh"} {
		if info, err := os.Stat(cand); err == nil && !info.IsDir() {
			return cand
		}
	}
	t.Skip("no /bin/sh on this host")
	return ""
}

// writeFixtureTarball produces a tarball whose layout matches what Prepare
// expects: bin/sh, bin/node (stub), lib/, tmp/, etc/. The shell entry is a
// symlink to the host shell so commands actually run.
func writeFixtureTarball(t *testing.T, path string, hostShell string) {
	t.Helper()

	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)

	writeDir := func(name string) {
		if err := tw.WriteHeader(&tar.Header{
			Name: name, Typeflag: tar.TypeDir, Mode: 0o755,
		}); err != nil {
			t.Fatalf("tar dir %s: %v", name, err)
		}
	}
	writeSymlink := func(name, target string) {
		if err := tw.WriteHeader(&tar.Header{
			Name: name, Typeflag: tar.TypeSymlink, Linkname: target, Mode: 0o777,
		}); err != nil {
			t.Fatalf("tar symlink %s: %v", name, err)
		}
	}
	writeFile := func(name string, content []byte, mode int64) {
		if err := tw.WriteHeader(&tar.Header{
			Name: name, Typeflag: tar.TypeReg, Mode: mode, Size: int64(len(content)),
		}); err != nil {
			t.Fatalf("tar header %s: %v", name, err)
		}
		if _, err := tw.Write(content); err != nil {
			t.Fatalf("tar body %s: %v", name, err)
		}
	}

	writeDir("bin/")
	writeDir("lib/")
	writeDir("usr/")
	writeDir("usr/bin/")
	writeDir("usr/lib/")
	writeDir("tmp/")
	writeDir("etc/")
	writeSymlink("bin/sh", hostShell)

	// Stub "node" binary — used by the InstallPackage prebaked-mode test.
	// Needs to be executable so hasBinary returns true.
	nodeScript := fmt.Sprintf("#!%s\necho v0.0.0-fixture\n", hostShell)
	writeFile("bin/node", []byte(nodeScript), 0o755)

	if err := tw.Close(); err != nil {
		t.Fatalf("tar close: %v", err)
	}
	if err := gz.Close(); err != nil {
		t.Fatalf("gz close: %v", err)
	}
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatalf("write tarball: %v", err)
	}
}

// TestFactoryMissingPrefix verifies the Factory rejects configs that omit the
// required prefix option.
func TestFactoryMissingPrefix(t *testing.T) {
	_, err := Factory(context.Background(), sandbox.Config{Options: map[string]string{}})
	if err == nil {
		t.Fatal("expected error for missing termux.prefix option")
	}
}

// TestCapabilities pins the values the track contract promises. If any of
// these drift, the registry fallback logic downstream will misbehave.
func TestCapabilities(t *testing.T) {
	b := &Backend{layout: prefixLayout{Root: "/tmp/x"}}
	c := b.Capabilities()
	if c.FullPOSIX {
		t.Error("FullPOSIX should be false — bionic, not glibc")
	}
	if !c.Network {
		t.Error("Network should be true")
	}
	if c.RootLikeSudo {
		t.Error("RootLikeSudo should be false — unrooted Android")
	}
	if c.SpeedFactor != 1.0 {
		t.Errorf("SpeedFactor want 1.0, got %v", c.SpeedFactor)
	}
	if c.IsolationTier != 1 {
		t.Errorf("IsolationTier want 1, got %d", c.IsolationTier)
	}
	if !c.PackageManager {
		t.Error("PackageManager should be true")
	}
}

// TestRegistered verifies the init() side-effect — the backend is reachable
// through sandbox.Open by its canonical name.
func TestRegistered(t *testing.T) {
	names := sandbox.Names()
	if !slices.Contains(names, backendName) {
		t.Fatalf("termux-prefix not registered; have %v", names)
	}
}

// TestPrepareExtractsAndStamps covers the happy path: Prepare unpacks the
// tarball, writes resolv.conf, links home, and stamps .installed. A second
// Prepare() must be a no-op (same mtime on the stamp).
func TestPrepareExtractsAndStamps(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	if !isExec(b.layout.shellPath()) {
		t.Fatalf("shell not executable at %s", b.layout.shellPath())
	}
	if got := b.layout.installedStamp(); got != "test-1" {
		t.Errorf("stamp want test-1, got %q", got)
	}

	info1, err := os.Stat(b.layout.stampFile())
	if err != nil {
		t.Fatalf("stat stamp: %v", err)
	}

	time.Sleep(10 * time.Millisecond) // give the filesystem a tick
	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare second call: %v", err)
	}
	info2, err := os.Stat(b.layout.stampFile())
	if err != nil {
		t.Fatalf("stat stamp 2: %v", err)
	}
	if !info1.ModTime().Equal(info2.ModTime()) {
		t.Errorf("stamp rewritten on idempotent Prepare: %v → %v", info1.ModTime(), info2.ModTime())
	}
}

// TestPrepareNoTarballNoPrefix confirms Prepare reports a useful error when
// the prefix does not exist and no tarball was configured.
func TestPrepareNoTarballNoPrefix(t *testing.T) {
	tmp := t.TempDir()
	sb, err := Factory(context.Background(), sandbox.Config{
		Options: map[string]string{optPrefix: filepath.Join(tmp, "nope")},
	})
	if err != nil {
		t.Fatalf("Factory: %v", err)
	}
	err = sb.(*Backend).Prepare(context.Background())
	if err == nil {
		t.Fatal("expected error for missing prefix + missing tarball")
	}
	if !strings.Contains(err.Error(), "termux.tarball") {
		t.Errorf("error should mention tarball option; got %v", err)
	}
}

// TestExecEcho is the headline acceptance test. Prepare, then Exec("echo
// ok") must succeed with exit 0 and stdout "ok\n".
func TestExecEcho(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}

	stdout, stderr, code, err := b.Exec(ctx, "echo ok", "")
	if err != nil {
		t.Fatalf("Exec err: %v (stderr=%q)", err, stderr)
	}
	if code != 0 {
		t.Fatalf("Exec exit=%d stderr=%q", code, stderr)
	}
	if strings.TrimSpace(stdout) != "ok" {
		t.Errorf("stdout want %q, got %q", "ok", stdout)
	}
}

// TestExecHonorsEnv verifies PATH and PREFIX point into the prefix — a
// regression test for any future refactor that lets the caller's PATH leak
// into the child. We use `sh -c 'echo $PREFIX'` because checking PATH would
// also match host paths appended at the tail.
func TestExecHonorsEnv(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	stdout, _, code, err := b.Exec(ctx, "echo $PREFIX", "")
	if err != nil || code != 0 {
		t.Fatalf("Exec: err=%v code=%d", err, code)
	}
	if strings.TrimSpace(stdout) != b.layout.Root {
		t.Errorf("PREFIX want %s, got %q", b.layout.Root, stdout)
	}
}

// TestExecNonZeroExit covers the failure path: the command ran but exited
// non-zero. This should not be reported as a Go error.
func TestExecNonZeroExit(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	_, _, code, err := b.Exec(ctx, "exit 42", "")
	if err != nil {
		t.Errorf("non-zero exit should not be a Go error, got %v", err)
	}
	if code != 42 {
		t.Errorf("exit want 42, got %d", code)
	}
}

// TestInstallPackageFromPrefix exercises the prebaked fast path: the fixture
// ships node, so requesting it should return installed=["node"] with no
// error. A missing package should surface ErrNoPackageManager.
func TestInstallPackageFromPrefix(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}

	installed, err := b.InstallPackage(ctx, []string{"node"})
	if err != nil {
		t.Fatalf("InstallPackage(node): %v", err)
	}
	if len(installed) != 1 || installed[0] != "node" {
		t.Errorf("installed want [node], got %v", installed)
	}

	_, err = b.InstallPackage(ctx, []string{"postgresql"})
	if !errors.Is(err, sandbox.ErrNoPackageManager) {
		t.Errorf("want ErrNoPackageManager for missing pkg, got %v", err)
	}
}

// TestIsReady runs the 3-second liveness probe against the fixture.
func TestIsReady(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	if !b.IsReady(ctx) {
		t.Error("IsReady should be true after Prepare")
	}
}

// TestDiagnose after Prepare should yield OK with all structural checks true.
func TestDiagnose(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	d := b.Diagnose(ctx)
	if d.Backend != backendName {
		t.Errorf("Backend want %s, got %s", backendName, d.Backend)
	}
	if !d.OK {
		t.Errorf("Diagnose should be OK after Prepare; checks=%v error=%s", d.Checks, d.Error)
	}
	if d.IsolationTier != 1 {
		t.Errorf("IsolationTier want 1, got %d", d.IsolationTier)
	}
}

// TestExtractTarballZipSlip confirms the extractor rejects tar entries that
// escape the prefix. The guard is critical because the prefix is extracted
// from an APK asset shipped to untrusted devices.
func TestExtractTarballZipSlip(t *testing.T) {
	tmp := t.TempDir()
	tarballPath := filepath.Join(tmp, "evil.tar.gz")

	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	content := []byte("pwned")
	if err := tw.WriteHeader(&tar.Header{
		Name: "../escape.txt", Typeflag: tar.TypeReg, Mode: 0o644, Size: int64(len(content)),
	}); err != nil {
		t.Fatalf("tar header: %v", err)
	}
	_, _ = tw.Write(content)
	_ = tw.Close()
	_ = gz.Close()
	if err := os.WriteFile(tarballPath, buf.Bytes(), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	p := prefixLayout{Root: filepath.Join(tmp, "prefix")}
	if err := p.ensureDirs(); err != nil {
		t.Fatalf("ensureDirs: %v", err)
	}
	err := p.extractTarball(context.Background(), tarballPath)
	if err == nil {
		t.Fatal("expected zip-slip error for ../escape.txt entry")
	}
	if _, err := os.Stat(filepath.Join(tmp, "escape.txt")); err == nil {
		t.Fatal("zip-slip write succeeded — extractor is unsafe")
	}
}

// TestTeardownIsNoOp confirms Teardown does not remove the prefix — the next
// Prepare() must be a cheap no-op.
func TestTeardownIsNoOp(t *testing.T) {
	_, b, cleanup := newFixturePrefix(t)
	defer cleanup()

	ctx := context.Background()
	if err := b.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	if err := b.Teardown(ctx); err != nil {
		t.Fatalf("Teardown: %v", err)
	}
	if _, err := os.Stat(b.layout.stampFile()); err != nil {
		t.Errorf("stamp removed by Teardown: %v", err)
	}
}
