# Mo-Code Architecture

## System overview

Mo-code is a two-process architecture running entirely on-device:

1. **Go daemon** — forked from OpenCode, stripped of Bubble Tea TUI, exposes a WebSocket + HTTP API on localhost
2. **Flutter app** — terminal-style UI that connects to the Go daemon via WebSocket

The Go daemon is managed by an Android foreground service that starts it on app launch and keeps it alive in the background.

## Architecture diagram (ASCII)

```
┌─────────────────────────────────────────────────────────────┐
│                    FLUTTER UI LAYER                         │
│                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌────────────────┐  │
│  │  Agent View   │  │ Task Manager  │  │ File Browser   │  │
│  │               │  │               │  │   + Git        │  │
│  │ • Stream AI   │  │ • Job queue   │  │ • File tree    │  │
│  │   output      │  │ • Progress    │  │ • Diff view    │  │
│  │ • Plan view   │  │ • Approve/    │  │ • Commit       │  │
│  │ • Live code   │  │   reject      │  │ • Push         │  │
│  │   preview     │  │ • Retry       │  │ • Branch       │  │
│  └───────┬───────┘  └───────┬───────┘  └───────┬────────┘  │
│          └──────────────────┼──────────────────┘            │
│                     ┌───────▼───────┐                       │
│                     │  WebSocket    │                       │
│                     │  Client       │                       │
│                     │  (Dart)       │                       │
│                     └───────┬───────┘                       │
└─────────────────────────────┼───────────────────────────────┘
                              │ ws://127.0.0.1:19280
                              │ (JSON messages, bidirectional)
┌─────────────────────────────┼───────────────────────────────┐
│                    GO BACKEND (LOCAL DAEMON)                 │
│                     ┌───────▼───────┐                       │
│                     │  WS + HTTP    │                       │
│                     │  Server       │                       │
│                     │  (Gorilla WS) │                       │
│                     └───────┬───────┘                       │
│          ┌──────────────────┼──────────────────┐            │
│  ┌───────▼───────┐  ┌──────▼──────┐  ┌────────▼────────┐  │
│  │ Agent Runtime │  │  Context    │  │ Tool Dispatcher │  │
│  │               │  │  Manager    │  │                 │  │
│  │ • Plan steps  │  │             │  │ • file.read     │  │
│  │ • Execute     │  │ • Token     │  │ • file.write    │  │
│  │   tools       │  │   budget    │  │ • shell.exec    │  │
│  │ • Iterate     │  │ • LSP-aware │  │ • git.*         │  │
│  │ • Stream      │  │   context   │  │ • search        │  │
│  │   results     │  │ • Convo     │  │                 │  │
│  │               │  │   threading │  │                 │  │
│  └───────────────┘  └─────────────┘  └─────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Provider Abstraction                    │   │
│  │  ┌─────────┐   ┌─────────┐   ┌─────────┐           │   │
│  │  │ Claude  │   │ Gemini  │   │ Copilot │   + more  │   │
│  │  │ API     │   │ API     │   │ API     │           │   │
│  │  └─────────┘   └─────────┘   └─────────┘           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Android Foreground Service                 │   │
│  │  • Starts Go binary on app launch                   │   │
│  │  • Persistent notification with task status          │   │
│  │  • Keeps daemon alive when app is backgrounded       │   │
│  │  • Restarts daemon if it crashes                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
    Local Filesystem      go-git             LLM APIs
    (app sandbox)      (pure Go)          (HTTPS outbound)
```

## UX screens

### Screen 1: Agent view (main screen)

The primary interface. Dark terminal aesthetic. Shows:

- **Provider switcher** — pill buttons at top: Claude | Gemini | Copilot. Active provider highlighted in purple.
- **Agent output stream** — terminal-style scrolling output showing:
  - User prompt (green, prefixed with `$`)
  - Agent plan (numbered steps, purple accent)
  - File operations (green checkmarks for created, amber for in-progress)
  - Token counter and file count in status bar
- **Live code preview** — collapsible panel showing the file currently being written, with syntax highlighting
- **Input bar** — at bottom. Text input + send button. Supports voice-to-text.

Design: dark background (#1a1a2e), monospace font, green/purple/amber accents. Terminal feel but touch-friendly with large tap targets.

### Screen 2: Background tasks

Shows all running, queued, and completed tasks:

- **Task cards** — each with:
  - Task name (from initial prompt)
  - Provider badge (which LLM is working on it)
  - Progress bar with step count (e.g., "4/7 steps done")
  - Color-coded left border: amber = running, green = complete, purple = queued
  - Action buttons on completed tasks: "Review diff" | "Push"
- **Notification preview** — bottom overlay showing latest completion

### Screen 3: File browser + git

Split into two sections:

- **File tree** — indented tree view with git status colors:
  - Green `+` prefix = added (staged)
  - Amber `~` prefix = modified
  - Normal color = untracked/unchanged
- **Diff preview** — tap any modified file to see inline diff (red/green lines)
- **Git bar** — top section showing:
  - Current repo name and branch
  - Commit and Push buttons
  - Staged changes summary ("3 added · 1 modified")

### Screen 4: Config / Settings

- API key management for each provider
- Default provider selection
- Working directory / project selection
- SSH key management for GitHub
- Theme options (dark only initially)
- Notification preferences

### Bottom navigation

Four tabs: Agent | Tasks | Files | Config

Swipe between tabs for fast navigation. Badge on Tasks tab shows count of running tasks.

## Go backend details

### Forking OpenCode

1. Clone OpenCode repository
2. Remove all Bubble Tea TUI packages (`internal/tui/`, `internal/app/`)
3. Remove the `cmd/opencode/` entry point (which initializes BubbleTea)
4. Keep these packages intact:
   - `internal/llm/` — provider abstraction, streaming, tool calling
   - `internal/lsp/` — LSP client for code intelligence
   - `internal/config/` — configuration management
   - `internal/db/` — conversation persistence (SQLite)
   - `internal/fileutil/` — file operations
5. Create new `cmd/mocode/main.go` — starts HTTP/WS server instead of TUI
6. Create new `api/` package — WebSocket handlers, message routing

### WebSocket server setup

```go
// api/server.go — simplified
func StartServer(port int, agent *agent.Agent) error {
    upgrader := websocket.Upgrader{CheckOrigin: func(r *http.Request) bool {
        return r.Host == "127.0.0.1" || r.Host == "localhost"
    }}

    http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
        conn, _ := upgrader.Upgrade(w, r, nil)
        client := NewClient(conn, agent)
        go client.ReadPump()
        go client.WritePump()
    })

    http.HandleFunc("/api/health", healthHandler)
    http.HandleFunc("/api/files", filesHandler)

    return http.ListenAndServe(fmt.Sprintf("127.0.0.1:%d", port), nil)
}
```

### Port selection

Default port: 19280. If occupied, scan upward. Write the active port to a known file path so the Flutter app can discover it.

```
/data/data/com.mocode.app/daemon_port
```

### Cross-compilation

```bash
# Build for Android ARM64
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o mocode-arm64 ./cmd/mocode/

# The binary is bundled inside the Flutter APK as a raw asset
# Flutter extracts it on first launch to app's internal storage
# Then starts it via Process.start()
```

### go-git for git operations

Use `github.com/go-git/go-git/v5` for all git operations. No dependency on native `git` binary.

Key operations to implement:
- `git.Clone(url, path)` — clone repos via HTTPS or SSH
- `git.Status(path)` — file status for the file browser
- `git.Add(path, files)` — stage files
- `git.Commit(path, message)` — commit staged changes
- `git.Push(path, remote)` — push to remote
- `git.Branch(path, name)` — create/switch branches
- `git.Diff(path)` — generate diff for display
- `git.Log(path, n)` — recent commit history

SSH key management via `golang.org/x/crypto/ssh` — generate keys in-app, user adds public key to GitHub.

## Flutter app details

### Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  web_socket_channel: ^2.4.0    # WebSocket client
  provider: ^6.1.0              # State management
  flutter_riverpod: ^2.4.0      # Alternative if preferred
  google_fonts: ^6.1.0          # Monospace font (JetBrains Mono)
  flutter_highlight: ^0.7.0     # Syntax highlighting
  path: ^1.8.3
  uuid: ^4.2.0
  shared_preferences: ^2.2.0    # Local config storage
  permission_handler: ^11.0.0   # File system permissions
  speech_to_text: ^6.6.0        # Voice input
  flutter_local_notifications: ^16.0.0
```

### State management

Use Riverpod for state management. Key state providers:

```dart
// Active WebSocket connection
final wsProvider = StateNotifierProvider<WsNotifier, WsState>(...);

// Current tasks (running, queued, completed)
final tasksProvider = StateNotifierProvider<TasksNotifier, List<Task>>(...);

// File tree for current project
final fileTreeProvider = StateNotifierProvider<FileTreeNotifier, FileTree>(...);

// Agent output stream (terminal lines)
final agentOutputProvider = StreamProvider<AgentMessage>(...);

// Selected provider (claude/gemini/copilot)
final activeProviderProvider = StateProvider<String>((ref) => 'claude');
```

### Terminal output renderer

Custom widget that renders a scrolling list of styled text spans. Each line has:
- Color based on message type (green for user input, white for output, amber for tool calls, purple for plan steps)
- Monospace font (JetBrains Mono)
- Auto-scroll to bottom on new content
- Tap-to-expand for tool results

```dart
class TerminalOutput extends ConsumerWidget {
  // Listens to agentOutputProvider stream
  // Renders each AgentMessage as a styled text span
  // Maintains scroll position (auto-scroll when at bottom)
}
```

### Background service (Android)

```kotlin
// ForegroundService.kt
class MoCodeForegroundService : Service() {
    private var daemonProcess: Process? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Mo-Code running"))

        // Extract and start Go binary
        val binaryPath = extractBinary()
        daemonProcess = ProcessBuilder(binaryPath, "--port", "19280")
            .directory(getFilesDir())
            .start()

        return START_STICKY  // Restart if killed
    }
}
```

## Checkpoint system technical details

### Checkpoint format

The checkpoint file uses a strict markdown format that any agent can parse:

```markdown
# Mo-Code Checkpoint

## Last updated
2025-01-15T14:30:00Z by claude-code

## Handoff note
Completed the WebSocket server setup. The handlers for task.start and
agent.stream are working. Next step is wiring the agent runtime to
stream through the WS connection instead of stdout. See api/handlers.go
lines 45-80 for the current implementation.

## Current phase
Phase 2 — Agent Core

## Completed
- [x] Fork OpenCode, strip Bubble Tea — backend/cmd/mocode/main.go
- [x] WebSocket server with Gorilla — backend/api/server.go
- [x] Message type definitions — backend/api/messages.go
- [x] Health check endpoint — backend/api/handlers.go

## In progress
- [ ] Wire agent runtime to WS stream
  - Current state: Agent starts tasks but output goes to stdout, not WS
  - Next step: Replace stdout writer with WS broadcast in agent/runner.go
  - Files touched: backend/agent/runner.go, backend/api/handlers.go
  - Blockers: None

## Not started
- [ ] Provider switching via WS message
- [ ] Tool result streaming
- [ ] Error recovery and reconnection

## Key decisions made
- WebSocket over FFI for Go↔Flutter bridge: cleaner separation, streaming for free — 2025-01-10
- Port 19280 as default, written to file for Flutter discovery — 2025-01-12
- Gorilla WebSocket over nhooyr: better docs, more stable — 2025-01-12
- go-git over native git binary: no external deps, pure Go — 2025-01-10

## Known issues
- Go binary size is ~25MB for arm64, may need UPX compression — medium
- SQLite for conversation storage needs WAL mode for concurrent access — low

## File map
- `flutter/` — Flutter app (scaffolded, agent_view WIP)
- `backend/cmd/mocode/` — Entry point, starts WS server
- `backend/api/` — WebSocket + HTTP layer (server, handlers, messages)
- `backend/agent/` — OpenCode agent runtime (kept mostly intact)
- `backend/context/` — OpenCode context manager (unchanged)
- `backend/provider/` — LLM providers (claude, gemini working; copilot stub)
```

### Programmatic checkpoint updates (Go)

The Go backend includes a `checkpoint` package for reading and writing:

```go
package checkpoint

type Checkpoint struct {
    LastUpdated string
    Agent       string
    HandoffNote string
    Phase       string
    Completed   []Task
    InProgress  []Task
    NotStarted  []Task
    Decisions   []Decision
    Issues      []Issue
    FileMap     map[string]string
}

func Read(path string) (*Checkpoint, error)
func Write(path string, cp *Checkpoint) error
func MarkComplete(path string, taskDesc string, notes string) error
func AddInProgress(path string, task Task) error
func SetHandoffNote(path string, agent string, note string) error
```

## Security considerations

- All WS/HTTP traffic on localhost only — never exposed to network
- API keys stored in Android Keystore (encrypted at rest)
- SSH keys generated in-app, never leave the device
- Go binary integrity verified via checksum on first extract
- No analytics or telemetry — fully local
