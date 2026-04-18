# Sandbox Backends — Parallel Track Plan

Four independent backends implement the `sandbox.Sandbox` interface. Each is a
separate worktree on its own branch. They do not touch each other's files.

**Lead:** Om's main Claude session (integration, review, release).
**Workers:** One Claude Code session per track, below.

## Interface contract (already on master)

- `backend/sandbox/sandbox.go` — `Sandbox` interface, `Capabilities`, `Diagnostic`
- `backend/sandbox/registry.go` — `Register(name, Factory)`, `Open(ctx, cfg)`, fallback chain
- `backend/sandbox/proot/backend.go` — reference adapter over existing `runtime.ProotRuntime`

Every track implements `Sandbox`, calls `sandbox.Register(name, Factory)` in `init()`,
lives in `backend/sandbox/<name>/`. Zero overlap with other tracks.

## Track status

| Track | Name | Branch | Worktree | Status | Owner |
|-------|------|--------|----------|--------|-------|
| A | termux-prefix | `feat/sandbox-termux` | `../worktrees/sandbox-termux` | not started | |
| B | qemu-tcg | `feat/sandbox-qemu` | `../worktrees/sandbox-qemu` | not started | |
| C | prebaked-rootfs | `feat/prebaked-rootfs` | `../worktrees/sandbox-prebake` | not started | |
| D | avf-microdroid | `feat/sandbox-avf` | `../worktrees/sandbox-avf` | ready for review | Claude (worker D) |

Update the row when you claim/start/finish a track.

## Setup (run once)

```bash
cd /mnt/linux_disk/opensource/mo-code
git worktree add ../worktrees/sandbox-termux  -b feat/sandbox-termux
git worktree add ../worktrees/sandbox-qemu    -b feat/sandbox-qemu
git worktree add ../worktrees/sandbox-prebake -b feat/prebaked-rootfs
git worktree add ../worktrees/sandbox-avf     -b feat/sandbox-avf
```

Each track opens Claude Code in its worktree:

```bash
cd ../worktrees/sandbox-termux && claude
```

Then paste the matching prompt below.

---

## Track A prompt — Termux-style bionic prefix backend

```
You are implementing backend #A of the mo-code sandbox system, working in an
isolated git worktree on branch feat/sandbox-termux.

GOAL: native-speed shell environment on unrooted Android 15. No ptrace, no VM.
Bundle busybox plus a bionic-linked toolset (git, nodejs, python3, curl) as
APK assets. First Prepare() extracts to $appFiles/termux-prefix. Exec() runs
binaries directly via os/exec with PATH/LD_LIBRARY_PATH pointing into the prefix.

OWNED FILES (do not touch anything else):
  backend/sandbox/termux/*.go
  scripts/build-termux-prefix.sh
  flutter/android/app/src/main/assets/termux-prefix/   (tarball goes here)
  docs/SANDBOX_TERMUX.md

INTERFACE TO IMPLEMENT: backend/sandbox/sandbox.go (already on master).
Register your Factory in init() as "termux-prefix".

CAPABILITIES you report:
  PackageManager: true   (if you ship `pkg` or implement installer)
  FullPOSIX:      false  (bionic, not glibc)
  Network:        true
  RootLikeSudo:   false
  SpeedFactor:    1.0
  IsolationTier:  1

REFERENCE: https://github.com/termux/termux-packages — their build scripts
produce bionic-compatible ELFs. You may vendor a subset of their prebuilt
binaries for arm64 (nodejs, python3, git, busybox).

ACCEPTANCE (you verify all three before marking track done):
  1. `go build ./...` clean from repo root.
  2. Unit test termux_test.go covers Exec("echo ok"), InstallPackage.
  3. On Android 15 (ask Om to test): `sandbox.Open(... backend="termux-prefix")`
     then InstallPackage([]string{"nodejs"}) → `node -v` exits 0.

DO NOT:
  - Modify anything outside your owned files list.
  - Change backend/sandbox/sandbox.go or registry.go.
  - Touch other tracks' directories (qemu, prebake, avf).
  - Commit prebuilt binaries >50MB without asking the lead first.

When done: commit, push branch, open PR against master titled
"feat(sandbox): Termux-style bionic-prefix backend (track A)".
Update docs/SANDBOX_TRACKS.md status row to "ready for review".
```

---

## Track B prompt — QEMU TCG full-VM backend

```
You are implementing backend #B of the mo-code sandbox system, working in an
isolated git worktree on branch feat/sandbox-qemu.

GOAL: bulletproof isolation via QEMU TCG (software-emulated ARM64 VM). Ships
qemu-system-aarch64 static binary plus alpine-prebaked.qcow2 as APK assets.
Prepare() boots the VM (<5s target). Exec() runs commands via virtio-serial
or SSH. Accept 10-50x native slowdown as the cost of real isolation.

OWNED FILES (do not touch anything else):
  backend/sandbox/qemu/*.go
  scripts/build-qemu-image.sh
  scripts/build-qemu-binary.sh
  flutter/android/app/src/main/assets/qemu/   (binary + qcow2 go here)
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
COMMS: virtio-serial (fastest) or SSH over user-mode networking. Pick one
and document the choice in docs/SANDBOX_QEMU.md.

ACCEPTANCE:
  1. `go build ./...` clean.
  2. Unit test qemu_test.go covers Prepare + Exec("echo ok") on a Linux host
     (not Android — Android integration is the lead's job).
  3. `apk add python3` inside the VM works. Prove this in the test.

DO NOT:
  - Modify anything outside your owned files list.
  - Change backend/sandbox/sandbox.go or registry.go.
  - Touch other tracks' directories.
  - Commit the qcow2 image (>50MB). Add to .gitignore, ship via release asset.
    The build script is versioned; the artifact is not.

When done: commit, push branch, open PR titled
"feat(sandbox): QEMU TCG full-VM backend (track B)".
Update docs/SANDBOX_TRACKS.md status to "ready for review".
```

---

## Track C prompt — Prebaked Alpine rootfs for proot

```
You are implementing track #C of the mo-code sandbox system, working in an
isolated git worktree on branch feat/prebaked-rootfs.

GOAL: ship a fully-provisioned Alpine arm64 rootfs as an APK asset so the
existing proot backend works on first launch with zero runtime apk. This
eliminates ISSUE-010 cascades (apk update dying silently under Android 15
zygote seccomp) without changing the proot backend itself.

OWNED FILES (do not touch anything else):
  scripts/build-prebaked-rootfs.sh
  backend/sandbox/proot/prebaked.go   (new file — adds prebaked extractor)
  flutter/android/app/src/main/assets/rootfs/alpine-prebaked-arm64.tar.gz  (artifact location)
  docs/SANDBOX_PREBAKED.md

BUILD APPROACH: Docker `alpine:3.19` + `qemu-user-static` for arm64.
Install inside the container:
  git, nodejs, npm, python3, py3-pip, curl, openssh-client, ca-certificates, bash
Then tar + gzip the filesystem. Target size <150MB compressed.

CODE CHANGE: add prebaked.go to backend/sandbox/proot/. Expose
  func ExtractPrebaked(ctx, tarballPath, destDir string) error
called by the existing proot extraction flow. Do NOT delete or modify the
existing runtime.ProotRuntime code paths; the runtime apk code stays as a
fallback for backends that want it.

ACCEPTANCE:
  1. `go build ./...` clean.
  2. Unit test extracts a small fixture tarball → verifies git/python3 present.
  3. Build script runs end-to-end on Linux host with docker available and
     emits flutter/android/app/src/main/assets/rootfs/alpine-prebaked-arm64.tar.gz.
  4. Ask Om to run the APK with the prebaked asset bundled: `python3 -c 'print(1)'`
     through the agent must exit 0 on first install, no `apk add` ever called.

DO NOT:
  - Modify anything outside your owned files list.
  - Change backend/sandbox/sandbox.go, registry.go, or backend/sandbox/proot/backend.go.
  - Commit the generated tarball if >80MB — add to .gitignore and ship via release.
  - Touch other tracks' directories.

When done: commit, push branch, open PR titled
"feat(sandbox): prebaked Alpine rootfs for proot backend (track C)".
Update docs/SANDBOX_TRACKS.md status to "ready for review".

URGENCY: this is the highest-priority track. Om is blocked on it for tonight's
beta test. If anything blocks you, surface it immediately rather than spinning.
```

---

## Track D prompt — AVF/Microdroid capability probe + stub backend

```
You are implementing track #D of the mo-code sandbox system, working in an
isolated git worktree on branch feat/sandbox-avf.

GOAL: on Pixel 7+ with pKVM, detect it and expose avf-microdroid as the
preferred backend. On OnePlus and other non-Pixel hardware, gracefully
return ErrBackendUnavailable from the Factory so the registry fallback
chain skips to qemu-tcg or proot. No crashes.

OWNED FILES (do not touch anything else):
  backend/sandbox/avf/*.go
  flutter/android/app/src/main/kotlin/io/github/omashishsoni/mocode/AvfProbe.kt
  docs/SANDBOX_AVF.md

INTERFACE: backend/sandbox/sandbox.go (already on master).
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
GO SIDE: JNI bridge reads the Kotlin-side result. If false,
Factory returns sandbox.ErrBackendUnavailable. If true, Factory returns
a Backend that boots a Microdroid VM and Exec()s via virtio-serial
(stub this with a TODO for now — real VM plumbing is a future PR).

ACCEPTANCE:
  1. `go build ./...` clean.
  2. On OnePlus CPH2467 (Om will test): backend registers, Factory returns
     ErrBackendUnavailable, registry picks next backend. No crash, no log noise.
  3. Unit test mocks the JNI bridge → verifies both paths (available/unavailable).

DO NOT:
  - Modify anything outside your owned files list.
  - Change backend/sandbox/sandbox.go or registry.go.
  - Touch other tracks' directories.
  - Implement full Microdroid boot — stub it, TODO it, acceptance is the probe.

When done: commit, push branch, open PR titled
"feat(sandbox): AVF/Microdroid probe + stub backend (track D)".
Update docs/SANDBOX_TRACKS.md status to "ready for review".
```

---

## Integration (lead only)

When a track PR opens:

1. Review the diff. Check: only owned files changed? Interface untouched? Acceptance met?
2. Merge to master.
3. Add anonymous import to `backend/cmd/mocode/main.go`:
   ```go
   _ "mo-code/backend/sandbox/<backend-name>"
   ```
4. Update default fallback chain in config to include the new backend.
5. Smoke test on Om's OnePlus.

When all four land: cut v1.4 release, update `docs/JIRA_EPIC.md`, close
ISSUE-010.

## Conflict-avoidance rules

- **Never** modify `backend/sandbox/sandbox.go` or `backend/sandbox/registry.go`
  from a track branch. These are lead-owned.
- **Never** modify another track's directory.
- Large binary artifacts (>50MB) go in .gitignore and ship as release assets,
  not in the repo.
- If a track needs a shared change to the interface, open a GitHub issue
  tagged `sandbox-interface` and ping the lead.
