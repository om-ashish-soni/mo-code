package sandbox

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"sync"
)

// ErrNoPackageManager is returned by backends that cannot install packages at runtime.
var ErrNoPackageManager = errors.New("sandbox: backend has no runtime package manager")

// ErrBackendUnavailable is returned by Factory when a backend can't run on this device.
var ErrBackendUnavailable = errors.New("sandbox: backend unavailable on this device")

// Config carries per-backend configuration parsed from mo-code's TOML/env.
// Backends receive only the keys that concern them via Factory.
type Config struct {
	// Backend is the requested backend name. "auto" means use FallbackChain.
	Backend string

	// FallbackChain is the ordered list of backends to try when Backend=="auto".
	// Registry walks the chain and picks the first that returns (Sandbox, nil).
	FallbackChain []string

	// Options is a free-form map of backend-specific settings.
	// Example: {"qemu.memory_mb": "1024", "proot.rootfs": "/path/to/tarball"}.
	Options map[string]string
}

// Factory builds a Sandbox for a given Config.
// Implementations may return ErrBackendUnavailable when hardware/OS support is missing.
type Factory func(ctx context.Context, cfg Config) (Sandbox, error)

var (
	registryMu sync.RWMutex
	factories  = map[string]Factory{}
)

// Register makes a backend available under its name.
// Safe to call from init() in backend subpackages.
func Register(name string, factory Factory) {
	registryMu.Lock()
	defer registryMu.Unlock()
	if _, exists := factories[name]; exists {
		panic(fmt.Sprintf("sandbox: backend %q already registered", name))
	}
	factories[name] = factory
}

// Names lists all registered backend names in stable (sorted) order.
func Names() []string {
	registryMu.RLock()
	defer registryMu.RUnlock()
	names := make([]string, 0, len(factories))
	for n := range factories {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// Open returns a ready-to-use Sandbox per the config.
// When cfg.Backend == "auto", walks cfg.FallbackChain and returns the first
// backend whose Factory succeeds. Does NOT call Prepare — caller decides when.
func Open(ctx context.Context, cfg Config) (Sandbox, error) {
	if cfg.Backend != "" && cfg.Backend != "auto" {
		return openOne(ctx, cfg.Backend, cfg)
	}

	chain := cfg.FallbackChain
	if len(chain) == 0 {
		chain = []string{"avf", "qemu-tcg", "termux", "proot-hardened"}
	}

	var lastErr error
	for _, name := range chain {
		sb, err := openOne(ctx, name, cfg)
		if err == nil {
			return sb, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = fmt.Errorf("no backends registered")
	}
	return nil, fmt.Errorf("sandbox: no backend available from chain %v: %w", chain, lastErr)
}

func openOne(ctx context.Context, name string, cfg Config) (Sandbox, error) {
	registryMu.RLock()
	factory, ok := factories[name]
	registryMu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("sandbox: backend %q not registered: %w", name, ErrBackendUnavailable)
	}
	sb, err := factory(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("sandbox: backend %q factory: %w", name, err)
	}
	return sb, nil
}
