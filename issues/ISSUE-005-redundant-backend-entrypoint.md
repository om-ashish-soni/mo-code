# ISSUE-005: Redundant/Unused Backend Entrypoint

## Status
RESOLVED (R4-C3)

## Description
The repository previously had confusion about whether the custom Go daemon or `opencode serve` was the primary backend.

## Resolution
The custom Go daemon (`backend/cmd/mocode/main.go`) is the sole backend. All references to `opencode serve` have been removed. Scripts (`start-server.sh`, `release.sh`) use the custom daemon. The daemon provides:
- HTTP API on localhost (health, config, status, copilot auth)
- WebSocket for real-time agent communication
- Agent engine with 6 providers, 16 tools, session persistence
- Plan mode with read-only agent
