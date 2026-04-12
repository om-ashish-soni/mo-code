# Mo-Code Redesign — Full Work Plan

*Created: 2026-04-13*
*Based on: REDESIGN_PLAN.md gap analysis of OpenCode + Claw-Code*

## Architecture

Mo-code = Flutter terminal UI + OpenCode Go backend, running locally on Android.
Multi-provider (Claude, Gemini, Copilot). OpenCode `serve` on port 4096 as primary backend.
Custom Go daemon for Copilot auth + future features.

## Already Completed (from REDESIGN_PLAN.md)

| Item | Description | Commit |
|------|-------------|--------|
| E1 | System prompt overhaul + per-provider prompts | `a4e8841` |
| E2 | File edit tool (in `file.go`) | `62f48c5` |
| E3 | Grep tool (`search.go`) | `62f48c5` |
| E4 | Glob tool (`search.go`) | `62f48c5` |
| E5 | Context compaction (`compaction.go`) | `a4e8841` |
| E7 | Output truncation (`truncate.go`) | `0a1dec2` |
| E8 | Instruction file discovery (`instructions.go`) | `a4e8841` |
| E10 | Shell tool improvements | `a4e8841` |
| E11 | Streaming markdown renderer (Flutter) | `9af401f` |
| E16 | Question/ask_user tool (`question.go`) | `0a1dec2` |
| E18 | Per-model context limits (`models.go`) | `52b348d` |
| — | Flutter event handling for all agent events | `4157a1c` |

---

## Round 1 — Foundation (4 parallel, no cross-dependencies)

| Agent | Role | Focus | Items | Key Files |
|-------|------|-------|-------|-----------|
| **C1** | Backend: Structured Results | Refactor all tools to return `ToolResult{Title, Metadata, Output}` instead of plain strings, update `engine.go` event emission | E6 | `backend/tools/tools.go`, all tool files, `backend/agent/engine.go` |
| **C2** | Backend: Session Persistence | SQLite/file store for conversations, save/restore across daemon restarts, session model | E9 | Create `backend/context/session_store.go`, modify `backend/agent/engine.go` |
| **C3** | Backend: New Tools | Subagent/Task tool + WebFetch with HTML→MD conversion | E14, E15 | Create `backend/tools/task.go`, `backend/tools/webfetch.go`, `backend/agent/subagent.go` |
| **C4** | Flutter: New Widgets | Diff viewer widget + TODO panel widget | E12, E13 | Create `flutter/lib/widgets/diff_viewer.dart`, `flutter/lib/widgets/todo_panel.dart` |

**Dependency:** None between agents. All can work in parallel.
**Output:** Backend has structured results + persistence + 2 new tools. Flutter has diff + TODO widgets.

---

## Round 2 — Features on top of Round 1 (4 parallel)

| Agent | Role | Focus | Items | Depends On |
|-------|------|-------|-------|------------|
| **C1** | Backend: Plan + Permissions | Read-only plan agent mode + granular permission system | E17, E22 | R1-C1 (structured results) |
| **C2** | Backend: Providers | OpenRouter, Ollama, Azure providers | E19 | R1-C1 (structured results) |
| **C3** | Flutter: Screens | Session history UI with resume + fuzzy file search | E20, E21 | R1-C2 (session persistence) |
| **C4** | Backend: Claw-Code Innovations | Summary compression budget + git context in system prompt + continuation preamble | H1, H3, H4 | R1-C1 (structured results) |

**Dependency:** All depend on Round 1 completion.
**Output:** Full multi-agent architecture, 6+ providers, session history in UI, smarter compaction.

---

## Round 3 — Integration + Mobile (4 parallel)

| Agent | Role | Focus | Items | Depends On |
|-------|------|-------|-------|------------|
| **C1** | Android: Foreground Service | Kotlin native layer, battery optimization, notification channel | — | R2 complete |
| **C2** | Testing: End-to-End | Test all tools against real Claude/Gemini/Copilot, fix mismatches | — | R2 complete |
| **C3** | Flutter: Polish | Error states, loading skeletons, empty states, network interruption, edge cases | — | R2 complete |
| **C4** | Release: Pipeline | Fix automation scripts, AAB build config, version bump, store listing review | — | R2 complete |

**Dependency:** All depend on Round 2 completion.
**Output:** App runs reliably on real Android, all providers tested, release-ready build pipeline.

---

## Round 4 — Final Hardening (3 parallel)

| Agent | Role | Focus | Depends On |
|-------|------|-------|------------|
| **C1** | Bug Fixes | Fix everything surfaced in Round 3 integration testing | R3 complete |
| **C2** | Performance + Resilience | Token usage optimization, reconnection logic, background task survival | R3 complete |
| **C3** | Docs + Scripts + QA | Update API_PROTOCOL.md, fix remaining issues (003-008b), final CHECKPOINT | R3 complete |

**Dependency:** All depend on Round 3 completion.
**Output:** Stable, documented, ready for beta.

---

## Round 5 — Beta Testing (1 session)

Single Claude session: install on device, run through all flows (agent chat, file browse, session resume, provider switching, diff viewing, plan mode), file bugs, fix what's fixable, stamp for Play Store.

**Om manual steps** (parallel with R4/R5): keystore generation, Play Console setup, AAB upload, tester rollout.

---

## Summary

```
R1 (4) → R2 (4) → R3 (4) → R4 (3) → R5 (1 beta)
15 Claude sessions + 1 beta + Om manual = shipped
```

## Reference Code

- **OpenCode repo:** anomalyco/opencode — primary reference for tools, prompts, session management
- **Claw-Code repo:** ultraworkers/claw-code — reference for compaction, session persistence, git context
- **REDESIGN_PLAN.md** — full gap analysis with code snippets and architecture notes

## Key Files Map

```
backend/
  agent/engine.go        — main agent loop, event emission
  agent/runner.go         — provider runner interface
  context/context.go      — system prompt builder
  context/compaction.go   — context compaction
  context/instructions.go — AGENTS.md/CLAUDE.md discovery
  context/models.go       — per-model context limits
  context/prompts.go      — per-provider prompt constants
  tools/tools.go          — tool registry + dispatch
  tools/file.go           — file read/write/edit
  tools/search.go         — grep + glob
  tools/shell.go          — shell execution
  tools/question.go       — ask_user tool
  tools/truncate.go       — output truncation
  tools/git.go            — git operations
  api/server.go           — HTTP API server
  api/messages.go         — API message types
  provider/               — Claude, Gemini, Copilot providers

flutter/
  lib/main.dart
  lib/screens/agent_screen.dart
  lib/screens/config_screen.dart
  lib/screens/files_screen.dart
  lib/screens/tasks_screen.dart
  lib/widgets/terminal_output.dart
  lib/widgets/input_bar.dart
  lib/widgets/provider_switcher.dart
  lib/api/daemon.go
```
