# Mo-Code UX Mockups

## Design system

### Colors (dark terminal theme)
- **Background:** `#1a1a2e` (main), `#12122a` (panels/cards), `#2a2a4a` (borders)
- **Text:** `#b4b2a9` (primary), `#6a6a8a` (secondary/muted)
- **Green:** `#5dca7a` (success, user input, file added)
- **Purple:** `#7f77dd` (accent, active provider, plan steps, brand)
- **Amber:** `#ef9f27` (in-progress, file modified, warnings)
- **Red:** `#e24b4a` (errors, file deleted, diff removed lines)
- **White:** `#ffffff` (active text, buttons on purple)

### Typography
- **Terminal text:** JetBrains Mono, 13px
- **UI labels:** System font (Roboto on Android), 14px
- **Section headers:** System font, 16px, medium weight

### Spacing
- **Screen padding:** 12px horizontal
- **Card padding:** 10px
- **Between cards:** 8px
- **Between sections:** 16px

### Components
- **Pills/badges:** 8-10px font, 3-6px vertical padding, 8-12px horizontal, border-radius 10px
- **Cards:** background #12122a, border-radius 8px, optional colored left border (3px)
- **Buttons:** 8-10px font, border-radius 8px, colored background or #2a2a4a
- **Input fields:** background #1a1a2e, border 1px #2a2a4a, border-radius 8px, 10px padding
- **Progress bars:** background #2a2a4a, colored fill, border-radius 3px, height 4px

---

## Screen 1: Agent view

This is where the user spends 80% of their time.

### Layout (top to bottom):
1. **Status bar** (height: 28px)
   - Left: "mo-code" in muted text
   - Right: green dot + active model name (e.g., "● claude-4")

2. **Provider switcher** (height: 32px, below status bar)
   - Horizontal row of pill buttons: Claude | Gemini | Copilot
   - Active pill: purple background (#7f77dd), white text
   - Inactive pills: dark background (#2a2a4a), muted text (#6a6a8a)
   - Bottom border: 1px #2a2a4a

3. **Terminal output** (fills remaining space minus input bar)
   - Scrollable vertical list of styled text spans
   - Each message type has distinct styling:
     - **User input:** green (#5dca7a), prefixed with `$ `
     - **Agent thinking:** muted (#6a6a8a), prefixed with `⟐ `
     - **Plan steps:** numbered with purple accent, white text
     - **File created:** green checkmark `✓ Created filename`
     - **File in progress:** amber spinner `⧖ Writing filename...`
     - **Token counter:** muted, small font, amber dot prefix
     - **Separator:** dashed line in muted color
   - Auto-scrolls to bottom on new content
   - User can scroll up to review history (pauses auto-scroll)
   - Tapping a file name opens it in code preview

4. **Live code preview** (collapsible, 0-200px height)
   - Shows when agent is writing a file
   - Header: filename in muted text, collapse arrow
   - Body: syntax-highlighted code with blinking cursor at write position
   - Background: #12122a, border-radius 6px, 8px padding

5. **Input bar** (fixed at bottom, height: 48px)
   - Background: #12122a, top border 1px #2a2a4a
   - Text field: placeholder "Type or speak...", muted text
   - Send button: 28px circle, purple (#7f77dd), white play icon
   - Microphone button: appears when speech_to_text is available

---

## Screen 2: Background tasks

### Layout:
1. **Header** (height: 44px)
   - "Active tasks" in primary text, medium weight

2. **Task list** (scrollable, fills remaining space)
   - Each task is a card (#12122a background, 8px border-radius)
   - Left border (3px) color indicates state:
     - Amber: running
     - Green: complete
     - Purple: queued
     - Red: failed
   - Card contents:
     - **Task name** (from prompt, truncated to ~30 chars), primary text, medium weight
     - **Provider + status** (e.g., "Claude · 4/7 steps done"), muted text, small
     - **Progress bar** (for running tasks): 4px height, colored fill
     - **Action buttons** (for completed tasks): "Review diff" (green pill), "Push" (dark pill)
     - **Meta badges** (for queued tasks): file count, estimated time

3. **Notification preview** (floating, above bottom nav)
   - Appears briefly when a task completes
   - Dark card with green checkmark and summary
   - Auto-dismisses after 5 seconds, swipeable

---

## Screen 3: File browser + git

### Layout:
1. **Git bar** (height: 56px)
   - Left side: repo name (primary text) + branch name (purple, prefixed with ⎇)
   - Right side: "Commit" button (green pill) + "Push" button (dark pill)

2. **File tree** (scrollable, fills ~60% of space)
   - Indented tree structure with expand/collapse arrows
   - Each entry: icon/prefix + filename
   - Git status coloring:
     - `+` green prefix = added/staged
     - `~` amber prefix = modified
     - No prefix, normal color = unchanged
     - `-` red prefix = deleted
   - Directories are collapsible with `▾`/`▸` indicators
   - Tapping a file opens diff preview or code viewer

3. **Diff preview** (bottom panel, ~40% of space)
   - Header: filename + "modified" label in muted text
   - Diff lines:
     - Red background + `-` prefix for removed lines
     - Green background + `+` prefix for added lines
     - Normal background for context lines
   - Monospace font, horizontal scroll for long lines

4. **Staged changes summary** (above bottom nav)
   - "3 added · 1 modified · unstaged: 0" with colored counts
   - Thin top border separator

---

## Screen 4: Config / Settings

### Layout:
1. **Provider settings** (expandable section per provider)
   - Provider name + status badge (configured/not configured)
   - API key field (password-masked, with show/hide toggle)
   - Model selector dropdown
   - "Test connection" button

2. **Git settings**
   - SSH key display (public key, with copy button)
   - "Generate new key" button
   - GitHub username field
   - Default remote URL

3. **App settings**
   - Default working directory picker
   - Notification preferences (toggles)
   - Background execution toggle
   - "Clear all data" danger button

---

## Bottom navigation

- Four equal-width tabs
- Each tab: icon (14px) + label (9px) stacked vertically
- Active tab: purple (#7f77dd) icon + text
- Inactive tabs: muted (#6a6a8a) icon + text
- Icons: ⌨ Agent | ☰ Tasks | ⎕ Files | ⚙ Config
- Background: #12122a, top border 1px #2a2a4a
- Tasks tab shows badge with active task count (small purple circle with white number)

---

## Interaction patterns

### Starting a task
1. User types prompt in agent view input bar (or uses voice)
2. Taps send button
3. Agent view shows plan, then streams execution
4. If user switches to another app, task continues in background
5. Notification fires when complete

### Reviewing completed work
1. Notification: "Task X ready — 3 files changed"
2. User taps notification → navigates to Files tab
3. File tree shows new/modified files with git colors
4. User taps modified file → sees diff
5. User taps "Commit" → enters message → confirms
6. User taps "Push" → progress indicator → done

### Switching providers mid-session
1. User taps different provider pill in agent view
2. Pill animates to active state
3. Next task will use the new provider
4. If a task is currently running, it continues with the original provider
5. Status bar updates to show new active model

### Multi-task workflow
1. User starts task A with Claude
2. While task A runs, user switches to Tasks tab
3. User navigates back to Agent tab
4. User starts task B with Gemini (task A continues in background)
5. Agent view shows task B stream
6. Tasks tab shows both tasks with progress
7. Notification when task A completes
