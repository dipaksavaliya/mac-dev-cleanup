---
name: cleanup
description: Free disk space, RAM, and CPU on a Mac used for development: safe cache cleanup, AI-agent worktree sweep that rescues unmerged work, memory-hog and runaway triage (Gradle daemons, idle Docker/Colima VM, leaked ChatGPT Codex helpers), and zombie/orphan process cleanup. Use when the user says cleanup, disk full, storage full, low space, system slow or lagging, RAM/CPU cleanup, kill zombie processes, or asks to free space or speed up the machine.
---

# Mac Dev-Machine Cleanup

A safe, repeatable routine for freeing **storage and RAM** on a macOS developer machine
(Apple Silicon or Intel). It works two ways:

- **As a Claude Code skill**: `git clone https://github.com/dipaksavaliya/mac-dev-cleanup ~/.claude/skills/cleanup`,
  then type `/cleanup`. (Or save just this file as `~/.claude/skills/cleanup/SKILL.md`; on first use the
  agent saves the four scripts at the bottom into `scripts/` next to it.)
- **By hand**: read the phases, save the scripts, run them yourself.

The guiding rule: **only remove things that rebuild themselves** (package caches, build output,
idle helper processes). Anything that could be someone's work goes to the Trash or gets rescued first.

---

## Things that will surprise you on macOS

1. **`du` lies; `df` tells the truth.** APFS clones files, so `du` counts shared blocks twice.
   Measure every gain as the change in `df -h /System/Volumes/Data` **before vs after**.
2. **Swap lives on your boot disk.** When free space drops by many GB within hours and you
   deleted nothing, the cause is memory pressure (swap files are 1 GB each in `/System/Volumes/VM`).
   Fix RAM first (Phase 3). Only a restart fully returns swap.
3. **Load average lags.** Right after a reboot Spotlight reindexing inflates it. Trust the
   *runnable* process count (`ps -Ao stat | grep -c '^R'`) instead.
4. **Activity Monitor's RSS undercounts.** Swapped-out memory doesn't show in RSS; the
   JetsamEvent reports in `/Library/Logs/DiagnosticReports/` name the real hog even after it exits.
5. **Cache cleans can free less than they report.** A tool may say "removed 9 GiB" while `df`
   moves 0.2 GB because project virtualenvs cloned those files.

---

## Phase 0: Situate (always do this first)

```bash
df -h /System/Volumes/Data | tail -1        # free space
sysctl vm.swapusage                         # swap in use
ls /System/Volumes/VM | grep -c swapfile    # swap files on disk
uptime
```

- **Is a build running?** (Gradle, Xcode, Flutter, `next build`; the triage script lists them.)
  If so, don't clear build caches, don't stop its daemon, and don't restart the machine.
- If the machine is too loaded for scripts to finish, take **one** `ps` snapshot to a file
  and analyze that instead of running many commands.

## Phase 1: Disk caches (safe, run without asking)

Run `scripts/disk-batch.sh`. It cleans re-downloadable caches only:
uv (prune), npm, pnpm (prune), bun, pip, Homebrew, Docker build cache, and trims the Colima VM disk
(`fstrim`, which deletes nothing and returns freed VM blocks to macOS, often 1–3 GB).

It then **prints** (never runs) the big caches you should clear yourself, because a
running IDE/build may be using them: Gradle caches, Xcode DerivedData, Chrome's cache.

`uv cache clean` (full, not prune) only on a "deep" request. Long-running `uvx` servers hold
its lock; killing them first (`pkill -f 'uv tool uvx'`) works but stops those MCP servers until
their apps restart.

## Phase 2: AI-agent worktrees

Coding agents (Claude Code, Codex, etc.) create git worktrees, often a full checkout plus
`node_modules`, and leave them behind. Run `scripts/worktree-audit.sh [root-dir]`.
It never deletes anything; it classifies each worktree:

| Verdict | Meaning | Action |
|---|---|---|
| **LIVE** | A process has its cwd inside, or its agent session wrote in the last 60 min | Never touch |
| **SAFE** | Clean and fully merged into the default branch | Re-check it's still idle, then `git -C <repo> worktree remove --force <wt> && git -C <repo> worktree prune` (the branch survives) |
| **RESCUE** | Uncommitted changes or unmerged commits | Rescue first (below), then remove |
| **PHANTOM** | Folder isn't a git worktree (stray files) | Move to Trash if idle |

**Rescue procedure** (ask the user first):
1. In the worktree: `git add -A && git commit -m "rescue: uncommitted work from <worktree>"`
2. Save a copy outside the repo: `git diff <default>...HEAD > ~/rescue/<name>.diff` and
   `git format-patch <default>..HEAD -o ~/rescue/<name>/`
3. Keep the commits reachable: `git branch rescue/<name> HEAD`
4. Then remove: `git worktree unlock <wt>; git worktree remove --force <wt>; git worktree prune`

**Also check** (the script doesn't cover these):
`du -sk ~/.codex/worktrees/*/* /private/tmp/* 2>/dev/null | sort -rn | head`.
Test runs can leave a full build per run under `<worktree>/test-results/`, and agents copy whole
source trees into `/private/tmp/<project>-*`. If a folder has been idle for more than 2 h and no process has its cwd
there (`lsof -d cwd | grep <dir>`), ask, then move it to the Trash.

## Phase 3: RAM / CPU triage

Run `scripts/process-triage.sh` (report only), then act per finding:

- **A single process over ~3 GB** is usually the culprit. Check its parent, cwd and CPU over
  a few samples before acting. Ask before killing anything you didn't start.
- **Idle Gradle daemon** (~0% CPU, no TCP clients, no build running): `./gradlew --stop` in its
  project, or `kill -TERM <pid>`. Prevent it: add `org.gradle.daemon.idletimeout=600000`
  to `~/.gradle/gradle.properties` (daemons exit 10 min after the last build).
- **Docker/Colima VM with 0 containers** (often holds 2–5 GB): ask, then `colima stop`
  (lossless; `colima start` brings it back) or quit Docker Desktop.
- **Docker wedged** (VM up, `docker info` hangs): ask, then `colima restart`.
- **Colima disk much bigger than `docker system df`** (orphaned containerd data): ask, then
  back up `~/.colima/default/colima.yaml`, run `colima delete --data --force`, restore the yaml,
  `colima start`. This destroys all images/volumes; projects rebuild their own.
- **Leaked ChatGPT Codex helpers** (the desktop app's app-server starts helper processes per
  thread and doesn't reap them; 40+ idle helpers seen): ask, then `scripts/reap-codex-helpers.py`
  (dry run), then `--kill`. It only touches helpers idle for more than 60 min and never an active task.
- **Zombies** can't be killed; if more than 5 share a parent, offer to restart that app.
- **Orphans** (dev processes whose cwd was deleted): kill them (TERM, then KILL after 5 s) and list what was killed.
- **User apps** (browsers, chat apps, Electron): report their totals, but never quit one without asking.

## Deep options (only on request)

- **Stale project dependencies**: delete `node_modules` / `.venv` only in projects idle 14+ days
  (no commits, no edits, no running process inside) that have a lockfile. Write each reinstall
  command (`pnpm install`, `uv sync`, …) to a notes file first.
- **Docker images**: remove only images no container uses (list them explicitly), then
  `colima ssh -- sudo fstrim -a`. Judge the gain with `docker system df` before/after (layers are shared).
- **Old app support folders**: `~/Library/Application Support` is often the biggest hog
  (old IDE versions, browser profiles, Electron caches). Move what you remove to the Trash; don't delete it outright.
- **Restart**: only with no build running. Note that Colima/Docker may not auto-start again.

## Hard rules

- Never hard-delete user data: it goes to `~/.Trash`, and the user empties it.
- Never `rm` Gradle/Xcode/browser caches for the user: print the command and let them run it.
- Never delete project `node_modules`/`.venv`, Downloads, or Documents except as the deep option above.
- Never kill in-flight builds, processes inside LIVE worktrees, or user-facing apps.
- Root-owned leftovers (from old `sudo npm`/`sudo` installs): give the user a one-line `sudo`
  command; never work around permissions.
- Report as: **free before → free after** (df), what was cleaned, what was skipped and why, what needs the user.

---

## Scripts

Save each script to `scripts/` next to this file and `chmod +x scripts/*`. All of them are read-only
except `disk-batch.sh` (caches only) and `reap-codex-helpers.py --kill`.

### scripts/disk-batch.sh

```zsh
#!/bin/zsh
# disk-batch.sh: safe cache cleanup. Everything here is a re-downloadable cache.
set -u
export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
NODE_BIN="$(ls -d $HOME/.nvm/versions/node/*/bin 2>/dev/null | tail -1)"
[ -n "$NODE_BIN" ] && export PATH="$NODE_BIN:$PATH"

FREE0=$(df -k / | tail -1 | awk '{print $4}')
echo "free before: $(( FREE0 / 1048576 )) GB"

# uv: prune keeps recently used entries; fail fast if a long-lived uvx process holds the lock
if command -v uv >/dev/null; then
  OUT=$(UV_LOCK_TIMEOUT=10 uv cache prune 2>&1 | tail -1)
  case "$OUT" in
    *Timeout*lock*) echo "uv cache busy (held by):"; ps -axo pid,etime,command | grep -E '[u]v tool uvx|[u]vx ' | cut -c1-110;;
    *) echo "uv: $OUT";;
  esac
fi
command -v npm  >/dev/null && npm cache clean --force 2>&1 | tail -1
command -v pnpm >/dev/null && pnpm store prune 2>&1 | tail -1
command -v brew >/dev/null && brew cleanup --prune=all -q 2>&1 | tail -1
rm -rf "$HOME/.bun/install/cache" "$HOME/Library/Caches/pip"
command -v docker >/dev/null && docker info >/dev/null 2>&1 && docker builder prune -f 2>&1 | tail -1
# Colima: return blocks freed inside the VM to macOS (deletes nothing)
if command -v colima >/dev/null && colima status >/dev/null 2>&1; then
  colima ssh -- sudo fstrim -a 2>/dev/null && echo "colima disk trimmed"
fi

FREE1=$(df -k / | tail -1 | awk '{print $4}')
echo "free after: $(( FREE1 / 1048576 )) GB (freed $(( (FREE1 - FREE0) / 1024 )) MB)"
echo
echo "CLEAR THESE YOURSELF (close the IDE/browser first):"
if ps -Ao command | grep -qE '[G]radleWrapperMain|[f]lutter (build|run|test)|[x]codebuild'; then
  echo "  !! a build is RUNNING: wait for it before clearing build caches"
fi
du -sh "$HOME/.gradle/caches" "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/Library/Caches/Google" 2>/dev/null | sed 's/^/  /'
echo '  -> rm -rf ~/.gradle/caches ~/Library/Developer/Xcode/DerivedData ~/Library/Caches/Google'
```

### scripts/process-triage.sh

```zsh
#!/bin/zsh
# process-triage.sh: RAM/CPU triage. REPORTS ONLY; it kills nothing.
set -u
setopt null_glob 2>/dev/null || true
PY=$(command -v /opt/homebrew/bin/python3 || command -v python3)
echo "== pressure =="
sysctl vm.swapusage | awk '{print "swap used:", $7, " (swap files live on the boot disk, 1 GB each)"}'
uptime | sed 's/.*load/load/'
echo "runnable now: $(ps -Ao stat | awk '$1 ~ /^R/' | wc -l | tr -d ' ')  (load avg lags; this is the live number)"
echo
echo "== biggest memory holders (a single process >3 GB = prime suspect) =="
top -l 1 -o mem -n 8 -stats pid,mem,command 2>/dev/null | tail -8 | sed 's/^/  /'
echo
echo "== process families by count (a leak shows up as dozens of one name) =="
ps -axo comm= | sed 's#.*/##' | sort | uniq -c | sort -rn | head -8 | sed 's/^/  /'
echo
echo "== latest macOS memory squeeze (jetsam names the culprit even after it exits) =="
JS=(/Library/Logs/DiagnosticReports/JetsamEvent-*(Nom)); J=${JS[1]:-}
if [ -n "$J" ]; then "$PY" - "$J" <<'PY'
import json, sys, os
d = json.loads(open(sys.argv[1]).read().split('\n', 1)[1])
t = max(d.get('processes', []), key=lambda p: p.get('rpages', 0), default={})
print(f"  {os.path.basename(sys.argv[1])[12:29]}  largest: {t.get('name','?')} pid {t.get('pid','?')} {t.get('rpages',0)*16384/1073741824:.1f} GB")
PY
else echo "  none"; fi
echo
echo "== IN-FLIGHT BUILDS (never kill; don't clear build caches or restart while these run) =="
ps -Ao pid,etime,command | grep -E '[G]radleWrapperMain|[f]lutter (build|run|test)|[x]codebuild|[n]ext build' | grep -vE 'zsh -c|bash -c' | cut -c1-120 | sed 's/^/  /'
echo "  (empty = none)"
echo
echo "== GRADLE DAEMONS (idle = ~0% CPU AND no TCP clients -> safe to stop) =="
for P in $(pgrep -f GradleDaemon); do
  C=$(lsof -a -p $P -iTCP -sTCP:ESTABLISHED -nP 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
  printf "  pid=%s up=%s cpu=%s%% tcp-clients=%s\n" $P "$(ps -p $P -o etime= | tr -d ' ')" "$(ps -p $P -o %cpu= | tr -d ' ')" $C
done
pgrep -f GradleDaemon >/dev/null || echo "  none"
echo
echo "== CHATGPT CODEX helper backlog =="
R=$(pgrep -f 'codex.*app-server' | head -1)
if [ -n "$R" ]; then echo "  app-server pid $R running -> run scripts/reap-codex-helpers.py (dry run) to count idle helpers"
else echo "  not running"; fi
echo
echo "== ZOMBIES (unkillable; restart the PARENT to reap) =="
ps -Aeo pid,ppid,stat,comm | awk '$3 ~ /^Z/ {printf "  pid=%s ppid=%s %s\n", $1, $2, $4}' | head -10
ps -Aeo stat | awk '$1 ~ /^Z/' | wc -l | awk '{print "  total zombies:", $1}'
echo
echo "== ORPHANS (dev processes whose cwd was deleted: safe kill candidates) =="
for P in $(ps -Ao pid,comm | awk '$2 ~ /(^|\/)(node|bun|deno|python[0-9.]*)$/ {print $1}'); do
  CWD=$(lsof -a -p "$P" -d cwd -Fn 2>/dev/null | awk '/^n/ {print substr($0,2)}')
  [ -n "$CWD" ] && [ ! -d "$CWD" ] && echo "  pid=$P $(ps -o comm= -p $P) cwd-GONE: $CWD"
done
echo "  (empty = none)"
echo
echo "== STRAY TEST RUNNERS (parent died, idle) =="
ps -Aeo pid,ppid,etime,pcpu,comm | awk '$2==1 && $5 ~ /(flutter_tester|dartvm|jest|vitest|pytest)/ && $4+0 < 5 {printf "  pid=%s age=%s %s\n", $1, $3, $5}' | head -10
echo "  (empty = none)"
echo
echo "== DOCKER / COLIMA =="
if command -v colima >/dev/null && colima status >/dev/null 2>&1; then
  if ! perl -e 'alarm 15; exec @ARGV' docker info >/dev/null 2>&1; then
    echo "  WEDGED: colima up but docker unresponsive -> ask, then 'colima restart'"
  else
    N=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    echo "  colima running | containers: $N"
    [ "$N" = 0 ] && echo "  IDLE VM (0 containers) -> ask, then 'colima stop' (lossless)"
    docker ps --format '  {{.Names}} ({{.RunningFor}})' 2>/dev/null | head -15
  fi
elif pgrep -x "Docker Desktop" >/dev/null || pgrep -f "Docker.app" >/dev/null; then
  echo "  Docker Desktop running | containers: $(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
else echo "  not running"; fi
```

### scripts/worktree-audit.sh

```zsh
#!/bin/zsh
# worktree-audit.sh [root]: find agent worktrees and classify LIVE / SAFE / RESCUE / PHANTOM.
# Prints TSV: verdict, size MB, path, detail. NEVER deletes anything.
set -u
ROOT="${1:-$HOME}"
find "$ROOT" \( -name node_modules -o -name Library -o -name .Trash -o -name .git \) -prune \
     -o -type d -path '*/.claude/worktrees' -print 2>/dev/null \
| while read -r WTDIR; do
  REPO="${WTDIR%/.claude/worktrees}"
  for WT in "$WTDIR"/*(N/); do
    if [ ! -e "$WT/.git" ]; then
      echo -e "PHANTOM\t$(du -sm "$WT" 2>/dev/null | cut -f1)\t$WT\tnot a git worktree (stray files): Trash if idle"; continue
    fi
    # LIVE (1): a process has its cwd inside (deleting it would break that session)
    if lsof +D "$WT" 2>/dev/null | awk 'NR>1 && $4=="cwd"' | grep -q .; then
      echo -e "LIVE\t$(du -sm "$WT" 2>/dev/null | cut -f1)\t$WT\tactive process inside: DO NOT TOUCH"; continue
    fi
    # LIVE (2): Claude Code in-process subagent; its transcript sits under the owning session
    LIVE_WHY=""
    for SUB in $HOME/.claude/projects/*/*/subagents/${WT:t}.jsonl(N); do
      [ -n "$(find "${SUB:h:h}.jsonl" -mmin -60 2>/dev/null)" ] && LIVE_WHY="owning agent session wrote <60 min ago"
    done
    # LIVE (3): a Claude Code session opened directly inside the worktree
    SLUG=$(print -r -- "$WT" | tr '/.' '--')
    if [ -z "$LIVE_WHY" ] && [ -n "$(find "$HOME/.claude/projects/$SLUG" -maxdepth 1 -name '*.jsonl' -mmin -60 2>/dev/null | head -1)" ]; then
      LIVE_WHY="a session inside this worktree wrote <60 min ago"
    fi
    if [ -n "$LIVE_WHY" ]; then
      echo -e "LIVE\t$(du -sm "$WT" 2>/dev/null | cut -f1)\t$WT\t$LIVE_WHY: DO NOT TOUCH"; continue
    fi
    DEFAULT=$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo main)
    DIRTY=$(git -C "$WT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    AHEAD=$(git -C "$WT" rev-list --count "$DEFAULT..HEAD" 2>/dev/null || echo 0)
    SZ=$(du -sm "$WT" 2>/dev/null | cut -f1)
    if [ "$DIRTY" -eq 0 ] && [ "$AHEAD" -eq 0 ]; then
      echo -e "SAFE\t$SZ\t$WT\tclean + merged into $DEFAULT (branch survives removal)"
    else
      echo -e "RESCUE\t$SZ\t$WT\tdirty=$DIRTY unmerged=$AHEAD: save patch/branch before removing"
    fi
  done
done
```

### scripts/reap-codex-helpers.py

```python
#!/usr/bin/env python3
"""Stop idle helper processes leaked by the ChatGPT desktop app's Codex app-server. Dry run unless --kill.

Targets ONLY descendants that are >60 min old AND <1% CPU, skipping codex-named hosts, the app-server,
ChatGPT itself, and every ancestor of a young/busy process (so a running Codex task is never touched).
"""
import collections, ctypes, os, re, signal, subprocess, sys, time
lib = ctypes.CDLL('/usr/lib/libproc.dylib')
class RU(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        'utime', 'stime', 'pkg_idle', 'intr', 'pageins', 'wired', 'resident', 'footprint', 'start', 'exit',
        'cutime', 'cstime', 'cpkg', 'cintr', 'cpageins', 'celapsed', 'bytes_read', 'bytes_written')]
def fp(p):
    r = RU(); return r.footprint if lib.proc_pid_rusage(p, 2, ctypes.byref(r)) == 0 else 0
def mins(et):
    et = et.strip(); days = 0
    if '-' in et: d, et = et.split('-', 1); days = int(d)
    p = [int(x) for x in et.split(':')]
    while len(p) < 3: p.insert(0, 0)
    return days * 1440 + p[0] * 60 + p[1]
alive = lambda p: subprocess.run(['kill', '-0', str(p)], capture_output=True).returncode == 0
rows = [l.split(None, 4) for l in subprocess.run(['ps', '-Ao', 'pid=,ppid=,etime=,%cpu=,command='], capture_output=True, text=True).stdout.splitlines()]
procs = {int(r[0]): (int(r[1]), r[2], float(r[3]), r[4]) for r in rows if len(r) == 5}
root = next((p for p, v in procs.items() if re.search(r'ChatGPT\.app/.*codex( |$)|CodexCLI\.app/Contents/MacOS/codex', v[3]) and 'app-server' in v[3]), None)
if not root: sys.exit("Codex app-server not running: nothing to do.")
chatgpt = next((p for p, v in procs.items() if v[3].startswith('/Applications/ChatGPT.app/Contents/MacOS/ChatGPT')), None)
kids = collections.defaultdict(list)
for p, v in procs.items(): kids[v[0]].append(p)
d, s = [], [root]
while s:
    for c in kids[s.pop()]: d.append(c); s.append(c)
protect = {root, chatgpt, os.getpid()}
for y in [x for x in d if mins(procs[x][1]) <= 60 or procs[x][2] >= 1.0]:
    q = y
    while q in procs and q != root: protect.add(q); q = procs[q][0]
targets = [x for x in d if x not in protect and mins(procs[x][1]) > 60 and procs[x][2] < 1.0
           and not re.search(r'codex', os.path.basename(procs[x][3].split()[0]), re.I)]
mem = sum(fp(x) for x in targets)
print(f"app-server {root}: {len(d)} descendants; idle targets: {len(targets)} (~{mem/1073741824:.2f} GB)")
if '--kill' not in sys.argv:
    print("dry run: re-run with --kill to stop them"); sys.exit(0)
for x in targets:
    try: os.kill(x, signal.SIGTERM)
    except ProcessLookupError: pass
time.sleep(6)
left = [x for x in targets if alive(x)]
for x in left:
    try: os.kill(x, signal.SIGKILL)
    except ProcessLookupError: pass
print(f"stopped {len(targets)} (SIGTERM {len(targets) - len(left)}, SIGKILL {len(left)}) | app-server: "
      f"{'running' if alive(root) else 'GONE'} | ChatGPT: {'running' if chatgpt and alive(chatgpt) else 'not found'}")
```

---

## Optional: weekly auto-clean

To run Phase 1 every Monday at 10:00, create `~/Library/LaunchAgents/local.cache-cleanup.plist`
with a `ProgramArguments` of `/bin/zsh <path>/scripts/disk-batch.sh`, a `StartCalendarInterval`
of `Weekday 1, Hour 10`, and `StandardOutPath` set to a log file. Then load it with
`launchctl load ~/Library/LaunchAgents/local.cache-cleanup.plist`.
