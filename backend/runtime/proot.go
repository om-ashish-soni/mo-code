// Package runtime provides the proot + Alpine Linux execution environment
// for running shell commands on Android without root access.
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

	// LoaderBin is the path to the proot loader binary.
	// On Android, rootfs binaries have app_data_file SELinux context which
	// cannot be exec'd directly. The loader (in nativeLibraryDir, apk_data_file
	// context) uses mmap to run binaries, bypassing the SELinux exec restriction.
	// Empty string = proot extracts its built-in loader (may fail on Android).
	LoaderBin string

	// installed tracks which apk packages have been installed in this session.
	installed   map[string]bool
	installedMu sync.RWMutex
}

// NewProotRuntime creates a runtime given paths to the proot binary,
// Alpine rootfs, and the projects directory on the host.
// loaderBin is the optional path to the proot-loader binary (empty = use built-in).
// Returns an error if required paths don't exist.
func NewProotRuntime(prootBin, rootFS, projectsDir, loaderBin string) (*ProotRuntime, error) {
	if _, err := os.Stat(prootBin); err != nil {
		return nil, fmt.Errorf("proot binary not found: %s", prootBin)
	}
	// Ensure execute permission (may be lost across app updates on Android).
	_ = os.Chmod(prootBin, 0o755)
	if _, err := os.Stat(rootFS); err != nil {
		return nil, fmt.Errorf("alpine rootfs not found: %s", rootFS)
	}
	if _, err := os.Stat(projectsDir); err != nil {
		// Create projects dir if it doesn't exist.
		if mkErr := os.MkdirAll(projectsDir, 0o755); mkErr != nil {
			return nil, fmt.Errorf("cannot create projects dir: %s: %v", projectsDir, mkErr)
		}
	}

	// Write resolv.conf inside rootfs so DNS works inside proot.
	// Use MOCODE_DNS env (set by Android DaemonService) or fallback to Google DNS.
	resolvPath := filepath.Join(rootFS, "etc", "resolv.conf")
	dnsServers := os.Getenv("MOCODE_DNS")
	if dnsServers == "" {
		dnsServers = "8.8.8.8,8.8.4.4"
	}
	var resolvContent strings.Builder
	for _, srv := range strings.Split(dnsServers, ",") {
		srv = strings.TrimSpace(srv)
		if srv != "" {
			resolvContent.WriteString("nameserver " + srv + "\n")
		}
	}
	_ = os.WriteFile(resolvPath, []byte(resolvContent.String()), 0o644)

	r := &ProotRuntime{
		ProotBin:    prootBin,
		RootFS:      rootFS,
		ProjectsDir: projectsDir,
		installed:   make(map[string]bool),
	}
	if loaderBin != "" {
		if _, err := os.Stat(loaderBin); err == nil {
			_ = os.Chmod(loaderBin, 0o755)
			r.LoaderBin = loaderBin
		}
	}
	return r, nil
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

	args := []string{
		"-0",                                    // fake root
		"-r", r.RootFS,                          // rootfs
		"-b", "/dev",                            // bind /dev
		"-b", "/proc",                           // bind /proc
		"-b", "/sys",                            // bind /sys
		"-b", r.ProjectsDir + ":/home/developer", // bind projects
	}
	// Bind host resolv.conf if it exists; otherwise rely on rootfs copy.
	if _, err := os.Stat("/etc/resolv.conf"); err == nil {
		args = append(args, "-b", "/etc/resolv.conf:/etc/resolv.conf")
	}
	// -w must come last so test assertions (and proot arg parsing) are stable.
	args = append(args, "-w", prootWorkDir)
	return args
}

// Exec runs a shell command inside the proot environment.
// The command runs as: proot [args] /bin/sh -c "<command>"
func (r *ProotRuntime) Exec(ctx context.Context, command, workDir string) (stdout, stderr string, exitCode int, err error) {
	args := r.prootArgs(workDir)
	args = append(args, "/bin/sh", "-c", command)

	cmd := exec.CommandContext(ctx, r.ProotBin, args...)
	cmd.Env = r.prootEnv()

	log.Printf("[proot] exec: %s %s", r.ProotBin, strings.Join(args, " "))

	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf

	runErr := cmd.Run()

	stdout = outBuf.String()
	stderr = errBuf.String()
	exitCode = 0

	if runErr != nil {
		if ctx.Err() == context.DeadlineExceeded {
			log.Printf("[proot] timeout: %s", command)
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
		log.Printf("[proot] FAILED exit=%d err=%v cmd=%q", exitCode, err, command)
		if stderr != "" {
			log.Printf("[proot] stderr: %s", strings.TrimSpace(stderr))
		}
	}

	return stdout, stderr, exitCode, err
}

// prootEnv returns the environment variables for the proot process.
// Includes both host-side vars (PROOT_TMP_DIR, LD_LIBRARY_PATH) and guest-side vars.
func (r *ProotRuntime) prootEnv() []string {
	env := []string{
		"HOME=/home/developer",
		"USER=developer",
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
		"LANG=C.UTF-8",
		"TERM=xterm-256color",
		"SHELL=/bin/sh",
		// Force ptrace mode — Android restricts seccomp-based interception.
		"PROOT_NO_SECCOMP=1",
	}

	// LD_LIBRARY_PATH: Termux proot is dynamically linked against libtalloc.so.
	// nativeLibraryDir is the only executable + writable-at-install location.
	// Android linker checks LD_LIBRARY_PATH before RUNPATH in the binary.
	nativeLibDir := filepath.Dir(r.ProotBin)
	env = append(env, "LD_LIBRARY_PATH="+nativeLibDir)

	// PROOT_LOADER: rootfs binaries have app_data_file SELinux context which
	// blocks direct execve from untrusted_app. The loader (apk_data_file in
	// nativeLibraryDir) uses mmap to exec binaries, bypassing SELinux exec check.
	if r.LoaderBin != "" {
		env = append(env, "PROOT_LOADER="+r.LoaderBin)
		log.Printf("[proot] env: loader=%s nativeLibDir=%s", r.LoaderBin, nativeLibDir)
	} else {
		log.Printf("[proot] WARNING: no PROOT_LOADER set — SELinux exec will likely fail on Android")
	}

	// PROOT_TMP_DIR: proot needs a writable tmp dir on the host.
	tmpDir := os.Getenv("TMPDIR")
	if tmpDir == "" {
		tmpDir = filepath.Join(r.RootFS, "tmp")
	}
	_ = os.MkdirAll(tmpDir, 0o755)
	env = append(env, "PROOT_TMP_DIR="+tmpDir)
	return env
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
