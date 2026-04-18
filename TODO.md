# Mo-Code TODO

## Redesign Round 1 — COMPLETE
- [x] E6: Structured tool results (Title, Metadata, Output) — C1
- [x] E9: Session persistence (session_store.go) — C2
- [x] E14: Subagent/Task tool (subagent.go, task.go) — C3
- [x] E15: WebFetch tool (webfetch.go) — C3
- [x] E12: Flutter diff viewer widget — C4
- [x] E13: Flutter TODO panel widget — C4

## Redesign Round 2 — COMPLETE
- [x] E17: Plan mode — read-only agent (C1)
- [x] E22: Permission system — granular tool/path control (C1)
- [x] E19: More providers — OpenRouter, Ollama, Azure (C2)
- [x] E20: Session history UI with resume (C3)
- [x] E21: Fuzzy file search in Flutter (C3)
- [x] H1: Summary compression budget (C4)
- [x] H3: Git context in system prompt (C4)
- [x] H4: Continuation preamble after compaction (C4)

## Redesign Round 3 — COMPLETE
- [x] Android foreground service (Kotlin native) (C1)
- [x] End-to-end integration testing — tools/e2e_test.go (20+ tests), agent/e2e_test.go (6 tests), cancel bug fix (C2)
- [x] Flutter polish (error states, loading, empty states, edge cases) (C3)
- [x] Release pipeline — all scripts fixed, release.sh created, v1.1.0+2, SDK 35, store listing updated (C4)

## Redesign Round 4 — PARTIAL (C3 done)
- [ ] Bug fixes from R3 testing
- [ ] Performance + resilience (token optimization, reconnection)
- [x] Docs + scripts + final QA — API_PROTOCOL.md rewritten, cmd tests added, /health alias, all issues resolved (C3)

## Round 5 — Beta testing (1 session)
- [ ] Full device test, bug fix, stamp for Play Store

## Play Store — Blocked on Om
- [x] Android scaffold, icon, signing, listing, privacy policy
- [x] Release script ready (`./scripts/release.sh`) with pre-flight checks
- [x] Version 1.2.0+3, compileSdk/targetSdk 35
- [x] Store listing updated with R1/R2 features
- [ ] Generate release keystore (Om — `keytool -genkey -v -keystore mocode-release.keystore -alias mocode -keyalg RSA -keysize 2048 -validity 10000`)
- [ ] Create `flutter/android/key.properties` from `key.properties.example`
- [ ] Build release AAB (Om — `./scripts/release.sh`)
- [ ] Play Console upload + internal testing

## FEAT-004 — Android 15 proot fix (v1.2.0)
- [x] Root cause: SELinux W^X blocks mmap(PROT_EXEC) on app_data_file (ISSUE-010)
- [x] Fix: memfd_create loader — loader.c patched, libproot-loader.so compiled (2.8KB)
- [x] Diagnostics: Diagnose() in Go, /api/runtime/diagnose endpoint, degraded banner in Flutter
- [x] Subagents receive proot runtime
- [x] Docs: ISSUE-010 and FEAT-004 written
- [ ] **Device test on Android 15 hardware** — run verify-loader.sh on OnePlus CPH2467
- [ ] Commit all changes + tag v1.2.0

## Sandbox Isolation Roadmap (3-tier)

### v1.3 — Hardened proot (LANDED 2026-04-18)
- [x] Strip host `/dev` and `/sys` binds in `runtime/proot.go`
- [x] Allowlist safe `/dev/*` char devices (null/zero/full/random/urandom/tty)
- [x] `IsolationTier()` returns `"proot-hardened"`; surfaced in `/api/runtime/diagnose`
- [x] Flutter Config screen shows tier badge with "Why?" explanation dialog
- [x] Policy regression test (`TestProotArgsIsolationPolicy`) blocks future re-binds of `/sys` or wholesale `/dev`
- [ ] Add libseccomp deny-list inside the proot child (ptrace, process_vm_*, kexec_*, bpf, init_module, mount, pivot_root, keyctl) — deferred to v1.3.1
- [ ] Materialize fake `/proc/cpuinfo /meminfo` files in rootfs as next /proc-leak mitigation step

### v1.4 — Shizuku + bubblewrap tier (SCOPED — see FEAT-005)
- [ ] Story 1: `runtime.Strategy` interface refactor
- [ ] Story 2: Shizuku detection + IPC bridge (Kotlin + MethodChannel)
- [ ] Story 3: Bundle bubblewrap + slirp4netns ARM64 in jniLibs
- [ ] Story 4: `BwrapRuntime` Go implementation + seccomp BPF whitelist
- [ ] Story 5: slirp4netns "internet only" networking
- [ ] Story 6: Onboarding screen (Wireless Debugging → Shizuku pair)
- [ ] Story 7: Capability detection + safe fallback to proot

### v2.0 — AVF Microdroid tier (Pixel 7+ only, FEAT-006 to be written)
- [ ] Detect Pixel + Android 14+ + `MANAGE_VIRTUAL_MACHINE` grant
- [ ] Bundle Microdroid OR interop with pre-installed Linux Terminal app
- [ ] Onboarding: `adb shell pm grant ... MANAGE_VIRTUAL_MACHINE`

Background, sources, threat model: `docs/features/FEAT-005-shizuku-bubblewrap-tier.md` and `~/.secondmem/knowledge/engineering/android-sandbox-isolation-mocode.md`.

## Linux Desktop Beta (next)
- [ ] Fix APPLICATION_ID in flutter/linux/CMakeLists.txt
- [ ] Hide bootstrap UI on non-Android (agent_screen.dart)
- [ ] Hide proot/runtime section on non-Android (config_screen.dart)
- [ ] Write scripts/run-linux.sh (daemon + flutter launcher)
- [ ] flutter build linux --release → test end-to-end
- [ ] Package tarball → GitHub Release

## MO-63 — Static NDK binaries (permanent fix, future)
- [ ] Compile node, python3, git, busybox as static ARM64 .so files
- [ ] Ship in jniLibs/arm64-v8a/ (always executable, no SELinux issue)
- [ ] Implement Strategy pattern + feature toggles alongside this
- [ ] Opens iOS path (same approach, iOS toolchain)

## Pre-redesign completed
- [x] Go backend daemon + health endpoint
- [x] OpenCode serve integration
- [x] Flutter app scaffold (Agent, Files, Tasks, Config)
- [x] Slash commands, Copilot auth, stop button
- [x] System prompt overhaul (E1), file edit (E2), grep (E3), glob (E4)
- [x] Context compaction (E5), output truncation (E7)
- [x] Instruction discovery (E8), shell improvements (E10)
- [x] Streaming markdown (E11), per-model limits (E18), ask_user (E16)
- [x] All Flutter compilation/analysis issues fixed
- [x] All Go tests passing
