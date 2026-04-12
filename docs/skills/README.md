# Mo-Code Agent Skill Pack

This folder documents the Codex skills that are useful for `mo-code`.

Use these docs when another agent joins the project and needs to know:

- which skills matter
- when to use them
- which ones are optional
- which ones are not worth installing for this repo

## Core rule

The primary project skill is `mo-code-creation`.

That skill should be treated as the default skill for work in this repository because it matches the project architecture and workflow:

- Flutter app
- Go daemon
- localhost WebSocket bridge
- Android foreground service
- provider switching
- git integration
- checkpoint handoff

## Recommended install set

Install this set for agents working regularly on `mo-code`:

```bash
npx skills add frontend-skill security-threat-model security-best-practices yeet gh-fix-ci gh-address-comments doc
```

After installing, restart Codex so the new skills are available.

## Skill files

- [mo-code-creation.md](./mo-code-creation.md)
- [frontend-skill.md](./frontend-skill.md)
- [security-threat-model.md](./security-threat-model.md)
- [security-best-practices.md](./security-best-practices.md)
- [yeet.md](./yeet.md)
- [gh-fix-ci.md](./gh-fix-ci.md)
- [gh-address-comments.md](./gh-address-comments.md)
- [doc.md](./doc.md)
- [not-recommended.md](./not-recommended.md)

## Selection guide

- Use `mo-code-creation` for all normal project work.
- Add `frontend-skill` for Flutter screens, terminal UI, design system, and interaction polish.
- Add `security-threat-model` before or during work on trust boundaries.
- Add `security-best-practices` when implementing credential storage, command execution, or daemon hardening.
- Add `yeet` when the task includes intentional commit, push, or PR creation.
- Add `gh-fix-ci` when GitHub Actions or PR checks fail.
- Add `gh-address-comments` when resolving review comments on a PR.
- Add `doc` when updating specs, checkpoints, implementation notes, or handoff docs.
