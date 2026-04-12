# Mo-Code TODO

## P0 — blocking
- [x] Bootstrap Go backend daemon with localhost health endpoint
- [x] Add daemon port discovery file support
- [x] Add localhost WebSocket endpoint and message envelope types
- [x] Research: OpenCode has built-in serve command — use instead of custom Go daemon
- [x] Install OpenCode and test integration
- [x] Test Flutter ↔ OpenCode serve connection
- [x] Fix Flutter compilation errors (duplicate listSessions, TerminalLine content)
- [x] Fix broken pubspec dependency (speech_to_text)
- [x] Fix config_screen API class mismatch (MoCodeAPI → OpenCodeAPI)

## P1 — important
- [x] Scaffold Flutter app structure (adapted to OpenCode HTTP API)
- [x] Implement WebSocket read/write lifecycle and keepalive (deprecated — now using HTTP + SSE)
- [x] Add `/api/config` endpoints (deprecated — now using OpenCode API)
- [x] Write backend tests for health and WS lifecycle
- [x] Add task manager and task lifecycle messages (deprecated)
- [x] Expand protocol structs beyond generic envelope/ack (deprecated)
- [x] Add file browser screen
- [x] Add task manager screen
- [x] Install recommended Codex skills from `docs/skills/README.md` on the local machine as needed
- [x] Implement slash commands (/model, /skills, /stop, /clear, /provider, /session)
- [x] Implement GitHub Copilot Device Auth flow (Go backend + Flutter UI)
- [x] Add stop/interrupt button for running tasks
- [x] Add Config screen with provider auth + working directory
- [ ] Wire .mocode centralized storage into active use
- [ ] Session/memory persistence across daemon restarts

## P2 — nice to have
- [x] Add basic repo automation scripts
- [ ] Update API_PROTOCOL.md to reflect current HTTP+SSE architecture
- [ ] Add tests for backend/cmd/mocode entrypoint
- [ ] Fix automation scripts (build-flutter.sh path assumptions)
- [ ] Android foreground service (Kotlin native layer)

## Done (last 10)
- [x] Slash commands, device auth, stop button, config tab — completed 2026-04-12
- [x] Fixed all Flutter compilation and analysis issues — completed 2026-04-12
- [x] Added Copilot auth HTTP endpoints to Go backend — completed 2026-04-12
- [x] Added fetchConfig/fetchStatus/sendWsMessage/cancelSession to OpenCodeAPI — completed 2026-04-12
- [x] Added WebSocket endpoint and passing backend tests — completed 2026-04-12
- [x] Added initial runnable Go daemon slice with health endpoint — completed 2026-04-12
- [x] Extracted project docs into `docs/` — completed 2026-04-12
- [x] Created global `mo-code-creation` skill — completed 2026-04-12
- [x] Flutter app adapted to use OpenCode HTTP API — completed 2026-04-12
- [x] Added repo automation scripts (setup, build-go, build-flutter, test, start-server) — completed 2026-04-12
