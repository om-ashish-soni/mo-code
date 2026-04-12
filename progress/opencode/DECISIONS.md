# OpenCode — Decisions

Decisions made during parallel work that may affect Claude's side.

## D1: Git tools use CLI, not go-git (for now)
**Decision:** `backend/tools/git.go` uses `exec.Command("git", ...)` instead of the `go-git` library.
**Rationale:** Status, diff, and log are read-only operations where the CLI is simpler and avoids adding a heavy dependency. go-git will be added later for programmatic operations (commit, push via SSH).
**Impact on Claude:** None — git tools are internal to the agent runtime, not exposed via API.

## D2: Tool results use structured JSON for file metadata
**Decision:** `FileWrite.Execute()` returns a JSON-encoded result with `output`, `files_created`, and `files_modified` fields. The `Dispatcher.Dispatch()` parses this to populate `Result.FilesCreated/FilesModified`.
**Rationale:** This lets the engine emit `EventFileCreate` and `EventFileModify` events that the task manager already tracks.
**Impact on Claude:** Task manager's `trackEvent` already handles these event kinds. No changes needed.

## D3: Engine uses provider.Registry directly
**Decision:** `Engine` takes a `*provider.Registry` (concrete type), not an interface.
**Rationale:** Simpler for the initial implementation. The Registry is a shared type both sides use. For testing, we construct a real Registry and configure mock providers.
**Impact on Claude:** No change needed — `main.go` already creates a `StubRunner`. When switching to `Engine`, it will need a `provider.NewRegistry()` and API key configuration.

## D4: Context Manager owns system prompt assembly
**Decision:** `context.BuildSystemPrompt()` generates the system prompt with working dir and tool names. The `Manager` prepends it as a system message when `Messages()` is called.
**Rationale:** Centralizes prompt construction. The engine doesn't need to know about prompt formatting.
**Impact on Claude:** None.

## D5: Max 25 tool rounds per task
**Decision:** The agent loop caps at 25 tool-call/result round-trips.
**Rationale:** Safety limit to prevent runaway loops. Can be made configurable later.
**Impact on Claude:** The API layer will receive an `EventError` + `EventDone` if this limit is hit.

## D6: Dangerous command blocklist in ShellExec
**Decision:** `isDangerous()` blocks: `rm -rf /`, `rm -rf /*`, `mkfs`, `dd if=/dev/zero`, fork bombs, `chmod -r 777`, `> /dev/sda`.
**Rationale:** Defense-in-depth for agent shell access. The comparison uses `strings.ToLower` for case-insensitive matching.
**Impact on Claude:** None — this is internal to the tools package.

## D7: Copilot uses GitHub OAuth device code flow
**Decision:** `copilot_auth.go` implements the full 3-step device code flow (device code → poll → exchange). The `Copilot` provider's `resolveToken()` prefers device flow tokens over direct API keys. `Registry.CopilotAuth()` exposes the auth instance for the API layer.
**Rationale:** This is how VS Code, Copilot CLI, and OpenCode authenticate with GitHub Copilot. The client ID `Iv1.b507a08c87ecfe98` is GitHub Copilot's public OAuth app. The API token is short-lived (~30 min) and auto-refreshes 5 min before expiry.
**Impact on Claude:** The API layer (`backend/api/`) needs new WS message types to drive the auth flow from the Flutter UI. See `progress/opencode/COPILOT_WS_INTEGRATION.md` for the protocol spec.

## D8: CopilotAuth test strategy uses rewriteTransport
**Decision:** Tests intercept HTTP at the `RoundTripper` level to redirect hardcoded GitHub URLs to `httptest.Server` instances, rather than making the URLs configurable.
**Rationale:** Avoids adding test-only configuration knobs to production code. The `rewriteTransport` pattern is self-contained in test files and doesn't leak into the auth implementation.
**Impact on Claude:** None.
