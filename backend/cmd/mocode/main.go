package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"mo-code/backend/agent"
	"mo-code/backend/api"
	agentctx "mo-code/backend/context"
	"mo-code/backend/provider"
	"mo-code/backend/runtime"
	"mo-code/backend/storage"
)

// initDNS overrides Go's default resolver when MOCODE_DNS is set.
// On Android the Go binary has no /etc/resolv.conf, so DNS falls back to
// [::1]:53 which doesn't exist. This reads comma-separated DNS servers
// (e.g. "8.8.8.8,8.8.4.4") from the env and dials them directly.
func initDNS() {
	dnsEnv := os.Getenv("MOCODE_DNS")
	if dnsEnv == "" {
		return
	}
	servers := strings.Split(dnsEnv, ",")
	for i := range servers {
		servers[i] = strings.TrimSpace(servers[i])
		if !strings.Contains(servers[i], ":") {
			servers[i] = servers[i] + ":53"
		}
	}
	log.Printf("DNS: using custom resolvers %v", servers)
	net.DefaultResolver = &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			d := net.Dialer{}
			var lastErr error
			for _, srv := range servers {
				conn, err := d.DialContext(ctx, "udp", srv)
				if err == nil {
					return conn, nil
				}
				lastErr = err
			}
			return nil, fmt.Errorf("all DNS servers failed: %w", lastErr)
		},
	}
}

func main() {
	initDNS()
	// Default port file: next to the binary, or project root via env.
	execPath, _ := os.Executable()
	portFile := filepath.Join(filepath.Dir(execPath), "daemon_port")
	if envPortFile := os.Getenv("MOCODE_PORT_FILE"); envPortFile != "" {
		portFile = envPortFile
	}

	// Create provider registry and configure with environment variables if available.
	registry := provider.NewRegistry()

	// Configure providers from environment variables if set.
	if claudeKey := os.Getenv("CLAUDE_API_KEY"); claudeKey != "" {
		registry.Configure("claude", provider.Config{APIKey: claudeKey})
	}
	if geminiKey := os.Getenv("GEMINI_API_KEY"); geminiKey != "" {
		registry.Configure("gemini", provider.Config{APIKey: geminiKey})
	}
	if copilotKey := os.Getenv("COPILOT_API_KEY"); copilotKey != "" {
		registry.Configure("copilot", provider.Config{APIKey: copilotKey})
	}
	if openrouterKey := os.Getenv("OPENROUTER_API_KEY"); openrouterKey != "" {
		registry.Configure("openrouter", provider.Config{APIKey: openrouterKey})
	}
	if ollamaURL := os.Getenv("OLLAMA_URL"); ollamaURL != "" {
		registry.Configure("ollama", provider.Config{APIKey: ollamaURL})
	} else {
		// Ollama is always configured (local, no key needed).
		registry.Configure("ollama", provider.Config{})
	}
	if azureKey := os.Getenv("AZURE_OPENAI_API_KEY"); azureKey != "" {
		model := os.Getenv("AZURE_OPENAI_DEPLOYMENT")
		registry.Configure("azure", provider.Config{APIKey: azureKey, Model: model})
	}

	// Load cached Copilot OAuth token from disk (persists across restarts).
	if auth := registry.CopilotAuth(); auth != nil {
		if auth.LoadToken() {
			log.Println("Copilot: loaded cached OAuth token from ~/.mocode/copilot_token.json")
		}
	}

	// Create the real agent engine.
	// Use MOCODE_WORKDIR env or default to current directory.
	workingDir, _ := os.Getwd()
	if envDir := os.Getenv("MOCODE_WORKDIR"); envDir != "" {
		workingDir = envDir
	}

	// Initialize session persistence under ~/.mocode/sessions.
	var sessions *agentctx.SessionStore
	storeDir, err := storage.DefaultDir()
	if err != nil {
		log.Printf("warning: could not init storage dir: %v (sessions disabled)", err)
	} else {
		sessions, err = agentctx.NewSessionStore(storeDir.Path(storage.DirSessions))
		if err != nil {
			log.Printf("warning: could not init session store: %v (sessions disabled)", err)
			sessions = nil
		} else {
			log.Printf("session store: %s (%d existing sessions)", storeDir.Path(storage.DirSessions), len(sessions.List()))
		}
	}

	// Initialize proot runtime if configured (Android: set by DaemonService).
	var proot *runtime.ProotRuntime
	prootBin := os.Getenv("MOCODE_PROOT_BIN")
	prootRootFS := os.Getenv("MOCODE_PROOT_ROOTFS")
	prootProjects := os.Getenv("MOCODE_PROOT_PROJECTS")
	if prootBin != "" && prootRootFS != "" {
		if prootProjects == "" {
			prootProjects = filepath.Join(workingDir, "projects")
		}
		var err error
		proot, err = runtime.NewProotRuntime(prootBin, prootRootFS, prootProjects)
		if err != nil {
			log.Printf("warning: proot runtime disabled: %v", err)
		} else {
			log.Printf("proot runtime: bin=%s rootfs=%s projects=%s", prootBin, prootRootFS, prootProjects)
			// Install essential packages in background (first launch only).
			go func() {
				essentials := []string{"git", "nodejs", "npm", "python3", "curl", "openssh"}
				log.Printf("proot: installing essential packages: %v", essentials)
				installed, installErr := proot.InstallPackages(context.Background(), essentials)
				if installErr != nil {
					log.Printf("warning: failed to install packages: %v", installErr)
				} else if len(installed) > 0 {
					log.Printf("proot: installed %v", installed)
				}
			}()
		}
	}

	engine := agent.NewEngine(registry, workingDir, sessions, proot)
	planEngine := agent.NewPlanEngine(registry, workingDir)

	server, err := api.Start(portFile, engine, registry, sessions, planEngine)
	if err != nil {
		log.Fatalf("start daemon: %v", err)
	}
	if proot != nil {
		server.SetProot(proot)
	}
	log.Printf("mo-code daemon listening on 127.0.0.1:%d", server.Port())
	log.Printf("port file: %s", portFile)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	if err := server.Close(); err != nil {
		log.Printf("shutdown error: %v", err)
	}
}
