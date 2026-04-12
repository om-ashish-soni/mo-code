# Mo-Code Checkpoint

## Last updated
2026-04-13 by Claude (C3, Round 5 beta testing complete)

## Handoff note
Round 5 beta testing COMPLETE. All flows tested on Linux desktop, bugs found and fixed. App is functional end-to-end.

Architecture: Custom Go daemon with agent engine, 6 providers (Claude, Gemini, Copilot, OpenRouter, Ollama, Azure). Flutter app with 5 screens (Agent, Files, Tasks, Config, Sessions). Localhost HTTP + WebSocket. Android foreground service keeps daemon alive when backgrounded. All providers have retry with exponential backoff, HTTP timeouts, and connection pooling. WebSocket auto-reconnects on disconnect.

**Play Store release:** Version 1.1.0+2, SDK 35, `./scripts/release.sh` ready. Blocked on Om: keystore generation, key.properties, run `./scripts/release.sh`, Play Console upload.

**Build status:** `flutter analyze` clean. `go build ./...`, `go test ./...`, `go vet ./...` all clean.

## Current phase
Round 5 COMPLETE — beta tested, all flows working.

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
