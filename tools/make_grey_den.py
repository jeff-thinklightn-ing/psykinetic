"""Lays levels/grey_den: the old grey's den (780 amended (14); enemy-ai's
old wolf design, the coordinator's approval; lore's name), the old wolf's
lair in the foothills. Its one way out is the foothills' den mouth at
(97, 31), under the high scarp's west end, opening south (maps'
make_foothills writes that side, "mouth": "den").

- The way in (RUN): two wide, north from the link at the bottom edge, then
  one turn east (TURN, three wide where the pack turns), so the den can't be
  seen from the door.
- The den (DEN, 11 x 11, its corners rounded): a round earth chamber (dirt), room for a
  fight with five wolves; his bed (BED) at its back, the far corner from the
  way in.
- Markers: the old wolf (monster_old_wolf) at his bed, held by Apex and never
  spawned as a level entity (as the bear's); enemy-ai's landing brings his
  row, so it sets HIS_MARKER True then and reruns this (till then his bed is
  bare, the place's cell); two
  den keepers (monster_wolf, ordinary wolves) that stay when he goes out;
  they come back after "respawn_s" (6000, as the wolves' cave's).
- The find at the bed's foot (CACHE_AT): a hunter's pack (prop.cache_pack,
  decision 599), items' loot table grey_den_cache. Bones the pack dragged in,
  as decor; a heap by the bed. No spear: no item lies flat as decor yet.
- The "lair" place "grey_den", "the old grey's den" (lore), held by nobody,
  "explore": true (a first visit's Wayfaring float).

Run from the checkout: python -B tools/make_grey_den.py. The same seed makes
the same level.
"""
import json
import os
import random

from PIL import Image

W, H = 24, 24
SEED = 814
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "dirt": (0x8A, 0x64, 0x40),
    "start": (0x00, 0xFF, 0xFF),
    "link": (0xFF, 0x00, 0xFF),
    "chest": (0x8C, 0x4A, 0x1C),
}
WOLF = "monster_wolf"
OLD_WOLF = "monster_old_wolf"
HIS_MARKER = False
LEGEND = {WOLF: "#6e6e78", OLD_WOLF: "#b4b4be"} if HIS_MARKER else {WOLF: "#6e6e78"}
OUT = os.path.join("levels", "grey_den")

LINK = (4, 22)
FROM_FOOTHILLS = (4, 20)
START = (5, 20)
# North from the link two wide, the turn three wide, east two wide into the den's side.
RUN = [(x, y) for x in (4, 5) for y in range(11, 22)] + [(x, y) for x in range(7, 10) for y in (8, 9)]
TURN = [(x, y) for x in (4, 5, 6) for y in (8, 9, 10)]
DEN = (10, 2, 11, 11)  # x, y, w, h
BED = (18, 4)
CACHE_AT = (17, 5)
KEEPERS = [(14, 6), (17, 9)]
BONES = [((19, 6), 2), ((12, 4), 1), ((15, 11), 1), ((5, 16), 1), ((8, 9), 1)]
SKYLIGHTS = [{"at": [15, 7], "radius": 1.5}]
CACHE = "grey_den_cache"
NAME = "the old grey's den"


def main():
    rng = random.Random(SEED)
    floor = {}
    x0, y0, w, h = DEN
    # Round: a corner cell's distance in from both sides (as the bear's chamber).
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            cx = min(x - x0, x0 + w - 1 - x)
            cy = min(y - y0, y0 + h - 1 - y)
            if cx + cy >= 2:
                floor[(x, y)] = "dirt"
    for cell in RUN + TURN:
        floor[cell] = "stone"
    # Rough sides: a cell dug here and there beside the den (never taking one
    # away), only where it opens on two sides or more (no nook to be boxed in).
    sides = ((1, 0), (-1, 0), (0, 1), (0, -1))
    rough = set()
    for cell in sorted(floor):
        if floor[cell] != "dirt":
            continue
        for dx, dy in sides:
            near = (cell[0] + dx, cell[1] + dy)
            if near not in floor and 1 <= near[0] < W - 1 and 1 <= near[1] < H - 2 and rng.random() < 0.15:
                floor[near] = "dirt"
                rough.add(near)
    pocket = True
    while pocket:
        pocket = False
        for cell in sorted(rough):
            if cell in floor and sum((cell[0] + dx, cell[1] + dy) in floor for dx, dy in sides) < 2:
                del floor[cell]
                pocket = True
    floor[LINK] = "stone"
    markers = {LINK: "link", START: "start", CACHE_AT: "chest"}
    if HIS_MARKER:
        markers[BED] = OLD_WOLF
    for cell in KEEPERS:
        markers[cell] = WOLF
    decor = [[c[0], c[1], 1, 0, "bones" if v == 2 else "scattered_bones", 1] for c, v in BONES]
    for cell in list(markers) + [FROM_FOOTHILLS, BED] + [(r[0], r[1]) for r in decor]:
        assert cell in floor, cell
    for skylight in SKYLIGHTS:
        assert tuple(skylight["at"]) in floor, skylight
    # His bed 2+ clear all round, and no leg under two wide (two-cell rule).
    for y in range(BED[1] - 1, BED[1] + 2):
        for x in range(BED[0] - 1, BED[0] + 2):
            assert (x, y) in floor, (x, y)
    # The den out of sight from the door: no floor cell of the den on the link's column north of the turn.
    assert not any((LINK[0], y) in floor and floor[(LINK[0], y)] == "dirt" for y in range(H))

    colours = dict(COLOURS)
    for kind, hexed in LEGEND.items():
        colours[kind] = tuple(int(hexed[i:i + 2], 16) for i in (1, 3, 5))
    layout = Image.new("RGB", (W * 2 - 1, H * 2 - 1), COLOURS["void"])
    for (x, y), ground in floor.items():
        layout.putpixel((2 * x, 2 * y), colours[markers.get((x, y), ground)])
    for (x, y), ground in floor.items():
        if (x + 1, y) in floor:
            layout.putpixel((2 * x + 1, 2 * y), colours[ground])
        if (x, y + 1) in floor:
            layout.putpixel((2 * x, 2 * y + 1), colours[ground])
        if all(c in floor for c in ((x + 1, y), (x, y + 1), (x + 1, y + 1))):
            layout.putpixel((2 * x + 1, 2 * y + 1), colours[ground])

    os.makedirs(OUT, exist_ok=True)
    layout.save(os.path.join(OUT, "layout.png"))
    config = {
        "name": "The old grey's den",
        "zone": "cave",
        "depth": 1,
        "ambient": 0.2,
        "walls": "cave",
        "floors": "cave",
        "mass": "rock",
        "music": "none",
        "ambience": "cave_lair",
        "starts": [list(START)],
        "spawn_points": {"from_foothills": list(FROM_FOOTHILLS)},
        "links": [{"at": list(LINK), "to_map": "foothills", "to_spawn": "from_grey_den"}],
        "legend": LEGEND,
        "skylights": SKYLIGHTS,
        "places": {"grey_den": {"at": list(BED), "kind": "lair", "radius": 12, "name": NAME,
                                "holder": "nobody", "explore": True}},
        "entities": [{"at": list(CACHE_AT), "art": "prop.cache_pack",
                      "props": {"cache": CACHE, "cache_place": NAME}}],
        "decor": decor,
        "respawn_s": {"wolf": 6000},
    }
    with open(os.path.join(OUT, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("grey_den: %d floor cells, %d decor rows, %d keepers" % (len(floor), len(decor), len(KEEPERS)))
    for y in range(H):
        print("%2d " % y + "".join("L" if (x, y) == LINK else "w" if (x, y) in KEEPERS else "B" if (x, y) == BED
                                   else "P" if (x, y) == CACHE_AT else ":" if floor.get((x, y)) == "dirt"
                                   else "." if (x, y) in floor else " " for x in range(W)))


if __name__ == "__main__":
    main()
