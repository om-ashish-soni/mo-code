# Mo-Code WebSocket API Protocol

## Connection

- **URL:** `ws://127.0.0.1:{PORT}/ws`
- **Port discovery:** Read port from `/data/data/com.mocode.app/daemon_port`
- **Keepalive:** Ping/pong every 30s, timeout after 60s
- **Reconnect:** Exponential backoff starting at 500ms, max 30s

## Message format

All messages are JSON with this envelope:

```json
{
  "type": "category.action",
  "id": "uuid-v4",
  "task_id": "uuid-v4 (optional, for task-scoped messages)",
  "payload": {}
}
```

## Message types

### Client → Server (Flutter → Go)

#### `task.start`
Start a new agent task.
```json
{
  "type": "task.start",
  "id": "msg-uuid",
  "payload": {
    "prompt": "Build a REST API with JWT auth",
    "provider": "claude",
    "working_dir": "/data/data/com.mocode.app/files/projects/my-api",
    "context_files": ["src/index.ts", "package.json"]
  }
}
```

#### `task.cancel`
Cancel a running or queued task.
```json
{
  "type": "task.cancel",
  "id": "msg-uuid",
  "task_id": "task-uuid"
}
```

#### `task.retry`
Retry a failed task.
```json
{
  "type": "task.retry",
  "id": "msg-uuid",
  "task_id": "task-uuid"
}
```

#### `provider.switch`
Switch the active LLM provider. Takes effect on the next task.
```json
{
  "type": "provider.switch",
  "id": "msg-uuid",
  "payload": {
    "provider": "gemini"
  }
}
```

#### `config.set`
Update configuration (API keys, preferences).
```json
{
  "type": "config.set",
  "id": "msg-uuid",
  "payload": {
    "key": "providers.claude.api_key",
    "value": "sk-ant-..."
  }
}
```

#### `fs.list`
Request file tree for a directory.
```json
{
  "type": "fs.list",
  "id": "msg-uuid",
  "payload": {
    "path": "/data/data/com.mocode.app/files/projects/my-api",
    "depth": 3,
    "include_git_status": true
  }
}
```

#### `fs.read`
Read a file's contents.
```json
{
  "type": "fs.read",
  "id": "msg-uuid",
  "payload": {
    "path": "src/index.ts"
  }
}
```

#### `git.status`
Get git status for the current project.
```json
{
  "type": "git.status",
  "id": "msg-uuid",
  "payload": {
    "path": "/data/data/com.mocode.app/files/projects/my-api"
  }
}
```

#### `git.commit`
Stage files and commit.
```json
{
  "type": "git.commit",
  "id": "msg-uuid",
  "payload": {
    "path": "/data/data/com.mocode.app/files/projects/my-api",
    "message": "feat: add auth middleware",
    "files": ["src/auth.ts", "src/middleware.ts"]
  }
}
```

#### `git.push`
Push commits to remote.
```json
{
  "type": "git.push",
  "id": "msg-uuid",
  "payload": {
    "path": "/data/data/com.mocode.app/files/projects/my-api",
    "remote": "origin",
    "branch": "feat/auth"
  }
}
```

#### `git.diff`
Get diff for a file or entire working tree.
```json
{
  "type": "git.diff",
  "id": "msg-uuid",
  "payload": {
    "path": "/data/data/com.mocode.app/files/projects/my-api",
    "file": "src/auth.ts"
  }
}
```

#### `git.clone`
Clone a repository.
```json
{
  "type": "git.clone",
  "id": "msg-uuid",
  "payload": {
    "url": "git@github.com:user/repo.git",
    "dest": "/data/data/com.mocode.app/files/projects/repo",
    "branch": "main"
  }
}
```

---

### Server → Client (Go → Flutter)

#### `agent.stream`
Streaming agent output. Sent continuously during task execution.
```json
{
  "type": "agent.stream",
  "task_id": "task-uuid",
  "payload": {
    "kind": "text",
    "content": "Creating project structure...",
    "timestamp": "2025-01-15T14:30:00Z"
  }
}
```

**`kind` values:**
- `"text"` — Plain text output from the agent
- `"plan"` — Agent's execution plan (numbered steps)
- `"tool_call"` — Agent is invoking a tool (includes tool name + args)
- `"tool_result"` — Tool execution result (includes stdout/stderr)
- `"file_create"` — File was created (includes path + content preview)
- `"file_modify"` — File was modified (includes path + diff)
- `"status"` — Status update (e.g., "Thinking...", "4/7 steps complete")
- `"error"` — Non-fatal error during execution
- `"token_usage"` — Token count update

#### `task.complete`
Task finished successfully.
```json
{
  "type": "task.complete",
  "task_id": "task-uuid",
  "payload": {
    "summary": "Created REST API with JWT auth",
    "files_created": ["src/index.ts", "src/auth.ts", "package.json"],
    "files_modified": [],
    "files_deleted": [],
    "total_tokens": 12450,
    "duration_ms": 45000
  }
}
```

#### `task.failed`
Task failed.
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

#### `task.queued`
Task was added to the queue.
```json
{
  "type": "task.queued",
  "task_id": "task-uuid",
  "payload": {
    "position": 2,
    "estimated_start": "2025-01-15T14:35:00Z"
  }
}
```

#### `fs.tree`
File tree response.
```json
{
  "type": "fs.tree",
  "payload": {
    "root": "/data/data/com.mocode.app/files/projects/my-api",
    "entries": [
      {"path": "src", "type": "dir", "children": [
        {"path": "src/index.ts", "type": "file", "git_status": "added", "size": 1240},
        {"path": "src/auth.ts", "type": "file", "git_status": "modified", "size": 890}
      ]},
      {"path": "package.json", "type": "file", "git_status": "added", "size": 320}
    ]
  }
}
```

#### `fs.content`
File content response.
```json
{
  "type": "fs.content",
  "payload": {
    "path": "src/index.ts",
    "content": "import express from 'express';\n...",
    "language": "typescript",
    "size": 1240
  }
}
```

#### `git.diff_result`
Diff response.
```json
{
  "type": "git.diff_result",
  "payload": {
    "file": "src/auth.ts",
    "hunks": [
      {
        "old_start": 5, "old_count": 3,
        "new_start": 5, "new_count": 5,
        "lines": [
          {"type": "context", "content": "import jwt from 'jsonwebtoken';"},
          {"type": "removed", "content": "const secret = 'hardcoded';"},
          {"type": "added", "content": "const secret = process.env.JWT_SECRET;"},
          {"type": "added", "content": "if (!secret) throw new Error('JWT_SECRET required');"}
        ]
      }
    ]
  }
}
```

#### `git.operation_result`
Result of a git operation (commit, push, clone, etc).
```json
{
  "type": "git.operation_result",
  "payload": {
    "operation": "push",
    "success": true,
    "message": "Pushed 3 commits to origin/feat/auth",
    "details": {}
  }
}
```

#### `config.current`
Current configuration state.
```json
{
  "type": "config.current",
  "payload": {
    "active_provider": "claude",
    "providers": {
      "claude": {"configured": true, "model": "claude-sonnet-4-20250514"},
      "gemini": {"configured": true, "model": "gemini-2.0-flash"},
      "copilot": {"configured": false}
    },
    "working_dir": "/data/data/com.mocode.app/files/projects/my-api"
  }
}
```

#### `server.status`
Server health and status.
```json
{
  "type": "server.status",
  "payload": {
    "uptime_seconds": 3600,
    "active_tasks": 1,
    "queued_tasks": 2,
    "memory_mb": 45,
    "version": "0.1.0"
  }
}
```

## Error handling

All errors include a consistent structure:
```json
{
  "type": "error",
  "id": "msg-uuid (echoed from request if applicable)",
  "payload": {
    "code": "PROVIDER_AUTH_FAILED",
    "message": "Invalid API key for Claude",
    "recoverable": true,
    "suggestion": "Check your API key in Settings"
  }
}
```

**Error codes:**
- `PROVIDER_AUTH_FAILED` — Bad API key
- `PROVIDER_RATE_LIMITED` — Rate limit hit, retry later
- `PROVIDER_UNAVAILABLE` — Provider API is down
- `TASK_CANCELLED` — Task was cancelled by user
- `TOOL_EXEC_FAILED` — Tool execution failed (includes stderr)
- `FS_PERMISSION_DENIED` — File system permission error
- `GIT_AUTH_FAILED` — SSH/HTTPS auth to remote failed
- `GIT_CONFLICT` — Merge conflict detected
- `INTERNAL_ERROR` — Unexpected server error
