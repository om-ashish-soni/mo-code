package runtime

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// writeStub creates an empty executable file. Fatal on error.
func writeStub(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

// stagedBundle creates a minimal on-disk bundle layout that satisfies
// NewQemuRuntime's existence checks.
func stagedBundle(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	writeStub(t, filepath.Join(dir, "bin", "qemu-system-aarch64"))
	writeStub(t, filepath.Join(dir, "boot", "vmlinuz-virt"))
	writeStub(t, filepath.Join(dir, "boot", "initramfs-rootfs-py.cpio.gz"))
	writeStub(t, filepath.Join(dir, qemuExecScript))
	return dir
}

func TestNewQemuRuntimeMissingBundle(t *testing.T) {
	_, err := NewQemuRuntime("", "")
	if err == nil {
		t.Fatal("expected error for empty bundleDir")
	}
}

func TestNewQemuRuntimeMissingFile(t *testing.T) {
	dir := stagedBundle(t)
	// Remove the kernel to simulate a broken bundle.
	if err := os.Remove(filepath.Join(dir, "boot", "vmlinuz-virt")); err != nil {
		t.Fatalf("remove kernel: %v", err)
	}
	_, err := NewQemuRuntime(dir, "")
	if err == nil || !strings.Contains(err.Error(), "vmlinuz-virt") {
		t.Fatalf("expected vmlinuz-virt error, got %v", err)
	}
}

func TestNewQemuRuntimeOK(t *testing.T) {
	dir := stagedBundle(t)
	projects := filepath.Join(t.TempDir(), "projects")
	r, err := NewQemuRuntime(dir, projects)
	if err != nil {
		t.Fatalf("NewQemuRuntime: %v", err)
	}
	if r.BundleDir == "" || !filepath.IsAbs(r.BundleDir) {
		t.Errorf("expected absolute BundleDir, got %q", r.BundleDir)
	}
	if r.ExecTimeout <= 0 {
		t.Errorf("expected positive ExecTimeout default, got %v", r.ExecTimeout)
	}
	if r.ShellBin == "" {
		t.Errorf("expected non-empty ShellBin default")
	}
	if _, err := os.Stat(projects); err != nil {
		t.Errorf("projects dir should be created, got %v", err)
	}
	if r.IsolationTier() != "qemu-tcg" {
		t.Errorf("expected isolation tier qemu-tcg, got %q", r.IsolationTier())
	}
}

func TestQemuEnvIncludesTimeout(t *testing.T) {
	dir := stagedBundle(t)
	r, err := NewQemuRuntime(dir, "")
	if err != nil {
		t.Fatalf("NewQemuRuntime: %v", err)
	}
	r.ExecTimeout = 45 * time.Second

	env := r.qemuEnv()
	want := "QEMU_EXEC_TIMEOUT=45"
	if !slices.Contains(env, want) {
		t.Errorf("env missing %q; got %v", want, env)
	}
}

func TestInstallPackagesRejectedInBeta(t *testing.T) {
	dir := stagedBundle(t)
	r, err := NewQemuRuntime(dir, "")
	if err != nil {
		t.Fatalf("NewQemuRuntime: %v", err)
	}
	_, err = r.InstallPackages(context.TODO(), []string{"git"})
	if err == nil {
		t.Fatal("expected error from InstallPackages in v1 beta")
	}
}

func TestTruncate(t *testing.T) {
	cases := []struct {
		in   string
		max  int
		want string
	}{
		{"hello", 10, "hello"},
		{"hello", 5, "hello"},
		{"hello world", 5, "hello…"},
	}
	for _, tc := range cases {
		got := truncate(tc.in, tc.max)
		if got != tc.want {
			t.Errorf("truncate(%q, %d) = %q, want %q", tc.in, tc.max, got, tc.want)
		}
	}
}
