# Mo-Code Checkpoint

## Last updated
2026-04-12 by Claude

## Handoff note
Architecture pivot: Using OpenCode's built-in `serve` command as backend instead of custom Go daemon. OpenCode provides headless HTTP API on port 4096 with session management, message sending, and SSE events. Flutter app adapted to use OpenCode HTTP API.

Custom Go daemon retained for Copilot device auth endpoints and future features that OpenCode doesn't cover.

**Play Store release:** Android scaffold regenerated, applicationId `io.github.omashishsoni.mocode`, app icon generated, release signing wired, store listing and privacy policy written. Blocked on: Android SDK install, keystore generation, AAB build, and Play Console upload (all manual steps by Om).

## Current phase
Play Store internal testing release — config done, build pending

## Completed
- [x] Loaded canonical docs from `docs/`
- [x] Created initial repo structure for `backend/` and `flutter/`
- [x] Added README.md, CHECKPOINT.md, and TODO.md
- [x] Added minimal Go daemon in backend/cmd/mocode/ (optional)
- [x] Added localhost HTTP server with health endpoint
- [x] Verified Go build and tests pass
- [x] Research: OpenCode has built-in serve command - use instead of custom Go daemon
- [x] Install OpenCode and test integration
- [x] Scaffold Flutter app (Agent, Files, Tasks screens)
- [x] Wire Flutter to OpenCode HTTP API
- [x] Add file browser screen
- [x] Add task manager screen
- [x] Install recommended Codex skills
- [x] Add repo automation scripts
- [x] Fix Flutter compilation errors (duplicate listSessions, TerminalLine content param)
- [x] Fix broken pubspec dependency (flutter_speech_to_text → speech_to_text)
- [x] Fix config_screen MoCodeAPI → OpenCodeAPI class reference
- [x] Add fetchConfig/fetchStatus/sendWsMessage to OpenCodeAPI
- [x] Implement slash commands (/model, /skills, /stop, /clear, /provider, /session)
- [x] Implement Copilot GitHub Device Auth flow (Go endpoints + Flutter UI)
- [x] Add stop/interrupt button to InputBar (red stop when task running)
- [x] Add Config tab to bottom navigation (4th tab)
- [x] Add cancelSession API for task interruption
- [x] Clean up all Dart analysis warnings (0 issues)
- [x] All Go tests passing (agent, api, context, provider, tools)
- [x] Play Store: Android scaffold regenerated with applicationId io.github.omashishsoni.mocode
- [x] Play Store: App icon generated (terminal >_ theme, all densities + adaptive)
- [x] Play Store: Release signing config wired into build.gradle.kts
- [x] Play Store: Store listing and privacy policy written
- [x] Play Store: .gitignore updated for keystore/key.properties

## In progress
- [ ] Play Store release — keystore generation, AAB build, Play Console upload (Om manual steps)
- [ ] Wire .mocode centralized storage into active use
- [ ] Session/memory persistence across daemon restarts
- [ ] Android foreground service (Kotlin)

## Known issues resolved (from issues/)
- ISSUE-001: Flutter codebase — RESOLVED (exists)
- ISSUE-002: API mismatch — RESOLVED (config_screen fixed to OpenCodeAPI)
- ISSUE-007a: Broken pubspec — RESOLVED (speech_to_text)
- ISSUE-007b: Flutter compilation errors — RESOLVED (duplicate method, missing param)
- ISSUE-008a: Missing fonts — RESOLVED (assets exist)

## Known issues remaining
- ISSUE-003: Stale protocol docs (API_PROTOCOL.md still describes old WebSocket format)
- ISSUE-004: Missing cmd tests (backend/cmd/mocode has no test files)
- ISSUE-005: Redundant backend entrypoint (custom daemon vs OpenCode serve)
- ISSUE-006: Broken automation scripts (build-flutter.sh assumes flutter/ path)
- ISSUE-008b: Health endpoint 404 on custom daemon (works on OpenCode serve)

## File map
- `backend/` — Go daemon with auth endpoints, agent engine, provider registry
- `flutter/` — Flutter mobile app (4 screens: Agent, Files, Tasks, Config)
- `scripts/` — build and test automation
- `docs/` — project spec and reference docs
- `docs/skills/` — skill guidance for agents
- `progress/claude/` — Claude's progress tracking
- `progress/opencode/` — OpenCode's progress tracking
- `issues/` — beta testing issue tracker
