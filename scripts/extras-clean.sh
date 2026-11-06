#!/bin/zsh
# extras-clean.sh [--apply] [project-root]: editor, AI-tool and Cargo caches, plus leftover reports.
# Default: report only. --apply: move the SAFE tier to ~/.Trash/mac-dev-cleanup-<date> (undo by moving it back).
# Everything else is report-only. Coverage and safety ideas adapted from Mac Sai (BSD-3-Clause), see NOTICE.
set -u
setopt null_glob extended_glob
APPLY=0; [ "${1:-}" = "--apply" ] && { APPLY=1; shift; }
ROOT="${1:-$HOME/workspace}"
AS="$HOME/Library/Application Support"
TRASH="$HOME/.Trash/mac-dev-cleanup-$(date +%Y-%m-%d)"
sz() { [ $# -eq 0 ] && { printf "%7.1f MB" 0; return; }; du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%7.1f MB", s/1024}'; }

# Refuse anything that is not a real path inside $HOME's caches: no symlinks, no protected or user-data roots
guard_path() {
  local p=$1 r
  [ -n "$p" ] && [ -e "$p" ] && [ ! -L "$p" ] || return 1
  r=${p:A}
  case "$r" in
    "$HOME"/Documents*|"$HOME"/Downloads*|"$HOME"/Desktop*|"$HOME"/Pictures*|"$HOME"/Library/Mobile\ Documents*) return 1 ;;
    "$HOME"/*) [ "$r" = "$p" ] ;;
    *) return 1 ;;
  esac
}
safe() {  # safe <label> <skip-reason-or-empty> <paths...>
  local label=$1 why=$2 p ok=(); shift 2
  for p in "$@"; do guard_path "$p" && ok+=("$p") || { [ -e "$p" ] && echo "  BLOCK  refused by path guard: $p"; }; done
  local s=$(sz "${ok[@]}")
  if [ ${#ok} -eq 0 ]; then echo "  -     $s  $label (nothing there)"
  elif [ -n "$why" ]; then echo "  SKIP  $s  $label ($why)"
  elif [ $APPLY = 1 ]; then
    for p in "${ok[@]}"; do
      mkdir -p "$TRASH${p:h}" && mv "$p" "$TRASH$p"
    done
    echo "  TRASH $s  $label"
  else echo "  SAFE  $s  $label"; fi
}
running() { pgrep -xq "$1" && echo "$1 is running: quit it first"; }
editor() {  # editor <label> <app-support-folder> <process-name>
  local b="$AS/$2"
  safe "$1 caches" "$(running "$3")" "$b/Cache"(N) "$b/Code Cache"(N) "$b/GPUCache"(N) "$b/CachedData"(N) "$b/CachedProfilesData"(N)
}

echo "== SAFE tier (rebuilds itself) $([ $APPLY = 1 ] && echo "— moving to $TRASH" || echo '— report only, re-run with --apply') =="
editor "Cursor" Cursor Cursor
editor "VS Code" Code Electron
editor "Windsurf" Windsurf Windsurf
editor "Antigravity" Antigravity Antigravity

# Session history, memory and projects are user data and are never listed here
CLAUDE=""; pgrep -q claude && CLAUDE="Claude Code is running"
safe "Claude Code paste and shell caches" "$CLAUDE" "$HOME/.claude/cache"(N) "$HOME/.claude/paste-cache"(N) "$HOME/.claude/shell-snapshots"(N)
CODEX=""; pgrep -q -i codex && CODEX="Codex is running"
safe "Codex temp and cache" "$CODEX" "$HOME/.codex/.tmp"(N) "$HOME/.codex/cache"(N)
CARGO=""; pgrep -xq cargo && CARGO="cargo is running"
safe "Cargo registry downloads (re-downloaded on next build)" "$CARGO" "$HOME/.cargo/registry/cache"(N) "$HOME/.cargo/registry/src"(N)

echo
echo "== UNFINISHED DOWNLOADS (never removed; check them yourself) =="
DL=("$HOME"/Downloads/*.(download|crdownload|part|partial)(N))
if [ ${#DL} -eq 0 ]; then echo "  none"; else for f in "${DL[@]}"; do echo "  $(sz "$f")  ${f:t}"; done; fi

echo
echo "== BROKEN LOGIN ITEMS (program missing; remove with 'launchctl bootout' then delete the plist) =="
N=0
for f in "$HOME"/Library/LaunchAgents/*.plist(N) /Library/LaunchAgents/*.plist(N) /Library/LaunchDaemons/*.plist(N); do
  P=$(plutil -extract Program raw -o - "$f" 2>/dev/null || plutil -extract ProgramArguments.0 raw -o - "$f" 2>/dev/null)
  case "$P" in /*) [ -e "$P" ] || { echo "  ${f:t}  ->  $P"; N=$((N+1)); } ;; esac
done
[ $N = 0 ] && echo "  none"

echo
echo "== APP LEFTOVERS (no installed app matches; verify before removing, a helper may still use them) =="
# shortcut: only reverse-DNS folder names are checked, plain-named folders cannot be matched reliably
IDS=$(for a in /Applications/*.app(N) /Applications/*/*.app(N) "$HOME"/Applications/*.app(N) /System/Applications/*.app(N); do
  plutil -extract CFBundleIdentifier raw -o - "$a/Contents/Info.plist" 2>/dev/null
done | tr 'A-Z' 'a-z' | sort -u)
VENDORS=$(print -r -- "$IDS" | cut -d. -f1-2 | sort -u)
for d in "$HOME"/Library/Caches/*(N/) "$AS"/*(N/) "$HOME"/Library/Saved\ Application\ State/*(N/) "$HOME"/Library/HTTPStorages/*(N/) "$HOME"/Library/Containers/*(N/); do
  n=${d:t:l}; n=${n%.savedstate}
  [[ $n == [a-z0-9-]##.[a-z0-9-]##.* ]] || continue
  [[ $n == com.apple.* ]] && continue
  print -r -- "$VENDORS" | grep -qx "${n%%.*}.$(print -r -- "$n" | cut -d. -f2)" && continue
  echo "$(du -sk "$d" 2>/dev/null | cut -f1) ${d#$HOME/Library/}"
done | sort -rn | head -15 | awk '{k=$1; $1=""; printf "  %7.1f MB %s\n", k/1024, $0}'

echo
echo "== IDLE PROJECT BUILD FOLDERS under $ROOT (14+ days untouched; never removed here) =="
case "${ROOT:A}" in
  /|/System*|/Library*|/Applications*|/usr*|/bin*|/sbin*|/opt*|"$HOME"|"$HOME"/Library*) echo "  refusing to scan ${ROOT:A}: pick a code folder" ;;
  *)
    find "$ROOT" -maxdepth 6 -type d \( -name node_modules -o -name target -o -name .next -o -name Pods -o -name .venv -o -name venv -o -name build -o -name dist \) -prune 2>/dev/null | while read -r j; do
      p=${j:h}
      [ -e "$p/package.json" -o -e "$p/Cargo.toml" -o -e "$p/pyproject.toml" -o -e "$p/requirements.txt" -o -e "$p/Podfile" -o -e "$p/build.gradle" -o -e "$p/build.gradle.kts" ] || continue
      [ -n "$(find "$p" -maxdepth 2 -type f -mtime -14 -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -1)" ] && continue
      echo "$(du -sk "$j" 2>/dev/null | cut -f1) ${j#$ROOT/}"
    done | sort -rn | head -15 | awk '{k=$1; $1=""; printf "  %7.1f MB %s\n", k/1024, $0}' ;;
esac

if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  echo
  echo "== DOCKER (volumes can hold databases: report only, never pruned) =="
  docker system df 2>/dev/null | sed 's/^/  /'
fi
exit 0
