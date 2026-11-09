"""Lays levels/boar_lair (780 amended (12), forest phase D: the boar king's
lair, enemy-ai's apex-lair rule): a thorn-roofed den in a forest thicket,
its one way out a link up to the forest.

- A ragged hollow about 22 cells across, walled by the thicket (walls
  "thicket", art-kit's swept wall.thicket; floors "thicket", its earth and
  leaf litter), roofed
  (indoors; the coordinator: no sky, 650 unchanged), lit plainly ("ambient")
  and through gaps in the bramble ("skylights", 797): one at the door, so
  the first meeting is fair (enemy-ai: sight reads the light), one over the
  den, two at the sides.
- The way in from the south: two cells wide (no one-cell walkways), the
  link at its foot, "from_forest" just inside, a trodden run along it.
- The den at the north, the "lair" place's "at" and "den": the boar king's
  bed, his marker (monster_boar_king) on it, held by Apex and never spawned
  as a level entity (as the old grey's; enemy-ai's "the boar king", maps'
  piece). Apex brings his sounder of three with him.
- An open middle (OPEN, 12 x 12: nothing laid in it, room for the king's
  charge); the wallows, bones and rooted-up ground round the edges.
- No den keeper (780 amended (16), before v0.1.209: no loose boar at the
  mouth beyond his sounder). KEEPERS stays for one, should one come back.
- The find at the east wallow's edge (CACHE_AT): what he rooted up, a
  prop.cache_pack (decision 599) on items' loot table boar_lair_cache.
- The "lair" place, "the boar's lair" (the zone's own name, named once,
  815), held by nobody, "explore": true (a first visit's float).

Run from the checkout: python -B tools/make_boar_lair.py. The same seed
makes the same level.
"""
import json
import math
import os
import random

from PIL import Image

W, H = 28, 28
SEED = 780
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "start": (0x00, 0xFF, 0xFF),
    "link": (0xFF, 0x00, 0xFF),
    "chest": (0x8C, 0x4A, 0x1C),
}
BOAR = "monster_boar"
KING = "monster_boar_king"
LEGEND = {BOAR: "#8b5a2b", KING: "#5a3214"}
OUT = os.path.join("levels", "boar_lair")

CENTRE = (14.0, 12.5)
RADII = (11.5, 10.5)
OPEN = (8, 8, 12, 12)  # x, y, w, h: kept clear
LINK = (13, 26)
WAY = [(x, y) for x in (13, 14) for y in range(20, 27)]
FROM_FOREST = (13, 24)
START = (14, 24)
DEN = (14, 5)
WALLOWS = [((10, 4), 1), ((18, 4), 2), ((5, 11), 1)]
KEEPERS = []  # 780 amended (16): no den keeper at the mouth (the coordinator: no loose boar beyond his sounder)
CACHE_AT = (17, 5)
CACHE = "boar_lair_cache"
NAME = "the boar's lair"
BONES = [((12, 3), 1), ((16, 3), 2), ((16, 22), 1)]
ROOTED = [(7, 6), (21, 8), (23, 13), (5, 16), (7, 20), (21, 19), (9, 22)]
SKYLIGHTS = [{"at": [14, 21], "radius": 2.0}, {"at": [14, 5], "radius": 2.5},
             {"at": [6, 13], "radius": 1.5}, {"at": [22, 13], "radius": 1.5}]


def hollow():
    """The hollow's cells: an ellipse whose rim wanders a cell in or out."""
    rng = random.Random(SEED)
    wobble = [rng.uniform(-0.06, 0.06) for _ in range(16)]
    cells = set()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            dx, dy = (x - CENTRE[0]) / RADII[0], (y - CENTRE[1]) / RADII[1]
            angle = math.atan2(dy, dx) % (2 * math.pi)
            i = angle / (2 * math.pi) * 16
            a, b = wobble[int(i) % 16], wobble[(int(i) + 1) % 16]
            rim = 1.0 + a + (b - a) * (i - int(i))
            if math.hypot(dx, dy) <= rim:
                cells.add((x, y))
    return cells


def in_open(cell):
    x, y = cell
    return OPEN[0] <= x < OPEN[0] + OPEN[2] and OPEN[1] <= y < OPEN[1] + OPEN[3]


def main():
    floor = hollow() | set(WAY)
    markers = {LINK: "link", START: "start", CACHE_AT: "chest"}
    decor = []
    for cell, variant in WALLOWS:
        decor.append([cell[0], cell[1], 0, 1, "wallow", variant])
    for cell, variant in BONES:
        # A few scattered (scattered_bones) or a heap (the crypt's "bones").
        decor.append([cell[0], cell[1], 1, 0, "bones" if variant == 2 else "scattered_bones", 1])
    for i, cell in enumerate(ROOTED):
        way = [(0, 1), (1, 0), (0, -1), (-1, 0)][i % 4]
        decor.append([cell[0], cell[1], way[0], way[1], "rooted_ground", 1])
    for y in range(21, 27):
        decor.append([13, y, 0, 1, "trodden_run", 1])
    markers[DEN] = KING
    for cell in KEEPERS:
        markers[cell] = BOAR
    for row in decor:
        assert (row[0], row[1]) in floor and not in_open((row[0], row[1])), row
    for cell in list(markers) + [DEN, FROM_FOREST, CACHE_AT]:
        assert cell in floor, cell
    assert all((row[0], row[1]) != CACHE_AT for row in decor)

    colours = dict(COLOURS)
    for kind in LEGEND:
        colours[kind] = tuple(int(LEGEND[kind][i:i + 2], 16) for i in (1, 3, 5))
    meaning = {cell: markers.get(cell, "stone") for cell in floor}
    layout = Image.new("RGB", (W * 2 - 1, H * 2 - 1), COLOURS["void"])
    for (x, y), what in meaning.items():
        layout.putpixel((2 * x, 2 * y), colours[what])
    # Between two floor cells their ground, as LevelMap.to_image does.
    for (x, y) in meaning:
        if (x + 1, y) in meaning:
            layout.putpixel((2 * x + 1, 2 * y), COLOURS["stone"])
        if (x, y + 1) in meaning:
            layout.putpixel((2 * x, 2 * y + 1), COLOURS["stone"])
        if all(c in meaning for c in ((x + 1, y), (x, y + 1), (x + 1, y + 1))):
            layout.putpixel((2 * x + 1, 2 * y + 1), COLOURS["stone"])

    os.makedirs(OUT, exist_ok=True)
    layout.save(os.path.join(OUT, "layout.png"))
    config = {
        "name": "The boar's lair",
        "outdoor": False,
        "ambient": 0.3,
        "walls": "thicket",
        "floors": "thicket",
        "music": "none",
        "ambience": "thicket",
        "starts": [list(START)],
        "spawn_points": {"from_forest": list(FROM_FOREST)},
        "links": [{"at": list(LINK), "to_map": "forest", "to_spawn": "from_boar_lair"}],
        "legend": LEGEND,
        "skylights": SKYLIGHTS,
        "places": {"boar_lair": {"at": list(DEN), "kind": "lair", "radius": 10, "name": NAME,
                                 "holder": "nobody", "den": list(DEN), "explore": True}},
        "entities": [{"at": list(CACHE_AT), "art": "prop.cache_pack",
                      "props": {"cache": CACHE, "cache_place": NAME}}],
        "decor": decor,
        "respawn_s": {"boar": 6000},
    }
    with open(os.path.join(OUT, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("boar_lair: %d floor cells, %d decor rows, %d keepers" % (len(floor), len(decor), len(KEEPERS)))
    for y in range(H):
        print("".join("L" if (x, y) == LINK else "b" if (x, y) in KEEPERS else "K" if (x, y) == DEN else "c" if (x, y) == CACHE_AT
                      else "o" if (x, y) in floor and in_open((x, y)) else "." if (x, y) in floor else " "
                      for x in range(W)))


if __name__ == "__main__":
    main()
