#!/bin/zsh
# Runs extras-clean.sh --apply against a throwaway home and checks the path guard. Touches nothing real.
set -u
S=$(mktemp -d); S=${S:A}; H="$S/h"; AS="$H/Library/Application Support"
mkdir -p "$H/Documents/keep" "$AS/Windsurf/Cache" "$AS/Windsurf/User" "$H/.cargo/registry/cache/x" "$H/Downloads"
echo data > "$AS/Windsurf/Cache/a"; echo keep > "$AS/Windsurf/User/settings.json"
echo keep > "$H/Documents/keep/f"; echo x > "$H/.cargo/registry/cache/x/c"; touch "$H/Downloads/a.crdownload"
ln -s "$H/Documents" "$H/.cargo/registry/src"
OUT=$(HOME="$H" zsh "${0:A:h}/../scripts/extras-clean.sh" --apply "$S/code" 2>&1)
fail=0; check() { eval "$2" || { echo "FAIL: $1"; fail=1; }; }
check "cache moved out"        '[ ! -e "$AS/Windsurf/Cache" ]'
check "cache is in the Trash"  '[ -n "$(find "$H/.Trash" -name a -type f)" ]'
check "settings kept"          '[ -f "$AS/Windsurf/User/settings.json" ]'
check "symlink refused"        '[[ $OUT == *"refused by path guard"* ]] && [ -L "$H/.cargo/registry/src" ]'
check "Documents untouched"    '[ -f "$H/Documents/keep/f" ]'
check "downloads untouched"    '[ -e "$H/Downloads/a.crdownload" ]'
[ $fail = 0 ] && echo "all checks passed"
exit $fail
