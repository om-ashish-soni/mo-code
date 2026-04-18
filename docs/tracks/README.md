# Sandbox Track Prompts

Copy-paste prompts for the 4 parallel Claude Code workers.

| Track | File | Urgency | Where to paste |
|-------|------|---------|----------------|
| C — prebaked rootfs | [TRACK_C_PREBAKED.md](TRACK_C_PREBAKED.md) | **tonight** | Claude in `../worktrees/sandbox-prebake` |
| A — Termux prefix | [TRACK_A_TERMUX.md](TRACK_A_TERMUX.md) | 1-2 days | Claude in `../worktrees/sandbox-termux` |
| D — AVF probe | [TRACK_D_AVF.md](TRACK_D_AVF.md) | whenever | Claude in `../worktrees/sandbox-avf` |
| B — QEMU TCG | [TRACK_B_QEMU.md](TRACK_B_QEMU.md) | 3-5 days | Claude in `../worktrees/sandbox-qemu` |

## Spin up a worker

```bash
# pick a track, cd into its worktree
cd /mnt/linux_disk/opensource/worktrees/sandbox-prebake
claude
# then paste the entire contents of docs/tracks/TRACK_C_PREBAKED.md
```

## Full context

See `docs/SANDBOX_TRACKS.md` for the integration plan, merge sequence,
conflict rules, and per-track review checklist.
