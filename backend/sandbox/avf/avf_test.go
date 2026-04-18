package avf

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"mo-code/backend/sandbox"
)

func TestFactory_ProbeUnavailable_ReturnsErrBackendUnavailable(t *testing.T) {
	defer OverrideProbe(func(context.Context, sandbox.Config) (Result, error) {
		return Result{Available: false, Reason: "no pKVM"}, nil
	})()

	sb, err := Factory(context.Background(), sandbox.Config{})
	if sb != nil {
		t.Fatalf("expected nil Sandbox, got %T", sb)
	}
	if !errors.Is(err, sandbox.ErrBackendUnavailable) {
		t.Fatalf("expected ErrBackendUnavailable, got %v", err)
	}
	if want := "no pKVM"; err == nil || !contains(err.Error(), want) {
		t.Fatalf("expected reason %q in error, got %v", want, err)
	}
}

func TestFactory_ProbeAvailable_ReturnsBackend(t *testing.T) {
	defer OverrideProbe(func(context.Context, sandbox.Config) (Result, error) {
		return Result{Available: true, Reason: ""}, nil
	})()

	sb, err := Factory(context.Background(), sandbox.Config{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if sb == nil {
		t.Fatal("expected non-nil Sandbox")
	}
	if sb.Name() != "avf-microdroid" {
		t.Fatalf("name = %q, want avf-microdroid", sb.Name())
	}
	caps := sb.Capabilities()
	if caps.IsolationTier != 3 || !caps.FullPOSIX || !caps.Network || !caps.RootLikeSudo || !caps.PackageManager {
		t.Fatalf("capabilities mismatch: %+v", caps)
	}
	if caps.SpeedFactor != 1.2 {
		t.Fatalf("SpeedFactor = %v, want 1.2", caps.SpeedFactor)
	}
}

func TestFactory_ProbeError_Propagates(t *testing.T) {
	sentinel := errors.New("probe blew up")
	defer OverrideProbe(func(context.Context, sandbox.Config) (Result, error) {
		return Result{}, sentinel
	})()

	_, err := Factory(context.Background(), sandbox.Config{})
	if !errors.Is(err, sentinel) {
		t.Fatalf("expected probe error to propagate, got %v", err)
	}
	if errors.Is(err, sandbox.ErrBackendUnavailable) {
		t.Fatal("probe errors must not be misclassified as ErrBackendUnavailable")
	}
}

func TestBridgeProbe_OptionsOverride(t *testing.T) {
	cfg := sandbox.Config{Options: map[string]string{
		"avf.available": "true",
		"avf.reason":    "forced on for tests",
	}}
	r, err := bridgeProbe(context.Background(), cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !r.Available || r.Reason != "forced on for tests" {
		t.Fatalf("got %+v", r)
	}
}

func TestBridgeProbe_NoSignal_ReportsUnavailable(t *testing.T) {
	t.Setenv("MOCODE_AVF_PROBE_FILE", "")
	r, err := bridgeProbe(context.Background(), sandbox.Config{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if r.Available {
		t.Fatal("expected unavailable when no probe signal present")
	}
}

func TestBridgeProbe_ReadsProbeFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "avf_probe.json")
	body, _ := json.Marshal(map[string]any{
		"available": true,
		"reason":    "pKVM ok",
	})
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := sandbox.Config{Options: map[string]string{"avf.probe_file": path}}
	r, err := bridgeProbe(context.Background(), cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !r.Available || r.Reason != "pKVM ok" {
		t.Fatalf("got %+v", r)
	}
}

func TestBridgeProbe_MissingFileIsUnavailable(t *testing.T) {
	cfg := sandbox.Config{Options: map[string]string{
		"avf.probe_file": filepath.Join(t.TempDir(), "does-not-exist.json"),
	}}
	r, err := bridgeProbe(context.Background(), cfg)
	if err != nil {
		t.Fatalf("missing file should be soft-fail, got error: %v", err)
	}
	if r.Available {
		t.Fatal("expected unavailable when file absent")
	}
}

func TestBridgeProbe_InvalidBoolErrors(t *testing.T) {
	cfg := sandbox.Config{Options: map[string]string{"avf.available": "yesno"}}
	if _, err := bridgeProbe(context.Background(), cfg); err == nil {
		t.Fatal("expected error for invalid bool")
	}
}

func TestBackend_RegisteredInRegistry(t *testing.T) {
	if !slices.Contains(sandbox.Names(), "avf-microdroid") {
		t.Fatal("avf-microdroid not registered with sandbox registry")
	}
}

func TestBackend_DiagnoseStubsReportNotImplemented(t *testing.T) {
	b := &Backend{probeReason: "ok"}
	d := b.Diagnose(context.Background())
	if d.OK {
		t.Fatal("Diagnose.OK should be false until VM boot lands")
	}
	if d.Backend != "avf-microdroid" {
		t.Fatalf("Backend = %q", d.Backend)
	}
	if d.Details["probe_reason"] != "ok" {
		t.Fatalf("probe_reason missing from details: %+v", d.Details)
	}
	if _, _, _, err := b.Exec(context.Background(), "echo hi", ""); err == nil {
		t.Fatal("Exec stub should return an error until VM boot lands")
	}
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
