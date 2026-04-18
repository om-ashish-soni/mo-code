package qemu

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"
)

// vm represents a running qemu-system-aarch64 process.
type vm struct {
	cmd    *exec.Cmd
	stderr *cappedBuffer

	// overlayPath is the per-boot qcow2 overlay that wraps the read-only base
	// image. Empty if ReadOnlyBase was false (qemu -snapshot handles it).
	overlayPath string

	mu   sync.Mutex
	done bool
	exit error
}

// startVM spawns qemu with user-mode networking and an SSH port-forward.
// Returns once the qemu process has started (SSH may not yet be up).
func startVM(ctx context.Context, cfg config) (*vm, error) {
	diskArg, overlayPath, err := prepareDisk(cfg)
	if err != nil {
		return nil, err
	}

	args := []string{
		"-machine", cfg.MachineType,
		"-cpu", cfg.CPUModel,
		"-smp", strconv.Itoa(cfg.CPUs),
		"-m", strconv.Itoa(cfg.MemoryMB),
		"-nographic",
		"-no-reboot",
		"-drive", diskArg,
		// User-mode networking with a single hostfwd to SSH.
		"-netdev", fmt.Sprintf("user,id=n0,hostfwd=tcp:127.0.0.1:%d-:22", cfg.SSHPort),
		"-device", "virtio-net-pci,netdev=n0",
	}
	args = append(args, cfg.ExtraArgs...)

	cmd := exec.CommandContext(ctx, cfg.QemuBin, args...)
	// Detach from our process group so Ctrl+C on the host test runner doesn't
	// tear down the VM mid-run.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	stderr := &cappedBuffer{cap: 64 * 1024}
	cmd.Stderr = stderr
	cmd.Stdout = io.Discard
	cmd.Stdin = nil

	if err := cmd.Start(); err != nil {
		_ = os.Remove(overlayPath)
		return nil, fmt.Errorf("qemu: start %s: %w", cfg.QemuBin, err)
	}

	v := &vm{
		cmd:         cmd,
		stderr:      stderr,
		overlayPath: overlayPath,
	}

	// Reap the process in the background so alive() stays accurate.
	go func() {
		err := cmd.Wait()
		v.mu.Lock()
		v.done = true
		v.exit = err
		v.mu.Unlock()
	}()

	return v, nil
}

// prepareDisk returns the -drive arg string and the overlay path (if any).
// When cfg.ReadOnlyBase is true, builds an overlay qcow2 so the base image
// stays pristine across runs.
func prepareDisk(cfg config) (string, string, error) {
	if !cfg.ReadOnlyBase {
		// Rely on qemu's built-in -snapshot behavior with a writable-looking backing.
		return fmt.Sprintf("file=%s,if=virtio,format=qcow2,snapshot=on", cfg.ImagePath), "", nil
	}
	overlay := filepath.Join(cfg.DataDir, fmt.Sprintf("overlay-%d.qcow2", os.Getpid()))
	// qemu-img is usually next to qemu-system-aarch64; if it's not present,
	// fall back to snapshot=on which needs no external tool.
	imgTool := filepath.Join(filepath.Dir(cfg.QemuBin), "qemu-img")
	if _, err := os.Stat(imgTool); err != nil {
		return fmt.Sprintf("file=%s,if=virtio,format=qcow2,snapshot=on", cfg.ImagePath), "", nil
	}
	// Clean any stale overlay from a previous crashed run.
	_ = os.Remove(overlay)
	mkCmd := exec.Command(imgTool,
		"create", "-f", "qcow2",
		"-F", "qcow2",
		"-b", cfg.ImagePath,
		overlay,
	)
	if out, err := mkCmd.CombinedOutput(); err != nil {
		return "", "", fmt.Errorf("qemu-img create overlay: %w: %s", err, out)
	}
	return fmt.Sprintf("file=%s,if=virtio,format=qcow2", overlay), overlay, nil
}

// alive is true while the qemu process is still running.
func (v *vm) alive() bool {
	v.mu.Lock()
	defer v.mu.Unlock()
	return !v.done
}

// shutdown terminates qemu. Attempts SIGTERM first, then SIGKILL after grace.
func (v *vm) shutdown(_ context.Context, grace time.Duration) error {
	v.mu.Lock()
	done := v.done
	v.mu.Unlock()
	if done {
		_ = os.Remove(v.overlayPath)
		return nil
	}
	if v.cmd.Process != nil {
		_ = v.cmd.Process.Signal(syscall.SIGTERM)
	}
	deadline := time.Now().Add(grace)
	for time.Now().Before(deadline) {
		v.mu.Lock()
		done = v.done
		v.mu.Unlock()
		if done {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	if !done && v.cmd.Process != nil {
		_ = v.cmd.Process.Kill()
	}
	// Drain wait-goroutine.
	for range 20 {
		v.mu.Lock()
		done = v.done
		v.mu.Unlock()
		if done {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	_ = os.Remove(v.overlayPath)
	return nil
}

// waitForSSH polls until a TCP connect to 127.0.0.1:sshPort succeeds, or timeout.
func waitForSSH(ctx context.Context, cfg config, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	addr := fmt.Sprintf("127.0.0.1:%d", cfg.SSHPort)
	var lastErr error
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		conn, err := net.DialTimeout("tcp", addr, 500*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			// TCP is up, but sshd may still be in banner-exchange.
			// Give it one more handshake check via an auth probe.
			probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			_, _, _, err := sshRun(probeCtx, cfg, "true")
			cancel()
			if err == nil {
				return nil
			}
			lastErr = err
		} else {
			lastErr = err
		}
		time.Sleep(500 * time.Millisecond)
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("timeout after %s", timeout)
	}
	return lastErr
}

// cappedBuffer is a bytes.Buffer that stops accepting data once it reaches cap
// bytes. Writes after the cap are silently dropped but still report len(p) so
// the caller (exec.Cmd's stderr pipe) doesn't treat them as errors. Prevents
// runaway qemu stderr from blowing memory over a long session.
type cappedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
	cap int
}

func (c *cappedBuffer) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	room := c.cap - c.buf.Len()
	if room <= 0 {
		return len(p), nil
	}
	if len(p) > room {
		c.buf.Write(p[:room])
		return len(p), nil
	}
	c.buf.Write(p)
	return len(p), nil
}

func (c *cappedBuffer) String() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.buf.String()
}

func (c *cappedBuffer) Len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.buf.Len()
}
