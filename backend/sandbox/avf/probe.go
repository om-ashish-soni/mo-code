package avf

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"strconv"

	"mo-code/backend/sandbox"
)

// Result is the AVF capability snapshot produced by the Kotlin-side
// AvfProbe and consumed by the Go-side Factory. Reason is human-readable
// (e.g. "API 33 < 34", "android.software.virtualization_framework not present")
// and surfaces in Diagnose() and registry-fallback logs.
type Result struct {
	Available bool
	Reason    string
}

// Probe is the indirection that lets tests substitute a fake. The default
// implementation reads the result the Kotlin layer wrote at app startup; see
// the package doc on backend.go for the bridge protocol.
type Probe func(ctx context.Context, cfg sandbox.Config) (Result, error)

// defaultProbe is the production probe. Tests swap this via OverrideProbe.
var defaultProbe Probe = bridgeProbe

// OverrideProbe replaces the package-level probe and returns a restore func.
// Intended for tests: defer OverrideProbe(fake)().
func OverrideProbe(p Probe) func() {
	prev := defaultProbe
	defaultProbe = p
	return func() { defaultProbe = prev }
}

// bridgeProbe resolves the AVF result from, in priority order:
//  1. cfg.Options["avf.available"]   — explicit override (tests, forced configs)
//  2. cfg.Options["avf.probe_file"]  — JSON written by AvfProbe.probeAndPersist
//  3. env MOCODE_AVF_PROBE_FILE      — same JSON, same shape
//
// When none is set we report unavailable rather than erroring, so non-Pixel
// devices register the backend cleanly and the Factory simply returns
// ErrBackendUnavailable to the registry.
func bridgeProbe(_ context.Context, cfg sandbox.Config) (Result, error) {
	if v := cfg.Options["avf.available"]; v != "" {
		ok, err := strconv.ParseBool(v)
		if err != nil {
			return Result{}, fmt.Errorf("avf: invalid avf.available=%q: %w", v, err)
		}
		return Result{Available: ok, Reason: cfg.Options["avf.reason"]}, nil
	}

	path := cfg.Options["avf.probe_file"]
	if path == "" {
		path = os.Getenv("MOCODE_AVF_PROBE_FILE")
	}
	if path == "" {
		return Result{Available: false, Reason: "no AVF probe result available (Kotlin probe not run)"}, nil
	}
	return readProbeFile(path)
}

func readProbeFile(path string) (Result, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return Result{Available: false, Reason: fmt.Sprintf("probe file %s not present", path)}, nil
		}
		return Result{}, fmt.Errorf("avf: read probe file %s: %w", path, err)
	}
	var raw struct {
		Available bool   `json:"available"`
		Reason    string `json:"reason"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		return Result{}, fmt.Errorf("avf: parse probe file %s: %w", path, err)
	}
	return Result{Available: raw.Available, Reason: raw.Reason}, nil
}
