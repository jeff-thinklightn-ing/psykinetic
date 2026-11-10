"""Adds free movement's measuring prints to a checkout, for playtest's lagged
pairs (the coordinator, 2026-11-10: every free-movement change is judged by
the lagged pair, classified, main against the branch). The prints are never
committed: patch a checkout, build and run, then undo. Run it with the
checkout's folder:

    python -I tools/stutter_log_patch.py <checkout>

Main and a branch take the same prints, so the counts compare like with like;
it refuses, saying which, if an anchor is not found exactly once. The prints
come only when the environment has PSY_STUTTER_LOG set (server and client):

  server, each blow's halt (World._halt_for_blow):
    [stutter] halt <name> tick <T> until <U>
  client, each correction of its own body (FreeNet.Own.confirm, fresh over
  0.02 cells: what Own.corrections counts, glided or shown at once), one line:
    [own] correction <size> tick <client tick> state <state tick>
      halt <state's halt byte, -1 on main> held <push/stun hold>
      at_once <error zeroed: shown at once> foe <cells from the server's
      centre to the nearest monster, -1 for none> pending <n>
      from <base before> to <base after>

Undo with `git checkout -- net/free_net.gd sim/world.gd` in the checkout.
"""
import sys
from pathlib import Path

NL = chr(10)
TAB = chr(9)
QUOTE = chr(34)

root = Path(sys.argv[1])


def insert_after(path: Path, anchor: str, lines: list[str]) -> None:
    s = path.read_text(encoding="utf-8")
    if "[stutter]" in s or "[own] correction" in s:
        print(f"{path}: already patched")
        return
    if s.count(anchor) != 1:
        raise SystemExit(f"{path}: anchor found {s.count(anchor)} times: {anchor!r}")
    at = s.index(anchor)
    end = s.index(NL, at) + 1
    path.write_bytes((s[:end] + "".join(line + NL for line in lines) + s[end:]).encode("utf-8"))
    print(f"{path}: patched")


def q(text: str) -> str:
    """A GDScript string literal."""
    return QUOTE + text + QUOTE


insert_after(root / "sim" / "world.gd",
    "func _halt_for_blow(entity: GridEntity, until_tick: int) -> void:",
    [TAB + "if OS.has_environment(" + q("PSY_STUTTER_LOG") + ") and free_body(entity):",
     TAB * 2 + "print(" + q("[stutter] halt %s tick %d until %d") + " % [entity.name, tick, until_tick])"])

# After the blend's choice (main: "error = off if off.length() < ...", the
# branch: "error = off if blends ..."): one line on either.
path = root / "net" / "free_net.gd"
blend = [line for line in path.read_text(encoding="utf-8").split(NL) if line.startswith(TAB * 3 + "error = off if ")]
if len(blend) != 1:
    raise SystemExit(f"{path}: the blend line found {len(blend)} times")
insert_after(path, blend[0], [
    TAB * 3 + "if fresh.length() > 0.02 and OS.has_environment(" + q("PSY_STUTTER_LOG") + "):",
    TAB * 4 + "var foe := -1.0",
    TAB * 4 + "for other: GridEntity in World.get_entities():",
    TAB * 5 + "if other is Monster and other.spawned and other.zone == entity.zone:",
    TAB * 6 + "var apart := Vector2(other.tile).distance_to(base)",
    TAB * 6 + "if foe < 0.0 or apart < foe:",
    TAB * 7 + "foe = apart",
    TAB * 4 + "print(" + q("[own] correction %.3f tick %d state %d halt %d held %s at_once %s foe %.2f pending %d from %s to %s") + " % [",
    TAB * 6 + "fresh.length(), World.tick, int(state[" + q("tick") + "]), int(state.get(" + q("halt") + ", -1)), overruled,",
    TAB * 6 + "error == Vector2.ZERO, foe, pending.size(), was, base])",
])
