"""Lays levels/hollowfell's template (decision 790, 769's phases 2-3: the
hills' mine, Hollowfell, under the plateau's west face): the three anchors
every generation keeps, the rest rock. The mine generator
(sim/level_gen/mine.gd, through Regen) lays the tunnels, bays, galleries,
pits, seams, track, arches, beams, lamps and monsters between them each
generation.

- "mouth" (west edge): the link up to the hills and the "from_hills" spawn,
  the start, two lamps and an arch over its inner end; ground lying
  elsewhere is gathered here when the level is laid again ("keep_ground").
- "chamber_east": a wide chamber with beams and a cart on a short siding.
- "chamber_south": a chamber with two seams in its walls.

Run from the checkout: python -B tools/make_hollowfell.py. The anchors are
flat (every floor at FLOOR_LEVEL), so the template has no ledges.
"""
import json
import os

from PIL import Image

W, H = 96, 72
FLOOR_LEVEL = 3
GREY_PER_LEVEL = 40
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "start": (0x00, 0xFF, 0xFF),
    "lantern": (0xFF, 0xF0, 0xB0),
    "seam": (0xB8, 0x73, 0x33),
    "cart": (0x7A, 0x3C, 0xB4),
    "link": (0xFF, 0x00, 0xFF),
}
OUT = os.path.join("levels", "hollowfell")

MOUTH = (1, 29, 13, 12)
CHAMBER_EAST = (80, 20, 14, 10)
CHAMBER_SOUTH = (70, 56, 12, 10)


def main():
    floor = set()
    markers = {}
    decor = []

    def room(x0, y0, x1, y1, cut=()):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                if (x, y) not in cut:
                    floor.add((x, y))

    def lamp(cell, way):
        markers[cell] = "lantern"
        decor.append([cell[0], cell[1], way[0], way[1], "mine_lamp", 1])

    # The mouth: a rough chamber opening west onto the link (two cells to
    # the edge) and east onto the mine (five cells at the anchor's edge).
    room(2, 31, 12, 38, cut={(2, 31), (3, 31), (12, 31), (2, 38), (11, 38), (12, 38)})
    room(13, 33, 13, 37)
    floor.update({(1, 34), (1, 35)})
    markers[(1, 34)] = "link"
    markers[(4, 35)] = "start"
    lamp((6, 31), (0, -1))
    lamp((8, 38), (0, 1))
    decor.append([13, 33, 0, 1, "mine_arch", 1])

    # chamber_east: 12 x 8, open west at its anchor's edge; beams north to
    # south every other line; a siding with buffers and the cart.
    room(81, 21, 92, 28, cut={(81, 21), (92, 21), (81, 28), (92, 28)})
    room(80, 23, 80, 26)
    for x in range(82, 92, 2):
        decor.append([x, 21, 0, 1, "mine_beam", 1])
    for x in range(84, 90):
        if x == 84:
            decor.append([x, 27, -1, 0, "mine_track", 3])
        elif x == 89:
            decor.append([x, 27, 1, 0, "mine_track", 3])
        else:
            decor.append([x, 27, 1, 0, "mine_track", 1])
    cart = (86, 27)
    markers[cart] = "cart"
    lamp((92, 24), (1, 0))
    lamp((87, 21), (0, -1))

    # chamber_south: 9 x 7, open north at its anchor's edge; two seams in
    # recesses of its east and south walls.
    # The seams sit inside the anchor's rect, its border rock, so no tunnel
    # dug outside it ever opens a recess.
    room(71, 57, 79, 63, cut={(71, 57), (79, 57), (71, 63), (79, 63)})
    room(73, 56, 77, 56)
    for seam in ((80, 60), (75, 64)):
        floor.add(seam)
        markers[seam] = "seam"
    lamp((71, 60), (-1, 0))
    lamp((78, 63), (0, 1))

    meaning = {cell: markers.get(cell, "stone") for cell in floor}
    layout = Image.new("RGB", (W * 2 - 1, H * 2 - 1), COLOURS["void"])
    heights = Image.new("RGB", (W * 2 - 1, H * 2 - 1), (0, 0, 0))
    grey = FLOOR_LEVEL * GREY_PER_LEVEL
    for (x, y), what in meaning.items():
        layout.putpixel((2 * x, 2 * y), COLOURS[what])
        heights.putpixel((2 * x, 2 * y), (grey, grey, grey))
    # Between two plain floor cells their ground, as LevelMap.to_image does.
    for (x, y), what in meaning.items():
        if what != "stone":
            continue
        if meaning.get((x + 1, y)) == "stone":
            layout.putpixel((2 * x + 1, 2 * y), COLOURS["stone"])
        if meaning.get((x, y + 1)) == "stone":
            layout.putpixel((2 * x, 2 * y + 1), COLOURS["stone"])
        if all(meaning.get(c) == "stone" for c in ((x + 1, y), (x, y + 1), (x + 1, y + 1))):
            layout.putpixel((2 * x + 1, 2 * y + 1), COLOURS["stone"])

    os.makedirs(OUT, exist_ok=True)
    layout.save(os.path.join(OUT, "layout.png"))
    heights.save(os.path.join(OUT, "height.png"))
    config = {
        "name": "Hollowfell",
        "outdoor": False,
        "ambient": 0.03,
        "depth": 1,
        "walls": "cave",
        "floors": "cave",
        "mass": "rock",
        "music": "music.barrow",
        "starts": [[4, 35]],
        "spawn_points": {"from_hills": [3, 34]},
        "links": [{"at": [1, 34], "to_map": "hills", "to_spawn": "from_hollowfell"}],
        # The siding's cart drawn as the mine's, along the track.
        "entities": [{"at": list(cart), "art": "prop.mine_cart", "facing": [1, 0]}],
        "decor": decor,
        "regenerate": {
            "generator": "mine",
            "every_days": 3,
            "entrance": "mouth",
            "keep_ground": "entrance",
            "anchors": [
                {"rect": list(MOUTH), "name": "mouth"},
                {"rect": list(CHAMBER_EAST), "name": "chamber_east"},
                {"rect": list(CHAMBER_SOUTH), "name": "chamber_south"},
            ],
            "monsters": {"imp": 4, "sneak": 3, "brute": 1},
            "bays": [4, 6],
            "galleries": [3, 5],
            "pits": [2, 3],
            "seams": [7, 10],
            "loops": 0.25,
        },
        "respawn_s": {"imp": 600, "sneak": 600, "brute": 900},
    }
    with open(os.path.join(OUT, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("hollowfell: %d anchor cells, %d decor rows" % (len(floor), len(decor)))


if __name__ == "__main__":
    main()
