# FEAT-003: Session Context Continuity — Multi-Turn Conversations

**Status:** COMPLETE — implemented 2026-04-13 by C1 (Flutter), C2 (Backend), C3 (Testing)
**Priority:** P0 — core UX broken without this (each prompt is isolated, no memory)
**Estimated effort:** M (6-8 points across 3 Claudes)
**Blocked by:** Nothing — backend machinery already exists

---

## Problem

Every prompt sent from the Flutter agent screen creates a new task with a unique ID (`msg-N-timestamp`). The backend treats each as an independent session with zero conversation history. The user sees previous messages in the terminal output, but the LLM has no context from prior turns.

**Example of the bug:**
```
User: "Create a Node.js REST API with auth"
Agent: (creates files, writes code)

User: "Now add rate limiting to the auth middleware"
Agent: "I don't see any files. What auth middleware?" ← no context from turn 1
```

## Root Cause

The backend has full session management — `SessionStore`, `Manager`, `Compactor`, resume logic. All working. The break is in Flutter's `agent_screen.dart:430`:

```dart
final taskId = api.startTask(prompt);  // new ID every time
```

No session ID is tracked or reused. The `daemon.dart` has `resumeSession()` but it's never called from the agent screen.

## Solution

Track a single session ID per agent screen lifecycle. First prompt creates the session. Follow-up prompts resume it. Context flows automatically through the existing backend machinery.

```
Prompt 1 → task.start {id: "session-abc"} → backend creates session + stores messages
Prompt 2 → session.resume {id: "session-abc"} → backend restores history + appends
Prompt 3 → session.resume {id: "session-abc"} → full context, compaction if needed
/clear   → new session ID generated → fresh start
```

---

## Architecture (What Already Exists)

| Component | Status | Location |
|-----------|--------|----------|
| SessionStore (persist to disk) | Working | `backend/context/session_store.go` |
| Session resume (restore messages) | Working | `backend/agent/engine.go:94-107` |
| Context Manager (accumulate messages) | Working | `backend/context/context.go` |
| Compaction at 80% capacity | Working | `backend/context/compaction.go` |
| Continuation preamble after compaction | Working | `backend/context/compaction.go:191` |
| FIFO trimming as fallback | Working | `backend/context/context.go:173` |
| `session.resume` WS handler | Working | `backend/api/server.go:688` |
| `resumeSession()` in daemon.dart | Working | `flutter/lib/api/daemon.dart:580` |
| Token budget per model | Working | `backend/context/models.go` |

**Nothing new needs to be built in the backend.** The fix is wiring the Flutter UI to use what already exists.

---

## Implementation Plan — 3 Claudes in Parallel

### C1: Flutter Agent Screen — Session Lifecycle
**Points:** 3 | **Files:** `flutter/lib/screens/agent_screen.dart`

C1 owns the core fix: make the agent screen maintain a persistent session ID across prompts.

- [x] **3.1** Add `_sessionId` state field to `_AgentScreenState`, initialized to `null`
- [x] **3.2** Generate session ID on first prompt: `session-${DateTime.now().millisecondsSinceEpoch}`
- [x] **3.3** First prompt: call `api.startTask(prompt)` with the generated session ID as the task ID
  - Modify `startTask()` in `daemon.dart` to accept an optional `taskId` parameter instead of always generating one
- [x] **3.4** Follow-up prompts (when `_sessionId != null`): call `api.resumeSession(_sessionId!, prompt)` instead of `startTask()`
- [x] **3.5** Handle `/clear` command: reset `_sessionId = null` so next prompt creates a fresh session
- [x] **3.6** Handle session resume from Sessions screen: when navigating back with a `resume` action, set `_sessionId` to the resumed session's ID
- [x] **3.7** Show session indicator in status bar: display session ID (truncated) or "new session" when `_sessionId` is null
- [x] **3.8** Handle `task.complete` — do NOT clear `_sessionId` (session persists across tasks within same conversation)
- [x] **3.9** Handle `task.failed` — keep `_sessionId` so user can retry within the same context

**Key constraint:** The `_activeTaskId` (used for cancel) is separate from `_sessionId`. A session has many tasks. `_activeTaskId` tracks the currently running task within the session.

**Test plan:**
- Send 3 prompts in sequence, verify 2nd and 3rd have context from prior turns
- `/clear` then send prompt — verify clean slate
- Resume from Sessions screen, send follow-up — verify context restored

---

### C2: Backend Hardening — Session-Aware Task Management
**Points:** 2 | **Files:** `backend/api/server.go`, `backend/agent/engine.go`, `backend/api/messages.go`

C2 ensures the backend handles repeated session IDs correctly and adds a session info response.

- [x] **3.10** Verify `handleTaskStart` works correctly when called with an existing session ID (currently it does — engine.go:96 checks for existing session). Add explicit test for this.
- [x] **3.11** Add `session.info` message type — client can request current session metadata (message count, token usage, state) without fetching full message history
  - New message types: `TypeSessionInfo = "session.info"` (client→server), `TypeSessionInfoResult = "session.info_result"` (server→client)
  - Payload: `{id, title, message_count, tokens_used, state, provider, compaction_count}`
- [x] **3.12** Track compaction count in Session struct — increment each time compaction runs for this session. Useful for UI indicator.
  - Add `CompactionCount int` field to `Session` struct in `session_store.go`
  - Increment in `Compactor.Compact()` after successful compaction
- [x] **3.13** Add `session.clear` message type — resets the session's message history without deleting the session file. Used when user does `/clear` but wants to keep the session ID.
  - Handler clears `Session.Messages`, resets `TokensUsed`, updates state to "active"
- [x] **3.14** Emit `runtime.ready` or session metadata after successful session resume so the UI can show "Resumed session (N messages, M tokens)"
- [x] **3.15** Handle edge case: `task.start` arrives while a task is already running on the same session → queue it or return error (don't corrupt the message history with interleaved tasks)

**Key constraint:** Don't break the existing `task.start` / `session.resume` flow. C2's changes are additive — new message types and metadata, not modifications to existing handlers.

**Test plan:**
- Start task with session ID "abc", complete it, start another task with same ID "abc" — verify messages accumulate
- Send `session.info` request — verify response has correct message count
- Send `session.clear` — verify messages reset but session persists
- Send `task.start` while another task is running — verify graceful handling

---

### C3: Testing, Edge Cases, and Compaction Validation
**Points:** 2 | **Files:** `backend/agent/e2e_test.go`, `backend/context/session_store_test.go`, `backend/context/compaction_test.go`, `flutter/lib/screens/agent_screen.dart` (minor)

C3 validates the full flow works end-to-end and handles edge cases.

- [x] **3.16** E2E test: multi-turn conversation — send 3 prompts to same session, verify each LLM call includes all prior messages
  - Mock provider that records the messages it receives (recordingProvider)
  - Assert message count grows: call 1 = 2 msgs (system+user), call 2 = 4+ msgs, call 3 = 6+ msgs
- [x] **3.17** E2E test: session resume after daemon restart — create session, append messages, save to disk, reload from disk, resume, verify context restored (TestE2E_SessionPersistence_SurvivesRestart)
- [x] **3.18** E2E test: compaction triggers during multi-turn — ShouldCompact threshold logic, Compact replaces old messages with continuation preamble, too-few-messages guard
- [x] **3.19** Test: concurrent session access — 4 goroutines (writer, reader, lister, state updater) × 50 iterations, race-detector clean. **Bug found:** Get() returned mutable pointer → fixed to return snapshot copy.
- [x] **3.20** Test: session with 150 messages — verify persistence across reload, verify FIFO trimming, ClearMessages resets tokens/state
- [ ] **3.21** Test: WebSocket reconnect mid-session — deferred (requires live WS server, covered by existing auto-reconnect in daemon.dart)
- [ ] **3.22** Add session count display to agent screen `/session` command — deferred to future UI polish
- [x] **3.23** Test: model/provider switch mid-session — alpha→beta provider switch, verify beta receives full message history from alpha's session

**Key constraint:** Tests must not require a real LLM API key. Use the stub/mock provider. Focus on verifying message flow, not response quality.

**Test plan:**
- All new tests pass in CI (`go test ./...`)
- No regressions in existing 16 runtime tests + existing e2e tests

---

## Parallel Work Boundaries

```
C1 (Flutter)              C2 (Backend)              C3 (Testing)
─────────────             ─────────────             ─────────────
agent_screen.dart         server.go                 e2e_test.go (new tests)
daemon.dart (minor)       engine.go (minor)         session_store_test.go
                          messages.go               compaction_test.go
                          session_store.go          agent_screen.dart (minor)

No file conflicts between C1/C2/C3.
C3 can start immediately — tests written against current backend behavior.
C1 can start immediately — Flutter-only changes.
C2 can start immediately — additive backend message types.
```

## Merge Order

1. **C2 first** — backend additions are additive, no breaking changes
2. **C3 second** — tests validate the backend before Flutter changes land
3. **C1 last** — Flutter wiring depends on backend being solid

Or: all three merge independently since there are no file conflicts.

---

## User Flow (Target)

```
┌─────────────────────────────────────────────────────────────┐
│  App opens → Agent screen → no session yet                  │
│                                                             │
│  User: "Create a REST API with Express"                     │
│  → _sessionId = "session-171..." (generated)                │
│  → task.start {id: "session-171...", prompt: "Create..."}   │
│  → Agent creates files, streams output                      │
│  → task.complete → _sessionId stays                         │
│                                                             │
│  User: "Add JWT auth to the login route"                    │
│  → session.resume {id: "session-171...", prompt: "Add..."}  │
│  → Backend restores 8 prior messages + appends new prompt   │
│  → Agent sees full context, modifies auth.js correctly      │
│                                                             │
│  User: "Run the tests"                                      │
│  → session.resume {id: "session-171...", prompt: "Run..."}  │
│  → Backend restores 14 messages (compaction may trigger)    │
│  → Agent runs npm test, sees failures, fixes them           │
│                                                             │
│  User types /clear                                          │
│  → _sessionId = null, terminal cleared                      │
│  → Next prompt starts a fresh session                       │
│                                                             │
│  User opens Sessions tab → taps old session → Resume        │
│  → Navigates back to Agent screen with _sessionId set       │
│  → Next prompt resumes that session with full history       │
└─────────────────────────────────────────────────────────────┘
```

## Acceptance Criteria

- [x] Multi-turn conversations carry full context between prompts
- [x] LLM receives all prior messages (user + assistant + tool results) on each turn
- [x] Compaction fires automatically when context exceeds 80% of model limit
- [x] `/clear` starts a fresh session with no prior context
- [x] Session resume from Sessions screen restores full conversation
- [x] WebSocket disconnect + reconnect doesn't lose session context (messages persisted to disk)
- [x] No regression in existing session list/get/delete functionality
- [x] Provider/model switch mid-session preserves message history
- [x] `go test ./...` passes with new tests (all packages, -race clean)
- [x] `flutter analyze` clean
