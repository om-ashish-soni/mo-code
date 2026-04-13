# FEAT-002: proot + Alpine Linux On-Device Runtime

**Status:** COMPLETE — implemented 2026-04-13 by C1 (Backend Go) and C2 (Flutter + Android)
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

### Story 1: Bootstrap — bundle and extract proot + Alpine — COMPLETE
**Points:** 3

- [x] Bundle static `proot` ARM64 binary in APK assets (v5.3.0, 1.5MB)
- [x] Bundle Alpine Linux minirootfs (aarch64) in APK assets (v3.21.3, 3.7MB)
- [x] First-launch extraction to app internal storage (RuntimeBootstrap.kt)
- [x] Progress UI: bootstrap progress polling with percentage in agent_screen.dart
- [x] SHA256 integrity verification on extracted proot binary
- [x] Skip extraction if already present and version matches (RUNTIME_VERSION marker)

**Files:** `scripts/download-runtime.sh`, `RuntimeBootstrap.kt`, `DaemonService.kt`, `agent_screen.dart`

### Story 2: proot integration in Go backend — COMPLETE
**Points:** 3

- [x] Go wrapper for proot execution in shell tool (`runtime/proot.go`)
- [x] Bind-mount user project directory into proot at `/home/developer`
- [x] DNS resolution inside proot (bind `/etc/resolv.conf`)
- [x] Environment setup: PATH, HOME, LANG, TERM
- [x] Capture stdout/stderr, stream to WebSocket
- [x] Timeout + kill for long-running commands
- [x] Working directory tracking across commands

**Files:** `backend/runtime/proot.go`, `backend/tools/shell.go`

### Story 3: Package auto-detection and installation — COMPLETE
**Points:** 2

- [x] Detect project type from 12 marker file rules (`runtime/detect.go`)
- [x] Auto-install required tools via `apk add` on first detection
- [x] Cache installed packages — dedup via AllPackages()
- [x] WS message `runtime.setup` with install progress (`api/messages.go`)
- [x] Agent can manually run `apk add <package>` when needed

**Files:** `backend/runtime/detect.go`, `backend/api/messages.go`

### Story 4: File and permission handling — COMPLETE
**Points:** 2

- [x] file.read/file.write work both inside and outside proot via bind mount
- [x] proot `-0` flag provides fake root — handle file permissions correctly
- [x] Environment variable passthrough (MOCODE_PROOT_BIN/ROOTFS/PROJECTS) from mo-code into proot

**Files:** `backend/tools/shell.go`, `backend/runtime/proot.go`, `backend/cmd/mocode/main.go`

### Story 5: Storage management UI — COMPLETE
**Points:** 1

- [x] Settings UI: show Alpine environment size, proot status, type in config_screen.dart
- [x] "Reset environment" button — wipe and re-extract rootfs with confirmation dialog
- [ ] Per-project cleanup — deferred to future UI polish

**Files:** `flutter/lib/screens/config_screen.dart`

### Story 6: Testing — COMPLETE
**Points:** 2

- [x] proot_test.go — ProotRuntime unit tests (Exec, IsReady, paths, RootFSSize)
- [x] detect_test.go — 12 marker rule tests, AllPackages dedup
- [x] e2e_test.go — tool integration tests
- [ ] Performance benchmark on physical device — deferred to future testing phase

**Files:** `backend/runtime/proot_test.go`, `backend/runtime/detect_test.go`

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

- [x] Alpine environment bootstraps on first launch in under 30 seconds
- [x] Agent can write a Node.js project and run `npm install && npm test` successfully
- [x] Agent can write a Python project and run `pip install && pytest` successfully
- [x] Auto-detection installs correct tools without user intervention (12 marker rules)
- [x] Shell output streams in real-time to the Flutter UI
- [x] Total base storage under 15MB (proot 1.5MB + rootfs 3.7MB = ~5.2MB base)
- [ ] RAM usage under 300MB with Node.js active — not yet benchmarked on device
- [x] No root required (proot userspace via ptrace)
- [x] Works on Android 12+ (API 31+, compileSdk 36)

## Dependencies

- None — this is a new subsystem. Integrates with existing shell tool in `backend/tools/shell.go`.

## Future extensions

- Remote execution fallback (FEAT-003) — if proot is too slow, SSH to a Codespace/VPS
- iOS support — proot won't work on iOS (no ptrace). iOS must use remote-only execution.
- Custom rootfs — let power users bring their own distro image
