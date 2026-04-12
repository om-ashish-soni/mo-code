# ISSUE-007: Flutter Compilation Errors — RESOLVED (2026-04-12)

The Flutter application fails to build due to several compilation errors in the `lib/` directory.

## Symptoms

Running `flutter run -d linux` results in the following errors:

1.  **Duplicate Declaration**: `lib/api/daemon.dart:250:39`: Error: 'listSessions' is already declared in this scope.
2.  **Missing Required Parameter**: `lib/screens/agent_screen.dart:75:30` (and others): Error: Required named parameter 'content' must be provided for `TerminalLine`.
3.  **Invalid Parameter**: `lib/screens/tasks_screen.dart:29:45`: Error: No named parameter with the name 'directory' in `listSessions`.

## Impact

The application cannot be launched for testing or development on the Linux platform.

## Proposed Fix (for developers)

- Remove the duplicate `listSessions` method in `lib/api/daemon.dart`.
- Provide the required `content` parameter (e.g., an empty string or specific separator text) when instantiating `TerminalLine`.
- Update the `listSessions` signature or its calls to match the intended API.
