# Track A — Termux-style bionic prefix backend

**Worktree**: `/mnt/linux_disk/opensource/worktrees/sandbox-termux`
**Branch**: `feat/sandbox-termux`

Copy the entire fenced block below and paste it to the Claude Code session
running inside the worktree above.

---

```
You are implementing backend #A of the mo-code sandbox system, working in an
isolated git worktree on branch feat/sandbox-termux.

GOAL: native-speed shell environment on unrooted Android 15. No ptrace, no VM.
Bundle busybox + bionic-linked toolset (git, nodejs, python3, curl) as APK
assets. Prepare() extracts to $appFiles/termux-prefix. Exec() runs binaries
directly via os/exec with PATH/LD_LIBRARY_PATH into the prefix.

OWNED FILES (do not touch anything else):
  backend/sandbox/termux/*.go
  scripts/build-termux-prefix.sh
  flutter/android/app/src/main/assets/termux-prefix/
  docs/SANDBOX_TERMUX.md

INTERFACE TO IMPLEMENT: backend/sandbox/sandbox.go (already on master).
Register your Factory in init() as "termux-prefix".

CAPABILITIES you report:
  PackageManager: true
  FullPOSIX:      false  (bionic, not glibc)
  Network:        true
  RootLikeSudo:   false
  SpeedFactor:    1.0
  IsolationTier:  1

REFERENCE: https://github.com/termux/termux-packages — vendor a subset of
their prebuilt arm64 binaries (nodejs, python3, git, busybox).

ACCEPTANCE:
  1. go build ./... clean from repo root.
  2. Unit test termux_test.go covers Exec("echo ok"), InstallPackage.
  3. On Android 15: sandbox.Open(... backend="termux-prefix") then
     InstallPackage(["nodejs"]) → `node -v` exits 0.

DO NOT modify backend/sandbox/sandbox.go, registry.go, or other tracks' dirs.
DO NOT commit prebuilt binaries >50MB without asking the lead first.

When done: commit, push branch, open PR titled
"feat(sandbox): Termux-style bionic-prefix backend (track A)".
Update docs/SANDBOX_TRACKS.md status row to "ready for review".
```
