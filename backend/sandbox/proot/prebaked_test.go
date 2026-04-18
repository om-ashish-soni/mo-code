package proot

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestExtractPrebaked_Fixture builds a tiny in-memory tar.gz that mimics the
// shape of the real prebaked Alpine tarball — a couple of directories, an
// executable "python3" script, a "git" stand-in, a symlink, and a regular
// config file — then extracts it and verifies the expected tree lands on
// disk with the right permissions.
//
// Keeping the fixture inline (rather than on disk) makes the test hermetic:
// it's both the unit test for ExtractPrebaked and a machine-readable spec
// for what a prebaked tarball must contain at minimum.
func TestExtractPrebaked_Fixture(t *testing.T) {
	tarball := buildFixtureTarball(t)

	dir := t.TempDir()
	tarballPath := filepath.Join(dir, "fixture.tar.gz")
	if err := os.WriteFile(tarballPath, tarball, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	destDir := filepath.Join(dir, "rootfs")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := ExtractPrebaked(ctx, tarballPath, destDir); err != nil {
		t.Fatalf("ExtractPrebaked: %v", err)
	}

	// Acceptance check #2 from the task brief: prebaked rootfs must contain
	// git and python3. The fixture simulates both at their canonical paths.
	mustExist(t, filepath.Join(destDir, "usr/bin/python3"))
	mustExist(t, filepath.Join(destDir, "usr/bin/git"))
	mustExist(t, filepath.Join(destDir, "etc/os-release"))

	// Regular file content round-trips.
	body, err := os.ReadFile(filepath.Join(destDir, "etc/os-release"))
	if err != nil {
		t.Fatalf("read os-release: %v", err)
	}
	if string(body) != "NAME=\"Alpine Linux\"\n" {
		t.Errorf("unexpected os-release content: %q", body)
	}

	// Executable bit survives extraction.
	info, err := os.Stat(filepath.Join(destDir, "usr/bin/python3"))
	if err != nil {
		t.Fatalf("stat python3: %v", err)
	}
	if info.Mode()&0o111 == 0 {
		t.Errorf("python3 is not executable: mode=%v", info.Mode())
	}

	// Symlink resolves to its intended target.
	linkTarget, err := os.Readlink(filepath.Join(destDir, "bin/sh"))
	if err != nil {
		t.Fatalf("readlink bin/sh: %v", err)
	}
	if linkTarget != "/bin/busybox" {
		t.Errorf("bin/sh symlink target = %q, want /bin/busybox", linkTarget)
	}
}

func TestExtractPrebaked_ZipSlip(t *testing.T) {
	// A malicious entry trying to escape destDir must not land outside.
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	writeTarFile(t, tw, "../escape.txt", []byte("pwned"), 0o644)
	if err := tw.Close(); err != nil {
		t.Fatalf("tw close: %v", err)
	}
	if err := gz.Close(); err != nil {
		t.Fatalf("gz close: %v", err)
	}

	dir := t.TempDir()
	tarballPath := filepath.Join(dir, "evil.tar.gz")
	if err := os.WriteFile(tarballPath, buf.Bytes(), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	destDir := filepath.Join(dir, "rootfs")

	if err := ExtractPrebaked(context.Background(), tarballPath, destDir); err != nil {
		t.Fatalf("ExtractPrebaked: %v", err)
	}

	if _, err := os.Stat(filepath.Join(dir, "escape.txt")); !os.IsNotExist(err) {
		t.Errorf("zip-slip succeeded: escape.txt was written to %s", dir)
	}
}

func TestExtractPrebaked_MissingTarball(t *testing.T) {
	err := ExtractPrebaked(context.Background(), "/nonexistent/path.tar.gz", t.TempDir())
	if err == nil {
		t.Fatal("expected error for missing tarball, got nil")
	}
}

// --- helpers ---

func buildFixtureTarball(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)

	writeTarDir(t, tw, "usr/")
	writeTarDir(t, tw, "usr/bin/")
	writeTarDir(t, tw, "bin/")
	writeTarDir(t, tw, "etc/")

	writeTarFile(t, tw, "usr/bin/python3", []byte("#!/bin/sh\necho python\n"), 0o755)
	writeTarFile(t, tw, "usr/bin/git", []byte("#!/bin/sh\necho git\n"), 0o755)
	writeTarFile(t, tw, "etc/os-release", []byte("NAME=\"Alpine Linux\"\n"), 0o644)
	writeTarSymlink(t, tw, "bin/sh", "/bin/busybox")

	if err := tw.Close(); err != nil {
		t.Fatalf("tw close: %v", err)
	}
	if err := gz.Close(); err != nil {
		t.Fatalf("gz close: %v", err)
	}
	return buf.Bytes()
}

func writeTarDir(t *testing.T, tw *tar.Writer, name string) {
	t.Helper()
	if err := tw.WriteHeader(&tar.Header{
		Name:     name,
		Mode:     0o755,
		Typeflag: tar.TypeDir,
	}); err != nil {
		t.Fatalf("write dir header %s: %v", name, err)
	}
}

func writeTarFile(t *testing.T, tw *tar.Writer, name string, data []byte, mode int64) {
	t.Helper()
	if err := tw.WriteHeader(&tar.Header{
		Name:     name,
		Mode:     mode,
		Size:     int64(len(data)),
		Typeflag: tar.TypeReg,
	}); err != nil {
		t.Fatalf("write file header %s: %v", name, err)
	}
	if _, err := tw.Write(data); err != nil {
		t.Fatalf("write file body %s: %v", name, err)
	}
}

func writeTarSymlink(t *testing.T, tw *tar.Writer, name, target string) {
	t.Helper()
	if err := tw.WriteHeader(&tar.Header{
		Name:     name,
		Linkname: target,
		Mode:     0o777,
		Typeflag: tar.TypeSymlink,
	}); err != nil {
		t.Fatalf("write symlink header %s: %v", name, err)
	}
}

func mustExist(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Errorf("expected %s to exist: %v", path, err)
	}
}
