# Mo-Code API Protocol

*Last updated: 2026-04-13 (R4-C3)*

Mo-code uses a custom Go daemon (`backend/cmd/mocode`) that exposes both HTTP REST endpoints and a WebSocket for real-time communication. All traffic is localhost-only (`127.0.0.1`).

## Connection

- **HTTP base:** `http://127.0.0.1:{PORT}/api/`
- **WebSocket:** `ws://127.0.0.1:{PORT}/ws`
- **Default port:** 19280 (scans upward if occupied, up to +50)
- **Port discovery:** Read from `daemon_port` file next to the binary, or path set via `MOCODE_PORT_FILE` env
- **Keepalive:** Ping/pong every 30s, read deadline 60s
- **Origin check:** Only `127.0.0.1`, `localhost`, `*.localhost` origins accepted

## HTTP Endpoints

### `GET /api/health`
Health check. Always available.
```json
{"status": "ok", "service": "mo-code-daemon", "timestamp": "2026-04-13T10:00:00Z"}
```

### `GET /api/status`
Server status and metrics.
```json
{
  "uptime_seconds": 3600,
  "active_tasks": 1,
  "queued_tasks": 0,
  "memory_mb": 45,
  "version": "0.1.0"
}
```

### `GET /api/config`
Returns current configuration (active provider, provider status, working directory).

### `POST /api/provider/switch`
Switch active provider. Body: `{"provider": "gemini"}`.

### `POST /api/auth/copilot/device`
Start GitHub Copilot device auth flow. Returns device code and verification URL.

### `POST /api/auth/copilot/poll`
Poll for Copilot auth completion. Body: `{"device_code": "..."}`.

---

## WebSocket Protocol

All WebSocket messages use this JSON envelope:

```json
{
  "type": "category.action",
  "id": "msg-uuid",
  "task_id": "task-uuid (optional)",
  "payload": {}
}
```

---

### Client → Server Messages

#### `task.start` — Start agent task
```json
{
  "type": "task.start",
  "id": "msg-uuid",
  "payload": {
    "prompt": "Fix the auth middleware",
    "provider": "claude",
    "working_dir": "/path/to/project",
    "context_files": ["src/auth.go"]
  }
}
```

#### `plan.start` — Start plan-only task (read-only, no file writes)
Same payload as `task.start`. Uses the plan engine which only has read-only tools.
```json
{
  "type": "plan.start",
  "id": "msg-uuid",
  "payload": {
    "prompt": "How would you refactor the auth module?",
    "provider": "claude"
  }
}
```

#### `task.cancel` — Cancel running task
```json
{"type": "task.cancel", "id": "msg-uuid", "task_id": "task-uuid"}
```

#### `task.retry` — Retry failed/canceled task
```json
{"type": "task.retry", "id": "msg-uuid", "task_id": "task-uuid"}
```

#### `provider.switch` — Switch active provider
```json
{"type": "provider.switch", "id": "msg-uuid", "payload": {"provider": "gemini"}}
```

#### `config.set` — Update configuration
```json
{"type": "config.set", "id": "msg-uuid", "payload": {"key": "providers.claude.api_key", "value": "sk-ant-..."}}
```

#### `session.list` — List all sessions
```json
{"type": "session.list", "id": "msg-uuid"}
```

#### `session.get` — Get session details
```json
{"type": "session.get", "id": "msg-uuid", "payload": {"id": "session-uuid"}}
```

#### `session.resume` — Resume a previous session
```json
{"type": "session.resume", "id": "msg-uuid", "payload": {"id": "session-uuid", "prompt": "continue"}}
```

#### `session.delete` — Delete a session
```json
{"type": "session.delete", "id": "msg-uuid", "payload": {"id": "session-uuid"}}
```

#### `fs.list` / `fs.read` — File operations (stub, not yet implemented)

#### `git.*` — Git operations (stub, not yet implemented)
`git.status`, `git.commit`, `git.push`, `git.diff`, `git.clone`

---

### Server → Client Messages

#### `agent.stream` — Streaming agent output
Sent continuously during task execution. The `kind` field determines the content type.

```json
{
  "type": "agent.stream",
  "task_id": "task-uuid",
  "payload": {
    "kind": "text",
    "content": "Creating project structure...",
    "metadata": {},
    "timestamp": "2026-04-13T10:00:00Z"
  }
}
```

**`kind` values:**

| Kind | Description | Metadata |
|------|-------------|----------|
| `text` | Streaming text from the agent (markdown) | — |
| `tool_call` | Agent invoking a tool | `tool_call_id`, `args` |
| `tool_result` | Tool execution result | `tool_call_id`, `tool_name`, `title`, `error` |
| `file_create` | File created | — |
| `file_modify` | File modified | — |
| `plan` | Plan step | — |
| `status` | Status update ("Thinking...") | — |
| `error` | Non-fatal error | — |
| `token_usage` | Token count update | `input`, `output` |
| `diff` | File diff data | `file`, `hunks` (structured diff) |
| `todo_update` | TODO panel update | `items` (array of `{id, content, status}`) |
| `done` | Stream finished | — |

#### `task.complete` — Task finished successfully
```json
{
  "type": "task.complete",
  "task_id": "task-uuid",
  "payload": {
    "summary": "Created REST API with JWT auth",
    "files_created": ["src/auth.go"],
    "files_modified": ["go.mod"],
    "files_deleted": [],
    "total_tokens": 12450,
    "duration_ms": 45000
  }
}
```

#### `task.failed` — Task failed
```json
{
  "type": "task.failed",
  "task_id": "task-uuid",
  "payload": {
    "error": "API rate limit exceeded",
    "recoverable": true,
    "suggestion": "Wait 60 seconds and retry"
  }
}
```

#### `task.queued` — Task queued
```json
{
  "type": "task.queued",
  "task_id": "task-uuid",
  "payload": {"position": 2}
}
```

#### `session.list_result` — Session list response
Returns array of session objects with id, title, timestamps, provider, model.

#### `session.get_result` — Session detail response
Returns full session object including message history.

#### `config.current` — Configuration state
```json
{
  "type": "config.current",
  "payload": {
    "active_provider": "claude",
    "providers": {
      "claude": {"configured": true, "model": "claude-sonnet-4-20250514"},
      "gemini": {"configured": true, "model": "gemini-2.0-flash"},
      "copilot": {"configured": false},
      "openrouter": {"configured": false},
      "ollama": {"configured": true},
      "azure": {"configured": false}
    },
    "working_dir": "/home/user/project"
  }
}
```

#### `server.status` — Server status
Same shape as `GET /api/status`.

#### `error` — Error response
```json
{
  "type": "error",
  "id": "echoed-msg-id",
  "payload": {
    "code": "PROVIDER_AUTH_FAILED",
    "message": "Invalid API key for Claude",
    "recoverable": true,
    "suggestion": "Check your API key in Settings"
  }
}
```

---

## Error Codes

| Code | Description |
|------|-------------|
| `PROVIDER_AUTH_FAILED` | Bad API key |
| `PROVIDER_RATE_LIMITED` | Rate limit hit |
| `PROVIDER_UNAVAILABLE` | Provider API down |
| `TASK_CANCELLED` | Task canceled by user |
| `TOOL_EXEC_FAILED` | Tool execution failed |
| `FS_PERMISSION_DENIED` | File system permission error |
| `GIT_AUTH_FAILED` | SSH/HTTPS auth failed |
| `GIT_CONFLICT` | Merge conflict |
| `INTERNAL_ERROR` | Unexpected server error |
| `UNSUPPORTED_MESSAGE` | Unknown message type |
| `INVALID_PAYLOAD` | Malformed payload |

## Providers

| Provider | Config env var | Auth method |
|----------|---------------|-------------|
| `claude` | `CLAUDE_API_KEY` | API key |
| `gemini` | `GEMINI_API_KEY` | API key |
| `copilot` | Device auth (no key) | GitHub OAuth |
| `openrouter` | `OPENROUTER_API_KEY` | API key |
| `ollama` | `OLLAMA_URL` (optional) | Local, no key |
| `azure` | `AZURE_OPENAI_API_KEY` + `AZURE_OPENAI_DEPLOYMENT` | API key |
