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
