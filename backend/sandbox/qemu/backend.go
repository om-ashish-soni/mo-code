// Package qemu implements the mo-code sandbox.Sandbox interface over a
// software-emulated ARM64 VM using qemu-system-aarch64 (TCG, no KVM).
//
// Isolation tier 3 (full VM). Accept a 10-50x slowdown vs native as the
// price of true kernel-level isolation from the Android host.
//
// Comms choice: SSH over user-mode networking (see docs/SANDBOX_QEMU.md).
// Rationale: no custom in-guest agent required, reuses golang.org/x/crypto/ssh
// (already a transitive dep), and gives a familiar shell surface for debugging.
package qemu

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"mo-code/backend/sandbox"
)

const backendName = "qemu-tcg"

// Defaults used when Options are missing.
const (
	defaultMemoryMB = 512
	defaultCPUs     = 1
	defaultSSHPort  = 2222
	defaultSSHUser  = "root"
	// defaultSSHPassword matches the password baked into the alpine image
	// by scripts/build-qemu-image.sh. The VM is only reachable on 127.0.0.1
	// (user-mode net with hostfwd), so this is a loopback-only credential.
	defaultSSHPassword = "mocode"
	defaultBootTimeout = 90 * time.Second
)

// Backend is a QEMU-backed Sandbox implementation.
type Backend struct {
	cfg config

	mu       sync.Mutex
	vm       *vm       // running qemu process, nil before Prepare.
	prepared bool
}

// config holds parsed options.
type config struct {
	QemuBin      string
	ImagePath    string
	DataDir      string
	MemoryMB     int
	CPUs         int
	SSHPort      int
	SSHUser      string
	SSHPassword  string
	BootTimeout  time.Duration
	ExtraArgs    []string
	MachineType  string // e.g. "virt"
	CPUModel     string // e.g. "cortex-a72"
	ReadOnlyBase bool   // if true, wrap image in a throwaway overlay qcow2
}

// Factory builds a qemu-tcg backend from sandbox.Config options.
//
// Required:
//
//	qemu.bin     — absolute path to qemu-system-aarch64 binary
//	qemu.image   — absolute path to the alpine qcow2 image
//	qemu.data_dir — writable host directory for overlay/qcow2 + state
//
// Optional:
//
//	qemu.memory_mb  (default 512)
//	qemu.cpus       (default 1)
//	qemu.ssh_port   (default 2222)
//	qemu.ssh_user   (default root)
//	qemu.ssh_pass   (default "mocode" — matches image build)
//	qemu.machine    (default "virt")
//	qemu.cpu_model  (default "cortex-a72")
//	qemu.boot_timeout (default 90s — e.g. "60s", "2m")
//	qemu.readonly_base (default true — use snapshot overlay so base qcow2 stays pristine)
func Factory(_ context.Context, cfg sandbox.Config) (sandbox.Sandbox, error) {
	c, err := parseConfig(cfg.Options)
	if err != nil {
		return nil, err
	}
	return &Backend{cfg: c}, nil
}

func init() {
	sandbox.Register(backendName, Factory)
}

func parseConfig(opts map[string]string) (config, error) {
	c := config{
		MemoryMB:     defaultMemoryMB,
		CPUs:         defaultCPUs,
		SSHPort:      defaultSSHPort,
		SSHUser:      defaultSSHUser,
		SSHPassword:  defaultSSHPassword,
		BootTimeout:  defaultBootTimeout,
		MachineType:  "virt",
		CPUModel:     "cortex-a72",
		ReadOnlyBase: true,
	}

	c.QemuBin = opts["qemu.bin"]
	c.ImagePath = opts["qemu.image"]
	c.DataDir = opts["qemu.data_dir"]
	if c.QemuBin == "" || c.ImagePath == "" || c.DataDir == "" {
		return c, fmt.Errorf("qemu: missing required options (qemu.bin, qemu.image, qemu.data_dir)")
	}

	if v := opts["qemu.memory_mb"]; v != "" {
		n, err := parsePositiveInt(v)
		if err != nil {
			return c, fmt.Errorf("qemu.memory_mb: %w", err)
		}
		c.MemoryMB = n
	}
	if v := opts["qemu.cpus"]; v != "" {
		n, err := parsePositiveInt(v)
		if err != nil {
			return c, fmt.Errorf("qemu.cpus: %w", err)
		}
		c.CPUs = n
	}
	if v := opts["qemu.ssh_port"]; v != "" {
		n, err := parsePositiveInt(v)
		if err != nil {
			return c, fmt.Errorf("qemu.ssh_port: %w", err)
		}
		c.SSHPort = n
	}
	if v := opts["qemu.ssh_user"]; v != "" {
		c.SSHUser = v
	}
	if v := opts["qemu.ssh_pass"]; v != "" {
		c.SSHPassword = v
	}
	if v := opts["qemu.machine"]; v != "" {
		c.MachineType = v
	}
	if v := opts["qemu.cpu_model"]; v != "" {
		c.CPUModel = v
	}
	if v := opts["qemu.boot_timeout"]; v != "" {
		d, err := time.ParseDuration(v)
		if err != nil {
			return c, fmt.Errorf("qemu.boot_timeout: %w", err)
		}
		c.BootTimeout = d
	}
	if v := opts["qemu.readonly_base"]; v != "" {
		c.ReadOnlyBase = v == "1" || strings.EqualFold(v, "true")
	}
	if v := opts["qemu.extra_args"]; v != "" {
		c.ExtraArgs = strings.Fields(v)
	}

	if _, err := os.Stat(c.QemuBin); err != nil {
		return c, fmt.Errorf("qemu binary not found: %s", c.QemuBin)
	}
	if _, err := os.Stat(c.ImagePath); err != nil {
		return c, fmt.Errorf("qemu image not found: %s", c.ImagePath)
	}
	if err := os.MkdirAll(c.DataDir, 0o755); err != nil {
		return c, fmt.Errorf("qemu.data_dir: %w", err)
	}
	if !filepath.IsAbs(c.QemuBin) || !filepath.IsAbs(c.ImagePath) || !filepath.IsAbs(c.DataDir) {
		return c, errors.New("qemu: bin, image, and data_dir must be absolute paths")
	}
	return c, nil
}

func parsePositiveInt(s string) (int, error) {
	var n int
	if _, err := fmt.Sscanf(s, "%d", &n); err != nil {
		return 0, err
	}
	if n <= 0 {
		return 0, fmt.Errorf("must be > 0, got %d", n)
	}
	return n, nil
}

func (b *Backend) Name() string { return backendName }

func (b *Backend) Capabilities() sandbox.Capabilities {
	return sandbox.Capabilities{
		PackageManager: true,
		FullPOSIX:      true,
		Network:        true,
		RootLikeSudo:   true,
		SpeedFactor:    20.0,
		IsolationTier:  3,
	}
}

// Prepare boots the VM and waits for SSH to accept connections.
// Idempotent: subsequent calls return nil if the VM is alive.
func (b *Backend) Prepare(ctx context.Context) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.prepared && b.vm != nil && b.vm.alive() {
		return nil
	}
	// Clean up any zombie VM from a prior Prepare.
	if b.vm != nil {
		_ = b.vm.shutdown(ctx, 2*time.Second)
		b.vm = nil
	}
	v, err := startVM(ctx, b.cfg)
	if err != nil {
		return err
	}
	if err := waitForSSH(ctx, b.cfg, b.cfg.BootTimeout); err != nil {
		_ = v.shutdown(ctx, 2*time.Second)
		return fmt.Errorf("qemu: VM booted but SSH not reachable: %w", err)
	}
	b.vm = v
	b.prepared = true
	return nil
}

// Exec runs a shell command inside the guest via SSH.
// workDir, if non-empty, is used as the cwd (cd'd into before running).
func (b *Backend) Exec(ctx context.Context, command, workDir string) (string, string, int, error) {
	if err := b.ensureReady(ctx); err != nil {
		return "", "", -1, err
	}
	full := command
	if workDir != "" {
		full = fmt.Sprintf("cd %s && %s", shellQuote(workDir), command)
	}
	return sshRun(ctx, b.cfg, full)
}

// InstallPackage runs `apk add --no-cache` inside the guest.
func (b *Backend) InstallPackage(ctx context.Context, packages []string) ([]string, error) {
	if len(packages) == 0 {
		return nil, nil
	}
	if err := b.ensureReady(ctx); err != nil {
		return nil, err
	}
	args := make([]string, 0, len(packages))
	for _, p := range packages {
		args = append(args, shellQuote(p))
	}
	cmd := "apk add --no-cache " + strings.Join(args, " ")
	_, stderr, code, err := sshRun(ctx, b.cfg, cmd)
	if err != nil {
		return nil, fmt.Errorf("qemu: apk add: %w", err)
	}
	if code != 0 {
		return nil, fmt.Errorf("qemu: apk add exit %d: %s", code, strings.TrimSpace(stderr))
	}
	return packages, nil
}

// IsReady returns true if the VM is running and accepts SSH within a short window.
func (b *Backend) IsReady(ctx context.Context) bool {
	b.mu.Lock()
	alive := b.vm != nil && b.vm.alive()
	b.mu.Unlock()
	if !alive {
		return false
	}
	probeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	_, _, code, err := sshRun(probeCtx, b.cfg, "true")
	return err == nil && code == 0
}

// Diagnose reports a structured health snapshot.
func (b *Backend) Diagnose(ctx context.Context) sandbox.Diagnostic {
	d := sandbox.Diagnostic{
		Backend:       backendName,
		IsolationTier: 3,
		Checks:        map[string]bool{},
		Details:       map[string]string{},
	}

	_, errBin := os.Stat(b.cfg.QemuBin)
	d.Checks["bin_exists"] = errBin == nil
	_, errImg := os.Stat(b.cfg.ImagePath)
	d.Checks["image_exists"] = errImg == nil

	b.mu.Lock()
	d.Checks["vm_running"] = b.vm != nil && b.vm.alive()
	b.mu.Unlock()

	if d.Checks["vm_running"] {
		probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		stdout, _, code, err := sshRun(probeCtx, b.cfg, "echo ok")
		cancel()
		d.Checks["ssh_ok"] = err == nil && code == 0 && strings.TrimSpace(stdout) == "ok"
		if err != nil {
			d.Details["ssh_error"] = err.Error()
		}
	}

	d.OK = d.Checks["bin_exists"] && d.Checks["image_exists"] &&
		d.Checks["vm_running"] && d.Checks["ssh_ok"]
	if !d.OK {
		missing := []string{}
		for k, v := range d.Checks {
			if !v {
				missing = append(missing, k)
			}
		}
		d.Error = "failed checks: " + strings.Join(missing, ",")
	}
	return d
}

// Teardown gracefully powers off the guest, then kills qemu if it lingers.
func (b *Backend) Teardown(ctx context.Context) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.vm == nil {
		return nil
	}
	// Best-effort graceful poweroff. Ignore errors — we kill below anyway.
	if b.prepared {
		shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		_, _, _, _ = sshRun(shutdownCtx, b.cfg, "poweroff -f >/dev/null 2>&1 &")
		cancel()
	}
	err := b.vm.shutdown(ctx, 10*time.Second)
	b.vm = nil
	b.prepared = false
	return err
}

// ensureReady is a fast internal check: if not prepared, fail fast so callers
// don't accidentally wait 90s for a cold boot inside Exec.
func (b *Backend) ensureReady(_ context.Context) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.prepared || b.vm == nil || !b.vm.alive() {
		return errors.New("qemu: backend not prepared — call Prepare first")
	}
	return nil
}

// shellQuote wraps a string in single quotes for safe shell inclusion.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
