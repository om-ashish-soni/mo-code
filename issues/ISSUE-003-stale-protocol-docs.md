# ISSUE-003: Stale Protocol Documentation

## Status
RESOLVED (R4-C3)

## Description
`API_PROTOCOL.md` described a deprecated WebSocket-only format and was out of date with the actual HTTP + WebSocket architecture.

## Resolution
Fully rewrote `docs/API_PROTOCOL.md` to match the current implementation:
- HTTP REST endpoints (health, status, config, copilot auth)
- WebSocket message types (17 client→server, 13 server→client)
- All agent stream kinds including `diff` and `todo_update`
- Session management messages (list, get, resume, delete)
- Plan mode (`plan.start`)
- 6 providers with env var configuration
- All 11 error codes
