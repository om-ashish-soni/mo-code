# Mo-Code Checkpoint

## Last updated
2026-04-13 by Claude (C3, Round 3 Flutter polish complete)

## Handoff note
Round 3 C3 (Flutter polish) + C4 (release pipeline) complete. C1 (Android foreground service) and C2 (E2E testing) still pending.

Architecture: Custom Go daemon with agent engine, 6 providers (Claude, Gemini, Copilot, OpenRouter, Ollama, Azure). Flutter app with 5 screens (Agent, Files, Tasks, Config, Sessions). Localhost HTTP + WebSocket.

**Play Store release:** Version 1.1.0+2, SDK 35, `./scripts/release.sh` ready. Blocked on Om: keystore generation, key.properties, run `./scripts/release.sh`, Play Console upload.

**Build status:** `flutter analyze` passes clean (0 issues). Go build status from prior rounds.

## Current phase
Round 3 PARTIAL — C3 + C4 done, C1 + C2 pending

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

## Redesign Round 3 — PARTIAL (C3 + C4 done, C1 + C2 pending)
- [ ] Android foreground service (Kotlin) (C1)
- [ ] End-to-end integration testing (C2)
- [x] Flutter polish — shimmer loading, connection banner, auto-reconnect, error/retry states, pull-to-refresh (C3) ✓
- [x] Release pipeline — scripts fixed, release.sh, v1.1.0+2, SDK 35, store listing updated (C4) ✓

## Redesign Round 4 — PENDING
- [ ] Bug fixes from R3
- [ ] Performance + resilience
- [ ] Docs + scripts + final QA

## Round 5 — Beta testing (1 session)

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
- ISSUE-003: Stale protocol docs (API_PROTOCOL.md)
- ISSUE-004: Missing cmd tests
- ISSUE-005: Redundant backend entrypoint
- ~~ISSUE-006: Broken automation scripts~~ — RESOLVED (R3-C4, all scripts rewritten)
- ISSUE-008b: Health endpoint 404 on custom daemon

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
- `docs/` — project spec and reference docs
- `WORKPLAN.md` — full 4-round parallel work plan
- `REDESIGN_PLAN.md` — gap analysis with code snippets
