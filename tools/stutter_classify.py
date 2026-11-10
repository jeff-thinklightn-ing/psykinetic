"""Sorts a run's own-body corrections by cause (the coordinator's, 2026-11-10),
from the lines tools/stutter_log_patch.py prints:

    python -I tools/stutter_classify.py <server log> <client log> [player name]

Each correction is put in one class, the first that fits:
  halt   its state's tick falls within a blow's halt of this player, from the
         halt's tick to its end plus SLACK ticks (the states that carry it back
         to the client), or its state says halted (the branch's halt byte)
  held   the server held the body (a push's slide, a stun): Own.held_by_server
  foe    a monster within FOE_CELLS of the server's centre
  other  the rest
Prints the count, total and largest per class, and the largest correction's class.
"""
import re
import sys
from collections import defaultdict

SLACK = 3
FOE_CELLS = 2.0

server_log, client_log = sys.argv[1], sys.argv[2]
who = sys.argv[3] if len(sys.argv) > 3 else None

halts = []
for line in open(server_log, encoding="utf-8", errors="replace"):
    m = re.search(r"\[stutter\] halt (\S+) tick (\d+) until (\d+)", line)
    if m and (who is None or m.group(1) == who):
        halts.append((int(m.group(2)), int(m.group(3))))

rows = []
for line in open(client_log, encoding="utf-8", errors="replace"):
    m = re.search(r"\[own\] correction ([\d.]+) tick (\d+) state (\d+) halt (-?\d+) held (\w+) at_once (\w+) foe (-?[\d.]+) pending (\d+)", line)
    if not m:
        continue
    size, state, halt = float(m.group(1)), int(m.group(3)), int(m.group(4))
    held, at_once, foe = m.group(5) == "true", m.group(6) == "true", float(m.group(7))
    if halt > 0 or any(start <= state <= until + SLACK for start, until in halts):
        kind = "halt"
    elif held:
        kind = "held"
    elif 0.0 <= foe <= FOE_CELLS:
        kind = "foe"
    else:
        kind = "other"
    rows.append((kind, size, state, foe, at_once))

by = defaultdict(list)
shown = defaultdict(int)
for kind, size, _state, _foe, at_once in rows:
    by[kind].append(size)
    shown[kind] += 1 if at_once else 0
print(f"{len(halts)} halts on the server, {len(rows)} corrections on the client")
for kind in ("halt", "held", "foe", "other"):
    sizes = by.get(kind, [])
    if sizes:
        print(f"  {kind:5s} {len(sizes):3d}, {sum(sizes):.2f} cells in all, the largest {max(sizes):.3f}, {shown[kind]} shown at once")
    else:
        print(f"  {kind:5s}   0")
if rows:
    kind, size, state, foe, _at_once = max(rows, key=lambda r: r[1])
    print(f"largest: {size:.3f} cells, {kind} (state tick {state}, nearest foe {foe:.2f} cells)")
