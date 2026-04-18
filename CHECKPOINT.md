# Mo-Code Checkpoint

## Last updated
2026-04-14 by Claude (architecture review, Android 15 fix, Linux beta readiness)

## Handoff note
FEAT-004 proot Android 15 fix: IMPLEMENTED (loader compiled, pending device test).
Linux desktop beta: ~85% ready, 4 small gaps documented below.
Strategy pattern + feature toggles: brainstormed, deferred until MO-63.

---

## Current State (2026-04-14)

### Version: 1.2.0+3

### What's complete and working
- Full agent loop (16 tools, 6 providers, session continuity, compaction)
- proot + Alpine runtime on Android ≤14 — fully working
- FEAT-004 memfd_create loader — compiled, committed to jniLibs, **pending device test on Android 15**
- proot diagnostics: `Diagnose()` in Go, `/api/runtime/diagnose` endpoint, degraded banner in Flutter
- Subagents receive proot runtime (shell commands routed through Alpine)
- Docs: `docs/issues/ISSUE-010-proot-exit255-android15.md` written
- FEAT-004 status updated to IMPLEMENTED in `docs/features/FEAT-004-proot-android15-memfd-fix.md`

### Uncommitted changes (13 modified + 6 untracked)
All changes are related to FEAT-004 (proot diagnostics + Android 15 loader fix):

| File | Change |
|---|---|
| `backend/agent/engine.go` | Pass proot to subagent runner |
| `backend/agent/subagent.go` | Accept proot, conditional shell tool registration |
| `backend/agent/subagent_test.go` | 4 new tests |
| `backend/api/server.go` | POST /api/runtime/diagnose endpoint |
| `backend/cmd/mocode/main.go` | Diagnose() at startup, retry installs, detailed logging |
| `backend/runtime/proot.go` | Diagnose(), packageInstalledOnDisk(), seed installed map |
| `backend/runtime/proot_test.go` | 5 new diagnostic tests |
| `backend/tools/shell.go` | Exit-127 hints + apkPackageForCommand() |
| `flutter/lib/api/daemon.dart` | runProotDiagnostic() HTTP call |
| `flutter/lib/screens/agent_screen.dart` | _checkProotHealth() + degraded banner |
| `flutter/lib/screens/config_screen.dart` | Run Diagnostic button + result card |
| `flutter/pubspec.yaml` | Version 1.2.0+3 |
| `docs/JIRA_EPIC.md` | Feature tracking updates |

Untracked (new):
- `loader/loader.c` — patched proot loader with memfd_create fallback
- `flutter/android/app/src/main/jniLibs/arm64-v8a/libproot-loader.so` — compiled (2.8KB)
- `scripts/build-loader.sh` + `scripts/verify-loader.sh`
- `backend/mo-feed/` — tech intelligence pipeline
- `docs/issues/ISSUE-010-proot-exit255-android15.md` — new
- `store-listing/release-notes-1.2.0.txt`

---

## Next priorities

### P0 — Verify Android 15 fix on device
```bash
adb shell run-as io.github.omashishsoni.mocode \
  /data/app/*/lib/arm64/libproot.so \
    -0 -r .../files/runtime/rootfs \
    -b /dev -b /proc -b /sys \
    -w /home/developer \
    /bin/sh -c "echo ok && npm --version && python3 --version && git --version"
```
Expected: version strings, no exit 255. Then commit + release 1.2.0.

### P1 — Linux desktop beta (4 gaps, ~half day of work)
1. Fix `APPLICATION_ID` in `flutter/linux/CMakeLists.txt` (`com.example.mo_code` → `io.github.omashishsoni.mocode`)
2. Hide bootstrap progress UI on non-Android (`agent_screen.dart`)
3. Hide proot/runtime section in `config_screen.dart` on non-Android
4. Write `scripts/run-linux.sh` (starts daemon + Flutter together)
5. Package as tarball → GitHub Release

Linux flow (works today — just needs polish):
- `./scripts/start-server.sh` → daemon on port 19280
- `flutter build linux --release` → `build/linux/x64/release/bundle/mo_code`
- All tools work natively (no proot needed on Linux)

### P2 — MO-63: Static NDK binaries (permanent Android 15 fix)
Compile node, python3, git, busybox as static ARM64, ship as `.so` in jniLibs.
Eliminates proot dependency for common tools. Opens iOS path.
Implement alongside Strategy pattern + feature toggles (brainstormed 2026-04-14).

### P3 — Strategy pattern + feature toggles (deferred until MO-63)
`ExecutionStrategy` interface with DirectExec, Proot, StaticBin, Remote strategies.
`StrategyResolver` picks strategy per command based on `RuntimeToggles`.
Toggles auto-derived from Diagnose() at startup.
Worth doing at MO-63 time, premature before that (only 2 strategies today).

---

| Claude | Scope | Key files | Status |
|--------|-------|-----------|--------|
| **C1** | Flutter agent screen — session ID lifecycle, startTask vs resumeSession routing, /clear reset | `agent_screen.dart`, `daemon.dart` | **COMPLETE** |
| **C2** | Backend hardening — session.info, session.clear message types, compaction counter, concurrent task guard | `server.go`, `messages.go`, `session_store.go`, `engine.go` | **COMPLETE** |
| **C3** | Testing — multi-turn e2e, compaction under resume, concurrent access, provider switch | `e2e_test.go`, `session_store_test.go`, `compaction_test.go` | **COMPLETE** |

**No file conflicts between C1/C2/C3.** All can start in parallel.

**Build status:** `go build ./...`, `go test ./...`, `go vet ./...` all clean. `flutter analyze` clean (1 info-level lint).

## Current phase
FEAT-003: Session Context Continuity — ALL COMPLETE. Daemon bundling + logging fixed for on-device testing.

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

## Daemon Bundling + Logging — COMPLETE
- [x] **Root cause found:** Go daemon binary was never placed in APK `assets/bin/arm64-v8a/mocode` → `DaemonService.extractBinary()` returned null → daemon never started → health check failed → "connection failed, server not healthy"
- [x] Cross-compiled ARM64 binary: `GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build` (14MB static)
- [x] Placed at `flutter/android/app/src/main/assets/bin/arm64-v8a/mocode` + VERSION file
- [x] `DaemonService.kt` — daemon stdout/stderr now writes to `daemon.log` file (in addition to logcat)
- [x] `DaemonBridge.kt` — added `getLogs` platform channel method (returns last 200 lines)
- [x] `daemon.dart` — added `getDaemonLogs()` API method
- [x] `config_screen.dart` — "Daemon Logs" section with "View Logs" button → draggable bottom sheet with monospace logs + copy to clipboard
- [x] Binary is gitignored (14MB) — must run `scripts/build-go.sh --android` before building APK

**Build steps for USB debugging:**
```
cd backend && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o ../flutter/android/app/src/main/assets/bin/arm64-v8a/mocode ./cmd/mocode
echo "1.0.0" > ../flutter/android/app/src/main/assets/bin/VERSION
cd ../flutter && flutter build apk --debug
```

## FEAT-002: proot + Alpine Runtime — COMPLETE
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
