# ISSUE-008: Health Endpoint Not Found (404)

The `README.md` states that Phase 1 includes a "localhost health endpoint", but the daemon returns a 404 for `/health`.

## Symptoms

- Run `curl http://localhost:19280/health`
- Result: `404 page not found`

## Impact

The health of the daemon cannot be verified through the canonical endpoint.

## Proposed Fix

Ensure the `/health` route is registered in the Go backend API server.
