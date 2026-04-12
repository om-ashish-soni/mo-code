# ISSUE-003: Stale Protocol Documentation

## Status
Medium

## Description
`API_PROTOCOL.md` describes a complex WebSocket message format (e.g., `task.start`, `agent.stream`) but `CHECKPOINT.md` marks these as "deprecated — now using HTTP + SSE".

## Evidence
- `CHECKPOINT.md` under "P1 — important" marks WebSocket implementation as deprecated.
- `API_PROTOCOL.md` has not been updated to reflect the SSE/HTTP structure.

## Impact
Third-party integrations or frontend developers would be building against a deprecated protocol.
