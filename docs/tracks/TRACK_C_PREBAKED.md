# Track C — Prebaked Alpine rootfs (URGENT)

**Worktree**: `/mnt/linux_disk/opensource/worktrees/sandbox-prebake`
**Branch**: `feat/prebaked-rootfs`

Copy the entire fenced block below and paste it to the Claude Code session
running inside the worktree above.

---

```
You are implementing track #C of the mo-code sandbox system, working in an
isolated git worktree on branch feat/prebaked-rootfs.

GOAL: ship a fully-provisioned Alpine arm64 rootfs as an APK asset so the
existing proot backend works on first launch with zero runtime apk. This
eliminates ISSUE-010 cascades (apk update dying silently under Android 15
zygote seccomp) without changing the proot backend itself.

OWNED FILES (do not touch anything else):
  scripts/build-prebaked-rootfs.sh
  backend/sandbox/proot/prebaked.go
  flutter/android/app/src/main/assets/rootfs/alpine-prebaked-arm64.tar.gz
  docs/SANDBOX_PREBAKED.md

BUILD APPROACH: Docker alpine:3.19 + qemu-user-static for arm64. Install:
git, nodejs, npm, python3, py3-pip, curl, openssh-client, ca-certificates, bash.
Tar + gzip. Target <150MB compressed.

CODE CHANGE: add prebaked.go to backend/sandbox/proot/. Expose
  func ExtractPrebaked(ctx, tarballPath, destDir string) error
called by the existing proot extraction flow. Do NOT delete the runtime apk
code path — leave it as fallback.

ACCEPTANCE:
  1. go build ./... clean from repo root.
  2. Unit test extracts small fixture tarball, verifies git/python3 present.
  3. Build script runs end-to-end on Linux with docker, emits the tarball asset.
  4. On Om's OnePlus: python3 -c 'print(1)' through the agent exits 0 on first
     install, no apk add ever called.

DO NOT modify backend/sandbox/sandbox.go, registry.go, or proot/backend.go.
DO NOT touch other tracks' directories.
DO NOT commit the generated tarball if >80MB — add to .gitignore, ship via release.

When done: commit, push, open PR titled
"feat(sandbox): prebaked Alpine rootfs for proot backend (track C)".
Update docs/SANDBOX_TRACKS.md status row to "ready for review".

URGENCY: Om is blocked on this for tonight's beta test. If blocked, surface
immediately rather than spinning.
```
