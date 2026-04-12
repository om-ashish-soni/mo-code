# Skill: mo-code-creation

## Status

Already installed locally.

## Why this skill exists

This is the primary skill for `mo-code`. It is aligned to the repo's canonical docs and product direction.

It encodes the project's non-negotiable architecture:

- Flutter UI
- local Go daemon
- localhost WebSocket + HTTP bridge
- Android foreground service
- `go-git` instead of native `git`
- checkpoint-based handoff

## Use this skill when

- working anywhere in this repository
- building backend API or daemon slices
- building Flutter screens and WS wiring
- implementing provider switching
- implementing file and git workflows
- updating checkpoint or TODO state

## Expected behavior from agents

- read `CHECKPOINT.md` first
- read relevant docs from `docs/`
- align work to the current Jira phase
- preserve the WebSocket bridge architecture
- update `CHECKPOINT.md` and `TODO.md` after meaningful work

## Do not use this skill to justify

- FFI or gomobile bindings
- replacing the local daemon with a hosted backend
- native `git` as the default git engine
- chat-style UI that ignores the terminal-first design
