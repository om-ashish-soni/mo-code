package runtime

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// QemuRuntime runs commands inside a full aarch64 Alpine VM via qemu-system-aarch64
// in user-mode TCG (no KVM). This is Track B of the isolation roadmap: true
// CPU+RAM isolation from the host Android, at an ~8-12× speed cost.
//
// The VM bundle lives in BundleDir and must contain:
//
//	bundle/
//	  bin/qemu-system-aarch64
//	  lib/*.so                       # qemu deps (libglib, libcrypto, libssl, ...)
//	  roms/qemu/                     # firmware (edk2, efi-virtio.rom, etc.)
//	  boot/vmlinuz-virt              # Alpine aarch64 kernel
//	  boot/initramfs-rootfs-py.cpio.gz # Alpine rootfs + python3, busybox, apk
//	  qemu-exec-py.sh                # marker-framed one-shot RPC wrapper
//
// Each Exec() boots a fresh VM (~8-14 s cold) and tears it down when the
// command exits. This is fine for beta validation; a persistent-VM with
// virtio-serial RPC is the next optimization.
type QemuRuntime struct {
	// BundleDir is the absolute path to the qemu bundle (see layout above).
	BundleDir string

	// ProjectsDir is the host path where user projects live. Not yet shared
	// into the guest — placeholder for a future virtio-9p / virtiofs mount.
	ProjectsDir string

	// ExecTimeout bounds a single Exec() call. Defaults to 90 s if zero.
	ExecTimeout time.Duration

	// ShellBin is the absolute path to the host shell used to invoke
	// qemu-exec-py.sh. Defaults to "/system/bin/sh" on Android.
	ShellBin string
}

// qemuExecScript is the filename inside BundleDir.
const qemuExecScript = "qemu-exec-py.sh"

// NewQemuRuntime validates the bundle layout and returns a ready runtime.
// Does NOT boot a VM — that happens lazily per Exec().
func NewQemuRuntime(bundleDir, projectsDir string) (*QemuRuntime, error) {
	if bundleDir == "" {
		return nil, fmt.Errorf("qemu: bundleDir required")
	}
	abs, err := filepath.Abs(bundleDir)
	if err != nil {
		return nil, fmt.Errorf("qemu: resolve bundleDir: %w", err)
	}
	// Android 15 W^X: the qemu ELF is shipped via jniLibs and lives in
	// applicationInfo.nativeLibraryDir (SELinux apk_data_file, exec OK).
	// DaemonService exports MOCODE_QEMU_BIN pointing at it. Standalone/adb
	// smoke tests still fall back to $bundle/bin/qemu-system-aarch64.
	qemuBin := os.Getenv("MOCODE_QEMU_BIN")
	if qemuBin == "" {
		qemuBin = filepath.Join(abs, "bin", "qemu-system-aarch64")
	}
	required := []string{
		qemuBin,
		filepath.Join(abs, "boot", "vmlinuz-virt"),
		filepath.Join(abs, "boot", "initramfs-rootfs-py.cpio.gz"),
		filepath.Join(abs, qemuExecScript),
	}
	for _, p := range required {
		if _, err := os.Stat(p); err != nil {
			return nil, fmt.Errorf("qemu: missing bundle file %s: %w", p, err)
		}
	}
	// Ensure qemu binary + script have exec bit when we can (lost across APK
	// updates, and nativeLibraryDir is system-owned so chmod is best-effort).
	_ = os.Chmod(qemuBin, 0o755)
	_ = os.Chmod(filepath.Join(abs, qemuExecScript), 0o755)

	if projectsDir != "" {
		if _, err := os.Stat(projectsDir); err != nil {
			if mkErr := os.MkdirAll(projectsDir, 0o755); mkErr != nil {
				return nil, fmt.Errorf("qemu: create projectsDir %s: %w", projectsDir, mkErr)
			}
		}
	}
	return &QemuRuntime{
		BundleDir:   abs,
		ProjectsDir: projectsDir,
		ExecTimeout: 90 * time.Second,
		ShellBin:    "/system/bin/sh",
	}, nil
}

// IsolationTier reports the active sandbox strategy label.
func (r *QemuRuntime) IsolationTier() string { return "qemu-tcg" }

// Exec runs a shell command inside a freshly-booted Alpine VM.
// Output is captured via marker-delimited serial stream; exit code is the
// guest command's exit code. workDir is best-effort — we cd into it inside
// the guest so shell-relative paths work, but the host filesystem is NOT
// yet shared with the guest.
func (r *QemuRuntime) Exec(ctx context.Context, command, workDir string) (stdout, stderr string, exitCode int, err error) {
	if strings.TrimSpace(command) == "" {
		return "", "", -1, fmt.Errorf("qemu: empty command")
	}

	// Per-call timeout: honor the outer ctx if it has one; otherwise apply
	// ExecTimeout. The wrapper script also has its own QEMU_EXEC_TIMEOUT.
	callCtx := ctx
	if _, hasDeadline := ctx.Deadline(); !hasDeadline && r.ExecTimeout > 0 {
		var cancel context.CancelFunc
		callCtx, cancel = context.WithTimeout(ctx, r.ExecTimeout)
		defer cancel()
	}

	guestCmd := command
	if workDir != "" {
		guestCmd = fmt.Sprintf("cd %q 2>/dev/null; %s", workDir, command)
	}

	shellScript := filepath.Join(r.BundleDir, qemuExecScript)
	cmd := exec.CommandContext(callCtx, r.ShellBin, shellScript, guestCmd)
	cmd.Dir = r.BundleDir
	cmd.Env = r.qemuEnv()

	log.Printf("[qemu] exec: %s", truncate(command, 200))

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	runErr := cmd.Run()
	stdout = outBuf.String()
	stderr = errBuf.String()

	if runErr != nil {
		if callCtx.Err() == context.DeadlineExceeded {
			log.Printf("[qemu] timeout: %s", truncate(command, 200))
			return stdout, stderr, -1, fmt.Errorf("command timed out")
		}
		if exitErr, ok := runErr.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
			err = runErr
		}
	}

	if exitCode != 0 || err != nil {
		log.Printf("[qemu] exit=%d err=%v cmd=%q", exitCode, err, truncate(command, 120))
		if stderr != "" {
			log.Printf("[qemu] stderr(%d): %q", len(stderr), truncate(strings.TrimSpace(stderr), 300))
		}
	}
	return stdout, stderr, exitCode, err
}

// qemuEnv returns the env for invoking qemu-exec-py.sh. The script reads
// MOCODE_QEMU_BIN + MOCODE_QEMU_LD_LIBRARY_PATH exported by DaemonService so
// it can find qemu in nativeLibraryDir (apk_data_file, exec-allowed) instead
// of the old filesDir/qemu-smoke/bin/ path (app_data_file, W^X blocks exec).
func (r *QemuRuntime) qemuEnv() []string {
	env := []string{
		"HOME=" + r.BundleDir,
		"PATH=/system/bin:/system/xbin",
		"TMPDIR=" + r.BundleDir,
		"TERM=dumb",
	}
	for _, k := range []string{"MOCODE_QEMU_BIN", "MOCODE_QEMU_LD_LIBRARY_PATH"} {
		if v := os.Getenv(k); v != "" {
			env = append(env, k+"="+v)
		}
	}
	if v := os.Getenv("QEMU_EXEC_TIMEOUT"); v != "" {
		env = append(env, "QEMU_EXEC_TIMEOUT="+v)
	} else if r.ExecTimeout > 0 {
		env = append(env, fmt.Sprintf("QEMU_EXEC_TIMEOUT=%d", int(r.ExecTimeout.Seconds())))
	}
	return env
}

// InstallPackages is not supported in v1 beta: the VM runs with -net none,
// so apk has no network to fetch from. Callers should treat this as an
// allowed backend limitation and fall back to the packages baked into the
// initramfs (python3 + busybox coreutils).
func (r *QemuRuntime) InstallPackages(_ context.Context, _ []string) ([]string, error) {
	return nil, fmt.Errorf("qemu-tcg: package install not available in v1 beta (VM runs with -net none)")
}

// IsReady boots the VM and runs `echo ok` — slow (~10 s) but authoritative.
func (r *QemuRuntime) IsReady(ctx context.Context) bool {
	checkCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	stdout, _, code, err := r.Exec(checkCtx, "echo ok", "")
	return err == nil && code == 0 && strings.TrimSpace(stdout) == "ok"
}

// QemuDiagnosticResult is the structured health-check result.
type QemuDiagnosticResult struct {
	OK             bool   `json:"ok"`
	QemuBinExists  bool   `json:"qemu_bin_exists"`
	KernelExists   bool   `json:"kernel_exists"`
	InitramfsFound bool   `json:"initramfs_found"`
	ScriptExists   bool   `json:"script_exists"`
	EchoOK         bool   `json:"echo_ok"`
	PythonOK       bool   `json:"python_ok"`
	BootMillis     int64  `json:"boot_millis"`
	ExitCode       int    `json:"exit_code"`
	Stderr         string `json:"stderr,omitempty"`
	Error          string `json:"error,omitempty"`
	IsolationTier  string `json:"isolation_tier"`
}

// Diagnose runs a deeper health check: validates bundle layout, then boots
// the VM and verifies python3 is available.
func (r *QemuRuntime) Diagnose(ctx context.Context) QemuDiagnosticResult {
	result := QemuDiagnosticResult{ExitCode: -1, IsolationTier: r.IsolationTier()}

	qemuBin := os.Getenv("MOCODE_QEMU_BIN")
	if qemuBin == "" {
		qemuBin = filepath.Join(r.BundleDir, "bin", "qemu-system-aarch64")
	}
	if info, err := os.Stat(qemuBin); err == nil {
		result.QemuBinExists = true
		if info.Mode()&0o111 == 0 {
			log.Printf("[qemu] diagnose: qemu binary %s is not executable", qemuBin)
		}
	} else {
		result.Error = fmt.Sprintf("qemu binary not found: %s", qemuBin)
		return result
	}

	if _, err := os.Stat(filepath.Join(r.BundleDir, "boot", "vmlinuz-virt")); err == nil {
		result.KernelExists = true
	} else {
		result.Error = "kernel vmlinuz-virt missing"
		return result
	}
	if _, err := os.Stat(filepath.Join(r.BundleDir, "boot", "initramfs-rootfs-py.cpio.gz")); err == nil {
		result.InitramfsFound = true
	} else {
		result.Error = "initramfs-rootfs-py.cpio.gz missing"
		return result
	}
	if _, err := os.Stat(filepath.Join(r.BundleDir, qemuExecScript)); err == nil {
		result.ScriptExists = true
	} else {
		result.Error = qemuExecScript + " missing"
		return result
	}

	// Functional test: boot VM and run python3 --version.
	// We use python3 specifically (not echo) because echo is a sh builtin
	// and tells us nothing about the dynamic-ELF execve path — that's
	// exactly the gap this backend exists to close.
	checkCtx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	start := time.Now()
	stdout, stderr, code, execErr := r.Exec(checkCtx, "echo ok && /usr/bin/python3 -c 'print(\"py-ok\")'", "")
	result.BootMillis = time.Since(start).Milliseconds()
	result.ExitCode = code
	result.Stderr = strings.TrimSpace(stderr)

	if execErr != nil {
		result.Error = fmt.Sprintf("exec error: %v", execErr)
		return result
	}
	if strings.Contains(stdout, "ok") {
		result.EchoOK = true
	}
	if strings.Contains(stdout, "py-ok") {
		result.PythonOK = true
	}
	if code == 0 && result.EchoOK && result.PythonOK {
		result.OK = true
	} else if code != 0 {
		result.Error = fmt.Sprintf("diagnose test failed (exit %d): %s", code, strings.TrimSpace(stderr))
	}
	return result
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max] + "…"
}
