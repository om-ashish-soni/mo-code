# mo-code Redesign Plan: Competitive Gap Analysis & Roadmap

*Generated: 2026-04-12*
*Based on analysis of: opencode (anomalyco/opencode), claw-code (ultraworkers/claw-code), mo-code current state*

---

## A. Context Engineering Gaps

### A1. System Prompt Construction

**opencode** has per-provider system prompts (`anthropic.txt`, `gemini.txt`, `gpt.txt`, `beast.txt`, `kimi.txt`, `codex.txt`) with dramatically different tones and levels of detail. The Anthropic prompt alone is ~200 lines. The provider selection logic:

```typescript
// opencode: packages/opencode/src/session/system.ts
export function provider(model: Provider.Model) {
  if (model.api.id.includes("gpt-4") || model.api.id.includes("o1") || model.api.id.includes("o3"))
    return [PROMPT_BEAST]  // "Beast" mode for o-series
  if (model.api.id.includes("gemini-")) return [PROMPT_GEMINI]
  if (model.api.id.includes("claude")) return [PROMPT_ANTHROPIC]
  return [PROMPT_DEFAULT]
}
```

The environment section injects structured XML:
```typescript
environment(model) {
  return [`<env>`,
    `  Working directory: ${Instance.directory}`,
    `  Workspace root folder: ${Instance.worktree}`,
    `  Is directory a git repo: ${project.vcs === "git" ? "yes" : "no"}`,
    `  Platform: ${process.platform}`,
    `  Today's date: ${new Date().toDateString()}`,
    `</env>`]
}
```

**mo-code** uses a single 20-line `BuildSystemPrompt()` that is provider-agnostic:
```go
// mo-code: backend/context/context.go
func BuildSystemPrompt(workingDir string, toolNames []string) string {
    sb.WriteString("You are a coding agent running inside mo-code...")
    sb.WriteString("- Be efficient...")
}
```

**Gap**: mo-code's system prompt is ~15x shorter, lacks per-provider tuning, lacks XML-structured environment data, and has no code-style instructions, no tone/verbosity calibration, no examples.

### A2. Instruction File Discovery (AGENTS.md / CLAUDE.md)

**opencode** has a sophisticated instruction file system (`packages/opencode/src/session/instruction.ts`):
- Discovers `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md` in project root and global config
- Walks UP from any file being read to find nearby instruction files
- Supports remote URLs as instruction sources
- Deduplicates instruction files per assistant message
- Caches already-resolved instruction paths

**claw-code** similarly discovers `.claude.json` and `CLAUDE.md`, plus reads git context (branch, diff, status) into prompts.

**mo-code** has zero instruction file discovery. No AGENTS.md support, no CLAUDE.md loading, no project-level prompt customization.

### A3. Session Management & Compaction

**opencode** has a full session lifecycle:
- Sessions stored in SQLite with message/part granularity
- Automatic compaction when context exceeds model limits (configurable threshold)
- Compaction uses a dedicated "compaction agent" with its own prompt:
  ```
  Provide a detailed prompt for continuing our conversation above.
  Focus on what we did, what we're doing, which files we're working on...
  ```
- Pruning: old tool results are pruned first (keeps recent N turns protected)
- `PRUNE_MINIMUM = 20_000` tokens before actually pruning
- `PRUNE_PROTECT = 40_000` tokens of recent tool calls are never pruned
- Overflow detection with automatic recovery
- Session forking, parent-child relationships

**claw-code** adds:
- Session persistence to disk with rotation (`ROTATE_AFTER_BYTES: 256KB`)
- `CompactionConfig` with `preserve_recent_messages: 4` and `max_estimated_tokens: 10_000`
- Summary compression (dedup lines, truncate, budget-constrained)
- Continuation messages after compaction to seamlessly resume work

**mo-code** has basic context management:
- In-memory message list with char-based token estimation (`tokensPerChar = 4`)
- Simple FIFO trimming: drops oldest message when over budget
- No compaction/summarization
- No session persistence (context lost on restart)
- No overflow detection
- Fixed budget of 100K tokens with no per-model adaptation

### A4. Token Budgeting

**opencode**:
- Per-model context limits from provider metadata
- Reserves max output tokens from context budget
- `reserved` configurable: `min(COMPACTION_BUFFER=20K, maxOutputTokens)`
- Actual token counts from API responses used for overflow detection
- Output truncation system: `MAX_LINES=2000`, `MAX_BYTES=50KB` with full output saved to temp file

**mo-code**:
- Single `DefaultMaxTokens = 100_000` regardless of model
- `tokensPerChar = 4` estimation only (no API-reported counts used for budgeting)
- Shell output capped at 100KB, but no structured truncation system
- No temp file save for truncated output

---

## B. Prompt Engineering Gaps

### B1. System Prompt Quality

**opencode Anthropic prompt** key sections mo-code lacks:

1. **Tone calibration with examples**:
```
IMPORTANT: Keep your responses short... You MUST answer concisely with fewer than 4 lines
<example>
user: 2 + 2
assistant: 4
</example>
```

2. **Convention enforcement**:
```
NEVER assume that a given library is available, even if it is well known.
When you create a new component, first look at existing components...
```

3. **Proactiveness rules**:
```
You are allowed to be proactive, but only when the user asks you to do something.
Do not add additional code explanation summary unless requested.
```

4. **Code reference format**:
```
When referencing specific functions include the pattern `file_path:line_number`
```

5. **Task management with TodoWrite** - structured task tracking visible to users

**opencode Gemini prompt** adds:
- Explicit workflow steps: Understand -> Plan -> Implement -> Verify (Tests) -> Verify (Standards)
- New Application workflow with scaffolding guidance
- Security section: "Never introduce code that exposes, logs, or commits secrets"

**opencode Beast mode** (for o-series models):
- "THE PROBLEM CAN NOT BE SOLVED WITHOUT EXTENSIVE INTERNET RESEARCH"
- Forces WebFetch usage for verification
- TodoWrite mandatory for planning
- Much more aggressive autonomy encouragement

### B2. Tool Result Formatting

**opencode** structures tool results with metadata:
```typescript
return {
  title: "Description for UI",
  metadata: { output: preview(output), exit: code, description },
  output: fullOutput
}
```

The bash tool adds structured metadata tags:
```typescript
output += "\n\n<bash_metadata>\n" + meta.join("\n") + "\n</bash_metadata>"
```

**mo-code** returns raw strings from tools. No structured metadata, no title, no preview.

### B3. Error Handling in Prompts

**opencode**: Timeout metadata, exit codes, truncation notices, compaction error messages are all formatted for the LLM to understand context. Overflow errors have recovery paths.

**mo-code**: Simple `fmt.Sprintf("Error: %s", result.Error)` with no context about what happened or recovery suggestions.

---

## C. UI/UX Gaps (TUI/Desktop vs Flutter)

### C1. Views opencode Has That mo-code Lacks

**opencode UI components** (`packages/ui/src/components/`):
- `diff-changes.tsx` - Inline diff viewer with syntax highlighting
- `session-review.tsx` - Full session review with file changes
- `session-diff.ts` - Compute diffs between session snapshots
- `session-turn.tsx` - Individual conversation turns with collapsible tool outputs
- `todo-panel-motion.stories.tsx` - Animated TODO panel showing task progress
- `file-search.tsx` - File search within the UI
- `file-icon.tsx` / `file-media.tsx` - Rich file type icons and media preview
- `image-preview.tsx` - Image preview component
- `message-nav.tsx` - Navigate between messages in conversation
- `thinking-heading` - Display model thinking/reasoning
- `tool-error-card.tsx` - Structured error display for failed tools
- `tool-count-summary.tsx` - Summary of tool calls in a turn
- `markdown.tsx` with `markdown-stream.ts` - Streaming markdown renderer
- `text-reveal.tsx` / `typewriter.tsx` - Animated text reveal effects
- `progress-circle.tsx` - Progress indicators for long operations
- `context-menu.tsx` - Right-click context menus
- `resize-handle.tsx` - Resizable panels

**mo-code Flutter** has:
- `agent_screen.dart` - Main chat view (text-based terminal emulation)
- `config_screen.dart` - Provider configuration
- `files_screen.dart` - Basic file browser
- `tasks_screen.dart` - Task list
- `terminal_output.dart` - Basic text rendering with color coding
- `input_bar.dart` - Chat input
- `provider_switcher.dart` - Provider selection

**Missing in mo-code**:
- No diff viewer
- No session review/summary
- No TODO panel
- No file search
- No image/media preview
- No streaming markdown rendering (uses plain text)
- No progress indicators for long operations
- No message navigation
- No thinking/reasoning display
- No structured tool error display

### C2. Streaming Output

**opencode**: Streams token-by-token with structured events, uses markdown-stream parser for incremental rendering, has text reveal animations, handles partial markdown gracefully.

**mo-code**: Streams chunks via WebSocket events, appends raw text to terminal output. No markdown parsing, no incremental rendering.

### C3. Session Management UI

**opencode**: Full session list with titles, timestamps, auto-generated titles, session forking, session review with file diffs, parent-child session visualization.

**mo-code**: No session persistence UI. Tasks screen shows running tasks but no conversation history.

---

## D. Tool Gaps

### D1. Tools opencode Provides vs mo-code

| Tool | opencode | mo-code | Gap |
|------|----------|---------|-----|
| **Bash/Shell** | `bash.ts` with tree-sitter parsing, workdir, timeout, metadata, permission checks, path scanning | `shell.go` with basic exec, 30s timeout, simple blocklist | Major |
| **File Read** | `read.ts` with offset/limit, line numbers, PDF/image support, instruction file discovery | `file.go` FileRead with offset/limit, line numbers | Moderate |
| **File Write** | `write.ts` with pre-read requirement | `file.go` FileWrite (creates/overwrites) | Minor |
| **File Edit** | `edit.ts` with exact string replacement, replaceAll | None | **Missing** |
| **Multi-Edit** | `multiedit.ts` batched edits on one file | None | **Missing** |
| **Apply Patch** | `apply_patch.ts` with custom patch format | None | **Missing** |
| **Grep** | `grep.ts` with regex, file filtering, ripgrep | None (uses shell_exec + grep) | **Missing** |
| **Glob** | `glob.ts` with pattern matching | None (uses file_list) | **Missing** |
| **List (ls)** | `ls.ts` with tree rendering, ignore patterns, ripgrep | `file.go` FileList basic listing | Moderate |
| **Git Status** | Via bash | `git.go` GitStatus via go-git | Minor |
| **Git Diff** | Via bash | `git.go` GitDiff via CLI | Comparable |
| **Git Log** | Via bash | `git.go` GitLog via go-git | Comparable |
| **Git Add** | Via bash | `git.go` GitAdd via go-git | Comparable |
| **Git Commit** | Via bash | `git.go` GitCommit via go-git | Comparable |
| **Git Push** | Via bash | `git.go` GitPush with SSH auth | Comparable |
| **Task (Subagent)** | `task.ts` spawns subagent sessions | None | **Missing** |
| **TodoWrite** | `todo.ts` structured task tracking | None | **Missing** |
| **WebSearch** | `websearch.ts` via Exa API | None | **Missing** |
| **WebFetch** | `webfetch.ts` URL fetch with HTML->MD conversion | None | **Missing** |
| **CodeSearch** | `codesearch.ts` API documentation search | None | **Missing** |
| **Question** | `question.ts` interactive questions to user | None | **Missing** |
| **Plan Enter/Exit** | `plan.ts` plan mode transitions | None | **Missing** |
| **Skill** | `skill.ts` load specialized instructions | None | **Missing** |
| **LSP** | `lsp.ts` language server integration | None | **Missing** |

### D2. Tool Parameter Schema Quality

**opencode bash tool** parameters:
```typescript
z.object({
  command: z.string().describe("The command to execute"),
  timeout: z.number().describe("Optional timeout in milliseconds").optional(),
  workdir: z.string().describe("The working directory to run the command in...").optional(),
  description: z.string().describe("Clear, concise description of what this command does in 5-10 words..."),
})
```

**mo-code shell tool** parameters:
```json
{
  "command": {"type": "string", "description": "The shell command to execute"},
  "timeout_seconds": {"type": "integer", "description": "Custom timeout in seconds. Default: 30, max: 120"}
}
```

**Gap**: mo-code lacks `workdir` (forces cd), `description` (no UI metadata), and schemas are raw JSON strings instead of typed schemas.

### D3. Tool Result Formatting

**opencode** returns structured results with `title`, `metadata`, and `output` fields. The UI uses `title` for collapsed view, `metadata` for badges (exit code, line count), and `output` for expanded view.

**mo-code** returns plain strings. The UI has no structured tool result display.

---

## E. Concrete Redesign Recommendations

### P0 - Critical (Do First)

#### E1. Overhaul System Prompt (`backend/context/context.go`)

Replace `BuildSystemPrompt()` with a proper prompt builder. Proposed implementation:

```go
func BuildSystemPrompt(workingDir string, toolNames []string, providerName string, modelID string) string {
    var sb strings.Builder
    
    // Core identity
    sb.WriteString(corePrompt(providerName))
    
    // Environment block (XML structured for better LLM parsing)
    sb.WriteString("\n\n<env>\n")
    sb.WriteString(fmt.Sprintf("  Working directory: %s\n", workingDir))
    sb.WriteString(fmt.Sprintf("  Platform: %s\n", runtime.GOOS))
    sb.WriteString(fmt.Sprintf("  Today's date: %s\n", time.Now().Format("2006-01-02")))
    // Detect git
    if _, err := os.Stat(filepath.Join(workingDir, ".git")); err == nil {
        sb.WriteString("  Is directory a git repo: yes\n")
    } else {
        sb.WriteString("  Is directory a git repo: no\n")
    }
    sb.WriteString("</env>\n")
    
    // Tool listing with descriptions
    sb.WriteString("\nYou have access to these tools:\n")
    for _, name := range toolNames {
        sb.WriteString(fmt.Sprintf("- %s\n", name))
    }
    
    // Behavioral rules
    sb.WriteString(behavioralRules())
    
    // Project instructions (AGENTS.md, CLAUDE.md)
    if instructions := discoverInstructions(workingDir); instructions != "" {
        sb.WriteString("\n# Project Instructions\n")
        sb.WriteString(instructions)
    }
    
    return sb.String()
}

func corePrompt(provider string) string {
    switch provider {
    case "claude":
        return ANTHROPIC_PROMPT
    case "gemini":
        return GEMINI_PROMPT
    default:
        return DEFAULT_PROMPT
    }
}
```

**New file**: `backend/context/prompts.go` containing provider-specific prompt constants modeled after opencode's `anthropic.txt` and `gemini.txt`. Key sections to include:

```
# Tone and style
- Be concise and direct. Keep responses under 4 lines unless asked for detail.
- Use GitHub-flavored markdown for formatting.
- Only use emojis if explicitly requested.
- Do not add unnecessary preamble or postamble.

# Following conventions
- NEVER assume a library is available. Check package manifests first.
- When creating components, look at existing ones for conventions.
- Always follow security best practices. Never expose secrets.
- Do NOT add comments unless asked.

# Doing tasks
1. Search the codebase to understand context (use grep/glob in parallel)
2. Implement the solution
3. Verify with tests if applicable
4. Run lint/typecheck commands if available
- NEVER commit unless explicitly asked.

# Proactiveness
- Complete the requested task fully, including reasonable follow-ups.
- Do not surprise the user with unrequested actions.
- Do not explain changes unless asked.
```

**Files to modify**:
- `backend/context/context.go` - Rewrite `BuildSystemPrompt()`
- Create `backend/context/prompts.go` - Per-provider prompts
- Create `backend/context/instructions.go` - AGENTS.md/CLAUDE.md discovery

#### E2. Add Edit Tool (`backend/tools/edit.go`)

The most critical missing tool. LLMs need exact-string-replace semantics, not full file overwrites.

```go
type FileEdit struct {
    workDir string
}

func (f *FileEdit) Name() string { return "file_edit" }

func (f *FileEdit) Description() string {
    return "Performs exact string replacements in files. " +
        "You must read the file first before editing. " +
        "The edit will fail if oldString is not found or matches multiple locations. " +
        "Use replaceAll to change every occurrence."
}

func (f *FileEdit) Parameters() string {
    return `{
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Relative path to the file"},
            "old_string": {"type": "string", "description": "The exact text to replace"},
            "new_string": {"type": "string", "description": "The replacement text"},
            "replace_all": {"type": "boolean", "description": "Replace all occurrences. Default: false"}
        },
        "required": ["path", "old_string", "new_string"]
    }`
}
```

**Files to create**: `backend/tools/edit.go`
**Files to modify**: `backend/tools/dispatch.go` (register new tool)

#### E3. Add Grep Tool (`backend/tools/grep.go`)

Essential for codebase search without shell overhead.

```go
type GrepSearch struct {
    workDir string
}

func (g *GrepSearch) Name() string { return "grep" }

func (g *GrepSearch) Description() string {
    return "Search file contents using regular expressions. " +
        "Supports full regex syntax. Filter files with include parameter. " +
        "Returns file paths and matching line numbers."
}

func (g *GrepSearch) Parameters() string {
    return `{
        "type": "object",
        "properties": {
            "pattern": {"type": "string", "description": "Regex pattern to search for"},
            "path": {"type": "string", "description": "Directory to search in. Default: '.'"},
            "include": {"type": "string", "description": "File glob filter, e.g. '*.go'"},
            "context": {"type": "integer", "description": "Lines of context around matches. Default: 0"}
        },
        "required": ["pattern"]
    }`
}
```

**Files to create**: `backend/tools/grep.go`

#### E4. Add Glob Tool (`backend/tools/glob.go`)

Pattern-based file finding without shell.

**Files to create**: `backend/tools/glob.go`

#### E5. Context Compaction (`backend/context/compaction.go`)

When context exceeds 80% of model's limit, summarize older messages using the LLM itself:

```go
type Compactor struct {
    provider provider.Provider
}

func (c *Compactor) ShouldCompact(mgr *Manager, modelLimit int) bool {
    used := mgr.UsedTokens()
    return used > int(float64(modelLimit) * 0.8)
}

func (c *Compactor) Compact(ctx context.Context, mgr *Manager) error {
    // 1. Take all messages except last 4
    // 2. Send to LLM with compaction prompt
    // 3. Replace old messages with summary
    // 4. Preserve recent messages verbatim
}
```

Key: Use claw-code's approach - keep recent 4 messages, summarize the rest, prepend continuation preamble.

**Files to create**: `backend/context/compaction.go`
**Files to modify**: `backend/agent/engine.go` (call compaction in runLoop)

### P1 - High Priority (Next Sprint)

#### E6. Structured Tool Results

Change tool return type from `string` to structured result:

```go
type ToolResult struct {
    Output        string            `json:"output"`
    Title         string            `json:"title,omitempty"`
    Metadata      map[string]any    `json:"metadata,omitempty"`
    FilesCreated  []string          `json:"files_created,omitempty"`
    FilesModified []string          `json:"files_modified,omitempty"`
    ExitCode      *int              `json:"exit_code,omitempty"`
}
```

**Files to modify**: All tools in `backend/tools/`, `backend/agent/engine.go` event emission

#### E7. Output Truncation System

```go
const (
    MaxOutputLines = 2000
    MaxOutputBytes = 50 * 1024  // 50KB
)

func TruncateOutput(output string) (truncated string, full string, wasTruncated bool) {
    lines := strings.Split(output, "\n")
    if len(lines) <= MaxOutputLines && len(output) <= MaxOutputBytes {
        return output, "", false
    }
    // Save full output to temp file, return truncated version with notice
    preview := strings.Join(lines[:MaxOutputLines], "\n")
    return preview + "\n\n... (output truncated, full output saved)", output, true
}
```

**Files to create**: `backend/tools/truncate.go`
**Files to modify**: `backend/tools/shell.go`, `backend/tools/file.go`

#### E8. Instruction File Discovery

```go
func DiscoverInstructions(workDir string) string {
    files := []string{"AGENTS.md", "CLAUDE.md", "CONTEXT.md"}
    for _, f := range files {
        path := filepath.Join(workDir, f)
        if data, err := os.ReadFile(path); err == nil {
            return fmt.Sprintf("Instructions from: %s\n%s", path, string(data))
        }
    }
    // Walk up to find in parent directories
    // Check ~/.config/opencode/AGENTS.md for global instructions
    return ""
}
```

**Files to create**: `backend/context/instructions.go`
**Files to modify**: `backend/context/context.go`

#### E9. Session Persistence

Store conversation history so sessions survive daemon restarts.

**Files to create**: `backend/context/session_store.go`

Key model (inspired by claw-code):
```go
type Session struct {
    ID           string
    CreatedAt    time.Time
    UpdatedAt    time.Time
    Title        string
    Messages     []provider.Message
    WorkspaceDir string
    Model        string
    Provider     string
}
```

#### E10. Shell Tool Improvements

- Add `workdir` parameter (avoid forcing `cd`)
- Add `description` parameter (for UI metadata)
- Increase default timeout to 120s (30s is too short for builds)
- Add streaming output metadata updates
- Parse commands for external directory detection

**Files to modify**: `backend/tools/shell.go`

#### E11. Flutter Streaming Markdown Renderer

Replace plain text terminal output with proper markdown rendering.

**Files to modify**: `flutter/lib/widgets/terminal_output.dart`

Use `flutter_markdown` package with streaming support:
- Parse partial markdown as it arrives
- Handle code blocks with syntax highlighting
- Support diff display within markdown

#### E12. Flutter Diff Viewer Widget

New widget for displaying file diffs inline in conversation.

**Files to create**: `flutter/lib/widgets/diff_viewer.dart`

#### E13. Flutter TODO Panel

Visible task progress panel inspired by opencode's TodoWrite.

**Files to create**: `flutter/lib/widgets/todo_panel.dart`

### P2 - Important (Subsequent Sprints)

#### E14. Subagent / Task Tool

Allow the primary agent to spawn focused sub-tasks (explore, general research) with their own sessions.

**Files to create**: `backend/tools/task.go`, `backend/agent/subagent.go`

#### E15. WebFetch Tool

URL fetching with HTML to markdown conversion for documentation lookup.

**Files to create**: `backend/tools/webfetch.go`

#### E16. Question Tool

Allow the agent to ask the user clarifying questions with structured options.

**Files to create**: `backend/tools/question.go`
**Files to modify**: `backend/api/` (new WebSocket message type), `flutter/lib/widgets/` (question UI)

#### E17. Plan Mode

A read-only agent mode that plans without editing, using a dedicated plan prompt (from opencode's `plan.txt`).

**Files to create**: `backend/agent/plan_mode.go`

#### E18. Per-Model Context Limits

Map model IDs to their actual context windows instead of using a fixed 100K:

```go
var ModelLimits = map[string]int{
    "claude-sonnet-4-20250514": 200_000,
    "claude-opus-4-20250514":   200_000,
    "gpt-4o":                   128_000,
    "gemini-2.0-flash":         1_000_000,
    "gemini-2.5-pro":           1_000_000,
}
```

**Files to modify**: `backend/context/context.go`, `backend/provider/`

#### E19. Provider Model Discovery

opencode supports 20+ provider SDKs via ai-sdk. mo-code hardcodes 3 providers. Add:
- OpenRouter (access to many models through one API)
- Local/Ollama support
- Azure OpenAI
- AWS Bedrock

**Files to create**: `backend/provider/openrouter.go`, `backend/provider/ollama.go`

#### E20. Flutter Session History UI

- Session list with auto-generated titles
- Resume previous sessions
- Session diff review (what files changed)

**Files to create**: `flutter/lib/screens/sessions_screen.dart`
**Files to modify**: `flutter/lib/main.dart` (add navigation)

#### E21. Flutter File Search

In-app file search with fuzzy matching, replacing the basic file list.

**Files to modify**: `flutter/lib/screens/files_screen.dart`

#### E22. Permission System

opencode has a granular permission system (`Permission.fromConfig`) controlling which tools can be used, which directories can be accessed, which files can be read. mo-code has a simple `isDangerous()` blocklist.

**Files to create**: `backend/tools/permissions.go`

---

## F. Priority Matrix Summary

| Priority | Item | Impact | Effort |
|----------|------|--------|--------|
| **P0** | System prompt overhaul | Critical | Medium |
| **P0** | Add file_edit tool | Critical | Low |
| **P0** | Add grep tool | Critical | Low |
| **P0** | Add glob tool | Critical | Low |
| **P0** | Context compaction | Critical | High |
| **P1** | Structured tool results | High | Medium |
| **P1** | Output truncation | High | Low |
| **P1** | Instruction file discovery | High | Low |
| **P1** | Session persistence | High | High |
| **P1** | Shell tool improvements | High | Low |
| **P1** | Streaming markdown renderer | High | Medium |
| **P1** | Diff viewer widget | High | Medium |
| **P1** | TODO panel | Medium | Medium |
| **P2** | Subagent/Task tool | Medium | High |
| **P2** | WebFetch tool | Medium | Medium |
| **P2** | Question tool | Medium | Medium |
| **P2** | Plan mode | Medium | Medium |
| **P2** | Per-model context limits | Medium | Low |
| **P2** | More providers | Medium | High |
| **P2** | Session history UI | Medium | Medium |
| **P2** | File search UI | Low | Medium |
| **P2** | Permission system | Low | High |

---

## G. Key Architectural Lessons from opencode

### G1. Agent Architecture (Multi-Agent)

opencode runs 6 named agents:
- **build** - Default agent with full tool access
- **plan** - Read-only mode, can only edit plan files
- **general** - Subagent for parallel research tasks
- **explore** - Fast read-only codebase exploration
- **compaction** - Summarizes conversation history
- **title** - Generates session titles

Each has its own permission set and optional model override. mo-code runs a single agent loop.

### G2. Effect System

opencode uses the Effect-TS library for structured concurrency, dependency injection, and error handling. This is overkill for a Go backend (Go has goroutines and interfaces), but the key lesson is: **every tool operation should be cancellable, have a defined error path, and emit structured events**.

### G3. Tool Metadata Pattern

Every opencode tool returns `{ title, metadata, output }`. The `title` is shown collapsed in the UI, `metadata` drives badges and status indicators, `output` is the full result for the LLM. This three-tier pattern is essential for mobile where screen space is limited.

### G4. Bash Command Parsing

opencode uses tree-sitter to parse bash commands BEFORE execution to:
- Detect file paths being accessed (for permission checks)
- Identify external directory access
- Extract command names for permission matching

This is worth implementing for security on mobile where the agent has shell access.

---

## H. Claw-Code Innovations Worth Adopting

### H1. Summary Compression Budget

```rust
pub struct SummaryCompressionBudget {
    pub max_chars: usize,      // 1200
    pub max_lines: usize,      // 24
    pub max_line_chars: usize,  // 160
}
```

Compaction summaries are budget-constrained: dedup lines, truncate long lines, select most informative lines. This prevents summaries from consuming too much of the freed context.

### H2. Session Workspace Binding

Each session is bound to a `workspace_root`, preventing cross-project contamination when multiple instances run.

### H3. Git Context in System Prompt

```rust
pub struct ProjectContext {
    pub cwd: PathBuf,
    pub current_date: String,
    pub git_status: Option<String>,
    pub git_diff: Option<String>,
    pub git_context: Option<GitContext>,
    pub instruction_files: Vec<ContextFile>,
}
```

Injecting current git status and diff into the system prompt gives the agent immediate awareness of uncommitted changes without needing a tool call.

### H4. Continuation Preamble

After compaction, claw-code injects:
```
This session is being continued from a previous conversation that ran out of context.
The summary below covers the earlier portion of the conversation.
...
Continue the conversation from where it left off without asking the user any further questions.
Resume directly - do not acknowledge the summary, do not recap what was happening.
```

This prevents the LLM from wasting tokens on "I see from the summary that..." preamble.
