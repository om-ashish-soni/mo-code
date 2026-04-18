# Mo-Code Jira Epic

## Epic: MO-1 — Build Mo-Code Mobile AI Coding Agent

**Description:** Build a mobile-first AI coding agent that runs locally on Android. Flutter terminal-style UI connected to a forked OpenCode Go backend via WebSocket. Multi-provider support (Claude, Gemini, Copilot). Background task execution with git integration and checkpoint-based multi-agent handoff.

**Labels:** mobile, flutter, golang, ai-agent, opencode
**Priority:** P0
**Target:** 11 weeks

---

## Phase 1: Foundation (Weeks 1-3)

### Story: MO-10 — Fork and strip OpenCode
**Points:** 8 | **Assignee:** Claude / Codex | **Priority:** P0

**Description:** Fork OpenCode, remove all Bubble Tea TUI dependencies, create a headless entry point that starts a WebSocket server instead of a terminal UI.

**Subtasks:**
- [ ] **MO-10.1** — Clone OpenCode, create mo-code repo, initial commit
- [ ] **MO-10.2** — Identify and document all packages to keep vs remove (create `FORK_NOTES.md`)
- [ ] **MO-10.3** — Remove `internal/tui/`, `internal/app/` and all Bubble Tea imports
- [ ] **MO-10.4** — Remove `cmd/opencode/` entry point
- [ ] **MO-10.5** — Fix all compilation errors from removed packages (stub missing interfaces)
- [ ] **MO-10.6** — Create `cmd/mocode/main.go` — minimal entry point that starts HTTP server + logs to stdout
- [ ] **MO-10.7** — Verify `go build` succeeds for `linux/amd64` and `linux/arm64`
- [ ] **MO-10.8** — Write initial `CHECKPOINT.md` and `TODO.md`
- [ ] **MO-10.9** — Update `CHECKPOINT.md` with fork status

**Acceptance criteria:**
- `go build ./cmd/mocode/` succeeds on linux/arm64
- No Bubble Tea imports remain in the codebase
- Health check endpoint responds on localhost
- CHECKPOINT.md reflects current state

---

### Story: MO-11 — WebSocket + HTTP API layer
**Points:** 8 | **Assignee:** Claude / Codex | **Priority:** P0

**Description:** Build the API layer that replaces OpenCode's TUI. WebSocket for streaming bidirectional communication, HTTP for simple request/response endpoints.

**Subtasks:**
- [ ] **MO-11.1** — Add `gorilla/websocket` dependency
- [ ] **MO-11.2** — Create `api/server.go` — HTTP/WS server, localhost-only binding, port discovery
- [ ] **MO-11.3** — Create `api/messages.go` — define all WS message types as Go structs with JSON tags
- [ ] **MO-11.4** — Create `api/handlers.go` — WS upgrade handler, client connection manager
- [ ] **MO-11.5** — Implement client read/write pumps with ping/pong keepalive
- [ ] **MO-11.6** — Implement port file write (`daemon_port` in app data dir)
- [ ] **MO-11.7** — HTTP endpoints: `GET /api/health`, `GET /api/config`, `POST /api/config`
- [ ] **MO-11.8** — Write tests for WS connection lifecycle (connect, message, disconnect, reconnect)
- [ ] **MO-11.9** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- WebSocket server accepts connections on localhost
- Clients can send/receive JSON messages
- Port is written to discoverable file path
- Health check returns server status
- Tests pass

---

### Story: MO-12 — Flutter app scaffold
**Points:** 5 | **Assignee:** Gemini | **Priority:** P0

**Description:** Create the Flutter project with the four-tab navigation structure, dark terminal theme, and WebSocket client service.

**Subtasks:**
- [ ] **MO-12.1** — `flutter create mo_code` with Android target
- [ ] **MO-12.2** — Set up project structure (`screens/`, `widgets/`, `services/`, `models/`)
- [ ] **MO-12.3** — Configure dark terminal theme (colors, fonts, spacing)
- [ ] **MO-12.4** — Implement bottom navigation bar (Agent | Tasks | Files | Config)
- [ ] **MO-12.5** — Create `websocket_service.dart` — connect, reconnect, send, stream
- [ ] **MO-12.6** — Create placeholder screens for all four tabs
- [ ] **MO-12.7** — Add Riverpod state management setup
- [ ] **MO-12.8** — Test WS connection to a mock Go server
- [ ] **MO-12.9** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- App builds and runs on Android emulator
- Four tabs navigate correctly
- Dark terminal theme applied globally
- WebSocket service connects to localhost and handles disconnection

---

### Story: MO-13 — Agent view (terminal output)
**Points:** 5 | **Assignee:** Gemini | **Priority:** P0

**Description:** Build the main agent view screen — terminal-style scrolling output with provider switcher and input bar.

**Subtasks:**
- [ ] **MO-13.1** — Create `TerminalOutput` widget — scrollable, styled text spans
- [ ] **MO-13.2** — Implement message type styling (user input = green, output = white, tool = amber, plan = purple)
- [ ] **MO-13.3** — Create `ProviderSwitcher` widget — pill buttons for Claude/Gemini/Copilot
- [ ] **MO-13.4** — Create input bar widget — text field + send button
- [ ] **MO-13.5** — Wire `agentOutputProvider` stream to terminal widget
- [ ] **MO-13.6** — Auto-scroll behavior (scroll to bottom on new message, pause when user scrolls up)
- [ ] **MO-13.7** — Create `CodePreview` widget — collapsible syntax-highlighted file preview
- [ ] **MO-13.8** — Test with mock WS messages for all message types
- [ ] **MO-13.9** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- Terminal output renders streaming messages with correct colors
- Provider switcher changes active provider
- Input bar sends messages via WebSocket
- Auto-scroll works correctly
- Code preview expands/collapses

---

## Phase 2: Agent Core (Weeks 3-5)

### Story: MO-20 — Wire agent runtime to WebSocket
**Points:** 8 | **Assignee:** Claude / Codex | **Priority:** P0

**Description:** Connect OpenCode's agent runtime to the WebSocket API so that agent output streams to the Flutter UI instead of stdout.

**Subtasks:**
- [ ] **MO-20.1** — Study OpenCode's agent output interface (identify where stdout writes happen)
- [ ] **MO-20.2** — Create `api/bridge.go` — adapter that implements agent's output interface, writes to WS
- [ ] **MO-20.3** — Wire `task.start` WS message to agent.Run()
- [ ] **MO-20.4** — Stream agent plan steps as `agent.stream` messages (kind: "plan")
- [ ] **MO-20.5** — Stream tool calls and results as separate message kinds
- [ ] **MO-20.6** — Stream text output token-by-token
- [ ] **MO-20.7** — Send `task.complete` when agent finishes with file summary
- [ ] **MO-20.8** — Handle agent errors — stream error messages, don't crash
- [ ] **MO-20.9** — Test end-to-end: Flutter sends prompt → Go runs agent → Flutter receives stream
- [ ] **MO-20.10** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- Sending a prompt from Flutter triggers agent execution
- All agent output streams to Flutter in real-time
- Task completion sends summary with file list
- Errors are handled gracefully

---

### Story: MO-21 — Provider switching
**Points:** 5 | **Assignee:** Copilot | **Priority:** P0

**Description:** Implement runtime provider switching — user taps Claude/Gemini/Copilot in the UI, Go backend switches the active LLM provider.

**Subtasks:**
- [ ] **MO-21.1** — Review OpenCode's provider interface (`provider.go`)
- [ ] **MO-21.2** — Verify Claude provider works with current API (may need updates)
- [ ] **MO-21.3** — Verify Gemini provider works
- [ ] **MO-21.4** — Implement Copilot provider (if not in OpenCode already)
- [ ] **MO-21.5** — Add `provider.switch` WS message handler
- [ ] **MO-21.6** — Handle mid-task provider switch (queue for next task, don't interrupt current)
- [ ] **MO-21.7** — API key configuration via `config.set` WS message
- [ ] **MO-21.8** — Wire Flutter provider switcher to send `provider.switch` messages
- [ ] **MO-21.9** — Test each provider end-to-end
- [ ] **MO-21.10** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- All three providers produce valid agent output
- Switching providers mid-session works (takes effect on next task)
- API keys are configurable at runtime

---

### Story: MO-22 — Tool execution on Android
**Points:** 5 | **Assignee:** Claude / Codex | **Priority:** P1

**Description:** Verify and adapt OpenCode's tool implementations (file, shell, git) for the Android environment.

**Subtasks:**
- [ ] **MO-22.1** — Test `file.read` / `file.write` in Android app sandbox
- [ ] **MO-22.2** — Test `shell.exec` via `os/exec` on Android (verify common commands available)
- [ ] **MO-22.3** — Identify missing shell commands on stock Android — document and create fallbacks
- [ ] **MO-22.4** — Configure tool working directory to app sandbox or scoped storage
- [ ] **MO-22.5** — Implement file permission handling for Android 13+ scoped storage
- [ ] **MO-22.6** — Test tool execution end-to-end via agent
- [ ] **MO-22.7** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- File read/write works in app sandbox
- Shell commands execute (at minimum: ls, cat, mkdir, rm, cp, mv)
- Agent can use tools to create project files

---

## Phase 3: File & Git (Weeks 5-7)

### Story: MO-30 — Git integration via go-git
**Points:** 8 | **Assignee:** Copilot | **Priority:** P0

**Description:** Implement full git workflow using go-git (pure Go, no native git binary).

**Subtasks:**
- [ ] **MO-30.1** — Add `go-git/v5` dependency
- [ ] **MO-30.2** — Implement `git.clone` — clone via HTTPS and SSH
- [ ] **MO-30.3** — Implement `git.status` — return file status for file browser
- [ ] **MO-30.4** — Implement `git.add` — stage files
- [ ] **MO-30.5** — Implement `git.commit` — commit with message
- [ ] **MO-30.6** — Implement `git.push` — push to remote
- [ ] **MO-30.7** — Implement `git.diff` — generate diff output for display
- [ ] **MO-30.8** — Implement `git.branch` — list, create, checkout
- [ ] **MO-30.9** — Implement `git.log` — recent commit history
- [ ] **MO-30.10** — SSH key generation and storage (Android Keystore)
- [ ] **MO-30.11** — Wire all git operations to WS message handlers
- [ ] **MO-30.12** — Write tests for each git operation
- [ ] **MO-30.13** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- Can clone a GitHub repo, make changes, commit, and push — all from the app
- SSH key generation works, user can copy public key
- All git operations work through WebSocket messages

---

### Story: MO-31 — File browser UI
**Points:** 5 | **Assignee:** Gemini | **Priority:** P1

**Description:** Build the file browser screen with tree view, git status colors, and diff preview.

**Subtasks:**
- [ ] **MO-31.1** — Create `FileTree` widget — recursive indented tree with expand/collapse
- [ ] **MO-31.2** — Implement git status colors (green=added, amber=modified, gray=untracked)
- [ ] **MO-31.3** — Create `DiffView` widget — inline diff with red/green line highlighting
- [ ] **MO-31.4** — Create git action bar — branch display, commit button, push button
- [ ] **MO-31.5** — Wire file tree to `fs.tree` WS messages
- [ ] **MO-31.6** — Wire diff view to `git.diff` WS messages
- [ ] **MO-31.7** — Implement commit flow — tap commit → enter message → confirm
- [ ] **MO-31.8** — Implement push flow — tap push → confirm → progress indicator
- [ ] **MO-31.9** — Staged changes summary bar
- [ ] **MO-31.10** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- File tree displays project structure with correct git status indicators
- Tapping a modified file shows inline diff
- Commit and push flows work end-to-end

---

## Phase 4: Background & UX (Weeks 7-9)

### Story: MO-40 — Android foreground service
**Points:** 8 | **Assignee:** Minimax | **Priority:** P0

**Description:** Implement the Android foreground service that manages the Go daemon lifecycle and enables background task execution.

**Subtasks:**
- [ ] **MO-40.1** — Create `ForegroundService.kt` — start/stop Go daemon
- [ ] **MO-40.2** — Implement Go binary extraction from APK assets on first launch
- [ ] **MO-40.3** — Binary integrity verification (SHA256 checksum)
- [ ] **MO-40.4** — Persistent notification showing daemon status
- [ ] **MO-40.5** — Update notification with active task info (task name, progress)
- [ ] **MO-40.6** — Daemon crash detection and automatic restart
- [ ] **MO-40.7** — Handle app lifecycle — keep service running when app is backgrounded
- [ ] **MO-40.8** — Handle Android battery optimization — request exemption
- [ ] **MO-40.9** — Service stops cleanly when user explicitly quits
- [ ] **MO-40.10** — Wire Flutter to start/stop service via method channel
- [ ] **MO-40.11** — Test background execution — start task, switch apps, come back
- [ ] **MO-40.12** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- Go daemon starts automatically with app launch
- Daemon survives app backgrounding
- Notification shows current task status
- Daemon restarts if it crashes
- User can explicitly stop the service

---

### Story: MO-41 — Task manager UI
**Points:** 5 | **Assignee:** Gemini | **Priority:** P1

**Description:** Build the task manager screen showing running, queued, and completed background tasks.

**Subtasks:**
- [ ] **MO-41.1** — Create `TaskCard` widget — name, provider badge, progress bar, actions
- [ ] **MO-41.2** — Implement task states — queued (purple), running (amber), complete (green), failed (red)
- [ ] **MO-41.3** — Task list view — sorted by state (running first, then queued, then completed)
- [ ] **MO-41.4** — Action buttons on completed tasks — "Review diff" (navigates to Files tab), "Push"
- [ ] **MO-41.5** — Retry button on failed tasks
- [ ] **MO-41.6** — Task queue management — reorder queued tasks, cancel tasks
- [ ] **MO-41.7** — Wire to `task.*` WS messages for real-time updates
- [ ] **MO-41.8** — Badge on Tasks tab showing count of active tasks
- [ ] **MO-41.9** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- Task cards display correct state and progress
- Completed tasks have working action buttons
- Real-time updates via WebSocket
- Tab badge shows active count

---

### Story: MO-42 — Notification system
**Points:** 3 | **Assignee:** Minimax | **Priority:** P1

**Description:** Notifications when tasks complete, fail, or need user attention.

**Subtasks:**
- [ ] **MO-42.1** — Create `NotificationService` in Flutter
- [ ] **MO-42.2** — Task completion notification — "Task X ready for review: 3 files changed"
- [ ] **MO-42.3** — Task failure notification — "Task X failed: [error summary]"
- [ ] **MO-42.4** — Approval needed notification — "Task X needs your input"
- [ ] **MO-42.5** — Tap notification → navigate to relevant screen
- [ ] **MO-42.6** — Notification preferences in config screen
- [ ] **MO-42.7** — Update `CHECKPOINT.md`

**Acceptance criteria:**
- Notifications fire for task completion/failure
- Tapping notification opens the right screen
- User can configure notification preferences

---

## Phase 5: Polish & Ship (Weeks 9-11)

### Story: MO-50 — Voice input
**Points:** 3 | **Assignee:** Gemini | **Priority:** P2

**Subtasks:**
- [ ] **MO-50.1** — Integrate `speech_to_text` package
- [ ] **MO-50.2** — Add microphone button to input bar
- [ ] **MO-50.3** — Real-time transcription display
- [ ] **MO-50.4** — Auto-send on speech end (configurable)
- [ ] **MO-50.5** — Update `CHECKPOINT.md`

---

### Story: MO-51 — Onboarding & API key setup
**Points:** 3 | **Assignee:** Gemini | **Priority:** P1

**Subtasks:**
- [ ] **MO-51.1** — First-launch onboarding flow (3-4 screens)
- [ ] **MO-51.2** — API key entry for each provider (with validation)
- [ ] **MO-51.3** — SSH key generation wizard
- [ ] **MO-51.4** — "Try it" demo task with a sample project
- [ ] **MO-51.5** — Update `CHECKPOINT.md`

---

### Story: MO-52 — Error handling & resilience
**Points:** 5 | **Assignee:** Copilot | **Priority:** P1

**Subtasks:**
- [ ] **MO-52.1** — WS disconnection handling — auto-reconnect with backoff
- [ ] **MO-52.2** — Agent error recovery — surface errors in UI, allow retry
- [ ] **MO-52.3** — API rate limit handling — queue and retry with delay
- [ ] **MO-52.4** — Disk space checks before file operations
- [ ] **MO-52.5** — Network connectivity checks before LLM API calls
- [ ] **MO-52.6** — Crash reporting (local log file, no telemetry)
- [ ] **MO-52.7** — Update `CHECKPOINT.md`

---

### Story: MO-53 — Testing & Play Store prep
**Points:** 5 | **Assignee:** All agents | **Priority:** P1

**Subtasks:**
- [ ] **MO-53.1** — Unit tests for Go backend (api, agent bridge, git operations)
- [ ] **MO-53.2** — Widget tests for Flutter (terminal output, task cards, file browser)
- [ ] **MO-53.3** — Integration test — full flow: prompt → agent → files → commit → push
- [ ] **MO-53.4** — Performance testing — memory usage, daemon CPU, battery impact
- [ ] **MO-53.5** — Play Store listing — screenshots, description, privacy policy
- [ ] **MO-53.6** — APK signing and release build
- [ ] **MO-53.7** — Beta testing setup (Play Store internal track)
- [ ] **MO-53.8** — Final `CHECKPOINT.md` update

---

## Checkpoint discipline (for all agents)

Every story above ends with "Update CHECKPOINT.md". This is not optional. The checkpoint file is the single source of truth for project state. When four different agents are working on this project, the checkpoint is how they coordinate.

### Before starting work:
```bash
cat CHECKPOINT.md
cat TODO.md
```

### After completing a subtask:
```bash
# Update checkpoint programmatically or by editing the file
# Mark the subtask as done
# Add any new discoveries to Known Issues
# Add any new decisions to Key Decisions
```

### Before stopping work:
```bash
# Write a handoff note summarizing:
# - What you just did
# - What's next
# - Any gotchas the next agent should know
```

## Story dependency graph

```
MO-10 (Fork OpenCode)
  └─→ MO-11 (WS API layer)
        └─→ MO-20 (Wire agent to WS)
              └─→ MO-21 (Provider switching)
              └─→ MO-22 (Tool execution on Android)

MO-12 (Flutter scaffold)
  └─→ MO-13 (Agent view)
        └─→ MO-41 (Task manager UI)
        └─→ MO-50 (Voice input)

MO-11 + MO-12
  └─→ MO-20 (Wire agent — needs both backend and frontend)

MO-22 (Tools on Android)
  └─→ MO-30 (Git integration)
        └─→ MO-31 (File browser UI)

MO-20 (Agent wired)
  └─→ MO-40 (Foreground service)
        └─→ MO-42 (Notifications)

MO-21 (Providers)
  └─→ MO-51 (Onboarding + API keys)

All stories
  └─→ MO-52 (Error handling)
        └─→ MO-53 (Testing + ship)
```

## Parallel work streams

With 4 agents (Claude/Codex, Gemini, Copilot, Minimax), here's the optimal parallel schedule:

### Week 1-2:
- **Claude/Codex:** MO-10 (Fork OpenCode)
- **Gemini:** MO-12 (Flutter scaffold)
- **Copilot:** Set up repo, CI, write API protocol docs
- **Minimax:** Research Android foreground service patterns, write MO-40 design doc

### Week 2-3:
- **Claude/Codex:** MO-11 (WS API layer)
- **Gemini:** MO-13 (Agent view UI)
- **Copilot:** MO-21 (Provider implementations — can work against stubs)
- **Minimax:** Continue MO-40 design, start Kotlin service scaffold

### Week 3-5:
- **Claude/Codex:** MO-20 (Wire agent to WS)
- **Gemini:** Polish agent view, start MO-41 (Task manager)
- **Copilot:** MO-22 (Tool execution on Android) + MO-21 finish
- **Minimax:** MO-40 (Foreground service implementation)

### Week 5-7:
- **Claude/Codex:** Support git integration, complex agent scenarios
- **Gemini:** MO-31 (File browser UI)
- **Copilot:** MO-30 (Git via go-git)
- **Minimax:** MO-42 (Notifications)

### Week 7-9:
- **All:** Integration testing, bug fixing, polish
- **Gemini:** MO-50 (Voice), MO-51 (Onboarding)
- **Copilot:** MO-52 (Error handling)

### Week 9-11:
- **All:** MO-53 (Testing + ship)

---

## Phase 6: proot Android 15 Fix (ISSUE-010)

**Goal:** Fix shell command execution (npm, pip, git clone, etc.) on Android 15.
**Root cause:** Android 15 SELinux blocks `mmap(PROT_EXEC)` on `app_data_file` binaries — the proot loader crashes with SIGSEGV → exit 255.
**Fix:** Patch the proot loader to copy ELF segments into anonymous `memfd` files (no SELinux label) before mapping them executable.
**Spec:** `docs/features/FEAT-004-proot-android15-memfd-fix.md`

---

### Story: MO-60 — proot loader memfd_create patch
**Points:** 5 | **Assignee:** C1 | **Priority:** P0

**Description:** Patch `loader.c` from proot-me v5.3.0 to use `memfd_create` for ELF segment mapping. Cross-compile with Android NDK. Deploy as `libproot-loader.so`.

**Subtasks:**
- [ ] **MO-60.1** — Clone proot-me v5.3.0, set up NDK cross-compile toolchain
- [ ] **MO-60.2** — Write `scripts/build-loader.sh` — reproducible NDK build script
- [ ] **MO-60.3** — Patch `loader.c`: add `memfd_copy_segment()` helper using `SYS_memfd_create` syscall
- [ ] **MO-60.4** — Replace direct file mmap with memfd copy in `LOAD_ACTION_MMAP_FILE` handler
- [ ] **MO-60.5** — Compile: `aarch64-linux-android24-clang -static -fno-PIE -nostdlib`
- [ ] **MO-60.6** — Deploy to `flutter/android/app/src/main/jniLibs/arm64-v8a/libproot-loader.so`
- [ ] **MO-60.7** — Write `scripts/verify-loader.sh` — ptrace diagnostic probe to confirm fix
- [ ] **MO-60.8** — Rebuild APK, USB-test `echo ok` → `apk update` → `npm --version` on OnePlus CPH2467

**Acceptance criteria:**
- `proot /bin/sh -c "echo ok"` returns exit 0 on Android 15 API 35
- `npm --version`, `python3 --version`, `git --version` all succeed inside proot
- No regression on Android 12/13/14 (test on emulators)
- `libproot-loader.so` is ≤ 10KB static binary

---

### Story: MO-61 — Go backend proot diagnostics and error handling
**Points:** 3 | **Assignee:** C2 | **Priority:** P0

**Description:** Add startup proot health check, distinguish loader crash (exit 255) from command failure, emit structured `runtime.setup` error events so Flutter can show actionable status.

**Subtasks:**
- [ ] **MO-61.1** — `runtime/proot.go`: add `Diagnose(ctx)` — runs `echo ok`, returns typed `DiagnosticResult` (ok / loader_crash / exec_blocked / timeout)
- [ ] **MO-61.2** — `cmd/mocode/main.go`: call `proot.Diagnose()` at startup; log result; if loader_crash emit `runtime.setup` WS event with `phase: "failed"` and actionable message
- [ ] **MO-61.3** — `tools/shell.go`: distinguish exit 255 + empty stderr (loader crash) from exit 255 with stderr (command returned 255) — set `error` field accordingly
- [ ] **MO-61.4** — `runtime/proot_test.go`: add `TestDiagnose_*` tests with mock proot binary stubs
- [ ] **MO-61.5** — `runtime/proot_test.go`: fix pre-existing `TestProotArgs` failures (resolv.conf arg order) — **already done, verify still passing**

**Acceptance criteria:**
- Daemon logs clear reason for proot failure at startup
- Flutter receives `runtime.setup {phase: "failed", message: "..."}` when proot is broken
- Shell tool error message distinguishes loader crash from real command exit 255
- All runtime tests pass

---

### Story: MO-62 — Flutter/Android proot status UI and degraded mode
**Points:** 3 | **Assignee:** C3 | **Priority:** P1

**Description:** Show proot health in the UI, degrade gracefully when proot is broken (go-git tools still work), add diagnostic button in Config screen.

**Subtasks:**
- [ ] **MO-62.1** — `DaemonService.kt`: after `RuntimeBootstrap.bootstrap()`, call Go health endpoint; if proot failed log `W/MoCodeDaemon: proot unavailable` + set `DaemonService.prootAvailable = false`
- [ ] **MO-62.2** — `agent_screen.dart`: listen for `runtime.setup {phase: "failed"}` WS event; show amber banner "Shell runtime unavailable — git/file ops work, npm/pip require a fix"
- [ ] **MO-62.3** — `config_screen.dart`: add "Runtime Diagnostics" section — proot status badge (green/red), "Run Diagnostic" button that calls `/api/runtime/status` and shows raw result
- [ ] **MO-62.4** — `daemon.dart`: add `runProotDiagnostic()` method — POST `/api/runtime/diagnose`, return `DiagnosticResult`
- [ ] **MO-62.5** — `server.go`: add `POST /api/runtime/diagnose` endpoint that calls `proot.Diagnose()` and returns JSON
- [ ] **MO-62.6** — After MO-60 loader fix lands: remove degraded-mode banner, verify green status in config screen on device

**Acceptance criteria:**
- Config screen shows proot status (available / unavailable) in real time
- When proot is broken, agent screen shows amber banner listing what still works
- "Run Diagnostic" button returns result within 5 seconds
- After MO-60 fix: banner never appears on a healthy device

---

## Phase 6 parallel schedule

All three stories have **zero file conflicts** — they touch disjoint files:

| | C1 | C2 | C3 |
|---|---|---|---|
| `loader.c` (new) | ✅ | | |
| `scripts/build-loader.sh` (new) | ✅ | | |
| `jniLibs/libproot-loader.so` | ✅ | | |
| `runtime/proot.go` | | ✅ | |
| `runtime/proot_test.go` | | ✅ | |
| `cmd/mocode/main.go` | | ✅ | |
| `tools/shell.go` | | ✅ | |
| `DaemonService.kt` | | | ✅ |
| `agent_screen.dart` | | | ✅ |
| `config_screen.dart` | | | ✅ |
| `daemon.dart` | | | ✅ |
| `api/server.go` | | | ✅ |

**C1 and C2 can start immediately in parallel.**
**C3 depends on C2's `runtime.setup` failure event shape** (MO-61.2) — C3 should start after MO-61.2 is merged, or stub the event shape from the spec.

**Integration order:**
1. C2 merges first (backend diagnostics, no binary changes)
2. C1 merges (new loader binary — APK rebuild required)
3. C3 merges (UI wired to C2 events)
4. USB device test with all three merged
