"""Lays a building's inside as levels, a level per floor, from its spec
(levels/interiors/<building>.json; the tavern design's amendment, Jeff:
"probably, and allows multi floors, attics, rooms etc").

A spec names the building, its town, its wall and floor sets, its front door
(the floor, the room's cells inside it, the "side" of them it is in, south
if not said, and where it leads back out) and its floors. The front door is
a door in the wall (Jeff, 2026-11-06: "no door to exit. just a spot on the
ground"): a door edge from each of its cells to a doorstep cell outside
every room, the doorstep the link out, so one walks out through the door;
one arrives on its first cell, just inside. A floor has a level name, a size, an ambient light, its
rooms and its stairs:

- a room: an id, a use (USES), a rect; its doors, each the cells inside the
  room it opens from, the side it opens on and the room it leads "to"; a name
  if it is said mid-screen (Level.rooms_from; a hall or stair has none); what
  it holds ("beds", "holds" (stores drawn as decor: crates, barrels,
  sacks, with no hover and no click, since nothing openable gives nothing,
  Jeff), "hearth", "counter", "taps", "tables"). A common room's furniture
  (811 amended, art-kit's Mughouse pieces): its "hearth" the north or west
  cell of a fireplace two cells along a wall (both cells fire, the
  prop.wall_hearth over them as "wall" decor); its "counter" the west cell
  of a building.bar_counter three cells across, its front to the south,
  the taverner standing behind its middle; its "taps" the west cell of a
  building.tap_rack two across, its back to the north wall; its "tables"
  each the north-west cell of a building.tavern_table two by two (every
  other one laid, variant 2), a seat west of its top row and east of its
  bottom one. No piece on another, on a fire, a seat or a door's cell.
  With "candles" true (811 amended (4)), lit candles stand on each table's
  middle and the counter's (level.json "lit_candles", Level.lit_candles_from),
  each with a warm light of its own.
  A forge room (811 amended (2), Umbrage's smithy; art-kit's pieces) holds
  its "forge" (the west cell of a building.smithy_forge two across, its
  back to the north wall), its "anvil" (a prop.anvil, a cell, solid), its
  "trough" (a building.quench_trough), its "grindstone", its "bench" (the
  west cell of a building.smith_bench two across) and its "tool_wall" (a
  wall cell the smith's tools hang on, beside the west wall: variant 2, his
  tools gone, till the town has its smith), and "smith", the cell the smith
  works at, facing the anvil: the place "smithy", its "trade" "smith" and
  its "face" the anvil (npc's), named as the spec's place_name. A stores
  room's "heaps" are its ore, charcoal and iron bars in turn, lying on the
  floor (decor). No piece on another, on a door's cell or the smith's.
  Never a chest: chests are for dungeons only (Jeff, 2026-11-04). A
  player's storage at home is its own container piece (a strongbox,
  wardrobe or vault), and the locker is opened through a person.
- a stair: two cells side by side (the two-cell passages rule), the floor it
  reaches, the two cells beside it one arrives on from there, and its way
  ("up" or "down"), and its "facing" (north, south, west or east: the way its
  steps run, the link's own facing for its cue, Level.link_cues). Each cell
  is a link to the matching arrival on the other floor, whose stair back must
  be as wide. Never on the floor's south row, where the outer wall nearest
  the view hides it (811 amended (5)).

Every spec must make sense (the coordinator, 2026-11-04, with dungeon's
layout-sense rules) or nothing is written: every door leads into the room it
names, every room has a use, a hall joins two rooms or more, a room with one
way in holds something (a stair room holds its stair), and every room of
every floor is reached from the front door.

Run from the checkout: python -B tools/make_interior.py <building> [...]
(no name: every spec under levels/interiors).
"""
import json
import os
import sys

from PIL import Image

SPECS = os.path.join("levels", "interiors")
USES = ["common", "kitchen", "cellar", "room", "keeper", "attic", "hall", "stair", "forge", "stores"]
COLOURS = {
    "void": (0, 0, 0),
    "stone": (0x9A, 0x9A, 0x9A),
    "fire": (0xFF, 0x6A, 0x00),
    "wall": (0x3C, 0x2A, 0x22),
    "door": (0xC8, 0x8A, 0x3C),
    "start": (0x00, 0xFF, 0xFF),
    "link": (0xFF, 0x00, 0xFF),
}
SIDES = {"north": (0, -1), "south": (0, 1), "west": (-1, 0), "east": (1, 0)}
HOLDING = ["beds", "holds", "hearth", "counter", "taps", "tables", "forge", "heaps"]
# The stores a room's "holds" are drawn as, in turn (art-kit's prop.<kind>).
STORES = ["crate", "barrel", "sack"]
# The common room's pieces (Level.BUILDINGS' sizes, all solid, facing
# south): slot, cells across, cells deep.
TABLE = ("building.tavern_table", 2, 2)
COUNTER = ("building.bar_counter", 3, 1)
TAPS = ("building.tap_rack", 2, 1)
# A wall hearth's cells along its wall (prop.wall_hearth, 2.04 m wide).
HEARTH_WIDE = 2
# A common room's "candles" (811 amended (4), environment's numbers): lit
# prop.candles on each table's middle and the counter's, the metres up of the
# top they stand on and of their light over it.
TABLE_TOP = 0.79
COUNTER_TOP = 1.05
CANDLE_LIGHT_OVER_TABLE = 1.0
CANDLE_LIGHT_OVER_COUNTER = 1.4
# A table's candles a little softer and wider than the counter's, so a top
# keeps its grain (environment, from the stills): their light's energy, reach
# and falloff; the counter's are Client3D's own (CANDLE_ENERGY, _RANGE, _FALLOFF).
TABLE_CANDLE_LIGHT = {"energy": 0.9, "reach": 4.5, "falloff": 1.0}
# A forge room's pieces (811 amended (2), Level.BUILDINGS' sizes, all solid,
# facing south, their backs to the north): key -> (slot, across, deep).
FORGE_PIECES = {
    "forge": ("building.smithy_forge", 2, 1),
    "anvil": ("prop.anvil", 1, 1),
    "trough": ("building.quench_trough", 1, 1),
    "grindstone": ("building.grindstone", 1, 1),
    "bench": ("building.smith_bench", 2, 1),
}
# A stores room's "heaps", in turn (Level.DECOR_KINDS, flat).
HEAPS = ["heap_ore", "heap_charcoal", "stack_iron_bars"]
# The smith's tool wall while the town has no smith (art-kit's variant 2).
TOOLS_GONE = 2
# Godot imports a level's layout as an Image (Level._image), never a texture.
IMPORT = '[remap]\n\nimporter="image"\ntype="Image"\n'


class SpecError(Exception):
    pass


def cells_of(rect):
    x0, y0, w, h = rect
    return [(x, y) for y in range(y0, y0 + h) for x in range(x0, x0 + w)]


def bed_way(rect, cell):
    """The way a bed at [cell] lies with its head to the room's wall: the
    first of north, west, east, south whose step leaves the room while the
    cell behind (its foot) is inside it."""
    x0, y0, w, h = rect
    inside = lambda c: x0 <= c[0] < x0 + w and y0 <= c[1] < y0 + h
    for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
        if not inside((cell[0] + dx, cell[1] + dy)) and inside((cell[0] - dx, cell[1] - dy)):
            return (dx, dy)
    raise SpecError("the bed at %s is against no wall" % (cell,))


def hearth_cells(rect, cell):
    """A hearth at [cell]: its wall's step out of the room (north or west,
    as bed_way finds it) and its cells, [cell] and the next along that
    wall (south of it or east)."""
    way = bed_way(rect, cell)
    if way not in ((0, -1), (-1, 0)):
        raise SpecError("the hearth at %s is on no north or west wall" % (cell,))
    along = (abs(way[1]), abs(way[0]))
    cells = [(cell[0] + along[0] * i, cell[1] + along[1] * i) for i in range(HEARTH_WIDE)]
    x0, y0, w, h = rect
    if not all(x0 <= c[0] < x0 + w and y0 <= c[1] < y0 + h for c in cells):
        raise SpecError("the hearth at %s runs off its wall" % (cell,))
    return way, cells


def piece_cells(kind, at):
    _slot, across, deep = kind
    return [(at[0] + x, at[1] + y) for y in range(deep) for x in range(across)]


def furniture(room):
    """A common room's pieces [(kind, at, variant)], its hearth's fire
    cells and its seats."""
    pieces = []
    if room.get("counter"):
        pieces.append((COUNTER, room["counter"], 1))
    if room.get("taps"):
        pieces.append((TAPS, room["taps"], 1))
    for index, at in enumerate(room.get("tables", [])):
        pieces.append((TABLE, at, 1 + index % 2))
    fire = hearth_cells(room["rect"], room["hearth"])[1] if room.get("hearth") else []
    seats = []
    for x, y in room.get("tables", []):
        seats += [(x - 1, y), (x + TABLE[1], y + TABLE[2] - 1)]
    return pieces, fire, seats


def keeper_at(room):
    """Where the taverner stands: behind the counter's middle."""
    x, y = room["counter"]
    return [x + COUNTER[1] // 2, y - 1]


def furniture_faults(room):
    """A common room's furniture laid wrong: off the room, on another
    piece, a fire, a seat or a door's cell, or a seat or the taverner off
    the floor that is left."""
    faults = []
    try:
        pieces, fire, seats = furniture(room)
    except SpecError as e:
        return [str(e)]
    x0, y0, w, h = room["rect"]
    inside = lambda c: x0 <= c[0] < x0 + w and y0 <= c[1] < y0 + h
    doors = {tuple(c) for d in room.get("doors", []) for c in d["cells"]}
    taken = {}
    for kind, at, _variant in pieces:
        for cell in piece_cells(kind, at):
            if not inside(cell):
                faults.append("the %s at %s runs off the room at %s" % (kind[0], at, cell))
            elif cell in taken:
                faults.append("the %s at %s is on the %s at %s" % (kind[0], at, taken[cell], cell))
            elif cell in fire or cell in seats or cell in doors:
                faults.append("the %s at %s is on a fire, a seat or a door at %s" % (kind[0], at, cell))
            taken[cell] = kind[0]
    standing = seats + ([tuple(keeper_at(room))] if room.get("counter") else [])
    for cell in standing:
        if not inside(cell) or cell in taken or cell in fire:
            faults.append("%s, a seat or the taverner's, is off the floor" % (cell,))
    return faults


def forge_faults(room):
    """A forge room's pieces laid wrong: off the room, on another piece,
    a door's cell or the smith's; the smith off the floor that is left, or
    not beside the anvil; the tool wall on no wall."""
    faults = []
    x0, y0, w, h = room["rect"]
    inside = lambda c: x0 <= c[0] < x0 + w and y0 <= c[1] < y0 + h
    doors = {tuple(c) for d in room.get("doors", []) for c in d["cells"]}
    smith = tuple(room["smith"]) if room.get("smith") else None
    if smith is None or not room.get("anvil"):
        return ["a forge room with no \"smith\" or no \"anvil\""]
    taken = {}
    for key, kind in FORGE_PIECES.items():
        if not room.get(key):
            continue
        for cell in piece_cells(kind, room[key]):
            if not inside(cell):
                faults.append("the %s at %s runs off the room at %s" % (key, room[key], cell))
            elif cell in taken:
                faults.append("the %s at %s is on the %s at %s" % (key, room[key], taken[cell], cell))
            elif cell in doors or cell == smith:
                faults.append("the %s at %s is on a door or the smith at %s" % (key, room[key], cell))
            taken[cell] = key
    if not inside(smith) or smith in taken:
        faults.append("the smith's cell %s is off the floor" % (smith,))
    anvil = tuple(room["anvil"])
    if abs(smith[0] - anvil[0]) + abs(smith[1] - anvil[1]) != 1:
        faults.append("the smith at %s is not beside the anvil at %s" % (smith, anvil))
    if room.get("tool_wall"):
        try:
            bed_way(room["rect"], room["tool_wall"])
        except SpecError:
            faults.append("the tool wall at %s is on no wall" % (room["tool_wall"],))
    return faults


def spawn_name(from_level, index):
    return "from_%s_%d" % (from_level, index)


def check(spec):
    """The spec's faults, as lines; empty when it makes sense."""
    faults = []
    floors = {f["level"]: f for f in spec["floors"]}
    owner = {}  # (level, cell) -> room id
    for floor in spec["floors"]:
        level = floor["level"]
        w, h = floor["size"]
        for room in floor["rooms"]:
            if room.get("use") not in USES:
                faults.append("%s/%s: use %r is none of %s" % (level, room["id"], room.get("use"), USES))
            for cell in cells_of(room["rect"]):
                if not (0 <= cell[0] < w and 0 <= cell[1] < h):
                    faults.append("%s/%s: %s is off the floor" % (level, room["id"], cell))
                elif (level, cell) in owner:
                    faults.append("%s/%s: %s is %s's too" % (level, room["id"], cell, owner[(level, cell)]))
                else:
                    owner[(level, cell)] = room["id"]
    # Doors: each cell inside its room, the cell across its side inside "to".
    ways = {}  # (level, room) -> set of rooms or floors it opens to
    for floor in spec["floors"]:
        level = floor["level"]
        for room in floor["rooms"]:
            for door in room.get("doors", []):
                if len(door["cells"]) < 2:
                    faults.append("%s/%s: a door one cell wide (two-cell passages)" % (level, room["id"]))
                dx, dy = SIDES[door["side"]]
                for cell in door["cells"]:
                    cell = tuple(cell)
                    if owner.get((level, cell)) != room["id"]:
                        faults.append("%s/%s: door cell %s is not in the room" % (level, room["id"], cell))
                    across = (cell[0] + dx, cell[1] + dy)
                    if owner.get((level, across)) != door["to"]:
                        faults.append("%s/%s: the door at %s opens onto %s, not %s"
                                      % (level, room["id"], cell, owner.get((level, across)), door["to"]))
                ways.setdefault((level, room["id"]), set()).add(door["to"])
                ways.setdefault((level, door["to"]), set()).add(room["id"])
    # Stairs: two cells in a room, a stair back as wide on the floor reached.
    for floor in spec["floors"]:
        level = floor["level"]
        for stair in floor.get("stairs", []):
            if len(stair["cells"]) != 2 or len(stair["spawns"]) != 2:
                faults.append("%s: a stair to %s is not two cells with two arrivals" % (level, stair["to"]))
                continue
            rooms = {owner.get((level, tuple(c))) for c in stair["cells"] + stair["spawns"]}
            if None in rooms or len(rooms) != 1:
                faults.append("%s: the stair to %s is not inside one room (%s)" % (level, stair["to"], rooms))
            other = floors.get(stair["to"])
            back = [s for s in (other or {}).get("stairs", []) if s["to"] == level]
            if len(back) != 1:
                faults.append("%s: the stair to %s has %d stairs back" % (level, stair["to"], len(back)))
            # In sight (811 amended (5); Jeff: "no way to get down from the
            # 2nd floor"): a stair faces a way of its own, and never stands
            # on the floor's south row, where the outer wall nearest the
            # view hides it.
            if stair.get("facing") not in SIDES:
                faults.append("%s: the stair to %s has no \"facing\" (north, south, west or east)" % (level, stair["to"]))
            if any(c[1] == floor["size"][1] - 1 for c in stair["cells"]):
                faults.append("%s: the stair to %s stands on the south row, behind the near wall" % (level, stair["to"]))
            room = owner.get((level, tuple(stair["cells"][0])))
            ways.setdefault((level, room), set()).add("floor:" + stair["to"])
    # A hall joins two rooms or more; a room with one way in holds something.
    for floor in spec["floors"]:
        level = floor["level"]
        for room in floor["rooms"]:
            opens = ways.get((level, room["id"]), set())
            if room["use"] == "hall" and len([o for o in opens if not o.startswith("floor:")]) < 2:
                faults.append("%s/%s: a hall joining %d rooms" % (level, room["id"], len(opens)))
            for cell in room.get("beds", []):
                try:
                    bed_way(room["rect"], cell)
                except SpecError as e:
                    faults.append("%s/%s: %s" % (level, room["id"], e))
            if room["use"] == "common":
                faults += ["%s/%s: %s" % (level, room["id"], f) for f in furniture_faults(room)]
            if room["use"] == "forge":
                faults += ["%s/%s: %s" % (level, room["id"], f) for f in forge_faults(room)]
            holds = any(room.get(key) for key in HOLDING) or any(o.startswith("floor:") for o in opens)
            if len(opens) <= 1 and not holds and room["use"] not in ("common",):
                faults.append("%s/%s: a dead end holding nothing" % (level, room["id"]))
    # Every room reached from the front door; the door in a wall, its
    # doorstep outside every room.
    front = spec["front"]
    for cell in front["cells"]:
        step = doorstep(front, cell)
        if (front["floor"], tuple(cell)) not in owner:
            faults.append("the front door's cell %s is in no room" % (cell,))
        if (front["floor"], step) in owner:
            faults.append("the front door at %s opens into a room, not out of the building" % (cell,))
    start = (front["floor"], owner.get((front["floor"], tuple(front["cells"][0]))))
    seen = {start}
    todo = [start]
    while todo:
        level, room = todo.pop()
        for to in ways.get((level, room), set()):
            if to.startswith("floor:"):
                target = to[len("floor:"):]
                for stair in floors[target].get("stairs", []):
                    if stair["to"] == level:
                        nxt = (target, owner.get((target, tuple(stair["cells"][0]))))
                        if nxt not in seen:
                            seen.add(nxt)
                            todo.append(nxt)
            elif (level, to) not in seen:
                seen.add((level, to))
                todo.append((level, to))
    for floor in spec["floors"]:
        for room in floor["rooms"]:
            if (floor["level"], room["id"]) not in seen:
                faults.append("%s/%s: not reached from the front door" % (floor["level"], room["id"]))
    return faults


def doorstep(front, cell):
    """The cell outside the front door from [cell], on the door's side."""
    dx, dy = SIDES[front.get("side", "south")]
    return (cell[0] + dx, cell[1] + dy)


def lay(spec, floor):
    level = floor["level"]
    w, h = floor["size"]
    room_of = {}
    for room in floor["rooms"]:
        for cell in cells_of(room["rect"]):
            room_of[cell] = room["id"]
    markers = {}
    links = []
    spawns = {}
    starts = []
    front = spec["front"]
    steps = []
    if front["floor"] == level:
        for cell in front["cells"]:
            step = doorstep(front, cell)
            steps.append((tuple(cell), step))
            markers[step] = "link"
            links.append({"at": list(step), "to_map": front["to_map"], "to_spawn": front["to_spawn"]})
        # One arrives from the street just inside the door.
        inside = list(front["cells"][0])
        spawns[front["spawn"]] = inside
        starts.append(inside)
        for _cell, step in steps:
            w = max(w, step[0] + 1)
            h = max(h, step[1] + 1)
    for stair in floor.get("stairs", []):
        for index, cell in enumerate(stair["cells"]):
            markers[tuple(cell)] = "link"
            links.append({"at": list(cell), "to_map": stair["to"], "to_spawn": spawn_name(level, index), "cue": stair["way"],
                          "facing": list(SIDES[stair["facing"]])})
        for index, cell in enumerate(stair["spawns"]):
            spawns[spawn_name(stair["to"], index)] = list(cell)
    buildings = []
    decor = []
    lit_candles = []
    named = {}
    passages = {}
    places = {}
    beds = []
    for room in floor["rooms"]:
        for cell in room.get("beds", []):
            beds.append(list(cell) + list(bed_way(room["rect"], cell)))
        if room["use"] == "common":
            # The common room's furniture (811 amended): solid pieces, and
            # the hearth's two fire cells under its wall decor.
            pieces, fire, seats = furniture(room)
            for (slot, _across, _deep), at, variant in pieces:
                piece = {"slot": slot, "at": list(at)}
                if variant != 1:
                    piece["variant"] = variant
                buildings.append(piece)
            for cell in fire:
                markers[cell] = "fire"
            if room.get("hearth"):
                way, _cells = hearth_cells(room["rect"], room["hearth"])
                decor.append([room["hearth"][0], room["hearth"][1], way[0], way[1], "wall_hearth", 1])
            if room.get("candles"):
                # Lit candles (811 amended (4)): on each table's middle, where
                # its four cells meet, and on the middle of the counter's top.
                for x, y in room.get("tables", []):
                    lit_candles.append(dict({"at": [x + (TABLE[1] - 1) / 2, y + (TABLE[2] - 1) / 2], "top": TABLE_TOP,
                                             "up": CANDLE_LIGHT_OVER_TABLE}, **TABLE_CANDLE_LIGHT))
                if room.get("counter"):
                    x, y = room["counter"]
                    lit_candles.append({"at": [x + (COUNTER[1] - 1) / 2, y], "top": COUNTER_TOP,
                                        "up": CANDLE_LIGHT_OVER_COUNTER})
            if room.get("counter"):
                # The tavern (772's keys, Level.tavern_of): the taverner
                # behind the counter, a seat each side of every table; its
                # lore entry (lore's regions.json place) if the spec names one.
                places["tavern"] = {"at": keeper_at(room), "kind": "tavern", "radius": 1, "name": spec.get("place_name", "the tavern"),
                                    "rect": room["rect"], "seats": [list(c) for c in seats]}
                if spec.get("lore_id"):
                    places["tavern"]["lore_id"] = spec["lore_id"]
                if room.get("hearth"):
                    places["tavern"]["hearth"] = list(room["hearth"])
        if room["use"] == "forge":
            # The smithy's forge room (811 amended (2)): its solid pieces, the
            # tool wall hung beside its wall, and the place the smith works at.
            for key, (slot, _across, _deep) in FORGE_PIECES.items():
                if room.get(key):
                    buildings.append({"slot": slot, "at": list(room[key])})
            if room.get("tool_wall"):
                way = bed_way(room["rect"], room["tool_wall"])
                decor.append([room["tool_wall"][0], room["tool_wall"][1], way[0], way[1], "tool_wall", TOOLS_GONE])
            places["smithy"] = {"at": list(room["smith"]), "kind": "smithy", "radius": 1, "name": spec.get("place_name", "the smithy"),
                                "rect": room["rect"], "trade": "smith", "face": list(room["anvil"])}
            if spec.get("lore_id"):
                places["smithy"]["lore_id"] = spec["lore_id"]
        for index, cell in enumerate(room.get("heaps", [])):
            decor.append([cell[0], cell[1], 0, 1, HEAPS[index % len(HEAPS)], 1])
        for index, cell in enumerate(room.get("holds", [])):
            # Plain decor (Level.DECOR_KINDS, flat): never a Pushable crate.
            decor.append([cell[0], cell[1], 0, 1, STORES[index % len(STORES)], 1])
        entry = {"id": room["id"], "use": room["use"], "rect": room["rect"],
                 "doors": [{"to": d["to"], "cells": d["cells"], "side": d["side"]} for d in room.get("doors", [])]}
        for key in ("beds", "counter", "taps", "hearth"):
            if room.get(key):
                entry[key] = room[key]
        if room.get("name"):
            entry["name"] = room["name"]
            named[room["id"]] = entry
        else:
            passages[room["id"]] = entry
    if not starts:
        first = floor["stairs"][0]["spawns"][0]
        starts.append(list(first))
    doors = set()
    for room in floor["rooms"]:
        for door in room.get("doors", []):
            dx, dy = SIDES[door["side"]]
            for cell in door["cells"]:
                doors.add(frozenset({tuple(cell), (cell[0] + dx, cell[1] + dy)}))

    layout = Image.new("RGB", (w * 2 - 1, h * 2 - 1), COLOURS["void"])
    for (x, y) in room_of:
        layout.putpixel((2 * x, 2 * y), COLOURS[markers.get((x, y), "stone")])
    # The front door: a door edge from each cell to its doorstep, the link.
    for (x, y), (sx, sy) in steps:
        layout.putpixel((2 * sx, 2 * sy), COLOURS["link"])
        layout.putpixel((x + sx, y + sy), COLOURS["door"])
    for (x, y), room in room_of.items():
        for nx, ny, px, py in ((x + 1, y, 2 * x + 1, 2 * y), (x, y + 1, 2 * x, 2 * y + 1)):
            other = room_of.get((nx, ny))
            if other is None:
                continue
            if frozenset({(x, y), (nx, ny)}) in doors:
                layout.putpixel((px, py), COLOURS["door"])
            elif other != room:
                layout.putpixel((px, py), COLOURS["wall"])
            elif (x, y) not in markers and (nx, ny) not in markers:
                layout.putpixel((px, py), COLOURS["stone"])
    out = os.path.join("levels", level)
    os.makedirs(out, exist_ok=True)
    layout.save(os.path.join(out, "layout.png"))
    imported = os.path.join(out, "layout.png.import")
    if not os.path.exists(imported) or 'importer="image"' not in open(imported, encoding="utf-8").read():
        with open(imported, "w", encoding="utf-8", newline="\n") as f:
            f.write(IMPORT)
    config = {
        "name": floor["name"],
        "outdoor": False,
        "town": spec["town"],
        "building": spec["building"],
        "storeys": [f["level"] for f in spec["floors"]],
        "ambient": floor["ambient"],
        "walls": spec["walls"],
        "floors": spec["floors_set"],
        "starts": starts,
        "spawn_points": spawns,
        "links": links,
        "buildings": buildings,
        "decor": decor,
        "places": places,
        "beds": beds,
        "rooms": named,
        "passages": passages,
    }
    if lit_candles:
        config["lit_candles"] = lit_candles
    if spec.get("spots"):
        # Where its people stand and sit (Level.spots_from, the frozen-townsfolk mend): laid by hand
        # in the spec, written through as they are; Level checks them.
        config["spots"] = spec["spots"]
    with open(os.path.join(out, "level.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(config, f, indent="\t")
        f.write("\n")
    print("%s: %d cells, %d rooms, %d links" % (level, len(room_of), len(floor["rooms"]), len(links)))


def main(names):
    if not names:
        names = sorted(n[:-5] for n in os.listdir(SPECS) if n.endswith(".json"))
    failed = False
    for name in names:
        with open(os.path.join(SPECS, name + ".json"), encoding="utf-8") as f:
            spec = json.load(f)
        faults = check(spec)
        if faults:
            failed = True
            print("%s makes no sense, nothing written:" % name)
            for fault in faults:
                print("  " + fault)
            continue
        for floor in spec["floors"]:
            lay(spec, floor)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
