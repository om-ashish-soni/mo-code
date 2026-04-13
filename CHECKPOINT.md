# Mo-Code Checkpoint

## Last updated
2026-04-13 by Claude (C3, FEAT-003 testing — COMPLETE)

## Handoff note
FEAT-002 proot+Alpine: COMPLETE. FEAT-003 session context continuity: ALL THREE CLAUDES COMPLETE (C1 Flutter, C2 Backend, C3 Testing).

| Claude | Scope | Key files | Status |
|--------|-------|-----------|--------|
| **C1** | Flutter agent screen — session ID lifecycle, startTask vs resumeSession routing, /clear reset | `agent_screen.dart`, `daemon.dart` | **COMPLETE** |
| **C2** | Backend hardening — session.info, session.clear message types, compaction counter, concurrent task guard | `server.go`, `messages.go`, `session_store.go`, `engine.go` | **COMPLETE** |
| **C3** | Testing — multi-turn e2e, compaction under resume, concurrent access, provider switch | `e2e_test.go`, `session_store_test.go`, `compaction_test.go` | **COMPLETE** |

**No file conflicts between C1/C2/C3.** All can start in parallel.

**Build status:** `go build ./...`, `go test ./...`, `go vet ./...` all clean. `flutter analyze` clean (1 info-level lint).

## Current phase
FEAT-003: Session Context Continuity — ALL COMPLETE (C1 Flutter, C2 Backend, C3 Testing). All tests pass with -race.

## FEAT-003: Session Context Continuity — PENDING
**Bug:** `agent_screen.dart:430` generates new task ID per prompt → backend sees each as independent session → LLM has zero context from prior turns.
**Fix:** Track session ID in agent screen state. First prompt = `task.start`. Follow-ups = `session.resume`. Backend already handles this correctly.
**Spec:** `docs/features/FEAT-003-session-context-continuity.md`

### C1 (Flutter) — COMPLETE
- [x] Add `_sessionId` state to `_AgentScreenState`
- [x] Generate session ID on first prompt, reuse for follow-ups
- [x] First prompt → `startTask()` with session ID; follow-ups → `resumeSession()`
- [x] `/clear` resets `_sessionId`; session resume from Sessions screen sets `_sessionId`
- [x] Show session indicator in status bar
- [x] `task.complete`/`task.failed` keep `_sessionId` (session persists across tasks)
Files: `flutter/lib/screens/agent_screen.dart`, `flutter/lib/api/daemon.dart`

### C2 (Backend) — COMPLETE
- [x] Add `session.info` message type (client requests session metadata without full history)
- [x] Add `session.clear` message type (reset messages without deleting session)
- [x] Add `CompactionCount` field to Session struct, increment on compaction
- [x] Emit session metadata after successful resume
- [x] Handle `task.start` while task already running on same session (error guard)
Files: `backend/api/server.go`, `backend/api/messages.go`, `backend/context/session_store.go`, `backend/agent/engine.go`

### C3 (Testing) — COMPLETE
- [x] E2E: multi-turn conversation (3 prompts, verify message accumulation via recordingProvider)
- [x] E2E: session resume after daemon restart (covered by existing TestE2E_SessionPersistence_SurvivesRestart)
- [x] E2E: compaction triggers during multi-turn (ShouldCompact threshold, Compact replaces old messages, too-few-messages guard)
- [x] Test: concurrent session access (4 goroutines × 50 iterations, race-detector clean)
- [x] Test: 150 messages + ClearMessages (messages reset, tokens zeroed, title preserved, persistence verified)
- [x] Test: provider switch mid-session (alpha→beta, verify beta receives full history)
- [x] Test: concurrent task guard (reject second task.start on same session ID)
- [x] SummaryBudget unit tests (truncate long lines, cap lines, cap chars, deduplicate)
- [x] IncrementCompaction + UpdateTokens + NotFound variants
- [x] **Bug fix:** SessionStore.Get() returned mutable pointer → data race. Fixed to return snapshot copy with cloned Messages slice.
Files: `backend/agent/e2e_test.go`, `backend/context/session_store_test.go`, `backend/context/compaction_test.go`, `backend/context/session_store.go`

## FEAT-002: proot + Alpine Runtime — IN PROGRESS
### C1 (Backend Go) — COMPLETE
- [x] `backend/runtime/proot.go` — ProotRuntime struct, Exec(), InstallPackages(), IsReady(), RootFSSize()
- [x] `backend/runtime/detect.go` — DetectProject() with 12 marker rules, AllPackages() dedup
- [x] `backend/tools/shell.go` — NewShellExecWithProot(), platform-aware routing, execDirect() helper
- [x] `backend/tools/tools.go` — DispatcherOpts, DefaultDispatcherWithOpts() with proot support
- [x] `backend/api/messages.go` — TypeRuntimeSetup, TypeRuntimeReady, payload structs
- [x] `backend/agent/engine.go` — Engine stores proot, passes to dispatcher
- [x] `backend/cmd/mocode/main.go` — MOCODE_PROOT_ROOT env var, auto-init proot runtime
- [x] `backend/runtime/proot_test.go` + `detect_test.go` — 16 tests, all passing
- [x] `go build ./...`, `go test ./...`, `go vet ./...` — all clean

### C2 (Flutter + Android) — COMPLETE
- [x] Bundle proot v5.3.0 ARM64 static binary (1.5MB) + Alpine 3.21.3 rootfs (3.7MB) in APK assets
- [x] `scripts/download-runtime.sh` — downloads + verifies proot + Alpine with SHA256 checksums
- [x] `RuntimeBootstrap.kt` — first-launch extraction with SHA256 verification, progress callbacks, version-based skip, Java tar fallback
- [x] `DaemonService.kt` — calls RuntimeBootstrap before daemon start, passes MOCODE_PROOT_BIN/ROOTFS/PROJECTS env vars
- [x] `DaemonBridge.kt` — added getRuntimeStatus() + resetRuntime() platform channel methods
- [x] `daemon.dart` — added getRuntimeStatus(), resetRuntime(), fetchRuntimeStatus() API methods
- [x] `main.go` — reads MOCODE_PROOT_BIN/ROOTFS/PROJECTS env vars, inits ProotRuntime, passes to server
- [x] `server.go` — GET /api/runtime/status endpoint, SetProot() method
- [x] `config_screen.dart` — Runtime Environment section with status, size, reset button + confirmation dialog
- [x] `agent_screen.dart` — bootstrap progress polling (progress bar + percentage during first launch extraction)
- [x] `.gitignore` — added *.aab, *.apk, .kotlin/, .gradle/, **/.cxx/, runtime binary assets
- [x] `scripts/release.sh` — improved with --quick flag, javac check, keystore path fix documentation
- [x] `docs/PLAY_STORE_DEPLOYMENT.md` — full deployment guide (setup, build, upload, version bumping, data safety, troubleshooting)
- [x] Release AAB builds successfully (44.3MB)

## Redesign Round 1 — COMPLETE (2026-04-13)
- [x] E6: Structured tool results — `Result{Title, Metadata, Output}` across all 16 tools (C1)
- [x] E9: Session persistence — `session_store.go` with save/restore across restarts (C2)
- [x] E14: Subagent/Task tool — `subagent.go` + `task.go` for spawning focused sub-sessions (C3)
- [x] E15: WebFetch tool — `webfetch.go` with HTML→markdown conversion (C3)
- [x] E12: Flutter diff viewer widget — `diff_viewer.dart` (C4)
- [x] E13: Flutter TODO panel widget — `todo_panel.dart` (C4)

## Redesign Round 2 — COMPLETE
- [x] E17: Plan mode — read-only agent mode (C1) ✓
- [x] E22: Permission system — granular tool/path permissions (C1) ✓
- [x] E19: More providers — OpenRouter, Ollama, Azure (C2) ✓
- [x] E20: Session history UI — Flutter screen with resume (C3) ✓
- [x] E21: Fuzzy file search — Flutter file search (C3) ✓
- [x] H1: Summary compression budget (C4) ✓
- [x] H3: Git context in system prompt (C4) ✓
- [x] H4: Continuation preamble after compaction (C4) ✓

## Redesign Round 3 — COMPLETE
- [x] Android foreground service — DaemonService.kt, DaemonBridge.kt, platform channel, daemon.dart integration (C1) ✓
- [x] End-to-end integration testing — tools/e2e_test.go (20+ tests), agent/e2e_test.go (6 tests), cancel bug fix in engine.go (C2) ✓
- [x] Flutter polish — shimmer loading, connection banner, auto-reconnect, error/retry states, pull-to-refresh (C3) ✓
- [x] Release pipeline — scripts fixed, release.sh, v1.1.0+2, SDK 35, store listing updated (C4) ✓

## Redesign Round 4 — COMPLETE
- [x] Bug fixes from R3 — no outstanding bugs after C2 E2E testing (C1) ✓
- [x] Performance + resilience — provider retry with backoff, HTTP timeouts + connection pooling across all 6 providers, WebSocket auto-reconnect in daemon.dart (C1) ✓
- [x] Docs + scripts + final QA (C3) — API_PROTOCOL.md rewritten, cmd tests added, /health alias, all issues resolved ✓

## Round 5 — Beta Testing — COMPLETE
- [x] Agent chat flow — streaming works, task.complete received (C3) ✓
- [x] Model/provider switching — all Copilot models, 3 provider switches, error handling (C3) ✓
- [x] File browser — bug found: missing HTTP endpoints `/file/content`, `/find/file`, `/find`, `/session`. Fixed in server.go (C3) ✓
- [x] Session history — list, get, delete via WebSocket (C3) ✓
- [x] Config screen — config.set, status, provider.switch all working (C3) ✓
- [x] Error states — invalid types, empty prompts handled gracefully (C3) ✓
- [x] Model selection redesign — GitHub Copilot is single provider with multiple models, not separate providers. Rewrote provider_switcher.dart with flat model lists per provider (C3) ✓
- [x] Auto-reconnect — exponential backoff (1s→30s), manual retry, connection banner (C3) ✓

### Bugs found and fixed during R5:
1. **Missing HTTP endpoints** — Flutter Files tab and session listing non-functional. Added `/file/content`, `/find/file`, `/find`, `/session` handlers to server.go
2. **File path doubling** — `/file/content?path=backend/api/server.go` resolved to `backend/backend/api/server.go` when daemon CWD was `backend/`. Fixed path resolution logic
3. **Model selection architecture** — Switching to "Claude Sonnet 4" under Copilot incorrectly changed provider to `claude`. Redesigned: models are flat list within each provider, model switch sends `config.set` not `provider.switch`

## Pre-redesign completed
- [x] Bootstrap Go backend daemon with health endpoint
- [x] Research: OpenCode serve as backend
- [x] Scaffold Flutter app (4 screens)
- [x] Wire Flutter to OpenCode HTTP API
- [x] Fix all Flutter compilation/analysis issues
- [x] Implement slash commands, Copilot auth, stop button, config tab
- [x] Play Store config (icon, signing, listing, privacy policy)
- [x] Overhaul system prompt + per-provider prompts (E1)
- [x] File edit tool (E2), Grep (E3), Glob (E4)
- [x] Context compaction (E5)
- [x] Output truncation (E7)
- [x] Instruction file discovery (E8)
- [x] Shell tool improvements (E10)
- [x] Streaming markdown renderer (E11)
- [x] Per-model context limits (E18)
- [x] Ask_user/Question tool (E16)
- [x] Handle all agent event kinds in Flutter UI

## Known issues remaining
- ~~ISSUE-003: Stale protocol docs~~ — RESOLVED (R4-C3, API_PROTOCOL.md fully rewritten)
- ~~ISSUE-004: Missing cmd tests~~ — RESOLVED (R4-C3, main_test.go with 5 tests)
- ~~ISSUE-005: Redundant backend entrypoint~~ — RESOLVED (R4-C3, confirmed custom daemon is sole backend)
- ~~ISSUE-006: Broken automation scripts~~ — RESOLVED (R3-C4, all scripts rewritten)
- ~~ISSUE-008b: Health endpoint 404~~ — RESOLVED (R4-C3, added /health alias route)

All known issues resolved.

## Build note
All packages compile and pass tests: `go build ./...`, `go test ./...`, `go vet ./...` clean.

## File map
- `backend/` — Go daemon with agent engine, tools, providers, session persistence
- `backend/agent/` — Engine, plan engine, subagent runner, stub
- `backend/context/` — System prompt, compaction, instructions, session store, models
- `backend/tools/` — 16 tools: file, shell, git, search, edit, question, webfetch, task
- `backend/provider/` — 6 providers: claude, gemini, copilot, openrouter, ollama, azure
- `backend/provider/openai_compat.go` — Shared OpenAI-compatible request/SSE code
- `flutter/` — Flutter mobile app (5 screens + diff viewer, TODO panel, session history, shimmer loading, connection banner widgets)
- `scripts/` — setup, build-go, build-flutter, test, start-server, release (all fixed)
- `backend/cmd/mocode/main_test.go` — 5 tests for port file, working dir, provider env vars
- `docs/` — project spec and reference docs (API_PROTOCOL.md fully current)
- `issues/` — issue tracker (all 5 issues resolved)
- `WORKPLAN.md` — full 4-round parallel work plan
- `REDESIGN_PLAN.md` — gap analysis with code snippets
