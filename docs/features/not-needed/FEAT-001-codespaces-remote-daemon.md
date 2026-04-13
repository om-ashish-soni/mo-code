# FEAT-001: GitHub Codespaces Remote Daemon

**Status:** Proposed
**Priority:** P0 — Unlocks core value prop (vibe code from phone)
**Epic:** Remote Development
**Estimated effort:** M (3-5 days across backend + Flutter + docs)

---

## Problem

mo-code's daemon binds exclusively to `127.0.0.1` and rejects non-localhost WebSocket origins. Users cannot connect their phone to a daemon running in a cloud environment. This means the app only works when the daemon runs on the same device or local network — defeating the purpose of mobile vibe coding.

## Solution

Enable the Go daemon to run inside GitHub Codespaces (and other cloud environments) so that users can:

1. Open a Codespace for their repo
2. Start the daemon with one command
3. Connect from the mo-code app on their phone

## Feasibility Analysis

### What already works

| Component | Status | Notes |
|-----------|--------|-------|
| Daemon runs on Linux | Ready | Go binary, no special deps |
| API keys via env vars | Ready | `CLAUDE_API_KEY`, `GEMINI_API_KEY`, `COPILOT_API_KEY`, etc. |
| Flutter `baseUrl` configurable | Ready | `daemon.dart:37` — `configure(baseUrl: ...)` exists |
| HTTP REST endpoints | Ready | Standard HTTP, works through any reverse proxy |
| WebSocket streaming | Partial | Works over WSS, but origin check blocks non-localhost |

### What needs changes

| Component | Blocker | Fix |
|-----------|---------|-----|
| Server binding | Hard-coded `127.0.0.1` in `listenLocalhost()` (`server.go:1043-1048`) | Add `MOCODE_HOST` env var, default `127.0.0.1`, allow `0.0.0.0` |
| WebSocket origin | `CheckOrigin` rejects non-localhost (`server.go:46-57`) | Add `MOCODE_ALLOWED_ORIGINS` env var; auto-allow `*.app.github.dev` |
| Flutter connect UI | No UI to enter remote daemon URL | Add "Connect to remote" in Config screen |
| Auth/security | No auth on HTTP/WS endpoints | Add optional bearer token (`MOCODE_AUTH_TOKEN`) |
| TLS | Daemon serves plain HTTP | Codespaces port forwarding handles TLS termination — no change needed |

### Codespaces port forwarding

GitHub Codespaces automatically forwards ports over HTTPS:
- Daemon listens on `0.0.0.0:19280` inside the Codespace
- Codespaces exposes it as `https://<codespace-name>-19280.app.github.dev`
- Supports both HTTP and WebSocket (WSS) through the same URL
- Port visibility: `private` (requires GitHub auth) or `public`
- TLS termination handled by Codespaces — daemon stays plain HTTP

### Security considerations

- **Private ports (default):** Codespaces requires GitHub session cookie — only the Codespace owner can access. Safe for most users.
- **Public ports:** Anyone with the URL can connect. Must require `MOCODE_AUTH_TOKEN` when port is public.
- **Bearer token auth:** Simple shared secret. User sets `MOCODE_AUTH_TOKEN=<random>` in Codespace, enters same token in app. No OAuth complexity.
- **No new attack surface:** Daemon already executes shell commands — it's designed to be used by its owner. Auth just prevents unauthorized access to an already-powerful tool.

---

## Implementation Plan

### Story 1: Configurable server binding
**Points:** 2

- [ ] Add `MOCODE_HOST` env var (default `127.0.0.1`)
- [ ] Modify `listenLocalhost()` → `listenOn(host, startPort, maxScan)` in `server.go`
- [ ] When `MOCODE_HOST=0.0.0.0`, bind to all interfaces
- [ ] Update port file to include host:port, not just port
- [ ] Add `--host` CLI flag as alternative to env var

**Files:** `backend/api/server.go`, `backend/cmd/mocode/main.go`

### Story 2: Flexible WebSocket origin check
**Points:** 1

- [ ] Add `MOCODE_ALLOWED_ORIGINS` env var (comma-separated patterns)
- [ ] Auto-allow `*.app.github.dev` and `*.github.dev` when `MOCODE_HOST=0.0.0.0`
- [ ] Support wildcard matching (e.g. `*.gitpod.io`)
- [ ] Keep localhost always allowed

**Files:** `backend/api/server.go`

### Story 3: Optional bearer token auth
**Points:** 2

- [ ] Add `MOCODE_AUTH_TOKEN` env var
- [ ] When set, require `Authorization: Bearer <token>` on all HTTP requests
- [ ] Require token in WebSocket upgrade request (query param `?token=` or header)
- [ ] Return 401 Unauthorized without token
- [ ] Skip auth for `/api/health` (allows connectivity check before auth)

**Files:** `backend/api/server.go` (middleware)

### Story 4: Flutter "Connect to Remote" UI
**Points:** 3

- [ ] Add "Remote Daemon" section in Config screen
- [ ] Text field for daemon URL (e.g. `https://xxx-19280.app.github.dev`)
- [ ] Text field for auth token (obscured)
- [ ] "Test Connection" button — hits `/api/health`
- [ ] Persist remote URL + token in SharedPreferences
- [ ] On app start, try saved remote URL before falling back to localhost
- [ ] Show connected server URL in status bar (local vs remote indicator)
- [ ] QR code scanner option — daemon prints QR code in terminal with connection URL + token

**Files:** `flutter/lib/screens/config_screen.dart`, `flutter/lib/api/daemon.dart`

### Story 5: One-line install script + devcontainer
**Points:** 2

- [ ] Create `scripts/install-remote.sh` — downloads Go binary for platform, starts daemon
- [ ] Create `.devcontainer/devcontainer.json`:
  ```json
  {
    "name": "mo-code",
    "image": "mcr.microsoft.com/devcontainers/go:1.22",
    "postStartCommand": "go build -o mocode ./backend/cmd/mocode && ./mocode serve --host 0.0.0.0",
    "forwardPorts": [19280],
    "portsAttributes": { "19280": { "label": "mo-code daemon", "onAutoForward": "notify" } }
  }
  ```
- [ ] README section: "Use from your phone"
- [ ] Print connection URL + QR code on daemon startup when `MOCODE_HOST=0.0.0.0`

**Files:** `.devcontainer/devcontainer.json`, `scripts/install-remote.sh`, `README.md`

### Story 6: Connection resilience for mobile
**Points:** 2

- [ ] Handle Codespace sleep (idle timeout) — show "Codespace sleeping" state
- [ ] Auto-reconnect with exponential backoff (already exists for localhost, verify it works for remote)
- [ ] Handle HTTPS certificate issues gracefully
- [ ] Offline mode — queue messages when disconnected, send on reconnect
- [ ] Connection quality indicator in status bar

**Files:** `flutter/lib/api/daemon.dart`, `flutter/lib/widgets/connection_banner.dart`

---

## Out of Scope (Future)

- **Gitpod / Railway / Fly.io support** — same pattern, different devcontainer configs. Do after Codespaces is validated.
- **Mo-code hosted SaaS** — managed infra, multi-tenant. Different product entirely.
- **GitHub App / OAuth flow** — auto-create Codespace from the phone. Complex, requires GitHub App registration.
- **Phone-native daemon** — not feasible for real coding (no build tools, no project files).

## User Flow (Target)

```
┌─────────────────────────────────────────────────────────┐
│  1. User has a GitHub repo they want to work on         │
│                                                         │
│  2. Opens Codespace (GitHub mobile app or browser)      │
│     └─ If repo has .devcontainer: daemon auto-starts    │
│     └─ If not: runs `curl ... | sh` one-liner           │
│                                                         │
│  3. Terminal shows:                                     │
│     ┌─────────────────────────────────────────────┐     │
│     │  mo-code daemon running on 0.0.0.0:19280    │     │
│     │  Remote URL: https://xxx-19280.app.gith...  │     │
│     │                                             │     │
│     │  ██████████  ← QR code                      │     │
│     │  ██  ██  ██                                 │     │
│     │  ██████████  Scan to connect                │     │
│     └─────────────────────────────────────────────┘     │
│                                                         │
│  4. User opens mo-code app → Config → Scan QR          │
│     └─ Auto-fills URL + auth token                      │
│     └─ Tests connection → "Connected"                   │
│                                                         │
│  5. Start vibe coding from Agent tab                    │
└─────────────────────────────────────────────────────────┘
```

## Acceptance Criteria

- [ ] Daemon runs in a GitHub Codespace and accepts connections from a phone on a different network
- [ ] WebSocket streaming works through Codespaces port forwarding (no dropped frames, no origin errors)
- [ ] Auth token prevents unauthorized access
- [ ] Flutter app can connect to remote daemon via URL + token
- [ ] Connection persists across app backgrounding
- [ ] Codespace sleep is handled gracefully (reconnect when it wakes)
- [ ] One-command setup in any terminal: `curl -fsSL <url> | sh`
- [ ] QR code shown on daemon start for instant mobile pairing
