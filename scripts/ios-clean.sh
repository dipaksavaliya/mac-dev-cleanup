#!/bin/zsh
# ios-clean.sh [--apply]: Xcode, iOS simulator, CocoaPods, SwiftPM, Carthage and React Native caches.
# Default: report sizes only. --apply: remove the SAFE tier (everything in it rebuilds itself).
# Never touches Archives (needed to symbolicate crash reports), simulator app data, or device backups.
set -u
setopt null_glob
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
D="$HOME/Library/Developer"
TMP="${TMPDIR:-/tmp}"
sz() { [ $# -eq 0 ] && { printf "%7.1f MB" 0; return; }; du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%7.1f MB", s/1024}'; }
safe() {  # safe <label> <skip-reason-or-empty> <paths...>
  local label=$1 why=$2; shift 2
  local s=$(sz "$@")
  if [ $# -eq 0 ]; then echo "  -     $s  $label (nothing there)"
  elif [ -n "$why" ]; then echo "  SKIP  $s  $label ($why)"
  elif [ $APPLY = 1 ]; then rm -rf "$@"; echo "  DONE  $s  $label"
  else echo "  SAFE  $s  $label"; fi
}

if ! command -v xcrun >/dev/null || ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools not found: nothing to clean."; exit 0
fi
FREE0=$(df -k / | tail -1 | awk '{print $4}')
BUILDING=""; ps -Ao command | grep -qE '[x]codebuild|[s]wift-frontend' && BUILDING="a build is running"
XCODE=""; pgrep -x Xcode >/dev/null && XCODE="Xcode is open: quit it first"
BOOTED=$(xcrun simctl list devices booted 2>/dev/null | grep -c Booted)
SIM=""; [ "$BOOTED" -gt 0 ] && SIM="$BOOTED simulator(s) booted: run 'xcrun simctl shutdown all' first"
METRO=""; pgrep -f '[m]etro|react-native start|expo start' >/dev/null && METRO="Metro bundler running"

echo "== SAFE tier (rebuilds itself) $([ $APPLY = 1 ] && echo '— applying' || echo '— report only, re-run with --apply') =="
safe "Xcode DerivedData (build products + index; next build is a full rebuild)" "${BUILDING:-$XCODE}" "$D"/Xcode/DerivedData/*(ND)
safe "Xcode caches" "$XCODE" "$HOME/Library/Caches/com.apple.dt.Xcode"(N)
safe "SwiftUI preview simulators" "$XCODE" "$D"/Xcode/UserData/Previews(N)
safe "Simulator dyld caches" "$SIM" "$D"/CoreSimulator/Caches/*(ND)

# Old device support: keep the most recently used OS version per platform (rebuilt when a device reconnects)
OLD=()
for P in "$D"/Xcode/*OS\ DeviceSupport(N/); do
  V=("$P"/*(N/om)); OLD+=("${V[@]:1}")
done
safe "Old iOS/watchOS/tvOS DeviceSupport (newest kept)" "" "${OLD[@]}"

# Simulators whose runtime is gone; simctl removes them and their data folders
UNAV=(${(f)"$(xcrun simctl list devices unavailable 2>/dev/null | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')"})
UDIRS=(); for U in "${UNAV[@]}"; do [ -d "$D/CoreSimulator/Devices/$U" ] && UDIRS+=("$D/CoreSimulator/Devices/$U"); done
if [ ${#UNAV} -eq 0 ]; then echo "  -     $(sz)  Unavailable simulators (none)"
elif [ $APPLY = 1 ]; then xcrun simctl delete unavailable && echo "  DONE  $(sz "${UDIRS[@]}")  ${#UNAV} unavailable simulators"
else echo "  SAFE  $(sz "${UDIRS[@]}")  ${#UNAV} unavailable simulators (xcrun simctl delete unavailable)"; fi

safe "CocoaPods download cache" "" "$HOME/Library/Caches/CocoaPods"(N)
# Only the cache: ~/Library/org.swift.swiftpm holds package-collection config and security fingerprints
safe "SwiftPM cache" "$BUILDING" "$HOME/Library/Caches/org.swift.swiftpm"(N)
safe "Carthage cache" "" "$HOME/Library/Caches/org.carthage.CarthageKit"(N)
safe "React Native Metro/Haste caches" "$METRO" "$TMP"/metro-*(N) "$TMP"/haste-map-*(N)

echo
echo "== ASK FIRST (not removed by --apply) =="
A=("$D"/Xcode/Archives/*/*.xcarchive(N))
echo "  $(sz "$D"/Xcode/Archives(N))  ${#A} Xcode archives: delete old ones in Xcode > Window > Organizer, only after their dSYMs are uploaded"
echo "  $(sz "$D"/CoreSimulator/Devices(N))  all simulator devices: 'xcrun simctl erase all' wipes every simulator's apps and data"
RT=$(xcrun simctl runtime list 2>/dev/null | grep -E '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')
if [ -n "$RT" ]; then
  echo "  simulator runtimes (remove unused ones with 'xcrun simctl runtime delete <id>'; Xcode > Settings > Components re-downloads):"
  print -r -- "$RT" | sed 's/^/      /'
else echo "  simulator runtimes: none installed as disk images"; fi
XS=(/Applications/Xcode*.app(N/))
(( ${#XS} > 1 )) && echo "  ${#XS} Xcode versions installed: ${XS[*]:t} (each 10+ GB; move unused ones to the Trash)"
echo
echo "== NEVER (user data) =="
echo "  $(sz "$HOME/Library/Application Support/MobileSync/Backup"(N))  iPhone/iPad backups: manage only in Finder > device > Manage Backups"

FREE1=$(df -k / | tail -1 | awk '{print $4}')
[ $APPLY = 1 ] && echo && echo "freed $(( (FREE1 - FREE0) / 1024 )) MB per df"
exit 0
