---
name: mo-code
description: Build mo-code — a mobile-first AI coding agent app. Flutter terminal-style UI + OpenCode Go backend running locally on Android (iOS later). Multi-provider (Claude, Gemini, Copilot). Background task execution, git integration, checkpoint-based multi-agent handoff. Use this skill whenever working on any part of mo-code — Flutter UI, Go backend, WebSocket bridge, provider abstraction, git integration, checkpoint system, or project scaffolding. Also trigger when the user mentions "mo-code", "mobile coding agent", "opencode flutter", "mobile IDE", or anything about building/coding from a phone.
---

# Mo-Code: Mobile-First AI Coding Agent

## What is mo-code?

Mo-code is a mobile app that lets you build software from your phone and push it to GitHub. You describe what you want, an AI agent writes the code, runs commands, and iterates — all locally on-device, with work continuing in the background.

It is NOT a chat wrapper. It is a full agent runtime with file system access, shell execution, git operations, and multi-provider LLM support.

## Core philosophy

- Build on mobile, push to GitHub — that is the entire UX
- Agent does the typing, you approve and redirect
- Work runs in background even when you switch apps
- Every agent session checkpoints progress so the next agent (or human) picks up seamlessly

## Architecture overview

Read `references/ARCHITECTURE.md` for the full technical architecture with diagrams. Here is the summary:

```
┌─────────────────────────────────────┐
│  Flutter UI (terminal-style)        │
│  ┌──────┐ ┌──────┐ ┌─────────────┐ │
│  │Agent │ │Tasks │ │Files + Git  │ │
│  │View  │ │Mgr  │ │Browser      │ │
│  └──────┘ └──────┘ └─────────────┘ │
│  └──── WebSocket Client ──────┘    │
└──────────────┬──────────────────────┘
               │ ws://localhost:PORT
┌──────────────▼──────────────────────┐
│  OpenCode Go Backend (local daemon) │
│  ┌────────┐ ┌────────┐ ┌────────┐  │
│  │Agent   │ │Context │ │Tool    │  │
│  │Runtime │ │Manager │ │Dispatch│  │
│  └────────┘ └────────┘ └────────┘  │
│  ┌─────────────┐ ┌──────────────┐  │
│  │Provider     │ │WS + HTTP     │  │
│  │Abstraction  │ │Server        │  │
│  └─────────────┘ └──────────────┘  │
│  └── Android Foreground Service ─┘ │
└──────────────┬──────────────────────┘
       ┌───────┼───────┐
       ▼       ▼       ▼
   Claude  Gemini  Copilot
       │               │
   Local FS        go-git
```

### Bridge: Go ↔ Flutter

The Go backend runs as a localhost WebSocket + HTTP server. Flutter connects via `ws://localhost:PORT`. This approach was chosen because:

- Clean process separation — no FFI memory management
- Streaming for free — WebSocket is ideal for token-by-token LLM output
- Easy to debug — you can curl the Go server independently
- Future-proof — web/desktop clients can connect to the same server

Do NOT use gomobile bind or dart:ffi. The WebSocket bridge is the canonical approach.

### Why OpenCode as backend

OpenCode provides battle-tested implementations of:

- Agent loop with planning, execution, and iteration
- Context management with token budgeting and LSP-aware file context
- Tool dispatch (file read/write, shell exec, git)
- Provider abstraction for multiple LLM APIs
- Conversation threading and management

We fork OpenCode and strip the Bubble Tea TUI layer, replacing it with an HTTP/WebSocket API layer.

## Checkpoint system (critical for multi-agent handoff)

Every agent working on mo-code MUST maintain the checkpoint file. This is how agents hand off work to each other.

### Checkpoint file: `CHECKPOINT.md`

Located at project root. Updated after every meaningful unit of work.

```markdown
# Mo-Code Checkpoint

## Last updated
[timestamp] by [agent-name]

## Current phase
[phase name from Jira epic]

## Completed
- [x] Task description — [brief notes on what was done]
- [x] Task description — [file paths affected]

## In progress
- [ ] Task description — [what's been started, where it left off]
  - Current state: [specific detail — e.g., "WebSocket handler written, needs auth middleware"]
  - Blockers: [if any]
  - Files touched: [list]

## Not started
- [ ] Task description
- [ ] Task description

## Key decisions made
- [Decision]: [rationale] — [date]
- [Decision]: [rationale] — [date]

## Known issues
- [Issue description] — [severity: low/medium/high]

## File map (what lives where)
- `flutter/` — Flutter app source
- `backend/` — OpenCode fork (Go)
- `backend/api/` — WebSocket + HTTP server layer (new)
- `backend/provider/` — LLM provider abstraction
- `docs/` — Architecture docs, this checkpoint
```

### Checkpoint rules

1. Update `CHECKPOINT.md` after completing any task or subtask
2. Update before stopping work (even if mid-task)
3. Include specific file paths and line references when relevant
4. Never delete history — append new entries, mark old ones as done
5. Every agent's first action is to READ `CHECKPOINT.md` before doing anything
6. Write a brief "handoff note" at the top when finishing a session

### TODO tracking: `TODO.md`

Separate from checkpoint. Living task list with priorities.

```markdown
# Mo-Code TODO

## P0 — blocking
- [ ] Description — assigned to [agent/human]

## P1 — important
- [ ] Description

## P2 — nice to have
- [ ] Description

## Done (last 10)
- [x] Description — completed [date]
```

## Project structure

```
mo-code/
├── CHECKPOINT.md              # Multi-agent handoff state
├── TODO.md                    # Living task list
├── README.md                  # Project overview
│
├── flutter/                   # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   │   ├── agent_view.dart        # Terminal-style agent output
│   │   │   ├── task_manager.dart      # Background task list
│   │   │   ├── file_browser.dart      # File tree + git status
│   │   │   └── config.dart            # Settings, API keys, provider select
│   │   ├── widgets/
│   │   │   ├── terminal_output.dart   # Streaming terminal renderer
│   │   │   ├── code_preview.dart      # Syntax-highlighted code view
│   │   │   ├── diff_view.dart         # Git diff display
│   │   │   ├── provider_switcher.dart # Claude/Gemini/Copilot pills
│   │   │   └── task_card.dart         # Background task progress card
│   │   ├── services/
│   │   │   ├── websocket_service.dart # WS connection to Go backend
│   │   │   ├── notification_service.dart
│   │   │   └── background_service.dart
│   │   └── models/
│   │       ├── agent_message.dart
│   │       ├── task.dart
│   │       └── file_node.dart
│   ├── android/
│   │   └── app/src/main/
│   │       └── kotlin/.../ForegroundService.kt
│   └── pubspec.yaml
│
├── backend/                   # OpenCode fork
│   ├── cmd/
│   │   └── mocode/
│   │       └── main.go        # Entry point — starts WS server, no TUI
│   ├── api/                   # NEW — WebSocket + HTTP API layer
│   │   ├── server.go          # HTTP/WS server setup
│   │   ├── handlers.go        # Route handlers
│   │   ├── messages.go        # WS message types
│   │   └── middleware.go      # Auth, CORS, logging
│   ├── agent/                 # From OpenCode — agent loop
│   ├── context/               # From OpenCode — context management
│   ├── provider/              # From OpenCode — LLM provider abstraction
│   │   ├── claude.go
│   │   ├── gemini.go
│   │   ├── copilot.go         # NEW — Copilot provider
│   │   └── provider.go        # Interface
│   ├── tools/                 # From OpenCode — tool implementations
│   │   ├── file.go
│   │   ├── shell.go
│   │   └── git.go             # Uses go-git, no native binary
│   ├── checkpoint/            # NEW — checkpoint system
│   │   ├── checkpoint.go      # Read/write CHECKPOINT.md
│   │   └── todo.go            # Read/write TODO.md
│   ├── go.mod
│   └── go.sum
│
└── docs/
    ├── ARCHITECTURE.md
    ├── SETUP.md
    └── API.md                 # WebSocket message protocol docs
```

## WebSocket message protocol

All communication between Flutter and Go uses JSON messages over WebSocket.

```json
// Flutter → Go: Start a task
{
  "type": "task.start",
  "id": "uuid",
  "payload": {
    "prompt": "Build a REST API with auth",
    "provider": "claude",
    "working_dir": "/data/projects/my-api"
  }
}

// Go → Flutter: Agent streaming output
{
  "type": "agent.stream",
  "task_id": "uuid",
  "payload": {
    "kind": "text|tool_call|tool_result|plan|status",
    "content": "...",
    "metadata": {}
  }
}

// Go → Flutter: Task complete
{
  "type": "task.complete",
  "task_id": "uuid",
  "payload": {
    "files_created": ["src/index.ts", "src/auth.ts"],
    "files_modified": [],
    "summary": "Created REST API with JWT auth"
  }
}

// Flutter → Go: Git operations
{
  "type": "git.commit",
  "payload": {
    "message": "feat: add auth middleware",
    "files": ["src/auth.ts", "src/middleware.ts"]
  }
}

// Go → Flutter: File tree
{
  "type": "fs.tree",
  "payload": {
    "root": "/data/projects/my-api",
    "entries": [
      {"path": "src/index.ts", "type": "file", "git_status": "added"},
      {"path": "src/auth.ts", "type": "file", "git_status": "modified"}
    ]
  }
}
```

See `references/API_PROTOCOL.md` for the complete message specification.

## Build phases

Read `references/JIRA_EPIC.md` for the full Jira epic with stories and subtasks. Summary:

### Phase 1 — Foundation (weeks 1-3)
Fork OpenCode, strip TUI, build WebSocket API layer, scaffold Flutter app, basic terminal output.

### Phase 2 — Agent core (weeks 3-5)
Wire agent runtime to WS, implement provider switching (Claude/Gemini/Copilot), streaming output, tool execution.

### Phase 3 — File & git (weeks 5-7)
File browser, git status, diff view, commit/push flow, go-git integration.

### Phase 4 — Background & UX (weeks 7-9)
Android foreground service, background task manager, notifications, task queue.

### Phase 5 — Polish & ship (weeks 9-11)
Voice input, onboarding, API key management, error handling, testing, Play Store prep.

## Platform-specific notes

### Android
- Shell execution works natively via `os/exec` — Android is Linux
- Go cross-compiles to `linux/arm64` with `GOOS=linux GOARCH=arm64`
- Background execution via Android foreground service with persistent notification
- File storage in app sandbox (`context.getFilesDir()`)
- SSH keys stored in Android Keystore for GitHub auth

### iOS (deferred)
- No `fork/exec` — shell tools won't work
- Options when we get here: sandboxed interpreter, remote execution, or "edit + push only" mode
- Go compiles to iOS via gomobile but exec-dependent tools need replacement
- Background limits are severe — 30s max without special entitlements

## Agent-specific instructions

### For Claude (Claude Code / Codex)
You are likely the primary architect. Focus on the Go backend — the agent runtime, context manager, and WebSocket API layer. You understand OpenCode's patterns best. Start by reading the OpenCode source, identifying which packages to keep vs strip, and building the API layer.

### For Gemini
Focus on the Flutter UI layer. Build the terminal output renderer, provider switcher, and task manager screen. Use the UX mockups in `references/UX_MOCKUPS.md` as your guide. Ensure WebSocket client handles reconnection and streaming gracefully.

### For Copilot
Focus on integration glue — the provider abstraction (especially the Copilot provider itself), git operations via go-git, and the checkpoint system. Write comprehensive tests for the WebSocket protocol.

### For Minimax
Focus on the background service system, notification handling, and task queue. Ensure the Android foreground service keeps the Go daemon alive and provides meaningful progress notifications.

### For any agent
1. FIRST: Read `CHECKPOINT.md`
2. THEN: Read `TODO.md`
3. Work on the highest priority unblocked task
4. Update `CHECKPOINT.md` after each completed unit of work
5. Update `TODO.md` when tasks are completed or new ones discovered
6. Write tests for anything you build
7. Commit with conventional commit messages: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`
