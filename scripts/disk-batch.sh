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
