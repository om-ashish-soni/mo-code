package qemu

import (
	"context"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"mo-code/backend/sandbox"
)

// TestFactoryValidatesOptions covers the config parsing paths that do not
// need a real qemu binary to exercise.
func TestFactoryValidatesOptions(t *testing.T) {
	t.Parallel()

	// Missing required options.
	if _, err := Factory(context.Background(), sandbox.Config{}); err == nil {
		t.Fatal("expected error for empty options, got nil")
	}

	tmp := t.TempDir()
	bin := tmp + "/fake-qemu"
	img := tmp + "/fake.qcow2"
	must(t, os.WriteFile(bin, []byte("#!/bin/sh\nexit 0\n"), 0o755))
	must(t, os.WriteFile(img, []byte{}, 0o644))

	// Happy path parse — factory must succeed even though the binary is a stub.
	_, err := Factory(context.Background(), sandbox.Config{Options: map[string]string{
		"qemu.bin":      bin,
		"qemu.image":    img,
		"qemu.data_dir": tmp + "/data",
		"qemu.memory_mb": "768",
	}})
	if err != nil {
		t.Fatalf("factory with valid options: %v", err)
	}

	// Reject non-absolute paths.
	_, err = Factory(context.Background(), sandbox.Config{Options: map[string]string{
		"qemu.bin":      "fake-qemu",
		"qemu.image":    img,
		"qemu.data_dir": tmp,
	}})
	if err == nil {
		t.Fatal("expected abs-path rejection for qemu.bin, got nil")
	}
}

// TestCapabilities is a spec test: the track contract nails these numbers.
func TestCapabilities(t *testing.T) {
	t.Parallel()
	b := &Backend{}
	c := b.Capabilities()
	if !c.PackageManager || !c.FullPOSIX || !c.Network || !c.RootLikeSudo {
		t.Fatalf("capabilities booleans wrong: %+v", c)
	}
	if c.SpeedFactor != 20.0 {
		t.Fatalf("SpeedFactor = %v, want 20.0", c.SpeedFactor)
	}
	if c.IsolationTier != 3 {
		t.Fatalf("IsolationTier = %d, want 3", c.IsolationTier)
	}
	if b.Name() != "qemu-tcg" {
		t.Fatalf("Name = %q", b.Name())
	}
}

// TestRegistryRegistered verifies init() hooks qemu-tcg into the registry.
func TestRegistryRegistered(t *testing.T) {
	t.Parallel()
	if !slices.Contains(sandbox.Names(), "qemu-tcg") {
		t.Fatalf("qemu-tcg not registered; registry has %v", sandbox.Names())
	}
}

func TestExecBeforePrepareFails(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	bin := tmp + "/fake-qemu"
	img := tmp + "/fake.qcow2"
	must(t, os.WriteFile(bin, []byte("#!/bin/sh\nexit 0\n"), 0o755))
	must(t, os.WriteFile(img, []byte{}, 0o644))

	sb, err := Factory(context.Background(), sandbox.Config{Options: map[string]string{
		"qemu.bin":      bin,
		"qemu.image":    img,
		"qemu.data_dir": tmp + "/d",
	}})
	if err != nil {
		t.Fatal(err)
	}
	_, _, code, err := sb.Exec(context.Background(), "echo hi", "")
	if err == nil || code != -1 {
		t.Fatalf("Exec before Prepare: want error+code=-1, got err=%v code=%d", err, code)
	}
	if !strings.Contains(err.Error(), "not prepared") {
		t.Fatalf("error should mention 'not prepared', got: %v", err)
	}
}

// TestQemuIntegration boots a real VM and exercises Exec + InstallPackage.
// Skipped unless MOCODE_QEMU_BIN and MOCODE_QEMU_IMAGE point at real artifacts.
// This is the track's end-to-end acceptance test.
func TestQemuIntegration(t *testing.T) {
	bin := os.Getenv("MOCODE_QEMU_BIN")
	img := os.Getenv("MOCODE_QEMU_IMAGE")
	if bin == "" || img == "" {
		t.Skip("MOCODE_QEMU_BIN / MOCODE_QEMU_IMAGE not set — skipping integration test")
	}
	if _, err := os.Stat(bin); err != nil {
		t.Skipf("qemu binary not present: %v", err)
	}
	if _, err := os.Stat(img); err != nil {
		t.Skipf("qemu image not present: %v", err)
	}

	data := t.TempDir()
	opts := map[string]string{
		"qemu.bin":          bin,
		"qemu.image":        img,
		"qemu.data_dir":     data,
		"qemu.ssh_port":     "24422",
		"qemu.boot_timeout": "120s",
	}
	if v := os.Getenv("MOCODE_QEMU_SSH_PASS"); v != "" {
		opts["qemu.ssh_pass"] = v
	}

	sb, err := Factory(context.Background(), sandbox.Config{Options: opts})
	if err != nil {
		t.Fatalf("Factory: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	if err := sb.Prepare(ctx); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	t.Cleanup(func() {
		teardownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = sb.Teardown(teardownCtx)
	})

	if !sb.IsReady(ctx) {
		t.Fatal("IsReady returned false after successful Prepare")
	}

	stdout, _, code, err := sb.Exec(ctx, "echo ok", "")
	if err != nil {
		t.Fatalf("Exec echo: %v", err)
	}
	if code != 0 {
		t.Fatalf("echo exit code = %d, want 0", code)
	}
	if strings.TrimSpace(stdout) != "ok" {
		t.Fatalf("echo stdout = %q, want %q", stdout, "ok")
	}

	// apk add python3 — the headline acceptance case.
	installed, err := sb.InstallPackage(ctx, []string{"python3"})
	if err != nil {
		t.Fatalf("InstallPackage python3: %v", err)
	}
	if len(installed) != 1 || installed[0] != "python3" {
		t.Fatalf("InstallPackage returned %v, want [python3]", installed)
	}

	// Prove python3 actually runs.
	stdout, _, code, err = sb.Exec(ctx, "python3 -c 'print(1+1)'", "")
	if err != nil {
		t.Fatalf("Exec python3: %v", err)
	}
	if code != 0 || strings.TrimSpace(stdout) != "2" {
		t.Fatalf("python3 output: code=%d stdout=%q", code, stdout)
	}

	d := sb.Diagnose(ctx)
	if !d.OK {
		t.Fatalf("Diagnose not OK: %+v", d)
	}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}
