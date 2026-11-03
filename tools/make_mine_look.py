"""Lays levels/mine_look (decision 769, phase 1: the mine's look test, Jeff:
"irregular walls, shafts that npcs can be knocked down, wood arch/rafters,
ore deposits, mine carts and tracks.. wide tunnels that interconnect and
twist and turn"). Not linked into the world: run it with --map=mine_look.

A small mine, 48 x 36 cells: an entrance chamber by the west edge (the
edge still), two tunnels east from it that twist and meet again past a
deep chamber (a loop), one narrowing to 3 cells, one widening to 5, a
shaft beside the north tunnel (floor three levels down: a knocked foe
falls), seams in recesses (a floor cell walled on three sides), track
with a cart on the south tunnel's straight, lamps, arches across the
tunnels where they run straight, beams over the chamber. Every cell not
dug is void, drawn as the rock mass ("mass": "rock", terrain's side).

Run from the checkout: python -B tools/make_mine_look.py, then
tools/trace_ledges.tscn for its "ledges" (decision 585: the shaft's rim).
Same seed, same level. A dev level (Level.DEV_LEVELS): no way reaches it.
"""
import json
import math
import os
import random

from PIL import Image

W, H = 48, 36
SEED = 769
FLOOR_LEVEL = 3
PIT_LEVEL = 0
GREY_PER_LEVEL = 40
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "start": (0x00, 0xFF, 0xFF),
    "lantern": (0xFF, 0xF0, 0xB0),
    "seam": (0xB8, 0x73, 0x33),
    "cart": (0x7A, 0x3C, 0xB4),
}
OUT = os.path.join("levels", "mine_look")
SIDES = [(1, 0), (-1, 0), (0, 1), (0, -1)]


def main():
    roll = random.Random(SEED)
    floor = set()
    height = {}

    def dig(cell, level=FLOOR_LEVEL):
        x, y = cell
        if 1 <= x < W - 1 and 1 <= y < H - 1:
            floor.add(cell)
            height[cell] = level

    def tunnel(points, widths):
        """A tunnel along [points], its width eased between [widths] (one a
        point), its sides roughened by the roll: never under 3 across."""
        for i in range(len(points) - 1):
            (ax, ay), (bx, by) = points[i], points[i + 1]
            wa, wb = widths[i], widths[i + 1]
            steps = max(1, int(math.hypot(bx - ax, by - ay) * 4))
            for s in range(steps + 1):
                t = s / steps
                cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
                radius = (wa + (wb - wa) * t) / 2.0 + roll.uniform(-0.15, 0.35)
                radius = max(radius, 1.5)
                for x in range(int(cx - radius) - 1, int(cx + radius) + 2):
                    for y in range(int(cy - radius) - 1, int(cy + radius) + 2):
                        if math.hypot(x - cx + 0.5, y - cy + 0.5) <= radius:
                            dig((x, y))

    def room(x0, y0, x1, y1):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                dig((x, y))

    # The entrance chamber by the west edge.
    room(2, 14, 8, 21)
    # The north tunnel: twisting, narrowing to 3 in its middle.
    tunnel([(8.5, 16.5), (13, 12), (19, 9.5), (25, 9.5), (30, 6.5), (36, 7.5), (40.5, 13)],
           [4, 4, 3, 3, 4, 4, 4])
    # The south tunnel: a straight run with the track, widening to 5.
    tunnel([(8.5, 20.5), (12, 26.5), (14, 28.5), (28, 28.5), (33, 27), (38, 25), (40.5, 22.5)],
           [4, 4, 4, 5, 5, 4, 4])
    # A cross tunnel between them (the loop's short way).
    tunnel([(22, 10.5), (21, 16), (23, 21), (22, 27.5)], [3, 3, 4, 4])
    # The deep chamber the tunnels meet at: 8 across for its beams.
    room(37, 14, 44, 21)

    # The shaft: beside the north tunnel's narrow middle, three levels down.
    pit = [(x, y) for x in range(17, 21) for y in (6, 7)]
    for cell in pit:
        floor.add(cell)
        height[cell] = PIT_LEVEL
    # Its rim: the tunnel cells beside it stay at the floor's level.

    # Seams: a void cell beside the tunnel, walled on its three other
    # sides, dug as a recess.
    seams = []
    wanted = [(5, 13), (16, 14), (27, 5), (30, 31), (36, 30), (45, 17), (24, 18), (11, 24)]
    for near in wanted:
        best = None
        for x in range(near[0] - 3, near[0] + 4):
            for y in range(near[1] - 3, near[1] + 4):
                cell = (x, y)
                if cell in floor or not (1 <= x < W - 1 and 1 <= y < H - 1):
                    continue
                opens = [(x + dx, y + dy) for dx, dy in SIDES if (x + dx, y + dy) in floor]
                if len(opens) != 1 or height.get(opens[0]) != FLOOR_LEVEL:
                    continue
                # Its diagonals void too, so the recess is a notch, not a bay.
                if any((x + dx, y + dy) in floor for dx in (-1, 1) for dy in (-1, 1)
                       if (x + dx, y + dy) != opens[0]):
                    pass
                d = abs(x - near[0]) + abs(y - near[1])
                if best is None or d < best[0]:
                    best = (d, cell)
        if best is not None and all(abs(best[1][0] - s[0]) + abs(best[1][1] - s[1]) > 2 for s in seams):
            dig(best[1])
            seams.append(best[1])

    def walled(cell, way):
        return (cell[0] + way[0], cell[1] + way[1]) not in floor

    # Track along the south tunnel's straight, on row 28, buffers at its ends.
    track_row = 28
    track = [(x, track_row) for x in range(15, 28) if (x, track_row) in floor]
    decor = []
    for i, cell in enumerate(track):
        if i == 0:
            decor.append([cell[0], cell[1], -1, 0, "mine_track", 3])
        elif i == len(track) - 1:
            decor.append([cell[0], cell[1], 1, 0, "mine_track", 3])
        else:
            decor.append([cell[0], cell[1], 1, 0, "mine_track", 1])
    cart = track[len(track) // 2 + 2]

    # Arches across the tunnels where they run straight: a span wall to wall,
    # 3 to 5 across, the same at the cells either side along the way.
    def span(cell, way, most=6):
        if not walled(cell, (-way[0], -way[1])):
            return None
        far = cell
        width = 1
        while not walled(far, way) and width <= most:
            far = (far[0] + way[0], far[1] + way[1])
            width += 1
        if not walled(far, way):
            return None
        return width, far

    in_room = lambda c: (2 <= c[0] <= 8 and 14 <= c[1] <= 21) or (37 <= c[0] <= 44 and 14 <= c[1] <= 21)
    arches = []
    for cell in sorted(floor, key=lambda c: (c[0], c[1])):
        if in_room(cell) or height[cell] != FLOOR_LEVEL or cell in seams:
            continue
        for way, along in (((0, 1), (1, 0)), ((1, 0), (0, 1))):
            here = span(cell, way)
            if here is None or not 3 <= here[0] <= 5:
                continue
            width = here[0]
            cells = [(cell[0] + way[0] * k, cell[1] + way[1] * k) for k in range(width)]
            if any(c in seams or height.get(c) != FLOOR_LEVEL for c in cells):
                continue
            straight = True
            for side in (-1, 1):
                other = (cell[0] + along[0] * side, cell[1] + along[1] * side)
                there = span(other, way) if other in floor else None
                if there is None or there[0] != width:
                    straight = False
            if not straight:
                continue
            if any(abs(cell[0] - a[0]) + abs(cell[1] - a[1]) < 6 for a in arches):
                continue
            arches.append(cell)
            decor.append([cell[0], cell[1], way[0], way[1], "mine_arch", 1])
    # Beams over the deep chamber, wall to wall, every other line, all one
    # way: west to east, else north to south.
    beams = 0
    for way, lines, first in (((1, 0), range(14, 22), lambda k: (37, k)), ((0, 1), range(37, 45), lambda k: (k, 14))):
        last = None
        for k in lines:
            cell = first(k)
            here = span(cell, way, 10)
            if here is None or not 3 <= here[0] <= 10 or (last is not None and k - last < 2):
                continue
            decor.append([cell[0], cell[1], way[0], way[1], "mine_beam", 1])
            last = k
            beams += 1
        if beams >= 3:
            break

    # Lamps: on a wall every 11 cells or so along the tunnels, and the rooms.
    lamps = []
    lights = []
    for cell in sorted(floor, key=lambda c: (c[1], c[0])):
        if height[cell] != FLOOR_LEVEL or cell in seams or cell in track or cell == cart:
            continue
        for way in SIDES:
            if walled(cell, way) and all(abs(cell[0] - l[0]) + abs(cell[1] - l[1]) >= 11 for l in lamps):
                lamps.append(cell)
                decor.append([cell[0], cell[1], way[0], way[1], "mine_lamp", 1])
                lights.append(cell)
                break

    start = (4, 18)
    markers = {start: "start", cart: "cart"}
    for cell in seams:
        markers[cell] = "seam"
    for cell in lights:
        if cell not in markers:
            markers[cell] = "lantern"

    layout = Image.new("RGB", (W * 2, H * 2), COLOURS["void"])
    heights = Image.new("RGB", (W * 2, H * 2), (0, 0, 0))
    for (x, y) in floor:
        grey = height[(x, y)] * GREY_PER_LEVEL
        for px in (2 * x, 2 * x + 1):
            for py in (2 * y, 2 * y + 1):
                layout.putpixel((px, py), COLOURS["stone"])
                heights.putpixel((px, py), (grey, grey, grey))
    for cell, marker in markers.items():
        layout.putpixel((cell[0] * 2, cell[1] * 2), COLOURS[marker])

    os.makedirs(OUT, exist_ok=True)
    layout.save(os.path.join(OUT, "layout.png"))
    heights.save(os.path.join(OUT, "height.png"))
    config = {
        "name": "Mine look test",
        "outdoor": False,
        "depth": 1,
        "walls": "cave",
        "floors": "cave",
        "mass": "rock",
        "music": "music.barrow",
        "starts": [list(start)],
        # The cart drawn as the mine's (art-kit's prop.mine_cart), along the
        # track: its front (+z) east.
        "entities": [{"at": list(cart), "art": "prop.mine_cart", "facing": [1, 0]}],
        "decor": decor,
    }
    # The ledges trace_ledges wrote (the shaft's rim) kept: run it again
    # after a change to the shaft.
    old_path = os.path.join(OUT, "level.json")
    if os.path.exists(old_path):
        with open(old_path, encoding="utf-8") as f:
            ledges = json.load(f).get("ledges")
        if ledges:
            config["ledges"] = ledges
    with open(os.path.join(OUT, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("mine_look: %d floor cells, %d pit, %d seams, %d arches, %d lamps, %d track"
          % (len(floor), len(pit), len(seams), len(arches), len(lamps), len(track)))


if __name__ == "__main__":
    main()
