# Claude — Progress

## Branch: `claude/api-surface`

## Status: completed

## Scope
- Use OpenCode serve as backend (not custom Go daemon)
- Adapt Flutter client to use OpenCode HTTP API
- Test Flutter ↔ OpenCode integration

## Completed
- [x] Fixed main.go runner argument issue — completed 2026-04-12
- [x] Updated server_test.go to use real server with StubRunner — completed 2026-04-12
- [x] Verified `go build ./...` — completed 2026-04-12
- [x] Verified `go test ./...` (4 tests pass) — completed 2026-04-12
- [x] Scaffold Flutter app — completed 2026-04-12
- [x] Research OpenCode integration — completed 2026-04-12 (OpenCode has built-in `serve` command!)
- [x] Installed OpenCode 1.4.3 — completed 2026-04-12
- [x] Tested OpenCode serve API (session create, message send) — completed 2026-04-12
- [x] Fixed Flutter API client for OpenCode response format — completed 2026-04-12
- [x] Added Files screen with search and file viewer — completed 2026-04-12
- [x] Added Tasks screen with session list — completed 2026-04-12
- [x] Fixed Go provider registry naming conflict — completed 2026-04-12
- [x] Verified Codex skills already installed — completed 2026-04-12
- [x] Added repo automation scripts — completed 2026-04-12

## Blockers
_(none — all tasks complete)_

## Files touched
- `flutter/pubspec.yaml` — Added pubspec.yaml with dependencies
- `flutter/lib/theme/colors.dart` — Added dark terminal theme (colors, typography, spacing)
- `flutter/lib/models/messages.dart` — Added data models
- `flutter/lib/api/daemon.dart` — Added OpenCode HTTP client
- `flutter/lib/widgets/terminal_output.dart` — Added terminal output widget
- `flutter/lib/widgets/provider_switcher.dart` — Added provider pill switcher
- `flutter/lib/widgets/input_bar.dart` — Added input bar
- `flutter/lib/screens/agent_screen.dart` — Added agent screen
- `flutter/lib/screens/files_screen.dart` — Added files screen
- `flutter/lib/screens/tasks_screen.dart` — Added tasks screen
- `flutter/lib/main.dart` — Added main with navigation
- `flutter/android/app/src/main/AndroidManifest.xml` — Added permissions
- `scripts/setup.sh` — Project setup script
- `scripts/build-go.sh` — Go build script
- `scripts/build-flutter.sh` — Flutter build script
- `scripts/test.sh` — Test runner
- `scripts/start-server.sh` — OpenCode server starter

## Architecture
OpenCode is TypeScript/Bun-based with built-in headless server:
- Use `opencode serve --port 4096` as backend
- Flutter connects to OpenCode's HTTP API
- API: session management, message sending, SSE events
