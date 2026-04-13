# FEAT-002: proot + Alpine Linux On-Device Runtime

**Status:** PENDING — approved for implementation
**Priority:** P0 — enables true on-device vibe coding
**Epic:** MO-22 (Execution runtime: proot + Alpine Linux)
**Estimated effort:** XL (13 points, ~2-3 weeks)
**Jira ref:** MO-22 in JIRA_EPIC.md

---

## Problem

mo-code's agent can chat, edit files, and manage git — but it cannot execute code on the phone. When the agent needs to run `npm install`, `python test.py`, or `go build`, there is no runtime. Without code execution, the agent is a fancy chat UI, not a real coding tool.

## Solution

Bundle a proot-based Alpine Linux environment inside the APK. proot provides a userspace Linux environment on unrooted Android. Alpine provides a full package manager (`apk`) with 30,000+ packages.

### How it works

```
mo-code APK
  └── assets/
        ├── proot (static ARM64 binary, ~1.5MB)
        └── alpine-minirootfs-aarch64.tar.gz (~5MB)

First launch → extract to app internal storage:
  /data/data/com.mocode.app/
    ├── proot
    ├── alpine/          (extracted rootfs)
    │   ├── bin/ usr/ etc/
    │   └── home/developer/
    └── projects/        (user code, bind-mounted into proot)

Shell execution:
  proot -0 -r /data/.../alpine \
    -b /dev -b /proc -b /sys \
    -b /data/.../projects:/home/developer \
    -w /home/developer \
    /bin/sh -c "npm install && npm test"
```

### Auto-detection

| File detected | Tools installed |
|---|---|
| `package.json` | `apk add nodejs npm` |
| `requirements.txt` / `pyproject.toml` | `apk add python3 py3-pip` |
| `go.mod` | `apk add go` |
| `Cargo.toml` | `apk add rust cargo` |
| `Gemfile` | `apk add ruby` |

First install: 10-30 seconds per tool. Cached after that.

### Performance budget

- RAM: ~150-250MB with Node.js active (3-4% of 6GB phone)
- CPU: ~5-15% overhead vs native (proot translates syscalls via ptrace)
- Storage: 5MB base + 200-500MB with tools installed
- Battery: comparable to a game session

---

## Implementation Stories

### Story 1: Bootstrap — bundle and extract proot + Alpine
**Points:** 3

- [ ] Bundle static `proot` ARM64 binary in APK assets
- [ ] Bundle Alpine Linux minirootfs (aarch64) in APK assets (~5MB compressed)
- [ ] First-launch extraction to app internal storage
- [ ] Progress UI: "Setting up development environment..." with progress bar
- [ ] SHA256 integrity verification on extracted rootfs
- [ ] Skip extraction if already present and checksum matches

**Files:** Flutter assets, `DaemonService.kt` or new `RuntimeBootstrap.kt`

### Story 2: proot integration in Go backend
**Points:** 3

- [ ] Go wrapper for proot execution in shell tool
- [ ] Bind-mount user project directory into proot at `/home/developer/project`
- [ ] DNS resolution inside proot (bind `/etc/resolv.conf`)
- [ ] Environment setup: PATH, HOME, LANG, TERM
- [ ] Capture stdout/stderr, stream to WebSocket
- [ ] Timeout + kill for long-running commands
- [ ] Working directory tracking across commands

**Files:** `backend/tools/shell.go`, new `backend/runtime/proot.go`

### Story 3: Package auto-detection and installation
**Points:** 2

- [ ] Detect project type from marker files (package.json, go.mod, etc.)
- [ ] Auto-install required tools via `apk add` on first detection
- [ ] Cache installed packages — don't reinstall across sessions
- [ ] WS message `runtime.setup` with install progress
- [ ] Agent can manually run `apk add <package>` when needed

**Files:** `backend/runtime/detect.go`, `backend/api/messages.go`

### Story 4: File and permission handling
**Points:** 2

- [ ] file.read/file.write work both inside and outside proot via bind mount
- [ ] proot `-0` flag provides fake root — handle file permissions correctly
- [ ] Environment variable passthrough (API keys, config) from mo-code into proot

**Files:** `backend/tools/file.go`, `backend/runtime/proot.go`

### Story 5: Storage management UI
**Points:** 1

- [ ] Settings UI: show Alpine environment size (base + installed packages)
- [ ] "Reset environment" button — wipe and re-extract rootfs
- [ ] Per-project cleanup — remove node_modules, __pycache__, build artifacts

**Files:** `flutter/lib/screens/config_screen.dart`

### Story 6: Testing
**Points:** 2

- [ ] Test: Node.js project — write, npm install, npm test inside proot
- [ ] Test: Python project — write, pip install, pytest inside proot
- [ ] Test: agent writes code → auto-detects → installs → runs tests → streams results
- [ ] Test: concurrent shell commands
- [ ] Performance benchmark: measure proot overhead on target device

**Files:** `backend/runtime/proot_test.go`, `backend/tools/e2e_test.go`

---

## Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Play Store rejection (executing downloaded code) | Medium | proot + rootfs bundled in APK, not downloaded. No dynamic code loading. Termux precedent exists on Play Store. |
| proot ptrace overhead on heavy builds | Low | Accept for scripting/tests. Offer remote execution as alternative for heavy builds (FEAT-003). |
| APK size increase (~7MB) | Low | Acceptable. Most apps are 50-200MB. |
| Alpine package availability | Low | Alpine has 30k+ packages. Edge/testing repos cover nearly everything. |
| SELinux/seccomp blocking ptrace | Medium | Test on major Android versions (12-15). proot has workarounds for most restrictions. Termux community maintains patches. |

## Acceptance Criteria

- [ ] Alpine environment bootstraps on first launch in under 30 seconds
- [ ] Agent can write a Node.js project and run `npm install && npm test` successfully
- [ ] Agent can write a Python project and run `pip install && pytest` successfully
- [ ] Auto-detection installs correct tools without user intervention
- [ ] Shell output streams in real-time to the Flutter UI
- [ ] Total base storage under 15MB (proot + rootfs before tools)
- [ ] RAM usage under 300MB with Node.js active
- [ ] No root required
- [ ] Works on Android 12+ (API 31+)

## Dependencies

- None — this is a new subsystem. Integrates with existing shell tool in `backend/tools/shell.go`.

## Future extensions

- Remote execution fallback (FEAT-003) — if proot is too slow, SSH to a Codespace/VPS
- iOS support — proot won't work on iOS (no ptrace). iOS must use remote-only execution.
- Custom rootfs — let power users bring their own distro image
