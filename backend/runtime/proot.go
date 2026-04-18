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
	// Seed the installed map from the filesystem so we don't re-run apk add
	// on every daemon restart for packages that are already in the rootfs.
	for pkg := range packageBinaries {
		if r.packageInstalledOnDisk(pkg) {
			r.installed[pkg] = true
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

	// Isolation policy (v1.3 "proot-hardened" tier):
	//   - DO bind individual /dev/* char devices that are safe sinks/sources
	//     (null, zero, full, urandom, random, tty). These leak no host info.
	//   - DO bind /proc — most guest userland (sh, npm, python, busybox) reads
	//     /proc/self/* and breaks without it. /proc is the largest remaining
	//     leak vector (other-pid cmdline, /proc/net/tcp, daemon /maps); fixing
	//     it requires namespace isolation (v1.4 Shizuku+bwrap tier).
	//   - DO NOT bind /sys — Alpine userland rarely needs it and it leaks
	//     hardware/driver/cgroup paths. If a tool breaks, file it as bug.
	//   - DO NOT bind /dev wholesale — leaks block devices, input devices,
	//     binder, ashmem, etc.
	args := []string{}
	if os.Getenv("MOCODE_PROOT_VERBOSE") != "" {
		args = append(args, "-v", "1")
	}
	args = append(args,
		"-0",           // fake root
		"-r", r.RootFS, // rootfs
		"-b", r.ProjectsDir+":/home/developer", // user code
		"-b", "/proc", // see policy note above — leak vector, v1.4 target
	)
	for _, dev := range safeDevBinds {
		if _, err := os.Stat(dev); err == nil {
			args = append(args, "-b", dev)
		}
	}
	// Bind host resolv.conf if it exists; otherwise rely on rootfs copy.
	if _, err := os.Stat("/etc/resolv.conf"); err == nil {
		args = append(args, "-b", "/etc/resolv.conf:/etc/resolv.conf")
	}
	// -w must come last so test assertions (and proot arg parsing) are stable.
	args = append(args, "-w", prootWorkDir)
	return args
}

// safeDevBinds is the explicit allowlist of /dev entries bound into the guest.
// Each one is a stateless char device with no host-state leakage.
// Adding a new entry here is a security review — do not extend casually.
var safeDevBinds = []string{
	"/dev/null",
	"/dev/zero",
	"/dev/full",
	"/dev/random",
	"/dev/urandom",
	"/dev/tty",
}

// IsolationTier reports the active sandbox isolation strategy.
// Surfaced via /api/runtime/diagnose and the Flutter Config screen.
//
// Tiers (planned):
//   - "proot-hardened" (v1.3, current): proot+Alpine with /dev/sys host binds
//     stripped, only safe /dev/* entries, /proc still bound (leak vector).
//   - "bwrap-shizuku" (v1.4): bubblewrap in `shell` SELinux domain via Shizuku;
//     full user/net/pid/mount namespaces, slirp4netns "internet only".
//   - "avf-microdroid" (v2.0): hardware-isolated microVM via pKVM. Pixel only.
func (r *ProotRuntime) IsolationTier() string {
	return "proot-hardened"
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
		log.Printf("[proot] stderr(%d bytes): %q", len(stderr), strings.TrimSpace(stderr))
		log.Printf("[proot] stdout(%d bytes): %q", len(stdout), strings.TrimSpace(stdout))
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

	// nativeLibraryDir: Android's only location where files have apk_data_file SELinux
	// context, allowing mmap(PROT_EXEC). jniLibs are installed here automatically.
	nativeLibDir := filepath.Dir(r.ProotBin)

	// nativelinks: writable directory where we create symlinks from versioned .so names
	// (e.g. libpcre2-8.so.0) to the Android-compatible names in nativeLibDir
	// (e.g. libpcre2_8.so). musl ldso resolves these symlinks; the SELinux mmap check
	// hits the target file's apk_data_file context → PROT_EXEC allowed.
	// This unblocks dynamically-linked binaries (git, etc.) on Android 15.
	nativeLinksDir := filepath.Join(filepath.Dir(filepath.Dir(r.RootFS)), "nativelinks")
	r.setupNativeLinks(nativeLibDir, nativeLinksDir)

	// LD_LIBRARY_PATH: nativelinks first (versioned .so symlinks → apk_data_file targets),
	// then nativeLibDir (for any direct matches), then standard guest paths.
	env = append(env, "LD_LIBRARY_PATH="+nativeLinksDir+":"+nativeLibDir+":/usr/lib:/lib")

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

// nativeLinks maps Android-compatible jniLibs filenames (lib*.so) to the versioned
// SONAME that musl ldso actually searches for. The setup function creates symlinks
// in a writable directory so the versioned names resolve to apk_data_file targets.
//
// Android 15 SELinux W^X blocks mmap(PROT_EXEC) on app_data_file files (rootfs).
// Files in nativeLibraryDir have apk_data_file context and are executable.
// By symlinking versioned names → nativeLibDir files, the kernel's mmap check
// hits the target's apk_data_file context, bypassing the W^X restriction.
var nativeLinks = map[string]string{
	// libpcre2_8.so (jniLibs) ← libpcre2-8.so.0 (what git/grep/ripgrep NEED)
	"libpcre2_8.so": "libpcre2-8.so.0",
	// libz_1.so (jniLibs) ← libz.so.1 (what git, curl, many others NEED)
	"libz_1.so": "libz.so.1",
}

// setupNativeLinks creates a directory of versioned symlinks pointing from musl-expected
// names (e.g. libpcre2-8.so.0) to apk_data_file targets in nativeLibDir.
// Safe to call concurrently — uses atomic symlink replacement.
func (r *ProotRuntime) setupNativeLinks(nativeLibDir, nativeLinksDir string) {
	if err := os.MkdirAll(nativeLinksDir, 0o755); err != nil {
		log.Printf("[proot] setupNativeLinks: mkdir %s: %v", nativeLinksDir, err)
		return
	}
	for jniName, versionedName := range nativeLinks {
		target := filepath.Join(nativeLibDir, jniName)
		link := filepath.Join(nativeLinksDir, versionedName)
		// Skip if jniLibs file doesn't exist on this install.
		if _, err := os.Stat(target); err != nil {
			continue
		}
		// Create/replace symlink atomically: write to tmp then rename.
		tmp := link + ".tmp"
		_ = os.Remove(tmp)
		if err := os.Symlink(target, tmp); err != nil {
			log.Printf("[proot] symlink %s → %s: %v", versionedName, target, err)
			continue
		}
		if err := os.Rename(tmp, link); err != nil {
			log.Printf("[proot] rename symlink %s: %v", link, err)
			_ = os.Remove(tmp)
			continue
		}
		log.Printf("[proot] nativelink: %s → %s", versionedName, target)
	}
}

// packageBinaries maps apk package names to their expected binary paths inside the rootfs.
// Used by InstallPackages to skip packages whose binaries already exist on disk.
var packageBinaries = map[string]string{
	"git":     "usr/bin/git",
	"nodejs":  "usr/bin/node",
	"npm":     "usr/bin/npm",
	"python3": "usr/bin/python3",
	"curl":    "usr/bin/curl",
	"openssh": "usr/bin/ssh",
}

// packageInstalledOnDisk returns true if the package's binary already exists in the rootfs.
// This avoids running `apk add` after a daemon restart when packages persist in the rootfs.
func (r *ProotRuntime) packageInstalledOnDisk(pkg string) bool {
	rel, ok := packageBinaries[pkg]
	if !ok {
		return false
	}
	_, err := os.Stat(filepath.Join(r.RootFS, rel))
	return err == nil
}

// InstallPackages runs `apk add` for the given packages inside the proot environment.
// Skips packages that have already been installed in this session OR whose binaries
// already exist in the rootfs (persisted from a previous daemon run).
// Returns the list of packages that were actually installed.
func (r *ProotRuntime) InstallPackages(ctx context.Context, packages []string) (installed []string, err error) {
	var toInstall []string
	r.installedMu.RLock()
	for _, pkg := range packages {
		if !r.installed[pkg] && !r.packageInstalledOnDisk(pkg) {
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
		// Redirect apk stderr to a file inside the rootfs so we can see
		// it even if proot itself is killed by zygote seccomp before it
		// can propagate the child's stderr.
		errPath := filepath.Join(r.RootFS, "tmp", "apk-update.err")
		_ = os.MkdirAll(filepath.Dir(errPath), 0o755)
		_ = os.Remove(errPath)
		_, stderr, code, err := r.Exec(installCtx, "apk update 2>/tmp/apk-update.err", "")
		if err != nil || code != 0 {
			if body, rerr := os.ReadFile(errPath); rerr == nil && len(body) > 0 {
				log.Printf("[proot] apk-update.err: %q", strings.TrimSpace(string(body)))
			} else {
				log.Printf("[proot] apk-update.err: (no file; rerr=%v)", rerr)
			}
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

// DiagnosticResult holds the results of a proot runtime health check.
type DiagnosticResult struct {
	// OK is true when the full proot environment is functional.
	OK bool `json:"ok"`
	// BinExists is true when the proot binary file is present.
	BinExists bool `json:"bin_exists"`
	// BinExecutable is true when the proot binary has execute permission.
	BinExecutable bool `json:"bin_executable"`
	// LoaderExists is true when the loader binary is configured and present.
	LoaderExists bool `json:"loader_exists"`
	// RootFSExists is true when the rootfs directory is present.
	RootFSExists bool `json:"rootfs_exists"`
	// EchoOK is true when `echo ok` ran successfully inside proot.
	EchoOK bool `json:"echo_ok"`
	// ExitCode is the exit code from the echo test (-1 if not attempted).
	ExitCode int `json:"exit_code"`
	// Stderr is the stderr output from the echo test.
	Stderr string `json:"stderr,omitempty"`
	// Error is the human-readable failure description when OK is false.
	Error string `json:"error,omitempty"`
	// IsolationTier names the active sandbox strategy. See IsolationTier().
	IsolationTier string `json:"isolation_tier"`
}

// Diagnose runs a series of checks to determine whether the proot runtime is
// functional. Returns a DiagnosticResult with individual check results and a
// top-level OK flag. Safe to call from any goroutine.
func (r *ProotRuntime) Diagnose(ctx context.Context) DiagnosticResult {
	result := DiagnosticResult{ExitCode: -1, IsolationTier: r.IsolationTier()}

	// 1. Check proot binary.
	info, err := os.Stat(r.ProotBin)
	if err != nil {
		result.Error = fmt.Sprintf("proot binary not found: %s", r.ProotBin)
		return result
	}
	result.BinExists = true
	result.BinExecutable = info.Mode()&0o111 != 0

	// 2. Check loader binary (optional but required on Android).
	if r.LoaderBin != "" {
		if _, err := os.Stat(r.LoaderBin); err == nil {
			result.LoaderExists = true
		} else {
			log.Printf("[proot] diagnose: loader not found at %s", r.LoaderBin)
		}
	}

	// 3. Check rootfs directory.
	if _, err := os.Stat(r.RootFS); err != nil {
		result.Error = fmt.Sprintf("rootfs not found: %s", r.RootFS)
		return result
	}
	result.RootFSExists = true

	// 4. Functional test: run `echo ok` inside proot.
	checkCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	stdout, stderr, code, execErr := r.Exec(checkCtx, "echo ok", "")
	result.ExitCode = code
	result.Stderr = strings.TrimSpace(stderr)

	if execErr == nil && code == 0 && strings.TrimSpace(stdout) == "ok" {
		result.EchoOK = true
		result.OK = true
		return result
	}

	// Classify failure.
	if code == 255 && stdout == "" && stderr == "" {
		result.Error = "proot exited 255 with no output — Android 15 SELinux W^X restriction (ISSUE-010): " +
			"mmap(PROT_EXEC) on app_data_file binaries is blocked. " +
			"Fix: rebuild libproot-loader.so with memfd_create (MO-60)."
	} else if execErr != nil {
		result.Error = fmt.Sprintf("exec error: %v", execErr)
	} else {
		result.Error = fmt.Sprintf("echo test failed (exit %d): %s", code, strings.TrimSpace(stderr))
	}
	return result
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
