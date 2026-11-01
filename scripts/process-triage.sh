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
