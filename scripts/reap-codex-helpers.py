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
