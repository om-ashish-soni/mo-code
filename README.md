# mo-code

Mobile-first AI coding agent.

## What it is

`mo-code` is a two-process system:
- Flutter app for the mobile UI
- local Go daemon for the agent runtime

The bridge between them is localhost HTTP + WebSocket. The backend is intended to be a headless OpenCode-derived daemon, not a terminal app.

## Current status

Initial repo bootstrap in progress.

Phase 1 focus:
- baseline project files
- minimal Go daemon entrypoint
- localhost health endpoint
- daemon port file support

## Repo layout

```text
mo-code/
├── CHECKPOINT.md
├── TODO.md
├── README.md
├── backend/
│   ├── cmd/mocode/
│   └── api/
├── flutter/
└── docs/
```

## Constraints

- No `dart:ffi` or `gomobile`
- WebSocket bridge is canonical
- Go binds localhost only
- Git layer must use `go-git`
- Android foreground service owns daemon lifecycle
