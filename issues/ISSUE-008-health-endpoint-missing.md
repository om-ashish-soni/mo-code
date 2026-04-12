# ISSUE-008: Health Endpoint Not Found (404)

## Status
RESOLVED (R4-C3)

## Original Problem
`curl http://localhost:19280/health` returned 404.

## Root Cause
The health endpoint was registered at `/api/health`, not `/health`. The test used the wrong path.

## Fix
Added `/health` as an alias for `/api/health` in `server.go`. Both paths now work:
- `GET /api/health` — canonical path
- `GET /health` — convenience alias

Both return: `{"status": "ok", "service": "mo-code-daemon", "timestamp": "..."}`.
