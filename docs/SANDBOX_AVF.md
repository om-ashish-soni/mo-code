# Sandbox backend D — AVF / Microdroid

`avf-microdroid` runs guest commands inside an Android Virtualization Framework
(AVF) Microdroid VM. On Pixel 7+ with pKVM the VM is a true tier-3 isolation
boundary; on devices without pKVM (OnePlus, most non-Pixel hardware) the
backend reports unavailable and the registry falls through to `qemu-tcg` or
`proot-hardened`.

This PR ships **the capability probe and a registered Backend scaffold**.
Microdroid VM boot itself (virtmgr packaging, virtio-serial wiring) is the
follow-up PR — `Prepare`/`Exec`/`InstallPackage` currently return a
`TODO` error and `IsReady` reports false.

## Capabilities (when available)

| Field            | Value |
|------------------|-------|
| `PackageManager` | true  |
| `FullPOSIX`      | true  |
| `Network`        | true  |
| `RootLikeSudo`   | true  |
| `SpeedFactor`    | 1.2   |
| `IsolationTier`  | 3     |

## Probe bridge — Kotlin → Go

The "JNI bridge" the task brief mentions is, in practice, a tiny JSON file the
Android side writes once at app startup; the Go daemon reads it during
`Factory()`. There is no live JNI call — the Go daemon is a child process of
`DaemonService`, not a JNI'd library — so the contract is: write the result
where the daemon will look for it, and pass the path via env var.

### Kotlin side — `AvfProbe.kt`

```kotlin
val (result, file) = AvfProbe.probeAndPersist(context)
// file = ${context.filesDir}/avf_probe.json
// {"available":bool,"reason":string,"api_level":int,"device":string}
```

`probe(context)` itself is pure — call it from any thread. `probeAndPersist`
adds the file write and a single `Log.i` line; persistence failures are
logged, not thrown, so an unsupported device degrades to "no signal" rather
than a crash.

The probe rejects, in order:
1. `Build.VERSION.SDK_INT < 34` (Android 14 / `UPSIDE_DOWN_CAKE`).
2. `PackageManager.hasSystemFeature("android.software.virtualization_framework")` false.
3. `Class.forName("android.system.virtualmachine.VirtualMachineManager")` throws,
   or `getSystemService(VirtualMachineManager.class)` returns null.

`VirtualMachineManager` is reached via reflection so that a missing class on
older builds never throws at link time.

### Go side — `backend/sandbox/avf`

`Factory(ctx, cfg)` resolves the result in priority order:

1. `cfg.Options["avf.available"]` — explicit override (tests, forced configs).
   Use `cfg.Options["avf.reason"]` to label why it was forced.
2. `cfg.Options["avf.probe_file"]` — path to the JSON written by Kotlin.
3. `MOCODE_AVF_PROBE_FILE` env var — same JSON, same shape.

When none of those is set the probe reports unavailable (not an error). The
Factory then returns `sandbox.ErrBackendUnavailable` and the registry walks
to the next backend in the chain.

| Probe outcome | Factory returns                              | Registry behaviour |
|---------------|----------------------------------------------|--------------------|
| Available     | `*Backend, nil`                              | uses this backend  |
| Unavailable   | `nil, ErrBackendUnavailable` (wrapped)       | tries next backend |
| Probe error   | `nil, fmt.Errorf("avf: probe failed: %w", e)`| surfaces the error |

## Wiring this in (follow-up by integrator)

The `DaemonService` change needed to turn this on:

```kotlin
// in DaemonService.startDaemonProcess(), alongside the other env vars
val (_, probeFile) = AvfProbe.probeAndPersist(this)
env["MOCODE_AVF_PROBE_FILE"] = probeFile.absolutePath
```

`DaemonService.kt` is **not** owned by this track, so the change is left for
the lead session to pick up. Until it lands, the daemon sees no probe signal
and the AVF backend reports unavailable on every device — which is the safe
default.

## Acceptance check

- `go build ./sandbox/avf/...` — clean.
- `go test ./sandbox/avf/...` — 10 tests, both probe paths plus error paths.
- OnePlus CPH2467 dry run: with no `MOCODE_AVF_PROBE_FILE` set, the Factory
  returns `ErrBackendUnavailable("no AVF probe result available …")`. The
  registry walks to `qemu-tcg` → `proot-hardened` without log noise.

> Master `go build ./...` is currently broken in `backend/sandbox/proot/`
> (pre-existing, commit `908f3e3`: `b.rt.Diagnose` undefined). Out of scope
> for this track — flagged for the integrator.

## What ships next

- Bundle a Microdroid CDI / minimal guest rootfs as APK assets.
- `Prepare`: hand the VM config to `VirtualMachineManager.create()` from the
  Android side via a second method-channel call, then `start()` and wait for
  the virtio-serial endpoint.
- `Exec`: write command, read framed `{stdout, stderr, exit}` over virtio-serial.
- `InstallPackage`: `apt` inside the guest.
- `Diagnose`: extend `checks` map with `vm_booted`, `serial_open`, `agent_alive`.
