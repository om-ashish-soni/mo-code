# Sandbox Backend — QEMU TCG full-VM

Track B. Branch `feat/sandbox-qemu`. Implements `sandbox.Sandbox` under
`backend/sandbox/qemu/` and registers as `qemu-tcg`.

## What it is

A software-emulated ARM64 VM (qemu-system-aarch64, TCG mode, no KVM) running
Alpine 3.19. Isolation tier 3 — the guest has its own kernel, its own init,
its own syscalls. The Android host cannot see inside.

Price: 10–50× native slowdown. Speed factor reported as `20.0`. This is the
"bulletproof isolation at any cost" backend. For daily work, prefer the
proot or termux backends. For untrusted code or hard-isolation demos, this
is the one.

## Comms choice — SSH over user-mode networking

The track brief listed two options: **virtio-serial** (fastest) or **SSH over
user-mode networking**. I picked SSH.

**Why SSH:**

1. `golang.org/x/crypto/ssh` is already a transitive dep (via `go-git`). No
   new module required.
2. No custom in-guest agent — sshd is in Alpine's base. Lowers the build-image
   complexity and keeps the VM trivially debuggable from a host shell.
3. Standardized exec semantics: stdout, stderr, exit code, signal propagation
   all come from `ssh.Session` for free.
4. Matches how every other "run commands inside Linux" tool works, which
   means every Claude Code dev already understands the mental model.

**What I gave up:**

- Virtio-serial would be ~2× faster per exec (no TCP/IP stack, no TLS
  handshake). For a 20× slowdown budget this is in the noise.
- Virtio-serial would allow tunneling arbitrary byte streams without a
  port-forward. Not needed for v1.

If exec latency becomes the bottleneck, we can add a parallel virtio-serial
comms path later without changing the public `Sandbox` interface.

### Connection details

- Host: `127.0.0.1`
- Port: configurable via `qemu.ssh_port` (default **2222**)
- Transport: user-mode net with `hostfwd=tcp:127.0.0.1:<port>-:22`
- Auth: password (default `mocode`, configurable via `qemu.ssh_pass`).

The password is loopback-only: the guest is not reachable from the LAN (user
networking is the default NAT'd SLIRP stack). Host-key pinning is skipped for
the same reason; adding it would require baking a known host key into the
image and shipping it as an APK asset, which is not justified for a
127.0.0.1-only channel.

## Asset layout

Two artifacts ship as APK assets but live outside git (>50MB each):

```
flutter/android/app/src/main/assets/qemu/
├── qemu-system-aarch64-arm64   # built by scripts/build-qemu-binary.sh
├── qemu-img-arm64              # built by scripts/build-qemu-binary.sh
└── alpine-prebaked.qcow2       # built by scripts/build-qemu-image.sh
```

Build once on a Linux host, attach to a GitHub release. The APK build
pipeline pulls them down at package time.

`.gitignore` excludes all three paths. Do not commit them.

## Build flow

### Guest image

```bash
scripts/build-qemu-image.sh
```

Requires on the host: `qemu-system-aarch64`, `qemu-img`, `mkisofs`/`genisoimage`,
UEFI firmware (`qemu-efi-aarch64` / `edk2-aarch64`), ~4 GB free disk. Boots
Alpine's official netboot ISO with an answerfile + firstboot script that:

- Installs Alpine to a 1 GB qcow2 with sys-mode partitioning
- Sets root password (`mocode` by default)
- Enables sshd + root password auth
- Pre-installs `bash`, `ca-certificates`, `curl`, `git`, `openssh`

Produces `alpine-prebaked.qcow2` (~80 MB compressed qcow2).

### QEMU binary

```bash
ANDROID_NDK_HOME=/path/to/ndk scripts/build-qemu-binary.sh
```

Cross-compiles a static `qemu-system-aarch64` for Android (aarch64-linux-android,
API 28). Disables GTK/SDL/KVM/opengl — we only need TCG + slirp. Target binary
size: ~25 MB stripped.

## Backend options

Exposed via `sandbox.Config.Options`:

| key | default | notes |
|-----|---------|-------|
| `qemu.bin` | *(required)* | absolute path to qemu-system-aarch64 |
| `qemu.image` | *(required)* | absolute path to alpine-prebaked.qcow2 |
| `qemu.data_dir` | *(required)* | host dir for per-boot overlay qcow2 |
| `qemu.memory_mb` | 512 | guest RAM |
| `qemu.cpus` | 1 | vCPUs |
| `qemu.ssh_port` | 2222 | host-side port-forward |
| `qemu.ssh_user` | `root` | |
| `qemu.ssh_pass` | `mocode` | matches image build default |
| `qemu.machine` | `virt` | qemu `-machine` |
| `qemu.cpu_model` | `cortex-a72` | qemu `-cpu` |
| `qemu.boot_timeout` | 90s | how long Prepare waits for SSH |
| `qemu.readonly_base` | true | wrap base qcow2 in a throwaway overlay |
| `qemu.extra_args` | — | whitespace-split passthrough to qemu |

## Lifecycle

1. **Prepare(ctx)** — creates an overlay qcow2 (if `readonly_base=true`),
   spawns qemu, polls 127.0.0.1:ssh_port until a full SSH handshake completes,
   or fails after `boot_timeout`. Idempotent.
2. **Exec(ctx, cmd, workDir)** — opens a fresh SSH session, runs the command,
   returns (stdout, stderr, exit). One session per call; no long-lived shell.
3. **InstallPackage(ctx, pkgs)** — wraps `apk add --no-cache`.
4. **Teardown(ctx)** — sends `poweroff -f` over SSH, SIGTERMs qemu after a
   grace period, SIGKILLs if it lingers, deletes the overlay file.

## Acceptance

- `go build ./backend/sandbox/qemu/...` — clean.
- `go test ./backend/sandbox/qemu/` — unit tests cover config parsing,
  capability reporting, registry registration, and "Exec before Prepare fails".
- `TestQemuIntegration` (skipped unless `MOCODE_QEMU_BIN` + `MOCODE_QEMU_IMAGE`
  are set) boots the VM end-to-end and proves:
  - `echo ok` → `ok`, exit 0
  - `apk add python3` succeeds
  - `python3 -c 'print(1+1)'` → `2`
  - `Diagnose()` returns OK

Run the integration test:

```bash
MOCODE_QEMU_BIN=$PWD/flutter/android/app/src/main/assets/qemu/qemu-system-aarch64-arm64 \
MOCODE_QEMU_IMAGE=$PWD/flutter/android/app/src/main/assets/qemu/alpine-prebaked.qcow2 \
  go test ./backend/sandbox/qemu/ -run TestQemuIntegration -v -timeout 5m
```

## Known caveats

- **Boot time**: cold boot on a modern x86_64 desktop under TCG is ~15–25 s.
  The 5 s target in the track brief is aspirational — realistic only on
  KVM hosts (not Android). Leaving `boot_timeout` at 90 s.
- **qemu-img**: if not bundled beside qemu-system, the backend falls back to
  qemu's internal `-snapshot` mode (writes to a temp file inside $TMPDIR).
  Slightly less control but no external tool needed.
- **Android side**: wiring this backend into the APK (extracting assets,
  spawning the process, exposing options) is the lead's integration PR. This
  track ships Go-side only, per the brief.

## Pre-existing build issue (flagged)

The `backend/sandbox/proot/backend.go` adapter (lead-owned, on branch base)
calls `b.rt.Diagnose(ctx)`, but `runtime.ProotRuntime` has no `Diagnose`
method. `go build ./...` from the repo root fails with:

```
sandbox/proot/backend.go:74:12: b.rt.Diagnose undefined
```

This exists before any track-B changes (verified against `d94d4de` with the
qemu package stashed). Flagging here and in the PR body — not fixing from
this branch since `backend/sandbox/proot/` is outside track B's owned files.
