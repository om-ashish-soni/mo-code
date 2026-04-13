// Package runtime provides the proot + Alpine Linux execution environment
// for running shell commands on Android without root access.
package runtime

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// ProotRuntime wraps command execution through proot + Alpine Linux.
// On Android, this provides a full Linux userland (sh, npm, python, go, etc.)
// without requiring root access.
type ProotRuntime struct {
	// ProotBin is the absolute path to the proot static binary.
	ProotBin string

	// RootFS is the absolute path to the Alpine Linux rootfs directory.
	RootFS string

	// ProjectsDir is the host path where user projects live.
	// Bind-mounted into proot at /home/developer.
	ProjectsDir string

	// installed tracks which apk packages have been installed in this session.
	installed   map[string]bool
	installedMu sync.RWMutex
}

// NewProotRuntime creates a runtime given paths to the proot binary,
// Alpine rootfs, and the projects directory on the host.
// Returns an error if required paths don't exist.
func NewProotRuntime(prootBin, rootFS, projectsDir string) (*ProotRuntime, error) {
	if _, err := os.Stat(prootBin); err != nil {
		return nil, fmt.Errorf("proot binary not found: %s", prootBin)
	}
	if _, err := os.Stat(rootFS); err != nil {
		return nil, fmt.Errorf("alpine rootfs not found: %s", rootFS)
	}
	if _, err := os.Stat(projectsDir); err != nil {
		// Create projects dir if it doesn't exist.
		if mkErr := os.MkdirAll(projectsDir, 0o755); mkErr != nil {
			return nil, fmt.Errorf("cannot create projects dir: %s: %v", projectsDir, mkErr)
		}
	}

	return &ProotRuntime{
		ProotBin:    prootBin,
		RootFS:      rootFS,
		ProjectsDir: projectsDir,
		installed:   make(map[string]bool),
	}, nil
}

// prootArgs builds the proot command-line arguments.
func (r *ProotRuntime) prootArgs(workDir string) []string {
	// Resolve the working directory inside proot.
	// If workDir is relative to ProjectsDir, map it to /home/developer/<relative>.
	prootWorkDir := "/home/developer"
	if workDir != "" {
		rel, err := filepath.Rel(r.ProjectsDir, workDir)
		if err == nil && !strings.HasPrefix(rel, "..") {
			prootWorkDir = filepath.Join("/home/developer", rel)
		}
	}

	return []string{
		"-0",                                         // fake root
		"-r", r.RootFS,                               // rootfs
		"-b", "/dev",                                  // bind /dev
		"-b", "/proc",                                 // bind /proc
		"-b", "/sys",                                  // bind /sys
		"-b", r.ProjectsDir + ":/home/developer",      // bind projects
		"-b", "/etc/resolv.conf:/etc/resolv.conf",     // DNS resolution
		"-w", prootWorkDir,                            // working directory
	}
}

// Exec runs a shell command inside the proot environment.
// The command runs as: proot [args] /bin/sh -c "<command>"
func (r *ProotRuntime) Exec(ctx context.Context, command, workDir string) (stdout, stderr string, exitCode int, err error) {
	args := r.prootArgs(workDir)
	args = append(args, "/bin/sh", "-c", command)

	cmd := exec.CommandContext(ctx, r.ProotBin, args...)

	// Set environment variables inside proot.
	cmd.Env = r.prootEnv()

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	runErr := cmd.Run()

	stdout = outBuf.String()
	stderr = errBuf.String()
	exitCode = 0

	if runErr != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return stdout, stderr, -1, fmt.Errorf("command timed out")
		}
		if exitErr, ok := runErr.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			exitCode = -1
			err = runErr
		}
	}

	return stdout, stderr, exitCode, err
}

// prootEnv returns the environment variables set inside the proot container.
func (r *ProotRuntime) prootEnv() []string {
	return []string{
		"HOME=/home/developer",
		"USER=developer",
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
		"LANG=C.UTF-8",
		"TERM=xterm-256color",
		"SHELL=/bin/sh",
	}
}

// InstallPackages runs `apk add` for the given packages inside the proot environment.
// Skips packages that have already been installed in this session.
// Returns the list of packages that were actually installed.
func (r *ProotRuntime) InstallPackages(ctx context.Context, packages []string) (installed []string, err error) {
	var toInstall []string
	r.installedMu.RLock()
	for _, pkg := range packages {
		if !r.installed[pkg] {
			toInstall = append(toInstall, pkg)
		}
	}
	r.installedMu.RUnlock()

	if len(toInstall) == 0 {
		return nil, nil
	}

	// First update the package index (only if needed).
	r.installedMu.RLock()
	indexUpdated := r.installed["__apk_index__"]
	r.installedMu.RUnlock()

	if !indexUpdated {
		installCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
		defer cancel()
		_, stderr, code, err := r.Exec(installCtx, "apk update", "")
		if err != nil || code != 0 {
			return nil, fmt.Errorf("apk update failed (exit %d): %s %v", code, stderr, err)
		}
		r.installedMu.Lock()
		r.installed["__apk_index__"] = true
		r.installedMu.Unlock()
	}

	// Install packages.
	cmd := "apk add --no-cache " + strings.Join(toInstall, " ")
	installCtx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()

	_, stderr, code, execErr := r.Exec(installCtx, cmd, "")
	if execErr != nil || code != 0 {
		return nil, fmt.Errorf("apk add failed (exit %d): %s %v", code, stderr, execErr)
	}

	r.installedMu.Lock()
	for _, pkg := range toInstall {
		r.installed[pkg] = true
	}
	r.installedMu.Unlock()

	return toInstall, nil
}

// IsReady checks if the proot runtime is bootstrapped and functional.
// Runs a simple `echo ok` inside the environment.
func (r *ProotRuntime) IsReady(ctx context.Context) bool {
	checkCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	stdout, _, code, err := r.Exec(checkCtx, "echo ok", "")
	return err == nil && code == 0 && strings.TrimSpace(stdout) == "ok"
}

// RootFSSize returns the total size of the Alpine rootfs in bytes.
func (r *ProotRuntime) RootFSSize() (int64, error) {
	var total int64
	err := filepath.Walk(r.RootFS, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip errors (permission denied, etc.)
		}
		if !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total, err
}
