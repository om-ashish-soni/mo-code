// Package sandbox defines the backend-agnostic interface for executing commands
// inside an isolated Linux environment on Android. Concrete backends (proot,
// termux, qemu, avf) live in subpackages and register themselves via init().
package sandbox

import "context"

// Sandbox is the contract every execution backend implements.
// Backends are swappable via config: runtime.backend = "proot" | "termux" | "qemu" | "avf".
type Sandbox interface {
	// Name is the backend identifier used in config (e.g. "proot", "qemu-tcg").
	Name() string

	// Capabilities reports what this backend supports and its performance profile.
	Capabilities() Capabilities

	// Prepare performs one-time setup: extract rootfs, boot VM, warm caches.
	// Safe to call multiple times — second call should be a no-op if ready.
	Prepare(ctx context.Context) error

	// Exec runs a shell command and returns its output.
	// workDir is the guest-side directory; empty string = backend default.
	Exec(ctx context.Context, command, workDir string) (stdout, stderr string, exitCode int, err error)

	// InstallPackage adds tools to the sandbox. Returns the list actually installed.
	// Backends without a runtime package manager (e.g. prebaked-only) return
	// ErrNoPackageManager if asked for an uninstalled package.
	InstallPackage(ctx context.Context, packages []string) (installed []string, err error)

	// IsReady is a fast liveness probe. Should complete in <5s.
	IsReady(ctx context.Context) bool

	// Diagnose runs a deeper health check. Used by /api/runtime/diagnose.
	Diagnose(ctx context.Context) Diagnostic

	// Teardown releases resources (shuts down VMs, unmounts binds).
	// Idempotent.
	Teardown(ctx context.Context) error
}

// Capabilities describes what a backend can do and how fast.
// Used by the registry to pick the best available backend.
type Capabilities struct {
	// PackageManager: true if new tools can be added at runtime (apk, apt, pkg).
	PackageManager bool

	// FullPOSIX: true for glibc/musl environments. False for bionic-only (termux).
	FullPOSIX bool

	// Network: true if sockets inside the sandbox reach the internet unrestricted.
	Network bool

	// RootLikeSudo: true if the guest sees itself as root (fakeroot or real root).
	RootLikeSudo bool

	// SpeedFactor: relative to native execution. 1.0 = native, 10.0 = 10x slower.
	SpeedFactor float64

	// IsolationTier:
	//   0 = none (direct Android exec)
	//   1 = prefix (termux-style; same kernel, same UID)
	//   2 = syscall translation (proot, ptrace-based)
	//   3 = full VM (qemu-tcg, avf/microdroid)
	IsolationTier int
}

// Diagnostic is the generic health-check result surfaced to the UI.
type Diagnostic struct {
	OK            bool              `json:"ok"`
	Backend       string            `json:"backend"`
	IsolationTier int               `json:"isolation_tier"`
	Checks        map[string]bool   `json:"checks"`
	Error         string            `json:"error,omitempty"`
	Details       map[string]string `json:"details,omitempty"`
}
