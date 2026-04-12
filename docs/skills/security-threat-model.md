# Skill: security-threat-model

## Install

```bash
npx skills add security-threat-model
```

## Why it is useful for mo-code

`mo-code` crosses several trust boundaries:

- API keys stored on device
- SSH keys for git push
- localhost daemon exposed to the app
- shell and file execution by an agent
- provider switching and runtime config
- project directory access inside the app sandbox

This skill helps agents identify concrete risks before the system shape hardens.

## Use this skill when

- designing daemon and app trust boundaries
- exposing new HTTP or WebSocket surfaces
- adding config storage for provider credentials
- adding git clone, commit, or push flows
- deciding what agent tools should be allowed on Android

## Priority

High. Recommended early, not just after the app is feature-complete.

## Pair with

- `mo-code-creation`
- `security-best-practices`
