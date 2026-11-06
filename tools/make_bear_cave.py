"""Lays levels/bear_cave: the great bear's cave (the forest plan's phase B,
maps' sheet; enemy-ai's apex-lair rule; the coordinator's design). Its one
way out is the hills' cave mouth at (117, 102) (maps' make_hills writes that
side, "mouth": "cave").

A U, every leg 3 cells wide (the bear's body, two-cell rule well clear): in
from the mouth at the bottom edge going north, east along the bottom, north
up the east side, and west into the den chamber, so the den is out of sight
from the way in. The chamber is 14 x 13 open floor with its corners rounded
(the charge's straight run of 10, enemy-ai), the den cell 2+ clear all
round, its floor trampled (dirt) in a hollow round the den. Every cell not
dug is void, drawn as the rock mass ("mass": "rock"). A skylight over the
den (environment's "skylights") lights the fight. No door: the bear opens
none.

Run from the checkout: python -B tools/make_bear_cave.py. Same seed, same
level.
"""
import json
import os
import random

from PIL import Image

W, H = 22, 28
SEED = 780
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "dirt": (0x8A, 0x64, 0x40),
    "bear": (0x7A, 0x4A, 0x2A),
    "link": (0xFF, 0x00, 0xFF),
}
OUT = os.path.join("levels", "bear_cave")
# The den chamber (inclusive), the passage legs, the den, the mouth.
CHAMBER = (2, 2, 15, 14)
LEGS = [(3, 18, 5, 25), (3, 18, 19, 20), (17, 6, 19, 20), (15, 7, 17, 11)]
DEN = (6, 7)
LINK = (4, 26)
SPAWN = (4, 24)


def main():
    roll = random.Random(SEED)
    floor = {}

    def dig(x, y, kind="stone"):
        if 1 <= x < W - 1 and 1 <= y < H - 1:
            floor[(x, y)] = kind

    x0, y0, x1, y1 = CHAMBER
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            # Corners rounded: a cell's distance into a corner square.
            cx = min(x - x0, x1 - x)
            cy = min(y - y0, y1 - y)
            if cx + cy >= 2:
                dig(x, y)
    for ax, ay, bx, by in LEGS:
        for y in range(ay, by + 1):
            for x in range(ax, bx + 1):
                dig(x, y)
    # Rough sides: a cell dug here and there beside a leg or the chamber
    # (never taking one away, so no leg is under 3 across). Only where it
    # leaves no pocket (combat, from playtest's bear13 duel: a fighter boxed
    # in a corner): a dug cell with one open side is a dead-end nook, so it
    # is filled again until every rough cell opens on two sides or more.
    sides = ((1, 0), (-1, 0), (0, 1), (0, -1))
    rough = set()
    for cell in sorted(floor):
        for dx, dy in sides:
            near = (cell[0] + dx, cell[1] + dy)
            if near not in floor and roll.random() < 0.12:
                dig(*near)
                if near in floor:
                    rough.add(near)
    pocket = True
    while pocket:
        pocket = False
        for cell in sorted(rough):
            if cell in floor and sum((cell[0] + dx, cell[1] + dy) in floor for dx, dy in sides) < 2:
                del floor[cell]
                pocket = True
    # The trampled hollow round the den.
    for (x, y) in list(floor):
        if (x - DEN[0]) ** 2 + (y - DEN[1]) ** 2 <= 2.6 ** 2:
            floor[(x, y)] = "dirt"
    # The den 2+ clear all round.
    for y in range(DEN[1] - 2, DEN[1] + 3):
        for x in range(DEN[0] - 2, DEN[0] + 3):
            assert (x, y) in floor, (x, y)
    assert SPAWN in floor and LINK not in floor and (LINK[0], LINK[1] - 1) in floor
    floor[LINK] = "stone"  # Walked onto: the way out.

    # Two pixels a cell (Level's layout: a cell's top-left pixel, the rest
    # its edges, open in its own colour), a marker on its cell's pixel.
    image = Image.new("RGB", (W * 2, H * 2), COLOURS["void"])
    for (x, y), kind in floor.items():
        for px in (2 * x, 2 * x + 1):
            for py in (2 * y, 2 * y + 1):
                image.putpixel((px, py), COLOURS[kind])
    image.putpixel((DEN[0] * 2, DEN[1] * 2), COLOURS["bear"])
    image.putpixel((LINK[0] * 2, LINK[1] * 2), COLOURS["link"])
    os.makedirs(OUT, exist_ok=True)
    image.save(os.path.join(OUT, "layout.png"))

    config = {
        "name": "Bear cave",
        "outdoor": False,
        "depth": 1,
        "walls": "cave",
        "floors": "cave",
        "mass": "rock",
        "ambient": 0.03,
        "music": "none",
        "ambience": "cave_lair",
        "starts": [list(SPAWN)],
        "spawn_points": {"from_hills": list(SPAWN)},
        "links": [{"at": list(LINK), "to_map": "hills", "to_spawn": "from_bear_cave"}],
        "monsters": {"great_bear": {}},
        "legend": {"monster_great_bear": "#7a4a2a"},
        "skylights": [{"at": list(DEN), "radius": 3}],
    }
    with open(os.path.join(OUT, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("bear_cave: %d floor cells, den %s, link %s, spawn %s" % (len(floor), DEN, LINK, SPAWN))


if __name__ == "__main__":
    main()
