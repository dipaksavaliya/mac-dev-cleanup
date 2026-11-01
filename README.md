# mac-dev-cleanup

Free **disk space and RAM** on a macOS developer machine, safely. Built as a
[Claude Code](https://claude.com/claude-code) skill, but every script also runs fine by hand.

It only removes things that rebuild themselves (package caches, build output, idle helper
processes). Anything that could be someone's work is rescued or moved to the Trash, never hard-deleted.

## What it does

| Phase | What | Acts without asking? |
|---|---|---|
| 0. Situate | Free space, swap, load, running builds | read-only |
| 1. Disk caches | uv, npm, pnpm, bun, pip, Homebrew, Docker build cache, Colima `fstrim` | yes (caches only) |
| 2. Agent worktrees | Finds AI-agent git worktrees: LIVE / SAFE / RESCUE / PHANTOM | asks; rescues unmerged work first |
| 3. RAM / CPU | Memory hogs, idle Gradle daemons, idle or wedged Colima, leaked ChatGPT Codex helpers, zombies, orphans | asks before killing anything |

Gradle, Xcode DerivedData and browser caches are **printed, never deleted**: you clear them when your IDE is closed.

## Install

As a Claude Code skill:

```bash
git clone https://github.com/dipaksavaliya/mac-dev-cleanup ~/.claude/skills/cleanup
```

Then type `/cleanup` in Claude Code. The same folder works for other agents that read
`SKILL.md` files (for example, symlink it into `~/.codex/skills/cleanup`).

By hand:

```bash
git clone https://github.com/dipaksavaliya/mac-dev-cleanup && cd mac-dev-cleanup
zsh scripts/process-triage.sh          # RAM/CPU report (read-only)
zsh scripts/worktree-audit.sh ~/code   # agent worktree report (read-only)
zsh scripts/disk-batch.sh              # clean caches
python3 scripts/reap-codex-helpers.py  # dry run; add --kill to stop idle Codex helpers
```

[SKILL.md](SKILL.md) is the full playbook: what each finding means, what to do about it,
and the safety rules. It is self-contained, so you can share that one file on its own.

## Notes

- Measure gains with `df`, not `du`: APFS clones make `du` double-count.
- Swap files live on the boot disk, so a sudden drop in free space usually means memory pressure, not files.
- `worktree-audit.sh` uses `lsof +D` per worktree, so it can take a minute or two on a large tree.
  Point it at your code folder rather than `$HOME`.
- macOS only. Tested on Apple Silicon with zsh and Python 3.9+.

## License

MIT
