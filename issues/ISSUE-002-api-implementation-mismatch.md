# ISSUE-002: Documentation vs. Implementation Mismatch (API)

## Status
RESOLVED (2026-04-12) — config_screen.dart fixed to use OpenCodeAPI

## Description
`CHECKPOINT.md` (dated 2026-04-12) states:
> Architecture pivot: Using OpenCode's built-in serve command as backend instead of custom Go daemon.

However, the `backend/` directory still contains a full Go implementation of a WebSocket server using `gorilla/websocket`.

## Evidence
- `backend/api/server.go` contains `handleWebSocket` and uses the Gorilla library.
- `backend/go.mod` still includes `github.com/gorilla/websocket`.
- `ARCHITECTURE.md` and `API_PROTOCOL.md` have conflicting information about whether WebSocket or HTTP+SSE is canonical.

## Impact
Confusion for developers regarding the source of truth for the backend. It's unclear if `backend/` is deprecated or if the docs are premature.
