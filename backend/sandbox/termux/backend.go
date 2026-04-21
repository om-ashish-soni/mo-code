// Package termux implements the termux-prefix sandbox backend. See prefix.go
// for the on-disk layout and the docstring below for the runtime model.
package termux

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"mo-code/backend/sandbox"
)

// backendName is the identifier registered with sandbox.Register.
// Lead keeps the fallback chain authoritative in registry.go; tracks must
// not alter it, but "termux-prefix" is the canonical name documented there.
const backendName = "termux-prefix"

// Option keys read from sandbox.Config.Options.
//
//	termux.prefix   absolute path to the extraction target ($appFiles/termux-prefix)
//	termux.tarball  absolute path to the asset tarball to extract (required on first Prepare)
//	termux.projects host path to bind as $prefix/home (optional; falls back to $prefix/home)
//	termux.version  opaque version tag written to .installed (optional)
const (
	optPrefix   = "termux.prefix"
	optTarball  = "termux.tarball"
	optProjects = "termux.projects"
	optVersion  = "termux.version"
)

// Backend runs shell commands against a bionic-linked prefix. It satisfies
// sandbox.Sandbox and is registered via init() at package load.
type Backend struct {
	layout prefixLayout

	// tarballPath is the APK-asset-derived path to the bootstrap tarball.
	// Empty after a successful extraction if the caller cleared the option.
	tarballPath string

	// version is the stamp written on successful extraction (.installed).
	version string

	// prepareOnce guards first-time extraction — subsequent Prepare() calls
	// are cheap stat checks against the stamp file.
	prepareOnce sync.Mutex
	ready       bool
}

// Factory is the sandbox.Factory entry point for the termux-prefix backend.
// It only validates paths and constructs the Backend; it does NOT extract
// the tarball (that happens in Prepare).
func Factory(_ context.Context, cfg sandbox.Config) (sandbox.Sandbox, error) {
	prefix := cfg.Options[optPrefix]
	if prefix == "" {
		return nil, fmt.Errorf("termux: missing required option %q", optPrefix)
	}
	abs, err := filepath.Abs(prefix)
	if err != nil {
		return nil, fmt.Errorf("termux: abs %s: %w", prefix, err)
	}
	b := &Backend{
		layout: prefixLayout{
			Root:     abs,
			Projects: cfg.Options[optProjects],
		},
		tarballPath: cfg.Options[optTarball],
		version:     cfg.Options[optVersion],
	}
	return b, nil
}

func init() {
	sandbox.Register(backendName, Factory)
}

// Name returns the backend identifier.
func (b *Backend) Name() string { return backendName }

// Capabilities reports what the termux-prefix backend supports. Fixed values —
// see docs/SANDBOX_TERMUX.md for the rationale behind each flag.
func (b *Backend) Capabilities() sandbox.Capabilities {
	return sandbox.Capabilities{
		PackageManager: true,
		FullPOSIX:      false,
		Network:        true,
		RootLikeSudo:   false,
		SpeedFactor:    1.0,
		IsolationTier:  1,
	}
}

// Prepare extracts the bootstrap tarball into the prefix directory on first
// call and becomes a no-op on subsequent calls. If the stamp file matches
// the requested version, extraction is skipped even if the prefix exists
// from a previous install.
func (b *Backend) Prepare(ctx context.Context) error {
	b.prepareOnce.Lock()
	defer b.prepareOnce.Unlock()

	if err := b.layout.ensureDirs(); err != nil {
		return err
	}

	// Fast path: prefix already extracted at the requested version.
	if stamp := b.layout.installedStamp(); stamp != "" {
		if b.version == "" || stamp == b.version {
			if err := b.layout.linkHome(); err != nil {
				return err
			}
			if err := b.layout.writeResolvConf(); err != nil {
				return err
			}
			b.ready = true
			return nil
		}
		log.Printf("[termux] stamp mismatch: have %q want %q — re-extracting", stamp, b.version)
	}

	if b.tarballPath == "" {
		return fmt.Errorf("termux: prefix %s is unextracted and no %q provided", b.layout.Root, optTarball)
	}
	if _, err := os.Stat(b.tarballPath); err != nil {
		return fmt.Errorf("termux: tarball %s: %w", b.tarballPath, err)
	}

	extractCtx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	log.Printf("[termux] extracting %s → %s", b.tarballPath, b.layout.Root)
	if err := b.layout.extractTarball(extractCtx, b.tarballPath); err != nil {
		return err
	}
	if err := b.layout.linkHome(); err != nil {
		return err
	}
	if err := b.layout.writeResolvConf(); err != nil {
		return err
	}
	stamp := b.version
	if stamp == "" {
		stamp = "unversioned"
	}
	if err := b.layout.markInstalled(stamp); err != nil {
		return err
	}
	b.ready = true
	return nil
}

// Exec runs command through the prefix shell with PATH/LD_LIBRARY_PATH
// pointing into the prefix. workDir is a host-side directory; if it lives
// under layout.Projects it is used as-is, otherwise we fall back to the
// prefix home directory.
func (b *Backend) Exec(ctx context.Context, command, workDir string) (stdout, stderr string, exitCode int, err error) {
	shell := b.layout.shellPath()
	cmd := exec.CommandContext(ctx, shell, "-c", command)
	cmd.Env = b.execEnv()
	cmd.Dir = b.resolveWorkDir(workDir)

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	log.Printf("[termux] exec: %s -c %q (cwd=%s)", shell, command, cmd.Dir)
	runErr := cmd.Run()

	stdout = outBuf.String()
	stderr = errBuf.String()

	if runErr != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return stdout, stderr, -1, fmt.Errorf("termux: command timed out")
		}
		if exitErr, ok := runErr.(*exec.ExitError); ok {
			return stdout, stderr, exitErr.ExitCode(), nil
		}
		return stdout, stderr, -1, runErr
	}
	return stdout, stderr, 0, nil
}

// resolveWorkDir picks the cwd for an Exec invocation. Paths under Projects
// are respected as-is; anything else falls back to the prefix home.
func (b *Backend) resolveWorkDir(workDir string) string {
	if workDir == "" {
		return b.layout.homeDir()
	}
	abs, err := filepath.Abs(workDir)
	if err != nil {
		return b.layout.homeDir()
	}
	if b.layout.Projects != "" {
		if rel, err := filepath.Rel(b.layout.Projects, abs); err == nil && !strings.HasPrefix(rel, "..") {
			return abs
		}
	}
	// Allow explicit absolute paths inside the prefix itself (e.g. for
	// install scripts that run in $prefix/var/…).
	if rel, err := filepath.Rel(b.layout.Root, abs); err == nil && !strings.HasPrefix(rel, "..") {
		return abs
	}
	return b.layout.homeDir()
}

// execEnv returns the environment for child processes. We deliberately do
// NOT inherit the caller's PATH/LD_LIBRARY_PATH — those point at Android
// system paths and would cause shell tools to resolve the wrong binaries.
func (b *Backend) execEnv() []string {
	path := strings.Join([]string{
		b.layout.binDir(),
		b.layout.usrBinDir(),
		// Fall back to host paths last so `logcat`/`getprop` remain reachable
		// for diagnostic commands. The prefix PATH takes priority.
		"/system/bin",
		"/system/xbin",
	}, ":")
	ldPath := strings.Join([]string{
		b.layout.libDir(),
		b.layout.usrLibDir(),
	}, ":")
	return []string{
		"HOME=" + b.layout.homeDir(),
		"PATH=" + path,
		"LD_LIBRARY_PATH=" + ldPath,
		"PREFIX=" + b.layout.Root,
		"TERMUX_PREFIX=" + b.layout.Root,
		"TMPDIR=" + b.layout.tmpDir(),
		"SHELL=" + b.layout.shellPath(),
		"TERM=xterm-256color",
		"LANG=C.UTF-8",
		"USER=mocode",
	}
}

// InstallPackage delegates to the bundled pkg/apt if present; otherwise it
// verifies each requested binary already exists in the prefix and reports
// sandbox.ErrNoPackageManager for anything missing. Backends without a
// runtime index are expected to return ErrNoPackageManager per the
// interface contract.
func (b *Backend) InstallPackage(ctx context.Context, packages []string) ([]string, error) {
	if len(packages) == 0 {
		return nil, nil
	}

	// If the prefix ships pkg (Termux) or apt (Debian-in-Termux), try that
	// first. A non-zero exit is reported back as a normal error.
	if pm := b.packageManager(); pm != "" {
		quoted := make([]string, len(packages))
		for i, p := range packages {
			quoted[i] = shellQuote(p)
		}
		installCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
		defer cancel()
		cmd := fmt.Sprintf("%s install -y %s", pm, strings.Join(quoted, " "))
		_, stderr, code, err := b.Exec(installCtx, cmd, "")
		if err != nil {
			return nil, fmt.Errorf("termux: %s install: %w", pm, err)
		}
		if code != 0 {
			return nil, fmt.Errorf("termux: %s install exit %d: %s", pm, code, strings.TrimSpace(stderr))
		}
		return packages, nil
	}

	// Prebaked-only mode: report which of the requested packages are
	// reachable through PATH. Anything missing bubbles up as
	// ErrNoPackageManager so the caller knows to fall back.
	var installed, missing []string
	for _, pkg := range packages {
		if b.hasBinary(pkg) {
			installed = append(installed, pkg)
		} else {
			missing = append(missing, pkg)
		}
	}
	if len(missing) > 0 {
		return installed, fmt.Errorf("%w: %s", sandbox.ErrNoPackageManager, strings.Join(missing, ", "))
	}
	return installed, nil
}

// packageManager returns "pkg" or "apt" if either is available inside the
// prefix, or "" if the backend is prebaked-only.
func (b *Backend) packageManager() string {
	for _, name := range []string{"pkg", "apt"} {
		for _, dir := range []string{b.layout.binDir(), b.layout.usrBinDir()} {
			if isExec(filepath.Join(dir, name)) {
				return name
			}
		}
	}
	return ""
}

// hasBinary reports whether name is reachable through PATH-like resolution
// inside the prefix. Used for the prebaked-mode InstallPackage fast path.
func (b *Backend) hasBinary(name string) bool {
	for _, dir := range []string{b.layout.binDir(), b.layout.usrBinDir()} {
		if isExec(filepath.Join(dir, name)) {
			return true
		}
	}
	return false
}

// IsReady runs `echo ok` through the prefix shell and checks both exit code
// and stdout. Completes in well under the 5s contract budget.
func (b *Backend) IsReady(ctx context.Context) bool {
	checkCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	stdout, _, code, err := b.Exec(checkCtx, "echo ok", "")
	return err == nil && code == 0 && strings.TrimSpace(stdout) == "ok"
}

// Diagnose runs the full health-check battery surfaced to /api/runtime/diagnose.
func (b *Backend) Diagnose(ctx context.Context) sandbox.Diagnostic {
	checks := map[string]bool{}
	details := map[string]string{}

	checks["prefix_exists"] = dirExists(b.layout.Root)
	checks["shell_exec"] = isExec(b.layout.shellPath())
	checks["bin_exists"] = dirExists(b.layout.binDir())
	checks["lib_exists"] = dirExists(b.layout.libDir())
	checks["stamp_present"] = b.layout.installedStamp() != ""

	details["prefix"] = b.layout.Root
	details["shell"] = b.layout.shellPath()
	details["stamp"] = b.layout.installedStamp()
	if pm := b.packageManager(); pm != "" {
		details["package_manager"] = pm
	}

	// Only run the echo probe if structural checks passed — otherwise exec
	// will almost certainly fail and the error is less informative than the
	// check names above.
	diag := sandbox.Diagnostic{
		Backend:       backendName,
		IsolationTier: 1,
		Checks:        checks,
		Details:       details,
	}
	if checks["prefix_exists"] && checks["shell_exec"] {
		probeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		defer cancel()
		stdout, stderr, code, err := b.Exec(probeCtx, "echo ok", "")
		checks["echo_ok"] = err == nil && code == 0 && strings.TrimSpace(stdout) == "ok"
		if !checks["echo_ok"] {
			diag.Error = strings.TrimSpace(stderr)
			if diag.Error == "" && err != nil {
				diag.Error = err.Error()
			}
		}
	}
	diag.OK = allTrue(checks)
	return diag
}

// Teardown is a no-op: the prefix stays on disk across app restarts so the
// next Prepare() is cheap. Users wanting a clean slate should delete the
// prefix directory from the Android settings "Clear storage" flow.
func (b *Backend) Teardown(_ context.Context) error { return nil }

// dirExists is a small helper for Diagnose. Returns true for existing
// directories only — regular files at the same path do not count.
func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// allTrue reports whether every value in the map is true. Used to collapse
// the per-check status into a single OK flag.
func allTrue(m map[string]bool) bool {
	for _, v := range m {
		if !v {
			return false
		}
	}
	return len(m) > 0
}

// shellQuote wraps s in single quotes, escaping embedded single quotes.
// Used for package names passed to the prefix-side pkg/apt command line.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
