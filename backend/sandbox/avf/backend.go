// Package avf is the mo-code sandbox backend that runs commands inside an
// Android Virtualization Framework (AVF) Microdroid VM.
//
// Status: capability probe + scaffold. The probe shipped in this package
// already routes the registry correctly on Pixel 7+ (available) vs OnePlus
// and other non-pKVM hardware (ErrBackendUnavailable, fallback chain takes
// over). VM boot via virtmgr/virtio-serial is stubbed — see the TODOs on
// Prepare/Exec — and lands in a follow-up PR.
//
// Bridge protocol: AvfProbe.kt (flutter/android/app/src/main/kotlin/...)
// writes a JSON file with shape {"available":bool,"reason":string} into
// `${context.filesDir}/avf_probe.json`. DaemonService passes that path to
// the daemon via the MOCODE_AVF_PROBE_FILE env var. The Factory below reads
// it (or cfg.Options["avf.probe_file"] / cfg.Options["avf.available"]) and
// either returns a Backend or wraps the reason in ErrBackendUnavailable.
package avf

import (
	"context"
	"errors"
	"fmt"

	"mo-code/backend/sandbox"
)

const backendName = "avf-microdroid"

// errVMBootNotImplemented is the placeholder returned by Exec/Prepare/etc.
// until real Microdroid plumbing lands. It is *not* sandbox.ErrBackendUnavailable
// — the backend *is* available; we just haven't wired the VM yet.
var errVMBootNotImplemented = errors.New("avf-microdroid: Microdroid VM boot not implemented (TODO)")

// Backend is the sandbox.Sandbox implementation backed by an AVF Microdroid VM.
type Backend struct {
	probeReason string
}

// Factory is the sandbox.Factory for the AVF backend. Returns
// sandbox.ErrBackendUnavailable (wrapped) when the Kotlin-side probe reports
// the device cannot run Microdroid; the registry then falls through to the
// next backend in the chain (qemu-tcg, proot-hardened, ...).
func Factory(ctx context.Context, cfg sandbox.Config) (sandbox.Sandbox, error) {
	res, err := defaultProbe(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("avf: probe failed: %w", err)
	}
	if !res.Available {
		return nil, fmt.Errorf("avf: %s: %w", res.Reason, sandbox.ErrBackendUnavailable)
	}
	return &Backend{probeReason: res.Reason}, nil
}

func init() {
	sandbox.Register(backendName, Factory)
}

func (b *Backend) Name() string { return backendName }

func (b *Backend) Capabilities() sandbox.Capabilities {
	return sandbox.Capabilities{
		PackageManager: true,
		FullPOSIX:      true,
		Network:        true,
		RootLikeSudo:   true,
		SpeedFactor:    1.2,
		IsolationTier:  3,
	}
}

// Prepare boots the Microdroid VM and waits for the guest agent to be
// reachable over virtio-serial. TODO: implement once virtmgr packaging lands.
func (b *Backend) Prepare(_ context.Context) error {
	return errVMBootNotImplemented
}

// Exec runs a command inside the Microdroid VM via the virtio-serial channel.
// TODO: implement once Prepare brings a VM up.
func (b *Backend) Exec(_ context.Context, _, _ string) (string, string, int, error) {
	return "", "", -1, errVMBootNotImplemented
}

// InstallPackage runs apt inside the Microdroid guest.
// TODO: implement once Exec is wired.
func (b *Backend) InstallPackage(_ context.Context, _ []string) ([]string, error) {
	return nil, errVMBootNotImplemented
}

// IsReady reports whether the Microdroid VM is booted and reachable.
// TODO: probe the virtio-serial heartbeat.
func (b *Backend) IsReady(_ context.Context) bool { return false }

func (b *Backend) Diagnose(_ context.Context) sandbox.Diagnostic {
	return sandbox.Diagnostic{
		OK:            false,
		Backend:       backendName,
		IsolationTier: 3,
		Checks: map[string]bool{
			"probe_available": true,
			"vm_booted":       false,
		},
		Error: errVMBootNotImplemented.Error(),
		Details: map[string]string{
			"probe_reason": b.probeReason,
		},
	}
}

func (b *Backend) Teardown(_ context.Context) error { return nil }
