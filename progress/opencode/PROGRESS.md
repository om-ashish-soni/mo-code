# OpenCode — Progress

## Branch: `opencode/agent-runtime`

## Status: core packages complete, Copilot device auth complete, Engine wired into main.go, integration pending

## Scope
- Fork OpenCode and strip Bubble Tea TUI
- Expose agent runtime as Go package implementing `agent.Runner` interface
- Wire provider abstraction (Claude, Gemini, Copilot)
- Adapt tool dispatch (file, shell, git) for daemon mode
- Context management for token budgeting
- Tests for agent runtime and provider switching

## Completed

### Engine wiring and configuration (`backend/cmd/mocode/main.go`)
- `main.go` now creates `provider.Registry` and `agent.Engine` instead of `StubRunner`
- Provider API keys can be configured via environment variables: `CLAUDE_API_KEY`, `GEMINI_API_KEY`, `COPILOT_API_KEY`
- ConfigManager wired to Registry — when API keys are set via WS `config.set`, they flow to provider Registry automatically

### Tools package (`backend/tools/`)
- `tools.go` — `Tool` interface, `Dispatcher` (routes tool calls by name), `DefaultDispatcher` factory
- `file.go` — `FileRead` (with offset/limit, line numbers), `FileWrite` (create/overwrite with dir creation), `FileList` (recursive with depth limit)
- `shell.go` — `ShellExec` (timeout, output truncation, dangerous command blocking)
- `git.go` — `GitStatus` (porcelain v2), `GitDiff` (staged/unstaged, path filter), `GitLog` (count, oneline)
- `tools_test.go` — 16 tests covering dispatcher, all file tools, shell safety, path traversal

### Context package (`backend/context/`)
- `context.go` — `Manager` (conversation history, token budgeting, trimming, usage tracking), `BuildSystemPrompt`
- `context_test.go` — 9 tests covering add/retrieve, trimming, usage recording, clear, summary

### Agent engine (`backend/agent/`)
- `engine.go` — `Engine` struct implementing `Runner` interface. Full agentic loop: LLM call → tool calls → tool results → repeat (max 25 rounds). Emits all `EventKind` types. Compile-time `var _ Runner = (*Engine)(nil)` check.
- `engine_test.go` — 8 tests covering interface conformance, text-only responses, full tool-call loop, max rounds exceeded, status/cancel operations, engine info, unconfigured provider errors

### Build & test verification
- `go build ./cmd/mocode/` passes
- `go test ./...` passes (78 tests across 5 packages: agent=8, api=4, context=9, provider=38, tools=16)
- No new dependencies added to go.mod (git tools use CLI, not go-git)

## In progress
- Copilot WS protocol integration — auth flow works at provider level, but API layer needs new message types (`copilot.auth_start`, `copilot.auth_status`, `copilot.auth_poll`) to drive it via WebSocket. This is in Claude's domain (`backend/api/`); integration doc provided in `progress/opencode/COPILOT_WS_INTEGRATION.md`.

## Next steps
- Claude's API layer implements Copilot WS handlers (see integration doc)
- Add go-git dependency for programmatic git operations (commit, push via SSH)

## Blockers
_(none)_

## Files touched
- `backend/provider/provider.go` (created)
- `backend/provider/claude.go` (created)
- `backend/provider/gemini.go` (created)
- `backend/provider/copilot.go` (created → modified: auth integration)
- `backend/provider/copilot_auth.go` (created)
- `backend/provider/copilot_auth_test.go` (created)
- `backend/provider/registry.go` (created → modified: CopilotAuth accessor)
- `backend/provider/registry_test.go` (created)
- `backend/tools/tools.go` (created)
- `backend/tools/file.go` (created)
- `backend/tools/shell.go` (created)
- `backend/tools/git.go` (created)
- `backend/tools/tools_test.go` (created)
- `backend/context/context.go` (created)
- `backend/context/context_test.go` (created)
- `backend/cmd/mocode/main.go` (modified: Engine wiring, env var config)
- `progress/opencode/PROGRESS.md` (updated)
- `progress/opencode/DECISIONS.md` (updated)
- `progress/opencode/COPILOT_WS_INTEGRATION.md` (created)

## Decisions made
See `DECISIONS.md`.
