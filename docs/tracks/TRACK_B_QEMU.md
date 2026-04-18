# Track B — QEMU TCG full-VM backend

**Worktree**: `/mnt/linux_disk/opensource/worktrees/sandbox-qemu`
**Branch**: `feat/sandbox-qemu`

Copy the entire fenced block below and paste it to the Claude Code session
running inside the worktree above.

---

```
You are implementing backend #B of the mo-code sandbox system, working in an
isolated git worktree on branch feat/sandbox-qemu.

GOAL: bulletproof isolation via QEMU TCG (software-emulated arm64 VM). Ship
qemu-system-aarch64 static binary + alpine-prebaked.qcow2 as APK assets.
Prepare() boots VM (<5s target). Exec() runs commands via virtio-serial or SSH.
Accept 10-50x native slowdown as the cost of real isolation.

OWNED FILES (do not touch anything else):
  backend/sandbox/qemu/*.go
  scripts/build-qemu-image.sh
  scripts/build-qemu-binary.sh
  flutter/android/app/src/main/assets/qemu/
  docs/SANDBOX_QEMU.md

INTERFACE TO IMPLEMENT: backend/sandbox/sandbox.go (already on master).
Register your Factory in init() as "qemu-tcg".

CAPABILITIES you report:
  PackageManager: true
  FullPOSIX:      true
  Network:        true
  RootLikeSudo:   true
  SpeedFactor:    20.0
  IsolationTier:  3

BOOT TARGET: guest kernel 6.x + alpine 3.19 minimal, 512MB RAM, 1 vCPU.
COMMS: virtio-serial (fastest) or SSH over user-mode net. Pick one, document
the choice in docs/SANDBOX_QEMU.md.

ACCEPTANCE:
  1. go build ./... clean from repo root.
  2. Unit test qemu_test.go covers Prepare + Exec("echo ok") on Linux host
     (not Android — Android integration is the lead's job).
  3. `apk add python3` inside the VM works. Prove this in the test.

DO NOT modify backend/sandbox/sandbox.go, registry.go, or other tracks' dirs.
DO NOT commit the qcow2 image (>50MB). Add to .gitignore, ship via release asset.
Build script is versioned; artifact is not.

When done: commit, push branch, open PR titled
"feat(sandbox): QEMU TCG full-VM backend (track B)".
Update docs/SANDBOX_TRACKS.md status row to "ready for review".
```
