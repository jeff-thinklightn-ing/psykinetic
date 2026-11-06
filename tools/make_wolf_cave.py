"""Lays levels/wolf_cave (forest phase E: the wolves' cave, a pack's den
under a rock outcrop in the forest's west; enemy-ai's residents and layout,
the coordinator's find, light and deed): a small rock cave, one way out, a
link up to the forest.

- The mouth chamber (MOUTH): the way in from the forest at its foot, two
  cells wide; lit by a skylight so the pack's two watchers are plain.
- A short passage (PASSAGE, two wide, three long: short, so nobody holds
  it against a pack that circles) into the den.
- The den (DEN, about 12 x 12): a rock pillar in its middle (PILLAR, no
  floor) for the pack to circle round; dim (the level's "ambient"), one
  shaft of light by the pillar, never black; a torch a real help.
- The pack: four monster_wolf, two by the den cell within 3 to 4 cells, two
  in the mouth chamber as watchers (enemy-ai). An ordinary pack's den, not
  the old wolf's (the coordinator, on lore's fact: his pack is the hills'
  and foothills'), so the cave is open from the start.
- The find: a lost traveller's pack at the den's back behind the wolves, a
  cache (decision 599: each player searches it once; items' table), drawn
  prop.cache_pack. Bones of deer and boar the pack dragged in, as decor.
- The "lair" place "wolf_cave", "the wolves' cave" (lore), held by nobody,
  "explore": true (a first visit's Wayfaring float); enemy-ai's lair rule
  makes clearing it a deed. The wolves come back after "respawn_s" (6000,
  more than a game day).

Run from the checkout: python -B tools/make_wolf_cave.py. The same seed
makes the same level.
"""
import json
import os
import random

from PIL import Image

W, H = 32, 26
SEED = 781
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "start": (0x00, 0xFF, 0xFF),
    "link": (0xFF, 0x00, 0xFF),
    "chest": (0x8C, 0x4A, 0x1C),
}
WOLF = "monster_wolf"
LEGEND = {WOLF: "#6e6e78"}
OUT = os.path.join("levels", "wolf_cave")

MOUTH = (3, 14, 8, 7)  # x, y, w, h
WAY = [(x, y) for x in (6, 7) for y in range(21, 25)]
LINK = (6, 24)
FROM_FOREST = (7, 22)
START = (6, 22)
PASSAGE = [(x, y) for x in (11, 12, 13) for y in (16, 17)]
DEN = (14, 7, 12, 12)
PILLAR = [(x, y) for x in (19, 20) for y in (12, 13)]
DEN_CELL = (24, 9)
WOLVES = [(21, 9), (24, 12), (5, 16), (9, 18)]
PACK = (25, 8)
BONES = [((22, 8), 2), ((17, 9), 1), ((24, 17), 1), ((15, 15), 1), ((4, 19), 1)]
SKYLIGHTS = [{"at": [7, 17], "radius": 2.5}, {"at": [21, 14], "radius": 1.5}]
CACHE = "wolf_cave_cache"
NAME = "the wolves' cave"


def rect_cells(rect):
    x0, y0, w, h = rect
    return {(x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h)}


def ragged(rect, rng, bites):
    """The rect less a few cells bitten from its rim: a cave's wall wanders."""
    cells = rect_cells(rect)
    x0, y0, w, h = rect
    rim = [c for c in cells if c[0] in (x0, x0 + w - 1) or c[1] in (y0, y0 + h - 1)]
    rim.sort()
    for cell in rng.sample(rim, bites):
        cells.discard(cell)
    for corner in ((x0, y0), (x0 + w - 1, y0), (x0, y0 + h - 1), (x0 + w - 1, y0 + h - 1)):
        cells.discard(corner)
    return cells


def main():
    rng = random.Random(SEED)
    floor = ragged(MOUTH, rng, 5) | ragged(DEN, rng, 9) | set(PASSAGE) | set(WAY)
    # The passage's ends and the way in stay open whatever the rim lost.
    floor |= {(10, 16), (10, 17), (14, 16), (14, 17), (6, 20), (7, 20)}
    floor -= set(PILLAR)
    markers = {LINK: "link", START: "start", PACK: "chest"}
    for cell in WOLVES:
        markers[cell] = WOLF
    decor = [[c[0], c[1], 1, 0, "bones", v] for c, v in BONES]
    for cell in list(markers) + [DEN_CELL, FROM_FOREST] + [(r[0], r[1]) for r in decor]:
        assert cell in floor, cell
    for skylight in SKYLIGHTS:
        assert tuple(skylight["at"]) in floor, skylight

    colours = dict(COLOURS)
    colours[WOLF] = tuple(int(LEGEND[WOLF][i:i + 2], 16) for i in (1, 3, 5))
    meaning = {cell: markers.get(cell, "stone") for cell in floor}
    layout = Image.new("RGB", (W * 2 - 1, H * 2 - 1), COLOURS["void"])
    for (x, y), what in meaning.items():
        layout.putpixel((2 * x, 2 * y), colours[what])
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
        "name": "The wolves' cave",
        "zone": "cave",
        "ambient": 0.22,
        "walls": "cave",
        "floors": "cave",
        "mass": "rock",
        "music": "none",
        "ambience": "cave_lair",
        "starts": [list(START)],
        "spawn_points": {"from_forest": list(FROM_FOREST)},
        "links": [{"at": list(LINK), "to_map": "forest", "to_spawn": "from_wolf_cave"}],
        "legend": LEGEND,
        "skylights": SKYLIGHTS,
        "places": {"wolf_cave": {"at": list(DEN_CELL), "kind": "lair", "radius": 12, "name": NAME,
                                 "holder": "nobody", "explore": True}},
        "entities": [{"at": list(PACK), "art": "prop.cache_pack",
                      "props": {"cache": CACHE, "cache_place": NAME}}],
        "decor": decor,
        "respawn_s": {"wolf": 6000},
    }
    with open(os.path.join(OUT, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("wolf_cave: %d floor cells, %d decor rows, %d wolves" % (len(floor), len(decor), len(WOLVES)))
    for y in range(H):
        print("%2d " % y + "".join("L" if (x, y) == LINK else "w" if (x, y) in WOLVES else "D" if (x, y) == DEN_CELL
                                   else "P" if (x, y) == PACK else "#" if (x, y) in PILLAR else "." if (x, y) in floor
                                   else " " for x in range(W)))


if __name__ == "__main__":
    main()
