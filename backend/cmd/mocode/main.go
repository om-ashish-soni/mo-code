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
	"time"

	"mo-code/backend/agent"
	"mo-code/backend/api"
	agentctx "mo-code/backend/context"
	"mo-code/backend/provider"
	"mo-code/backend/runtime"
	"mo-code/backend/storage"
	"mo-code/backend/tools"
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
	prootLoader := os.Getenv("MOCODE_PROOT_LOADER")
	if prootBin != "" && prootRootFS != "" {
		if prootProjects == "" {
			prootProjects = filepath.Join(workingDir, "projects")
		}
		var err error
		proot, err = runtime.NewProotRuntime(prootBin, prootRootFS, prootProjects, prootLoader)
		if err != nil {
			log.Printf("warning: proot runtime disabled: %v", err)
		} else {
			log.Printf("proot runtime: bin=%s rootfs=%s projects=%s loader=%s", prootBin, prootRootFS, prootProjects, prootLoader)
			// Run startup diagnostics then install essential packages in background.
			go func() {
				diag := proot.Diagnose(context.Background())
				if diag.OK {
					log.Printf("proot: startup check OK (echo ok passed)")
				} else {
					log.Printf("proot: startup check FAILED — %s", diag.Error)
					log.Printf("proot: diagnostic detail: bin_exists=%v bin_executable=%v loader_exists=%v rootfs_exists=%v echo_ok=%v exit_code=%d stderr=%q",
						diag.BinExists, diag.BinExecutable, diag.LoaderExists, diag.RootFSExists, diag.EchoOK, diag.ExitCode, diag.Stderr)
					// Don't install packages if the runtime is broken — apk would fail too.
					return
				}
				essentials := []string{"git", "nodejs", "npm", "python3", "curl", "openssh"}
				log.Printf("proot: installing essential packages: %v", essentials)
				var installErr error
				var installed []string
				for attempt := 1; attempt <= 3; attempt++ {
					installed, installErr = proot.InstallPackages(context.Background(), essentials)
					if installErr == nil {
						break
					}
					log.Printf("proot: package install attempt %d/3 failed: %v", attempt, installErr)
					if attempt < 3 {
						time.Sleep(time.Duration(attempt*5) * time.Second)
					}
				}
				if installErr != nil {
					log.Printf("warning: failed to install packages after 3 attempts: %v", installErr)
				} else if len(installed) > 0 {
					log.Printf("proot: installed %v", installed)
				} else {
					log.Printf("proot: all essential packages already present in rootfs")
				}
			}()
		}
	}

	// Initialize qemu-tcg runtime if configured (Android: stronger isolation than proot).
	// When both are set, qemu wins for shell_exec; proot is still used for git tools.
	var qemu *runtime.QemuRuntime
	qemuBundle := os.Getenv("MOCODE_QEMU_BUNDLE")
	qemuProjects := os.Getenv("MOCODE_QEMU_PROJECTS")
	if qemuBundle != "" {
		if qemuProjects == "" {
			qemuProjects = filepath.Join(workingDir, "projects")
		}
		var err error
		qemu, err = runtime.NewQemuRuntime(qemuBundle, qemuProjects)
		if err != nil {
			log.Printf("warning: qemu runtime disabled: %v", err)
		} else {
			log.Printf("qemu runtime: bundle=%s projects=%s", qemuBundle, qemuProjects)
			go func() {
				diag := qemu.Diagnose(context.Background())
				if diag.OK {
					log.Printf("qemu: startup check OK (boot=%dms, python-ok)", diag.BootMillis)
				} else {
					log.Printf("qemu: startup check FAILED — %s", diag.Error)
					log.Printf("qemu: diagnostic detail: qemu_bin=%v kernel=%v initramfs=%v script=%v echo_ok=%v python_ok=%v",
						diag.QemuBinExists, diag.KernelExists, diag.InitramfsFound, diag.ScriptExists, diag.EchoOK, diag.PythonOK)
				}
			}()
		}
	}

	engine := agent.NewEngine(registry, workingDir, sessions, proot)
	if qemu != nil {
		engine = engine.WithQemu(qemu)
	}
	planEngine := agent.NewPlanEngine(registry, workingDir)

	server, err := api.Start(portFile, engine, registry, sessions, planEngine)
	if err != nil {
		log.Fatalf("start daemon: %v", err)
	}
	if proot != nil {
		server.SetProot(proot)
	}

	// Wire a shared dispatcher for the `!<cmd>` shell-bypass feature
	// (TypeDirectToolCall). Mirrors the backend config that Engine builds
	// per-task so runtime routing (qemu > proot > host) matches exactly.
	directDispatcher := tools.DefaultDispatcherWithOpts(workingDir, tools.DispatcherOpts{
		Proot: proot,
		Qemu:  qemu,
	})
	server.SetDispatcher(directDispatcher)
	log.Printf("direct tool dispatcher ready: tools=%v", directDispatcher.Names())

	log.Printf("mo-code daemon listening on 127.0.0.1:%d", server.Port())
	log.Printf("port file: %s", portFile)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	if err := server.Close(); err != nil {
		log.Printf("shutdown error: %v", err)
	}
}
