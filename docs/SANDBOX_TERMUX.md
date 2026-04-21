# Sandbox backend — termux-prefix (track A)

Native-speed shell environment on unrooted Android. Runs bionic-linked
binaries (busybox, bash, git, nodejs, python3, curl) directly against the
Android kernel via `os/exec`, with `PATH` and `LD_LIBRARY_PATH` pointing into
an app-private prefix directory. No `ptrace`, no VM, no syscall translation.

**Status:** track A of the sandbox redesign (see `docs/SANDBOX_TRACKS.md`).

## Registered name

`termux-prefix` — registered in `backend/sandbox/termux/backend.go`'s
`init()` by calling `sandbox.Register`.

## Capabilities

| Flag             | Value | Notes                                                    |
|------------------|-------|----------------------------------------------------------|
| `PackageManager` | true  | Delegates to `pkg`/`apt` inside the prefix when present. |
| `FullPOSIX`      | false | Bionic, not glibc. No NSS, no `getpwnam`, no sysv IPC.   |
| `Network`        | true  | Inherits the app's network permissions.                  |
| `RootLikeSudo`   | false | Same UID as the host app; no fakeroot layer.             |
| `SpeedFactor`    | 1.0   | Direct kernel entry — no emulation overhead.             |
| `IsolationTier`  | 1     | "Prefix" isolation: separate FS view, same kernel+UID.   |

## When to pick this backend

- You need compile/test/shell loops to feel native.
- The user has consented to running app-owned binaries directly on the
  kernel (same trust boundary as any third-party app).
- You do **not** need uid 0 semantics, full glibc, or kernel isolation. If
  you do, pick `qemu-tcg` or `avf-microdroid` instead.

## Architecture

```
mo-code (Android app, Go daemon)
    │
    │  sandbox.Open("termux-prefix", cfg)
    ▼
┌───────────────────────────────────────────┐
│ backend/sandbox/termux/Backend            │
│                                           │
│  Prepare ── extractTarball ──►  $prefix/  │
│           linkHome            ┌─────────┐ │
│           writeResolvConf     │ bin/    │ │
│                               │ lib/    │ │
│  Exec   ── os/exec CommandCtx │ etc/    │ │
│           env: PATH, LD_PATH  │ tmp/    │ │
│           cwd: home | project │ home -> │ │
│                               │  projs  │ │
│  Install── pkg/apt in-prefix  └─────────┘ │
└───────────────────────────────────────────┘
                      │
                      ▼
                 Android kernel
```

## Factory config

Keys read from `sandbox.Config.Options`:

| Key                | Required | Meaning                                                                 |
|--------------------|----------|-------------------------------------------------------------------------|
| `termux.prefix`    | yes      | Absolute path to the on-disk prefix (e.g. `$appFiles/termux-prefix`).   |
| `termux.tarball`   | first run| Absolute path to the bootstrap `.tar.gz`; unused once `.installed` set. |
| `termux.projects`  | no       | Host path linked as `$prefix/home` so shells `cd ~` into user code.     |
| `termux.version`   | no       | Opaque version string written to `.installed`; mismatches re-extract.   |

The Flutter side extracts the APK asset
`flutter/android/app/src/main/assets/termux-prefix/termux-prefix-arm64.tar.gz`
to the internal files directory and passes its path in via `termux.tarball`
on the first run.

## Prefix layout

Produced by `scripts/build-termux-prefix.sh`:

```
$prefix/
├── bin/            # busybox + symlinks, bash, git, node, python3, curl
├── lib/            # shared libraries (libcrypto, libssl, libnode, …)
├── libexec/        # helper executables (git-core/*, …)
├── etc/            # resolv.conf (written at Prepare), profile.d
├── share/          # terminfo, ca-certificates, python stdlib, …
├── home -> ../projects  # symlink to the host projects dir (if configured)
├── tmp/            # writable scratch, mode 1777
├── var/            # stateful data, package caches
├── usr -> .        # back-compat pointer for scripts hardcoded to $PREFIX/usr
└── .installed      # stamp: version=<tag>, extracted_at=<rfc3339>
```

## Runtime model

- **Prepare** is idempotent. First call extracts the tarball, writes
  `etc/resolv.conf`, and links `home → projects`. Later calls short-circuit
  when `.installed` matches the configured `termux.version`.
- **Exec** runs `$prefix/bin/sh -c "<command>"` via `os/exec.CommandContext`.
  `PATH` is `$prefix/bin:$prefix/usr/bin:/system/bin:/system/xbin` —
  prefix-first so bundled tools shadow Android stubs. `LD_LIBRARY_PATH` is
  `$prefix/lib:$prefix/usr/lib`. The caller's `PATH`/`LD_LIBRARY_PATH` are
  deliberately dropped to avoid leaking Android system paths.
- **InstallPackage** delegates to `pkg install -y` (or `apt install -y`) if
  either is present in the prefix. In prebaked-only mode (no package
  manager) it verifies the requested binaries are reachable through `PATH`
  and returns `sandbox.ErrNoPackageManager` for anything missing.
- **IsReady** is the standard `echo ok` probe with a 3s context.
- **Diagnose** reports the per-check grid consumed by `/api/runtime/diagnose`:
  `prefix_exists`, `shell_exec`, `bin_exists`, `lib_exists`, `stamp_present`,
  `echo_ok`.
- **Teardown** is a no-op. The prefix survives across app restarts so
  subsequent `Prepare()` calls are cheap. Users who want a clean slate
  should clear storage through Android settings.

## Security notes

- **Zip-slip guard:** `extractTarball` refuses any entry whose path resolves
  outside `$prefix`. Critical because the tarball rides in the APK and is
  eligible to be repackaged by anyone with signing keys.
- **Symlinks inside the tarball are allowed** but only within the extracted
  tree. Absolute-target symlinks in the bootstrap are kept as-is since they
  typically point to `../lib/<soname>` and similar — the Termux build
  process emits only such relative links.
- **No network pinning.** DNS servers come from `MOCODE_DNS` (env,
  comma-separated) or default to `8.8.8.8, 8.8.4.4`. The app still relies
  on Android's system-level DNS policy; the resolv.conf is only consulted
  by bundled tools that do their own resolution.
- **Caller environment leak:** `Exec()` sets a fixed env slice instead of
  appending to `os.Environ()`. Any future refactor that re-introduces
  inheritance needs to re-assess `DYLD_*`, `LD_PRELOAD`, and `GIT_*`
  variables the daemon process might carry.

## Known limits

- Not glibc. Software that hardcodes `/lib64/ld-linux-x86-64.so.2`,
  assumes `nss_files`, or otherwise depends on glibc-specific symbols will
  not run. Pick `qemu-tcg` for those workloads.
- Binaries in the Termux bootstrap are built with their DT_INTERP pointing
  at `/data/data/com.termux/files/usr/lib/ld-android.so`. On stock Termux
  installs that path exists; in mo-code's app-private prefix it does not.
  The repack step in `scripts/build-termux-prefix.sh` adds a `usr → .`
  symlink back-reference, and the shell entry point (`$prefix/bin/sh`) is
  invoked directly so the Android dynamic linker resolves its own
  interpreter rather than consulting DT_INTERP. For tools that reject that
  setup, run them under `$prefix/lib/ld-android.so` explicitly or ship a
  `patchelf`-ed copy.
- `FullPOSIX=false` flows into tool selection upstream. Check
  `sb.Capabilities().FullPOSIX` before attempting anything that fork-execs
  glibc-only utilities; fall back to the proot or QEMU backend when needed.

## Testing

- Unit tests (`backend/sandbox/termux/termux_test.go`) exercise the full
  interface against a fixture prefix that swaps in the host `/bin/sh` for
  the bundled shell. Run with:

  ```sh
  cd backend && go test ./sandbox/termux/...
  ```

- Android acceptance (track contract): once the APK ships the bootstrap
  tarball, `sandbox.Open(... backend="termux-prefix")` followed by
  `InstallPackage([]string{"nodejs"})` must leave `node -v` exiting 0.
  This is the lead's integration step — the Go side has no way to exercise
  the bundled arm64 binaries on an x86 Linux CI host.

## Build

```sh
./scripts/build-termux-prefix.sh \
    --pkgs "busybox bash coreutils git nodejs python curl ca-certificates"
```

The script produces
`flutter/android/app/src/main/assets/termux-prefix/termux-prefix-arm64.tar.gz`
(plus sidecar `.sha256` and `.version`). Keep the tarball under 50 MB —
the lead reviews larger artifacts before they land in the repo.
