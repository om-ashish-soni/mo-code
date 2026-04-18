# FEAT-006 — QEMU-TCG Sandbox on Unrooted Android

> **Status:** Beta (2026-04-18) · `!echo ok` verified end-to-end on OnePlus CPH2467 / Android 15 (stock, no root, no Shizuku, no ADB).
> **Tier:** Track B — true isolation escape hatch when proot's SELinux walls block real tooling.
> **Tradeoff:** Correctness is won. Speed is the next problem (first call ~2 min cold boot).

---

## 1. Why we did this

mo-code's default runtime is **proot + Alpine aarch64** (Tier 1). It works for shell builtins and busybox applets but fails on anything that does a secondary `execve` — Python, Node, npm, pip, gcc — because Android 15's `untrusted_app` SELinux domain denies `mmap(PROT_EXEC)` on files labelled `app_data_file` (everything under `filesDir`). Root cause analysis is in `FEAT-004-proot-android15-memfd-fix.md`.

We needed **one escape hatch that doesn't care about SELinux at all**. That is a full system emulator: the guest kernel runs Python on its own virtual CPU; the host kernel only ever sees QEMU doing userspace math and I/O on a TCG JIT. The `untrusted_app` domain never gets asked about guest syscalls because there are no guest syscalls on the host.

Product promise preserved: AI-generated code runs with CPU + RAM + (future) internet, nothing else. No host `/proc`, no host filesystem outside the mount we give it, no other apps.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter agent_screen.dart                                   │
│   user types "!echo ok"                                     │
│   → direct_tool_call WS msg (shell_exec, bypass=true)       │
└───────────────┬─────────────────────────────────────────────┘
                │ ws://127.0.0.1:19280/ws
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Go daemon (libmocode.so inside DaemonService)               │
│   api/server.go → go c.dispatch(raw)                        │
│   tools.shell_exec → runtime.QemuRuntime.Exec(ctx, cmd)     │
│   spawns: qemu-exec-py.sh "$cmd"                            │
└───────────────┬─────────────────────────────────────────────┘
                │ exec, env = MOCODE_QEMU_BIN + ..._LD_LIBRARY_PATH
                ▼
┌─────────────────────────────────────────────────────────────┐
│ qemu-exec-py.sh (POSIX shell, runs as app UID)              │
│   boots: qemu-system-aarch64 -machine virt -cpu max -m 256  │
│     -kernel vmlinuz-virt  -initrd initramfs-rootfs-py.cpio  │
│     -serial stdio -net none                                 │
│   drip-feeds guest script via named fifo, 0.15s/line        │
│   waits for "/ #" Alpine prompt on serial                   │
│   awk-parses output between __MO_QEMU_START__/_END_RC=N     │
└───────────────┬─────────────────────────────────────────────┘
                │ TCG JIT (no KVM — Android blocks /dev/kvm)
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Guest: Alpine aarch64 initramfs                             │
│   busybox init → /bin/sh → ( $CMD ) 2>&1 → poweroff -f      │
│   /usr/bin/python3 baked in                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. The four problems we had to solve

### 3.1 Android SELinux W^X blocks exec on `filesDir`

**Symptom:** `qemu-system-aarch64: Permission denied`, despite chmod 755.

**Root cause:** Android's `untrusted_app` SELinux domain denies `mmap(PROT_EXEC)` on files labelled `app_data_file` (that's everything an app writes to `getFilesDir()` / `getExternalFilesDir()`). It **allows** exec on files labelled `apk_data_file` — which is what Android extracts `jniLibs/<abi>/*.so` to at install time, into `applicationInfo.nativeLibraryDir`.

**Fix:** relocate the qemu binary + all 311 of its `.so` deps into `flutter/android/app/src/main/jniLibs/arm64-v8a/`.

Two mechanical wrinkles from AGP's native-lib packaging:
1. **Binary rename** — AGP's `**/*.so` filter only includes files whose name ends in `.so`. So `qemu-system-aarch64` is renamed **`libqemu-system-aarch64.so`** in the APK. It's still a PIE ELF executable; the extension is cosmetic.
2. **Versioned lib renames** — `.so.N.M.K` files don't match the filter either. Every versioned lib gets `.so` appended: `libbz2.so.1.0.8` → `libbz2.so.1.0.8.so`. But the runtime linker will ask for the **original** `libbz2.so.1` from `DT_NEEDED`. Solution: shim dir.

### 3.2 Shim directory for pretty sonames

**What:** at daemon startup, `DaemonService.kt` creates `filesDir/qemu-lib-shim/` and populates it with symlinks — one per versioned lib — that map the renamed filename back to the name the linker actually wants.

```kotlin
nativeLibDir.listFiles()?.forEach { f ->
  val base = f.name                                     // libbz2.so.1.0.8.so
  val linkName = if (base.matches(Regex(".*\\.so\\.[0-9].*\\.so$"))) {
    base.removeSuffix(".so")                            // libbz2.so.1.0.8
  } else { base }                                       // libfoo.so
  Files.createSymbolicLink(File(shim, linkName).toPath(), f.toPath())
}
```

SELinux checks the **target inode's** label, not the symlink's path, so exec through the link still resolves to `apk_data_file` and passes.

The daemon then exports:
```
MOCODE_QEMU_BIN=<nativeLibraryDir>/libqemu-system-aarch64.so
MOCODE_QEMU_LD_LIBRARY_PATH=<shimDir>:<nativeLibraryDir>:/system/lib64
```

Verified on device: `links=321` printed at startup, `./qemu-exec-py.sh "echo SMOKE_OK"` returns rc=0 with `SMOKE_OK` in output.

### 3.3 UART byte-drop on drip-feed

**Symptom:** guest shell received `echo` when we sent `echo ok` — the `ok ` was silently lost mid-FIFO.

**Root cause:** QEMU's emulated pl011 UART on `-machine virt` has a **16-byte FIFO and no flow control**. Bursting a multi-line script into the fifo outruns the guest reader.

**Fix:** `qemu-exec-py.sh` writes the guest script one line at a time with a `QEMU_LINE_PAUSE=0.15` sleep between lines. Empirically eliminates drop on Snapdragon 8 Gen 3.

### 3.4 WebSocket read-loop stall

**Symptom:** server wrote `direct_tool_result` after ~45s and got `broken pipe`. Client showed "Running shell (bypass)..." forever.

**Root cause:** `c.dispatch(raw)` was synchronous on the WS read loop. During the 30-90s QEMU boot, the reader wasn't consuming pong frames → gorilla/websocket's ping deadline expired → server thought the client was dead → hung up just before writing the result.

**Fix (one line):** `go c.dispatch(raw)` in `backend/api/server.go:326`. Concurrent writes are already guarded by `c.writeMu`.

**Companion fix:** Flutter `agent_screen.dart` now has a 90s client-side timeout for bypass calls — if the result never arrives, the UI renders `[shell bypass · TIMED OUT after 90s · client-side]` instead of hanging forever. And `_handleDirectToolResult` always prints runtime label + exit code + stderr inline on the chat. No more silent `exit=1`.

---

## 4. Guest runtime: what's in the VM

- **Kernel:** Alpine `vmlinuz-virt` aarch64, stock. No custom patches.
- **Initramfs:** `initramfs-rootfs-py.cpio.gz` ~40 MB — busybox + musl + CPython 3.12 baked in. Built with `scripts/build-initramfs.sh`.
- **Boot args:** `console=ttyAMA0 quiet rdinit=/init TERM=dumb`
- **No networking yet:** `-net none`. `apk add` is offline-only against whatever's in the initramfs.
- **No host FS yet:** guest cannot see `ProjectsDir`. Next big piece is a **virtio-9p** mount of `ProjectsDir` into `/home/developer` so `python3 factorial.py` can actually find the file.

---

## 5. RPC: marker-framed serial

No virtio-vsock on Alpine-virt boot without extra modules. We do the dumb thing: frame output on the serial log.

Guest script (built per-call by `qemu-exec-py.sh`):
```sh
stty -echo -icanon -onlcr 2>/dev/null
printf '\n%s\n' __MO_QEMU_START__
( $CMD ) 2>&1
printf '\n%s%d\n' __MO_QEMU_END_RC= $?
poweroff -f
```

Host side: wait for `/ #` prompt, push script into fifo, wait for qemu to exit, `awk` out everything between the two markers and extract `$?` as script exit code. Non-zero awk exit = markers missing → dump last 1 KB of serial log to stderr so the chat screen shows what actually happened.

---

## 6. What works today

| Case | Result |
|---|---|
| `!echo ok` | ✅ `[shell bypass · runtime=qemu-tcg · exit=0]` + `ok` |
| `!uname -a` | ✅ Linux localhost 6.x-alpine aarch64 |
| `!/usr/bin/python3 -c "print(2+2)"` | ✅ `4` |
| `!false` → exit=1 | ✅ exit code surfaced on chat, not silent |
| WS stays alive across full call | ✅ goroutine dispatch + 90s client timeout |

Boot + run + teardown: **~2 min per call** on OnePlus CPH2467. Not a bug — a fresh VM per command. See next section.

---

## 7. Known blockers

1. **Startup time dominates.** Cold-boot-per-call is unusable. Next work: **persistent VM daemon** — one `qemu-system-aarch64` process stays alive for the app's lifetime; commands dispatched over the existing marker protocol. First call ~2 min, every call after ~200 ms-1 s. Pure engineering, no new isolation risk.
2. **No filesystem bridge.** Guest can't see user files. virtio-9p mount of `ProjectsDir` → `/home/developer`. Guest-side: `/etc/fstab` entry + `mount -t 9p`. Host-side: `-fsdev local,path=$PROJECTS,security_model=none,id=proj -device virtio-9p-pci,fsdev=proj,mount_tag=proj`.
3. **No networking.** `-net none` today. Switch to `-netdev user` (slirp built into qemu) + route DNS + `apk add` toolchains.
4. **`/api/runtime/diagnose` is misleading.** Reports `qemu: startup check OK` without testing 9p or slirp. Must verify both before claiming OK on the Config screen.
5. **TCG perf on mobile.** TCG JIT is ~8-12× slower than KVM. Once the VM is persistent, this shows up as individual commands being 200ms-1s instead of 20ms, which is fine. `npm install` at scale is a separate conversation.

---

## 8. Files touched

Backend:
- `backend/runtime/qemu.go` — runtime wrapper; reads `MOCODE_QEMU_BIN` / `MOCODE_QEMU_LD_LIBRARY_PATH`, falls back to bundle layout for adb-standalone testing.
- `backend/runtime/qemu-exec-py.sh` — boot + drip-feed + marker-parse.
- `backend/sandbox/qemu/` — `Sandbox` interface impl, so the upcoming Shizuku/AVF tiers plug in the same way.
- `backend/api/server.go` — `go c.dispatch(raw)` unblock.

Android:
- `flutter/android/app/src/main/jniLibs/arm64-v8a/` — 317 files: binary (renamed `libqemu-system-aarch64.so`) + 311 `.so` deps (62 of them with appended `.so` for versioned names).
- `flutter/android/app/src/main/kotlin/.../DaemonService.kt` — shim-dir builder, env propagation.

Flutter:
- `flutter/lib/screens/agent_screen.dart` — 90s client-side timeout, always-render runtime/exit/stderr, no silent failures.

APK size: +150 MB (acceptable — QEMU's full dep set is expensive, but this lives in jniLibs and doesn't affect on-disk app data).

---

## 9. One-sentence summary

**Track B proved you can run arbitrary guest code inside a full aarch64 Linux VM on a stock unrooted Android 15 phone under the `untrusted_app` SELinux domain — by relocating the QEMU binary to `nativeLibraryDir` (the only exec-eligible label in the app sandbox) and shimming versioned sonames with symlinks — with no root, no Shizuku, no ADB shell.**

Speed is next. Correctness is won.
