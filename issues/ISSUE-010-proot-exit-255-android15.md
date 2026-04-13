# ISSUE-010: proot shell commands fail with exit code 255 on Android 15

**Status:** Open  
**Component:** `backend/runtime/proot.go`, `flutter/android/app/src/main/jniLibs/`  
**Device:** OnePlus CPH2467 (OP5958L1), Android 15 (API 35), ColorOS  
**Tracker:** om-ashish-soni/mo-code#4  

---

## Symptom

All shell commands routed through proot fail with **exit code 255** and empty stderr.
This blocks `git clone`, `apk update`, and every other shell-based tool the in-app agent uses.

```
[proot] exec: libproot.so -0 -r <rootfs> ... /bin/sh -c git clone ...
[proot] FAILED exit=255 err=<nil> cmd="git clone ..."
```

Previously (before adding the loader): stderr contained
`proot error: execve("/bin/sh"): Permission denied`

After adding the loader: stderr is **empty**, exit is **255**.

---

## Background

### Android SELinux execution model

| Location | SELinux context | execve | mmap(PROT_EXEC) |
|---|---|---|---|
| `nativeLibraryDir` (`lib/arm64/`) | `apk_data_file` | ✅ (`entrypoint` granted) | ✅ |
| `filesDir` | `app_data_file` | ❌ (`entrypoint` denied) | ✅ (in theory) |

Alpine rootfs is extracted to `filesDir/runtime/rootfs/`. Its binaries (`/bin/sh`, etc.)
cannot be `execve`'d directly. proot's **loader mechanism** is supposed to work around this:
instead of `execve(rootfs/bin/sh)`, proot `execve`s the loader (from `nativeLibraryDir`),
which opens `rootfs/bin/sh` and `mmap`s it into memory.

### What is in place

| Artifact | Path | Notes |
|---|---|---|
| `libproot.so` | `nativeLibraryDir` | proot-me v5.3.0, ARM64 static (1.5 MB) |
| `libproot-loader.so` | `nativeLibraryDir` | Compiled from proot-me v5.3.0 source, ARM64 static (2.2 KB), non-PIE |
| Alpine rootfs | `filesDir/runtime/rootfs/` | Extracted on first launch |
| `PROOT_LOADER` env | Set by `DaemonService.kt` | Points to `libproot-loader.so` |
| `PROOT_NO_SECCOMP=1` | Set in `proot.go` | Forces ptrace mode (seccomp blocked on Android) |

Confirmed working via logs:
```
[proot] env: loader=/data/app/.../lib/arm64/libproot-loader.so nativeLibDir=...
[proot] exec: /data/app/.../lib/arm64/libproot.so -0 -r <rootfs> ... /bin/sh -c apk update
[proot] FAILED exit=255 err=<nil>
```

---

## Root Cause Analysis

### Why exit 255?

proot's event loop (`src/tracee/event.c`) initialises `last_exit_status = -1`.
It is only updated when the tracee exits cleanly (`WIFEXITED`).
When the tracee is killed by a signal (`WIFSIGNALED`), `last_exit_status` stays `-1` → exit(255).

**Conclusion: the loader (or its child) is dying from a signal, not a clean exit.**

### Why is the loader crashing?

Three candidate causes, in order of likelihood:

#### 1. `ptrace(PTRACE_SETREGSET)` silently fails on Android 15 → NULL cursor → SIGSEGV

proot's loader mechanism works like this:
1. proot intercepts the child's `execve(/bin/sh)` via ptrace.
2. proot replaces the target with the loader (`execve(loader, ...)`).
3. After the loader's exec completes (PTRACE_EVENT_EXEC fires), proot writes the load-script
   address into `x0` (USERARG_1) via `ptrace(PTRACE_SETREGSET, ...)`.
4. The loader's `_start(void *cursor)` uses `cursor` (= `x0`) to walk the load script.

If Android 15's `untrusted_app` domain blocks `PTRACE_SETREGSET` (or it fails silently),
`x0 = 0` at loader entry → `_start` dereferences NULL → **SIGSEGV** → exit 255.

This is the most likely cause: no SELinux denial is logged for it because the restriction
may be in the seccomp filter or a kernel policy, not an AVC audit rule.

#### 2. `mmap(PROT_EXEC)` on `app_data_file` blocked (Android W^X)

Android 15 enforces W^X: pages cannot be both writable and executable.
The loader calls `mmap(addr, size, PROT_READ|PROT_EXEC, MAP_FIXED|MAP_PRIVATE, fd, offset)`
on rootfs binaries in `filesDir`. If the kernel blocks PROT_EXEC on `app_data_file` files,
`mmap` returns `MAP_FAILED` → loader calls `FATAL()` → `exit(182)`.

**Inconsistent with evidence**: FATAL() exits with code 182, not 255. Rules this out as primary.

#### 3. ptrace-based syscall interception blocked entirely

If `PTRACE_SETOPTIONS` with `PTRACE_O_TRACESYSGOOD` etc. fails, proot cannot intercept
syscalls at all. proot would then exit(EXIT_FAILURE) = exit(1), **not** 255. Rules this out.

---

## What was tried and ruled out

| Attempt | Outcome |
|---|---|
| Termux proot loader (18 KB) | ABI mismatch — v5.1.107 loader incompatible with proot-me v5.3.0 |
| `LD_LIBRARY_PATH` for `libtalloc.so` | Android 7+ ignores it for untrusted app children |
| Termux proot binary (dynamically linked) | `libtalloc.so` not found at runtime |
| `PROOT_NO_SECCOMP=1` alone | Not sufficient — underlying exec still fails |
| Compiled loader with `-fPIE -lc` | Wrong flags; "loader not found or doesn't work" |
| Correct loader (`-fno-PIE -nostdlib`, proot-me v5.3.0 source) | Exit 255, empty stderr |

---

## Proposed Fix Options

### Option A — memfd_create in the loader (recommended)

Modify `loader/loader.c` so that for each `LOAD_ACTION_MMAP_FILE` statement it:
1. Opens the target file (`app_data_file`)
2. Creates an anonymous in-memory file with `memfd_create("proot-elf", MFD_CLOEXEC)`
3. Copies the relevant range into the memfd
4. mmaps the memfd with `PROT_EXEC`

`memfd` files have no SELinux label, so W^X cannot block the mmap.
This also sidesteps any `PTRACE_SETREGSET` register-poking timing issue.

**Effort:** Medium — requires modifying loader C source and recompiling with NDK.

### Option B — Direct ptrace capability probe

Add a small test binary that:
- forks a child
- child: `PTRACE_TRACEME` + `SIGSTOP`
- parent: waits, then calls `ptrace(PTRACE_SETREGSET, child_pid, ...)`

Run from within the app (same SELinux context) to confirm whether register-poking works.
This narrows cause before committing to a fix.

**Effort:** Low — diagnostic only.

### Option C — Static musl busybox in rootfs

Replace Alpine's dynamically-linked `/bin/sh` and `/sbin/apk` with fully-static musl
binaries (no interpreter chain). The loader would only need to mmap one segment;
no `OPEN_NEXT` for the dynamic linker. Reduces the surface area of the failure.

**Effort:** Medium — need static busybox + static apk or busybox-based apk wrapper.

### Option D — Evaluate Termux / UserLAnd approach for Android 15

Termux and UserLAnd both run on Android 15. Research how they handle exec restrictions
(they may use a different proot fork or a different isolation technique entirely).

---

## Files to Change (for Option A)

- `/tmp/proot-src/src/loader/loader.c` — add memfd copy step
- `/tmp/proot-src/src/loader/memset.c` — already exists (custom memset stub)
- Recompile: `aarch64-linux-android24-clang -target aarch64-linux-android24 -static -fno-PIE -nostdlib ... -o libproot-loader-v4-arm64`
- Place at: `flutter/android/app/src/main/jniLibs/arm64-v8a/libproot-loader.so`
- Rebuild APK and redeploy

---

## Related

- GitHub issue: om-ashish-soni/mo-code#4
- `backend/runtime/proot.go` — `ProotRuntime.prootEnv()`, `ProotRuntime.Exec()`
- `flutter/android/app/src/main/kotlin/.../DaemonService.kt` — `startDaemonProcess()`
