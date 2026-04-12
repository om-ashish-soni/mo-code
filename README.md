# mo-code

**AI coding agent in your pocket.** Write, debug, and ship code from your phone — powered by Claude, Gemini, or GitHub Copilot.

```
$ /model claude-4-sonnet
Model set to: claude-4-sonnet

$ fix the auth middleware to validate JWT expiry

> Reading src/middleware/auth.go
> Editing src/middleware/auth.go
~ src/middleware/auth.go: added token expiry check
> Running go test ./middleware/...

Task completed
```

---

## Why

Every other AI coding tool assumes you're at a desk with a keyboard. **mo-code** doesn't.

- Waiting for CI? Review and fix from your phone.
- On the bus? Scaffold that new feature.
- SSH not an option? mo-code runs the agent **locally on your device**.

No cloud relay. No remote server. Your code stays on your phone.

---

## How it works

```
┌─────────────────────────────┐
│     Flutter Mobile App      │
│  ┌───────┬───────┬────────┐ │
│  │ Agent │ Files │ Tasks  │ │
│  │       │       │        │ │
│  │  Terminal-style UI with │ │
│  │  slash commands & live  │ │
│  │  streaming output       │ │
│  └───────┴───────┴────────┘ │
│            │ HTTP/WS         │
│            ▼                 │
│  ┌─────────────────────────┐ │
│  │   Go Agent Runtime      │ │
│  │  ┌───────────────────┐  │ │
│  │  │ Claude │ Gemini   │  │ │
│  │  │ Copilot (no key!) │  │ │
│  │  └───────────────────┘  │ │
│  │  Tools: file, shell, git│ │
│  └─────────────────────────┘ │
│         127.0.0.1 only       │
└─────────────────────────────┘
```

Two processes, one device. The Flutter app talks to a local Go daemon over localhost. Nothing leaves your phone unless you push to a remote.

---

## Features

**Multi-provider** — Switch between Claude, Gemini, and GitHub Copilot mid-conversation. Each provider is a hot-swappable backend.

**GitHub Copilot without API keys** — Sign in with your GitHub account using device auth flow. No tokens to copy-paste.

**Slash commands** — `/model`, `/skills`, `/stop`, `/clear`, `/provider`, `/session` — all work offline, no login required.

**Terminal-style UI** — Syntax-colored output, auto-scroll, tap-to-expand file operations. Dark theme with JetBrains Mono. Feels like a terminal, works like an app.

**Stop button** — Interrupt a running task instantly. No waiting for the model to finish.

**File browser** — Search and read files in your project without leaving the app.

**Task history** — Browse past sessions, pick up where you left off.

**Localhost only** — The daemon binds to `127.0.0.1`. No network exposure. No telemetry.

---

## Quick start

### Prerequisites

- Android device (or emulator)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.0+
- [Go](https://go.dev/dl/) 1.24+
- At least one provider: Claude API key, Gemini API key, or GitHub account (for Copilot)

### Build & run

```bash
# Clone
git clone https://github.com/AiCodeAgent/mo-code.git
cd mo-code

# Build Go backend
cd backend && go build -o mocode ./cmd/mocode && cd ..

# Start daemon
./backend/mocode &

# Run Flutter app
cd flutter
flutter pub get
flutter run
```

The app connects to `127.0.0.1:19280` automatically. Add your API key in the Config tab, or sign in with GitHub for Copilot.

---

## Slash commands

Commands work without login — they run locally in the app.

| Command | What it does |
|---------|-------------|
| `/model [name]` | List or switch models |
| `/skills` | Show all available commands |
| `/provider <name>` | Switch provider (claude, gemini, copilot) |
| `/stop` | Stop the current task |
| `/clear` | Clear terminal output |
| `/session` | Show current session info |

---

## Architecture

| Layer | Tech | Role |
|-------|------|------|
| **UI** | Flutter/Dart | 4 screens: Agent, Files, Tasks, Config |
| **Bridge** | HTTP + WebSocket | localhost on auto-discovered port |
| **Runtime** | Go | Agent loop, tool dispatch, provider registry |
| **Providers** | Go | Claude, Gemini, Copilot (OpenAI-compatible) |
| **Tools** | Go | File ops, shell exec, git (via go-git) |
| **Storage** | `~/.mocode/` | Config, sessions, memory, skills |

### Design constraints

- No `dart:ffi` or `gomobile` — clean process boundary
- Go daemon binds localhost only — no network exposure
- Git operations use pure-Go `go-git` — no system git dependency
- Android foreground service owns daemon lifecycle

---

## Project structure

```
mo-code/
├── backend/                  # Go agent runtime
│   ├── cmd/mocode/           # Daemon entrypoint
│   ├── agent/                # Agent loop + task runner
│   ├── api/                  # HTTP/WS server + auth endpoints
│   ├── provider/             # Claude, Gemini, Copilot + device auth
│   ├── context/              # Conversation history + token management
│   ├── storage/              # ~/.mocode persistence
│   └── tools/                # File, shell, git tool implementations
│
├── flutter/                  # Mobile app
│   └── lib/
│       ├── api/              # OpenCodeAPI client
│       ├── models/           # Message types + state
│       ├── screens/          # Agent, Files, Tasks, Config
│       ├── widgets/          # TerminalOutput, InputBar, ProviderSwitcher
│       └── theme/            # Dark terminal theme
│
├── docs/                     # Architecture, protocol, UX specs
├── issues/                   # Beta testing issue tracker
└── scripts/                  # Build & test automation
```

---

## Providers

| Provider | Auth method | Models |
|----------|------------|--------|
| **Claude** | API key (`sk-ant-...`) | claude-4-sonnet, claude-4-opus, claude-3.5-haiku |
| **Gemini** | API key (`AIza...`) | gemini-2.5-pro, gemini-2.5-flash |
| **Copilot** | GitHub device auth (no key needed) | gpt-4o, claude-4-sonnet |

Switch providers on the fly with the provider pills in the Agent screen or `/provider <name>`.

---

## Status

**Beta** — core agent loop, multi-provider support, and Flutter UI are functional. Actively fixing beta testing issues and adding features.

See [CHECKPOINT.md](CHECKPOINT.md) for detailed progress and [TODO.md](TODO.md) for the roadmap.

### What works
- Agent conversation with streaming output
- Provider switching (Claude / Gemini / Copilot)
- GitHub Copilot device auth (no API keys)
- Slash commands (offline, no login)
- File browser and task history
- Stop/interrupt running tasks
- Config screen with auth management

### What's next
- `.mocode` centralized storage integration
- Session persistence across restarts
- Android foreground service for daemon lifecycle
- Full git operations in-app

---

## Contributing

mo-code is open source. PRs welcome.

```bash
# Run Go tests
cd backend && go test ./...

# Run Dart analysis
cd flutter && dart analyze
```

---

## License

MIT
