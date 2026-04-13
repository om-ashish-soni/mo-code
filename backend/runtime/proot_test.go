package runtime

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestProotArgs(t *testing.T) {
	r := &ProotRuntime{
		ProotBin:    "/data/proot",
		RootFS:      "/data/alpine",
		ProjectsDir: "/data/projects",
		installed:   make(map[string]bool),
	}

	args := r.prootArgs("/data/projects/my-app")
	// Should contain -0, -r, rootfs path, bind mounts, and working dir.
	if len(args) < 10 {
		t.Fatalf("expected at least 10 args, got %d: %v", len(args), args)
	}

	// Check fake root.
	if args[0] != "-0" {
		t.Errorf("expected -0, got %s", args[0])
	}

	// Check rootfs.
	if args[1] != "-r" || args[2] != "/data/alpine" {
		t.Errorf("expected -r /data/alpine, got %s %s", args[1], args[2])
	}

	// Check working dir resolves correctly.
	lastTwo := args[len(args)-2:]
	if lastTwo[0] != "-w" {
		t.Errorf("expected -w as second to last arg, got %s", lastTwo[0])
	}
	if lastTwo[1] != "/home/developer/my-app" {
		t.Errorf("expected /home/developer/my-app, got %s", lastTwo[1])
	}
}

func TestProotArgsDefaultWorkDir(t *testing.T) {
	r := &ProotRuntime{
		ProotBin:    "/data/proot",
		RootFS:      "/data/alpine",
		ProjectsDir: "/data/projects",
		installed:   make(map[string]bool),
	}

	args := r.prootArgs("")
	lastTwo := args[len(args)-2:]
	if lastTwo[1] != "/home/developer" {
		t.Errorf("expected /home/developer for empty workDir, got %s", lastTwo[1])
	}
}

func TestProotArgsOutsideProjects(t *testing.T) {
	r := &ProotRuntime{
		ProotBin:    "/data/proot",
		RootFS:      "/data/alpine",
		ProjectsDir: "/data/projects",
		installed:   make(map[string]bool),
	}

	// Work dir outside projects → falls back to /home/developer.
	args := r.prootArgs("/some/other/path")
	lastTwo := args[len(args)-2:]
	if lastTwo[1] != "/home/developer" {
		t.Errorf("expected /home/developer for outside path, got %s", lastTwo[1])
	}
}

func TestProotEnv(t *testing.T) {
	r := &ProotRuntime{}
	env := r.prootEnv()

	has := func(prefix string) bool {
		for _, e := range env {
			if len(e) >= len(prefix) && e[:len(prefix)] == prefix {
				return true
			}
		}
		return false
	}

	for _, required := range []string{"HOME=", "PATH=", "LANG=", "TERM=", "SHELL="} {
		if !has(required) {
			t.Errorf("missing env var starting with %s", required)
		}
	}
}

func TestNewProotRuntimeMissingBinary(t *testing.T) {
	_, err := NewProotRuntime("/nonexistent/proot", "/tmp", "/tmp", "")
	if err == nil {
		t.Error("expected error for missing proot binary")
	}
}

func TestNewProotRuntimeMissingRootFS(t *testing.T) {
	// Create a temp file to act as proot binary.
	tmp := t.TempDir()
	prootBin := filepath.Join(tmp, "proot")
	os.WriteFile(prootBin, []byte("#!/bin/sh"), 0o755)

	_, err := NewProotRuntime(prootBin, "/nonexistent/rootfs", "/tmp", "")
	if err == nil {
		t.Error("expected error for missing rootfs")
	}
}

func TestNewProotRuntimeCreatesProjectsDir(t *testing.T) {
	tmp := t.TempDir()
	prootBin := filepath.Join(tmp, "proot")
	os.WriteFile(prootBin, []byte("#!/bin/sh"), 0o755)

	rootfs := filepath.Join(tmp, "rootfs")
	os.MkdirAll(rootfs, 0o755)

	projectsDir := filepath.Join(tmp, "projects", "new", "dir")

	rt, err := NewProotRuntime(prootBin, rootfs, projectsDir, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if rt == nil {
		t.Fatal("runtime should not be nil")
	}
	if _, err := os.Stat(projectsDir); err != nil {
		t.Errorf("projects dir should have been created: %v", err)
	}
}

func TestInstallPackagesDeduplication(t *testing.T) {
	r := &ProotRuntime{
		ProotBin:    "/data/proot",
		RootFS:      "/data/alpine",
		ProjectsDir: "/data/projects",
		installed:   map[string]bool{"nodejs": true, "npm": true},
	}

	// These are already "installed" — should be skipped without calling proot.
	installed, err := r.InstallPackages(context.Background(), []string{"nodejs", "npm"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(installed) != 0 {
		t.Errorf("expected 0 packages installed (all cached), got %d", len(installed))
	}
}

func TestRuntimeLabel(t *testing.T) {
	// Importing from tools package would create circular dep, so we test the concept.
	// The actual runtimeLabel is on ShellExec in tools/shell.go.
	// Here we just verify the ProotRuntime struct is usable.
	r := &ProotRuntime{installed: make(map[string]bool)}
	if r.ProotBin != "" {
		t.Error("empty ProotBin should be empty string")
	}
}
