// Package proot adapts the existing backend/runtime.ProotRuntime to the
// sandbox.Sandbox interface. No logic moves here — this is a thin wrapper
// so the rest of the system can talk to proot through the generic backend API.
package proot

import (
	"context"
	"fmt"

	"mo-code/backend/runtime"
	"mo-code/backend/sandbox"
)

const backendName = "proot-hardened"

// Backend wraps *runtime.ProotRuntime to satisfy sandbox.Sandbox.
type Backend struct {
	rt *runtime.ProotRuntime
}

// Factory is the sandbox.Factory for the proot backend.
// Requires cfg.Options["proot.bin"], ["proot.rootfs"], ["proot.projects"].
// Optional: ["proot.loader"].
func Factory(_ context.Context, cfg sandbox.Config) (sandbox.Sandbox, error) {
	bin := cfg.Options["proot.bin"]
	rootfs := cfg.Options["proot.rootfs"]
	projects := cfg.Options["proot.projects"]
	if bin == "" || rootfs == "" || projects == "" {
		return nil, fmt.Errorf("proot: missing required options (proot.bin, proot.rootfs, proot.projects)")
	}
	loader := cfg.Options["proot.loader"]

	rt, err := runtime.NewProotRuntime(bin, rootfs, projects, loader)
	if err != nil {
		return nil, err
	}
	return &Backend{rt: rt}, nil
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
		RootLikeSudo:   true, // fakeroot via proot -0
		SpeedFactor:    1.3,
		IsolationTier:  2,
	}
}

func (b *Backend) Prepare(_ context.Context) error {
	return nil
}

func (b *Backend) Exec(ctx context.Context, command, workDir string) (string, string, int, error) {
	return b.rt.Exec(ctx, command, workDir)
}

func (b *Backend) InstallPackage(ctx context.Context, packages []string) ([]string, error) {
	return b.rt.InstallPackages(ctx, packages)
}

func (b *Backend) IsReady(ctx context.Context) bool {
	return b.rt.IsReady(ctx)
}

func (b *Backend) Diagnose(ctx context.Context) sandbox.Diagnostic {
	r := b.rt.Diagnose(ctx)
	return sandbox.Diagnostic{
		OK:            r.OK,
		Backend:       backendName,
		IsolationTier: 2,
		Checks: map[string]bool{
			"bin_exists":     r.BinExists,
			"bin_executable": r.BinExecutable,
			"loader_exists":  r.LoaderExists,
			"rootfs_exists":  r.RootFSExists,
			"echo_ok":        r.EchoOK,
		},
		Error:   r.Error,
		Details: map[string]string{"isolation_tier_label": r.IsolationTier},
	}
}

func (b *Backend) Teardown(_ context.Context) error {
	return nil
}
