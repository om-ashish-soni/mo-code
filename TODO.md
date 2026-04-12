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
- [x] Version 1.1.0+2, compileSdk/targetSdk 35
- [x] Store listing updated with R1/R2 features
- [ ] Generate release keystore (Om — `keytool -genkey -v -keystore mocode-release.keystore -alias mocode -keyalg RSA -keysize 2048 -validity 10000`)
- [ ] Create `flutter/android/key.properties` from `key.properties.example`
- [ ] Build release AAB (Om — `./scripts/release.sh`)
- [ ] Play Console upload + internal testing

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
