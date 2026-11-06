# mac-dev-cleanup

Safely free **disk space and RAM** on a macOS developer machine: package caches, Xcode and
iOS simulator data, leftover AI-agent worktrees, idle Docker VMs, and memory hogs.

It ships as a [Claude Code](https://claude.com/claude-code) skill (type `/cleanup`), and every
script also runs fine by hand.

**The rule it follows:** only remove things that rebuild themselves. Anything that could be
someone's work (uncommitted code, Xcode archives, simulator app data, phone backups) is
rescued, listed for you to decide, or left alone. Nothing personal is ever hard-deleted.

## What it cleans

| Area | What | How |
|---|---|---|
| **Package caches** | uv, npm, pnpm, bun, pip, Homebrew, Docker build cache, Colima disk trim | `disk-batch.sh` runs automatically |
| **iOS / Xcode** | DerivedData, Xcode caches, SwiftUI previews, simulator caches, old DeviceSupport, unavailable simulators, CocoaPods / SwiftPM / Carthage caches, React Native Metro caches | `ios-clean.sh` reports; `--apply` cleans |
| **iOS, ask first** | Xcode Archives, simulator runtimes, all simulator data, extra Xcode versions | listed with the exact command; never automatic |
| **Editors and AI tools** | Cursor, VS Code, Windsurf, Antigravity caches, Claude Code and Codex caches, Cargo registry | `extras-clean.sh` reports; `--apply` moves them to the Trash |
| **Leftovers (report only)** | Unfinished downloads, broken login items, files from uninstalled apps, idle project build folders, Docker usage | `extras-clean.sh` lists them; you decide |
| **AI-agent worktrees** | Git worktrees left by Claude Code, Codex and other agents | `worktree-audit.sh` labels LIVE / SAFE / RESCUE / PHANTOM; unmerged work is saved to a branch + patch before removal |
| **RAM / CPU** | Processes over 3 GB, idle Gradle daemons, booted simulators, SourceKitService leaks, idle or wedged Colima, leaked ChatGPT Codex helpers, zombies, orphans | `process-triage.sh` reports; you approve each kill |
| **Printed for you** | Gradle and Chrome caches | shown with a one-line command; you run it with your IDE/browser closed |

## Install

### As a Claude Code skill

```bash
git clone https://github.com/dipaksavaliya/mac-dev-cleanup ~/.claude/skills/cleanup
```

Then type `/cleanup` in Claude Code, or just say "my disk is full" or "my Mac is slow".
Other agents that read `SKILL.md` files work too, for example:

```bash
ln -s ~/.claude/skills/cleanup ~/.codex/skills/cleanup
```

### By hand

```bash
git clone https://github.com/dipaksavaliya/mac-dev-cleanup && cd mac-dev-cleanup
```

```bash
zsh scripts/process-triage.sh          # RAM/CPU report (read-only)
```

```bash
zsh scripts/disk-batch.sh              # clean package caches
```

```bash
zsh scripts/ios-clean.sh               # Xcode/iOS report (read-only)
```

```bash
zsh scripts/ios-clean.sh --apply       # remove the safe Xcode/iOS tier
```

```bash
zsh scripts/extras-clean.sh ~/code     # editor/AI caches + leftovers report (read-only)
```

```bash
zsh scripts/extras-clean.sh --apply    # move the safe tier to the Trash
```

```bash
zsh scripts/worktree-audit.sh ~/code   # agent worktree report (read-only)
```

```bash
python3 scripts/reap-codex-helpers.py  # dry run; add --kill to stop idle Codex helpers
```

### Share a single file

[SKILL.md](SKILL.md) is self-contained: the full playbook plus all six scripts embedded.
Send just that file to anyone; their agent extracts the scripts on first use.

## Example: iOS report

```
== SAFE tier (rebuilds itself) — report only, re-run with --apply ==
  SAFE   8312.4 MB  Xcode DerivedData (build products + index; next build is a full rebuild)
  SKIP    912.0 MB  Simulator dyld caches (2 simulator(s) booted: run 'xcrun simctl shutdown all' first)
  SAFE   4120.7 MB  Old iOS/watchOS/tvOS DeviceSupport (newest kept)
  SAFE   2051.3 MB  6 unavailable simulators (xcrun simctl delete unavailable)
  SAFE    640.2 MB  CocoaPods download cache

== ASK FIRST (not removed by --apply) ==
  12480.0 MB  14 Xcode archives: delete old ones in Xcode > Window > Organizer, only after their dSYMs are uploaded
```

(The sizes are an illustration.)

## Safety guarantees

- Report first, act second: every script except `disk-batch.sh` is read-only unless you pass `--apply` / `--kill`.
- Skips anything in use: DerivedData while Xcode is open or building, simulator caches while one is booted, Metro caches while the bundler runs, worktrees with a live session.
- Never touches Xcode Archives, simulator app data, iPhone/iPad backups, Downloads or Documents.
- Unmerged agent work is committed to a `rescue/*` branch and saved as a patch before any worktree is removed.
- Root-owned leftovers get a printed `sudo` command, never a workaround.
- `extras-clean.sh` checks every path first: it refuses symlinks, anything outside your home folder, and Documents, Downloads, Desktop, Pictures and iCloud Drive. `--apply` moves files to the Trash, so you can undo it.
- Docker volumes are never pruned, because they can hold databases.

## Good to know

- **Measure with `df`, not `du`.** APFS clones make `du` count shared files twice.
- **A sudden drop in free space is usually memory, not files.** Swap files live on the boot disk;
  fix RAM pressure first, and only a restart returns all of it.
- `worktree-audit.sh` checks each worktree with `lsof`, so a big tree can take a minute or two.
  Point it at your code folder rather than `$HOME`.
- Requirements: macOS, zsh (the default shell), Python 3.9+. Xcode is optional; iOS checks skip themselves without it.

## Repository layout

```
SKILL.md            the playbook (and the single-file share, with scripts embedded)
scripts/
  disk-batch.sh         package caches
  ios-clean.sh          Xcode / simulators / CocoaPods / SwiftPM / Carthage / Metro
  extras-clean.sh       editor, AI-tool and Cargo caches; leftover reports
  process-triage.sh     RAM / CPU report
  worktree-audit.sh     agent worktree report
  reap-codex-helpers.py ChatGPT Codex helper reaper
tests/              sandbox test for extras-clean.sh (touches nothing real)
embed-scripts.py    re-embeds scripts/ into SKILL.md after you edit a script
NOTICE              third-party attribution
```

## Using Mac Sai alongside this

[Mac Sai](https://github.com/iliyami/MacSai) is a free, notarized, open-source GUI cleaner with a malware scanner,
app uninstaller and disk map:

```bash
brew install --cask mac-sai
```

**Warning: review every item before cleaning, and don't empty the Trash straight away.** On a real dev machine, Mac Sai's
cleanup moved Colima's live VM disks (`~/.colima/_lima/...`) to the Trash, and emptying the Trash deleted them. The VM kept
running on the deleted files, so everything looked healthy, but stopping it would have lost all Docker images and volumes.
The same run removed about 10,000 duplicate files, including IDs, salary files and contracts, which can break a backup
folder's completeness.

- Never select VM or container disks (`~/.colima`, `~/.lima`, Docker, UTM, Parallels), even when they show up as the biggest items.
- Exclude your code, backup and personal document folders from duplicate cleanups.
- If files go missing, check `~/Library/Logs/MacClean/operations.log`.
- Check a VM after any cleaner run: `lsof -p <VM pid> +L1` showing link count 0 on a disk file means it is already deleted.
  Copy the data out before stopping that VM.

This project adapts its editor and AI-tool cache coverage, leftover and broken login-item checks, project-root
limits, path guard and Trash-first approach (see [NOTICE](NOTICE)). Two features are deliberately left out because
they modify installed apps: language file removal and Universal Binary thinning.

## Contributing

Issues and PRs are welcome, especially new cache locations and other toolchains (Android SDK, Rust, Go).
Keep the core rule: only remove what rebuilds itself, and report before acting.
After changing anything in `scripts/`, run `python3 embed-scripts.py` so `SKILL.md` stays in sync.

## License

[MIT](LICENSE)
