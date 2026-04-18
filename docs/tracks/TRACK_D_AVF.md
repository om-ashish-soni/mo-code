# Track D — AVF/Microdroid probe + stub backend

**Worktree**: `/mnt/linux_disk/opensource/worktrees/sandbox-avf`
**Branch**: `feat/sandbox-avf`

Copy the entire fenced block below and paste it to the Claude Code session
running inside the worktree above.

---

```
You are implementing backend #D of the mo-code sandbox system, working in an
isolated git worktree on branch feat/sandbox-avf.

GOAL: on Pixel 7+ with pKVM, detect it and expose avf-microdroid as the
preferred backend. On OnePlus and other non-Pixel hardware, gracefully
return ErrBackendUnavailable from the Factory so the registry fallback
chain skips to qemu-tcg or proot. No crashes.

OWNED FILES (do not touch anything else):
  backend/sandbox/avf/*.go
  flutter/android/app/src/main/kotlin/io/github/omashishsoni/mocode/AvfProbe.kt
  docs/SANDBOX_AVF.md

INTERFACE TO IMPLEMENT: backend/sandbox/sandbox.go (already on master).
Register your Factory in init() as "avf-microdroid".

CAPABILITIES you report (when available):
  PackageManager: true
  FullPOSIX:      true
  Network:        true
  RootLikeSudo:   true
  SpeedFactor:    1.2
  IsolationTier:  3

KOTLIN SIDE: query android.system.virtualmachine.VirtualMachineManager
(API level 34+). If unavailable or throws: record false, propagate to Go.
GO SIDE: JNI bridge reads the Kotlin-side result. If false, Factory returns
sandbox.ErrBackendUnavailable. If true, Factory returns a Backend that boots
a Microdroid VM and Exec()s via virtio-serial (stub this with a TODO for
now — real VM plumbing is a future PR).

ACCEPTANCE:
  1. go build ./... clean from repo root.
  2. On OnePlus CPH2467 (Om will test): backend registers, Factory returns
     ErrBackendUnavailable, registry picks next backend. No crash, no log noise.
  3. Unit test mocks the JNI bridge → verifies both paths (available/unavailable).

DO NOT modify backend/sandbox/sandbox.go, registry.go, or other tracks' dirs.
DO NOT implement full Microdroid boot — stub it, TODO it, acceptance is the probe.

When done: commit, push branch, open PR titled
"feat(sandbox): AVF/Microdroid probe + stub backend (track D)".
Update docs/SANDBOX_TRACKS.md status row to "ready for review".
```
