# ISSUE-005: Redundant/Unused Backend Entrypoint

## Status
Medium

## Description
The repository contains a full Go backend implementation in `backend/`, but the primary automation script `scripts/start-server.sh` ignores it entirely in favor of `opencode serve`.

## Evidence
- `scripts/start-server.sh` explicitly calls `opencode serve --port 4096`.
- `backend/cmd/mocode/main.go` implements a server that uses `backend/api` logic, which is not being used by the scripts.

## Impact
Increased maintenance surface and confusion about which backend logic (custom vs. OpenCode) is active.
