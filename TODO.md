# Mo-Code TODO

## P0 — blocking
- [x] Bootstrap Go backend daemon with localhost health endpoint
- [x] Add daemon port discovery file support
- [x] Add localhost WebSocket endpoint and message envelope types
- [x] Research: OpenCode has built-in serve command — use instead of custom Go daemon
- [x] Install OpenCode and test integration
- [x] Test Flutter ↔ OpenCode serve connection

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

## P2 — nice to have
- [x] Add basic repo automation scripts

## Done (last 10)
- [x] Added WebSocket endpoint and passing backend tests — completed 2026-04-12
- [x] Added initial runnable Go daemon slice with health endpoint — completed 2026-04-12
- [x] Extracted project docs into `docs/` — completed 2026-04-12
- [x] Created global `mo-code-creation` skill — completed 2026-04-12
- [x] Flutter app adapted to use OpenCode HTTP API — completed 2026-04-12
- [x] Added repo automation scripts (setup, build-go, build-flutter, test, start-server) — completed 2026-04-12
