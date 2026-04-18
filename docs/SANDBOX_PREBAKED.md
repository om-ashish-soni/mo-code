# Sandbox Track C — Prebaked Alpine rootfs

## Problem

The stock Alpine minirootfs shipped by track's reference backend is empty. On
first launch, `RuntimeBootstrap` extracts it, and the agent's first command
triggers `apk update && apk add` to pull git / node / python / curl.

Under Android 15's zygote seccomp filter, `apk update` dies silently (see
`docs/issues/ISSUE-010.md`). The cascade is that `Exec()` returns exit 255
with empty stderr, the UI reports "sandbox failed", and the user is stuck.

## Fix

Prebake every package the agent needs into the rootfs tarball **offline**,
in a Docker build that runs under qemu-user-static. On-device, the first
launch extracts the already-populated tree and never calls `apk`.

The runtime `apk add` code path stays in place as a fallback for anything
the agent asks for beyond the prebaked set — `Installing` returns cleanly
if the package is already present, so no changes to the caller are needed.

## Files

| Path                                                                    | Purpose                                  |
| ----------------------------------------------------------------------- | ---------------------------------------- |
| `scripts/build-prebaked-rootfs.sh`                                      | Docker + qemu build of the arm64 rootfs  |
| `backend/sandbox/proot/prebaked.go`                                     | `ExtractPrebaked(ctx, tar, dest) error`  |
| `backend/sandbox/proot/prebaked_test.go`                                | Unit test with in-memory fixture tarball |
| `flutter/android/app/src/main/assets/rootfs/alpine-prebaked-arm64.tar.gz` | Built asset (gitignored if >80MB)      |

## Prebaked package set

Chosen to cover the 90% path for mo-code's agent tasks — clone a repo, run
npm/pip, talk to remote hosts — without bloating the APK:

- `git`
- `nodejs`, `npm`
- `python3`, `py3-pip`
- `curl`
- `openssh-client`
- `ca-certificates`
- `bash`

## Building the tarball

```bash
./scripts/build-prebaked-rootfs.sh
```

Requires Docker with qemu-user-static registered for arm64. The script calls
`tonistiigi/binfmt --install arm64` on start, which is a no-op if already
registered.

Output lands at
`flutter/android/app/src/main/assets/rootfs/alpine-prebaked-arm64.tar.gz`
together with a `PREBAKED_VERSION` marker. The Alpine version (`3.19`) is
pinned in the script; bump it there when rolling the base.

Target size is **< 150MB compressed**. If the build crosses **80MB** the file
is excluded from git (see `.gitignore`) and must ship via a GitHub release —
do not attempt to push a large tarball to the repo.

## Go API

```go
import "mo-code/backend/sandbox/proot"

// Called from the proot extraction flow (RuntimeBootstrap's Go counterpart,
// or any future in-process bootstrapper) to unpack the asset in place.
err := proot.ExtractPrebaked(ctx, tarballPath, destDir)
```

Behaviour:

- Creates `destDir` if missing. Does not wipe existing contents — the caller
  is expected to clear the directory first for a clean reinstall.
- Preserves exec bits so `/usr/bin/git`, `/usr/bin/python3` etc. remain
  runnable under proot.
- Handles regular files, directories, symlinks, and hard links (with a
  copy fallback when `link(2)` is rejected by the underlying filesystem).
- Skips device / fifo entries — proot binds `/dev` from the host.
- Silently drops any entry whose resolved path escapes `destDir` (zip-slip
  protection).
- Respects `ctx` cancellation between entries for cooperative abort on slow
  devices.

## Acceptance

1. `go build ./...` clean from `backend/`.
2. `go test ./sandbox/proot/...` passes — verifies the fixture tarball
   extracts with `git`, `python3`, and symlink targets intact.
3. `build-prebaked-rootfs.sh` runs end-to-end on Linux with Docker and emits
   the tarball asset under `flutter/android/app/src/main/assets/rootfs/`.
4. On Om's OnePlus: `python3 -c 'print(1)'` through the agent exits 0 on
   first install, with no `apk add` in the logs.

## Non-goals

- Replacing the runtime `apk add` path. Retained as a fallback for packages
  beyond the prebaked set.
- Supporting x86_64 / armhf. Only `linux/arm64` is built; other arches fall
  through to the minirootfs + runtime `apk` path.
- Changing the `sandbox.Sandbox` interface or the existing proot adapter.
  Track C is intentionally additive.
