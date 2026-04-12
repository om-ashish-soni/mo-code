# Mo-Code Checkpoint

## Last updated
2026-04-12 by Claude

## Handoff note
Architecture pivot: Using OpenCode's built-in `serve` command as backend instead of custom Go daemon. OpenCode provides headless HTTP API on port 4096 with session management, message sending, and SSE events. Flutter app adapted to use OpenCode HTTP API.

## Current phase
All phases complete - MVP ready

## Completed
- [x] Loaded canonical docs from `docs/`
- [x] Created initial repo structure for `backend/` and `flutter/`
- [x] Added README.md, CHECKPOINT.md, and TODO.md
- [x] Added minimal Go daemon in backend/cmd/mocode/ (optional)
- [x] Added localhost HTTP server with health endpoint
- [x] Verified Go build and tests pass
- [x] Research: OpenCode has built-in serve command - use instead of custom Go daemon
- [x] Install OpenCode and test integration
- [x] Scaffold Flutter app (Agent, Files, Tasks screens)
- [x] Wire Flutter to OpenCode HTTP API
- [x] Add file browser screen
- [x] Add task manager screen
- [x] Install recommended Codex skills
- [x] Add repo automation scripts

## File map
- `backend/` — Go daemon (optional, OpenCode serve preferred)
- `flutter/` — Flutter mobile app (3 screens)
- `scripts/` — build and test automation
- `docs/` — project spec and reference docs
- `docs/skills/` — skill guidance for agents
- `progress/claude/` — Claude's progress tracking
- `progress/opencode/` — OpenCode's progress tracking
