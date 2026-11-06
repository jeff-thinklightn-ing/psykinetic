extends RefCounted
## The "labyrinth" generator (decision 470): rooms and halls between a
## regenerating level's anchors, in one of two styles. The same contract as
## maze: static generate(template, config, seed) -> LevelMap, the anchors'
## cells, edges and heights the template's, the rest made here, the same
## seed the same map.
##
## "dwarven" (the halls under the castle's gatehouse: plain, heavy, built
## to last): rooms square-cut, a couple of great halls with a row of
## pillars, corridors straight with one bend, two cells wide between halls
## and anchors (or "ways" wide when the level says: five under the castle,
## 613), a door where a corridor meets a room, torches along the
## ways and inside the doors, alcoves off the rooms. "old" (the older
## labyrinths below, lore's third style): caverns grown from a seed cell,
## crooked ways by a walk biased toward where they go, blind ways wandering
## off into the rock, no doors, no torches (dark: lanterns matter). Both:
## the anchors and rooms are joined by a minimum spanning tree over their
## centres plus a share of extra ways for loops, then joined up wherever
## the anchors cut the map apart.
##
## The rules every dungeon is generated under (612, Jeff: "dungeons need
## procedural rule - whats different is just the arrangements"): a level's
## template is its arrangement, the fixed rooms (its anchors) and where
## they sit, and everything between comes from here. No passage is one
## cell wide (Tools.widen after the carving, Level.narrow_runs the check):
## a player, their companion and a second player pass each other; a
## doorway is a door edge in a room's wall, the one cell allowed, and the
## way outside it is as wide as any (no ring round a tomb narrows it); a
## dead end a cell deep (an alcove, a niche) may be one. A room with doors
## is walled where a way touches it (_wall_rooms), so its doors are its
## ways in.
##
## "barrow" (decision 541, Jeff's crypt page: tombs layered, the town's own
## near the top, the old dead below, oldest deepest): what each room is
## goes by its depth, the distance from the "entrance" anchor as a share of
## the farthest the map reaches (BANDS). Shallow: the town's tombs, square
## chambers with a door where a way comes in, torches by the doors and
## along the ways. Middle: passage graves, narrow and long, crooked ways in,
## no doors. Deep: the old caverns round the lair, no doors, no torches.
## Its niches are wall pieces (Regen.niches_of), never alcove cells (725).
## Chests go in the deepest blind ways' ends first; the dead, on open floor only (a
## cell with floor all round it and no wall edge of its own: never an
## alcove, a grave or a wall's foot; 631 amended), a third in each depth
## band, deepest first within a band (decision 631; layers with one band
## deepest first), monsters otherwise deepest first unless
## "near" sends a kind to an anchor (the robbers to the altar). Its ways
## are three cells wide (541 amended, Jeff: "way too cramped"), a brush
## along the path to a shallow tomb's door; the torches stand by the
## walls; the deep blind ways are short.
##
## Every style (725, Jeff: "the torches are always put in front of door
## ways. there are still too many 1 tile niches and 1 tile tight turns,
## often around doors. doors are still kind of small and narrow"): a door
## is two edges wide where the wall allows (_pair_doors; Client3D draws
## the pair as one door.double, World opens both), every floor cell outside
## the anchors stands in a clear 2 x 2 (Tools.clear_pinches; the test runs
## many seeds), alcoves and blind ways are two wide, and no torch stands
## on a door's cell or in its line (door_line).
##
## "tower" (decision 659, the tower's inside; Jeff: "The tower's inside
## shifts too"): a floor of a tower, each floor a small level of its own
## joined to the next by stair links kept in a shaft anchor at the same
## cells on every floor. The dwarven rules with no great halls: small
## square-cut rooms, ways two wide, a door where a way meets a room,
## torches (the cold lamps come with art-kit's piece), an alcove off some
## rooms; and a footprint: the block's "footprint" ("octagon" or "round",
## inscribed in the level's size, which is the template's; "square", the
## default, is the whole map) names the cells the generator may carve, and
## nothing is ever carved outside it (Tools.rock reads it from the map's
## extras), so the floor's outline is the tower's wall.
##
## The block's own keys (Level.regenerate_from passes them): "style"
## ("dwarven" unless "old", "barrow" or "tower"), "rooms": {"count": [lo, hi],
## "size": [[w, h] least, [w, h] most]}, "loops": the extra ways as a share
## of the nodes (0.2), "monsters": {kind: count} (brutes in the halls
## first, the rest in rooms and corridors), "chests": n (alcoves and blind
## ways first, then room corners), "crates": n (in rooms); barrow:
## "entrance": the anchor depth is counted from (the first unless named),
## "near": {kind: anchor name}, a kind laid nearest that anchor first;
## "layer" (580, the barrow in layers): 1 lays every room shallow (the
## town's tombs: square chambers with doors and torches, no bands, no
## caverns), 2 (the default) the tombs by depth, 3 every room deep (the
## dark caverns: crooked ways, no doors, no torches); "ways": how wide a
## way is carved, 3 (the default) or 5, an odd number of cells; "niches"
## (608, layer 1; Regen passes the template's top-level list): the first
## hall's niche edges, re-rolled and one of them made the hidden door each
## generation (niche_plan). The map returned carries the ways' cells in
## its extras as "paths" (647: Regen's decor roll keeps off them).

const Tools := preload("res://sim/level_gen/gen_tools.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLOOR := "stone"
const DEFAULT_COUNT: Array[int] = [6, 10]
const DEFAULT_LEAST := Vector2i(3, 3)
const DEFAULT_MOST := Vector2i(7, 7)
const DEFAULT_LOOPS := 0.2
## Great halls a dwarven level gets, when it has rooms enough.
const HALLS := 2
## A great hall's pillar blocks (2 x 2) sit this many cells apart (612: three clear between).
const PILLAR_PITCH := 5
## A torch every so many corridor cells, dwarven.
const TORCH_EVERY := 8
## How far a crooked way leans toward where it goes.
const LEAN := 0.65
## Barrow: the depth bands are Regen.BANDS, shared with the graves it writes.
## Barrow: a deep blind way is this long at most (541 amended; the old
## style's wander up to BLIND_LONG).
## 612: the rock between any two rooms, and from the anchors (two: a way
## squeezed between them is two wide).
const ROOM_GAP := 2
const BLIND_SHORT := 5
const BLIND_LONG := 10
## 608: the niche roll's own seed salt (the layout's rng is not touched),
## the share of the first hall's niches sealed with a slab (variant 2).
const NICHE_SALT := 0x6e1c4e
const NICHE_SLAB := 0.2


static func generate(template: LevelMap, config: Dictionary, seed: int) -> LevelMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchors := _set_in_rock(template, config.get("anchors", []))
	var style := str(config.get("style", "dwarven"))
	var old := style == "old"
	var map := template.copy()
	Tools.clear_outside(map, anchors)
	if style == "tower":
		# The tower's outline (659): the generator carves inside it alone.
		var inside := footprint(map.size, str(config.get("footprint", "square")))
		if not inside.is_empty():
			map.extras["footprint"] = inside
	_move_hidden(map, niche_plan(config, seed))
	var depth := _depth_setup(map, anchors, config) if style == "barrow" else {}
	var carved: Dictionary[Vector2i, bool] = {}
	var nodes := _anchor_nodes(template, anchors, depth)
	# An anchor with no way out into the rock (walled all round but for
	# another anchor: the barrow's hidden passage, the shortcut's nook) is
	# joined through its neighbour, never a node of its own.
	nodes = nodes.filter(func(node: Dictionary) -> bool: return _exit(map, template, anchors, node, node["centre"]) != null)
	var rooms := _place_rooms(map, anchors, config, old, rng, carved, depth)
	nodes.append_array(rooms)
	var corridors: Dictionary[Vector2i, bool] = {}
	# Barrow: the brush carves the way right up to a tomb's wall (612: no
	# ring narrows it to the door); _wall_rooms keeps the tomb shut but
	# for its door.
	# Dwarven (613, the Dwarven Halls): the same brush when the level names
	# "ways"; unsaid, its ways stay two wide as before.
	var brush := _brush_of(config) if style == "barrow" or config.has("ways") else 0
	var paths: Dictionary[Vector2i, bool] = {}
	# 806 (c), the hold: a trunk way from the entrance straight to the heart,
	# carved first (the spine rule: the walk at most 1.6 times the straight line).
	var trunk: Array = []
	if str(config.get("uses", "")) == "hold":
		var from := -1
		var to := -1
		for index in nodes.size():
			if nodes[index]["kind"] != "anchor":
				continue
			if nodes[index]["name"] == str(config.get("entrance", "")):
				from = index
			if nodes[index]["name"] == str(config.get("heart", "")):
				to = index
		if from >= 0 and to >= 0 and from != to:
			trunk = [from, to]
	var ways := _ways(nodes, config, rng)
	if not trunk.is_empty():
		ways.push_front(trunk)
	for way in ways:
		_carve_way(map, template, anchors, nodes[way[0]], nodes[way[1]], old, rng, carved, corridors, paths, depth, [], brush)
	var ends := _blind_ways(map, anchors, rooms, corridors, old, rng, carved, depth)
	# The width rule (612): rooms walled where a way touches them (their
	# alcoves stay theirs, a way through gets a door), then the map joined
	# up and every single-width run widened, into the ring outside a walled
	# room only when it must, and the rooms walled again where it did.
	var ring := _wall_rooms(map, rooms, ends, paths)
	Tools.join_up(map, anchors, carved)
	Tools.join_all(map, anchors, carved)
	var widened := Tools.widen(map, anchors, carved, ring)
	_wall_rooms(map, rooms, ends, paths, widened)
	# 725 (Jeff: "doors are still kind of small and narrow ... 1 tile tight
	# turns, often around doors"): every door two edges wide where it can
	# be, then every floor cell in a clear 2 x 2 (Tools.clear_pinches), never
	# into a walled room's ring; what that carved beside a room walled.
	# Nooks left (a cell the rock round a room's ring will not widen) are
	# filled (Tools.fill_nooks), and the clearing tried again on what that
	# leaves.
	var opened := _pair_doors(map, anchors, rooms, carved)
	var room_cells := {}
	for room in rooms:
		if not (room["doors"] as Array).is_empty():
			room_cells.merge(room["cells"])
	for pass_number in 3:
		var cleared := Tools.clear_pinches(map, anchors, carved, ring, room_cells)
		cleared.merge(opened)
		opened = {}
		if not cleared.is_empty():
			_wall_rooms(map, rooms, ends, paths, cleared)  # Never with none: an empty "only" walls every room again.
		if Tools.fill_nooks(map, anchors).is_empty() and cleared.is_empty():
			break
	if not old:
		_torches(map, anchors, rooms, corridors, depth, LIGHTS.get(style, "torch"))
	# 806 (c), the hold's rooms: a block with "uses": "hold" gives each room
	# its use and lays what it holds; the markers then lay what is left.
	var left := config
	if str(config.get("uses", "")) == "hold":
		left = _hold(map, anchors, rooms, nodes, config, rng)
	_markers(map, anchors, rooms, corridors, ends, left, rng, depth)
	map.extras["paths"] = paths
	return map


## What the generation lays besides cells and edges, for Regen to add to
## the generated level.json: {section: rows} (806 (c): the hold's
## buildings, decor, entities, carvings and laid_rooms; {} otherwise).
static func rows_of(map: LevelMap) -> Dictionary:
	return (map.extras.get("rows", {}) as Dictionary).duplicate(true)


## [param anchors] as the carving sees them: beside a niche-sized anchor
## (NICHE_MOST cells a side at most: the barrow's niche, "a niche in the
## wall", the lost runner's place), each cell of its ring not on an open
## side (a side whose edges are all walled) stays rock, a 1 x 1 anchor of
## the template's rock, so no way is carved round it and it stays set in the
## rock with only its mouth on the way (Jeff: "barrows still had some odd
## shaped rooms like a single file hallway around a room with a door"). The
## level's own anchors (Regen's) are as they were.
static func _set_in_rock(template: LevelMap, anchors: Array) -> Array:
	var out: Array = anchors.duplicate()
	for anchor: Variant in anchors:
		if not anchor is Dictionary:
			continue
		var rect: Rect2i = anchor["rect"]
		if rect.size.x > NICHE_MOST or rect.size.y > NICHE_MOST:
			continue
		var open := _open_sides(template, rect)
		for cell in Level.rect_cells(rect.grow(1)):
			if rect.has_point(cell):
				continue
			var side := Vector2i(signi(cell.x - clampi(cell.x, rect.position.x, rect.end.x - 1)),
				signi(cell.y - clampi(cell.y, rect.position.y, rect.end.y - 1)))
			if (side.x == 0 or side.y == 0) and open.has(side):
				continue  # Its mouth: the way comes up to it.
			out.append({"rect": Rect2i(cell, Vector2i.ONE), "name": ""})
	return out


## How many cells a side an anchor is at most to be set in the rock
## (_set_in_rock): a niche, never a hall.
const NICHE_MOST := 2


## The sides of [param rect] (unit steps) where any walkable cell of it on
## [param template] faces out through an edge that is not a wall.
static func _open_sides(template: LevelMap, rect: Rect2i) -> Dictionary:
	var open := {}
	for cell in Level.rect_cells(rect):
		if not template.walkable(cell):
			continue
		for direction in DIRECTIONS:
			if not rect.has_point(cell + direction) and template.edge(Terrain.edge_key(cell, direction)) != "wall":
				open[direction] = true
	return open


## The cells inside a tower's outline (659) for a level [param size] cells:
## "octagon", the map's rect with a cell of rim kept and each corner cut
## off along a diagonal about 0.29 of the shorter side in (a regular
## octagon's corner); "round", a disc of the shorter side's half less a
## cell about the middle; anything else {}, meaning the whole map. Nothing
## here assumes a size: the template's says it.
static func footprint(size: Vector2i, kind: String) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	if kind != "octagon" and kind != "round":
		return out
	var side := mini(size.x, size.y)
	var cut := roundi(0.29 * side)
	var centre := Vector2(size - Vector2i.ONE) * 0.5
	var radius := side * 0.5 - 1.0
	for y in range(1, size.y - 1):
		for x in range(1, size.x - 1):
			var inside: bool
			if kind == "octagon":
				var u := mini(x, size.x - 1 - x)
				var v := mini(y, size.y - 1 - y)
				inside = u + v >= cut + 1
			else:
				inside = Vector2(x, y).distance_to(centre) <= radius
			if inside:
				out[Vector2i(x, y)] = true
	return out


## Whether every cell of [param rect] lies inside the map's footprint (659),
## or the map has none.
static func _in_footprint(map: LevelMap, rect: Rect2i) -> bool:
	if not map.extras.has("footprint"):
		return true
	var inside: Dictionary = map.extras["footprint"]
	for cell in Level.rect_cells(rect):
		if not inside.has(cell):
			return false
	return true


# --- The hidden door (608) --------------------------------------------------------------

## The first hall's niches for a generation (608; layer 1 with the
## template's "niches" in [param config]): each [x, y, dx, dy, kind,
## variant] re-rolled, the town's dead in arches ("a") or hollows ("c"), a
## slab (variant 2) NICHE_SLAB of the time, and one of them picked as the
## hidden door ("hidden", variant 1), by its own rng from [param seed] and
## NICHE_SALT. {niches, before: the hall cell at the pick, alcove: the cell
## behind it, edge: the door's edge key, was_alcove and was_edge: the
## template's own hidden niche's, if it has one}; {} off layer 1 or with
## no niches listed.
static func niche_plan(config: Dictionary, seed: int) -> Dictionary:
	var listed: Variant = config.get("niches", [])
	if int(config.get("layer", 2)) != 1 or not listed is Array or (listed as Array).is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ NICHE_SALT
	var niches: Array = []
	var was := -1
	for entry: Variant in listed:
		if not entry is Array or (entry as Array).size() != 6:
			continue
		if str(entry[4]) == "hidden":
			was = niches.size()
		niches.append([int(entry[0]), int(entry[1]), int(entry[2]), int(entry[3]),
				"a" if rng.randf() < 0.5 else "c", 2 if rng.randf() < NICHE_SLAB else 1])
	if niches.is_empty():
		return {}
	var pick := rng.randi_range(0, niches.size() - 1)
	niches[pick][4] = "hidden"
	niches[pick][5] = 1
	var before := Vector2i(niches[pick][0], niches[pick][1])
	var step := Vector2i(niches[pick][2], niches[pick][3])
	var plan := {"niches": niches, "before": before, "alcove": before + step, "edge": Terrain.edge_key(before, step)}
	if was >= 0:
		var was_before := Vector2i(niches[was][0], niches[was][1])
		var was_step := Vector2i(niches[was][2], niches[was][3])
		plan["was_alcove"] = was_before + was_step
		plan["was_edge"] = Terrain.edge_key(was_before, was_step)
	return plan


## The hidden door moved on [param map] as [param plan] (niche_plan) says:
## the template's alcove filled with rock, its door edge and the walls
## round it cleared (the hall's wall stands there again), the pick's
## alcove carved with the link marker in it, a door edge between and walls
## on its other sides. The one change a generation makes inside the
## entrance anchor (465 keeps the rest verbatim).
static func _move_hidden(map: LevelMap, plan: Dictionary) -> void:
	if plan.is_empty():
		return
	if plan.has("was_alcove"):
		var was: Vector2i = plan["was_alcove"]
		map.set_cell(was, "void")
		for direction: Vector2i in DIRECTIONS:
			map.set_edge(Terrain.edge_key(was, direction), "clear")
	var alcove: Vector2i = plan["alcove"]
	map.set_cell(alcove, "link")
	for direction: Vector2i in DIRECTIONS:
		var key := Terrain.edge_key(alcove, direction)
		map.set_edge(key, "door" if key == plan["edge"] else "wall")


# --- Depth (barrow) -------------------------------------------------------------------

## The barrow's depth: {centre: the entrance anchor's centre, far: the
## farthest any cell of the map is from it}; {} for the other styles.
static func _depth_setup(map: LevelMap, anchors: Array, config: Dictionary) -> Dictionary:
	if anchors.is_empty():
		return {}
	var entrance: Dictionary = anchors[0]
	var wanted := str(config.get("entrance", ""))
	for anchor: Dictionary in anchors:
		if str(anchor.get("name", "")) == wanted:
			entrance = anchor
	var rect: Rect2i = entrance["rect"]
	var centre := rect.position + rect.size / 2
	var far := 1
	for corner: Vector2i in [Vector2i.ZERO, Vector2i(map.size.x - 1, 0), Vector2i(0, map.size.y - 1), map.size - Vector2i.ONE]:
		far = maxi(far, Tools.distance(centre, corner))
	var layer := int(config.get("layer", 2))
	return {"centre": centre, "far": far, "fixed_band": 0 if layer == 1 else (2 if layer == 3 else -1)}


## How far the brush reaches each side of a way's path: "ways" cells wide
## (3 unless said, 5 for the deep), so 1 or 2.
static func _brush_of(config: Dictionary) -> int:
	return clampi((int(config.get("ways", 3)) - 1) / 2, 1, 3)


## How deep [param point] lies, 0 at the entrance to 1 at the map's farthest
## reach; 0 outside the barrow style.
static func _depth_of(depth: Dictionary, point: Vector2i) -> float:
	if depth.is_empty():
		return 0.0
	return clampf(float(Tools.distance(depth["centre"], point)) / float(depth["far"]), 0.0, 1.0)


## The band [param point] lies in: 0 shallow, 1 middle, 2 deep.
static func _band_of(depth: Dictionary, point: Vector2i) -> int:
	if int(depth.get("fixed_band", -1)) >= 0:
		return int(depth["fixed_band"])  # 580: layer 1 all shallow, layer 3 all deep.
	var d := _depth_of(depth, point)
	return 0 if d < Regen.BANDS[0] else (1 if d < Regen.BANDS[1] else 2)


## [param cells] deepest first (ties by cell), a set order to draw from.
static func _deepest_first(depth: Dictionary, cells: Array[Vector2i]) -> Array[Vector2i]:
	var out := cells.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Tools.distance(depth["centre"], a)
		var db := Tools.distance(depth["centre"], b)
		return da > db if da != db else a < b)
	return out


## [param cells] nearest [param point] first (ties by cell).
static func _nearest_first(point: Vector2i, cells: Array[Vector2i]) -> Array[Vector2i]:
	var out := cells.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Tools.distance(point, a)
		var db := Tools.distance(point, b)
		return da < db if da != db else a < b)
	return out


# --- Nodes: anchors and rooms --------------------------------------------------------

## Each anchor as a node: {cells (its walkable cells), rect, centre, kind
## "anchor", doors: []}.
static func _anchor_nodes(template: LevelMap, anchors: Array, depth: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for anchor: Dictionary in anchors:
		var rect: Rect2i = anchor["rect"]
		var cells: Dictionary[Vector2i, bool] = {}
		for cell in Level.rect_cells(rect):
			if template.walkable(cell):
				cells[cell] = true
		var centre := rect.position + rect.size / 2
		out.append({"cells": cells, "rect": rect, "centre": centre, "kind": "anchor", "doors": [], "band": _band_of(depth, centre),
			"name": str(anchor.get("name", ""))})
	return out


## Rooms placed at random in the rock, ROOM_GAP cells of rock at least between
## any two and from the anchors and the map's edge: "count" of them (a
## draw between lo and hi), each "size" between least and most. Dwarven:
## rectangles, the first HALLS of them great halls (wider, a row of pillars
## down the middle, kind "hall"); old: caverns, a blob grown inside the
## rectangle. Each a node {cells, rect, centre, kind, doors}.
static func _place_rooms(map: LevelMap, anchors: Array, config: Dictionary, old: bool, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool], depth: Dictionary) -> Array[Dictionary]:
	var spec: Variant = config.get("rooms", {})
	if not spec is Dictionary:
		spec = {}
	var count_range: Variant = spec.get("count", DEFAULT_COUNT)
	var lo: int = int(count_range[0]) if count_range is Array and count_range.size() == 2 else DEFAULT_COUNT[0]
	var hi: int = int(count_range[1]) if count_range is Array and count_range.size() == 2 else DEFAULT_COUNT[1]
	var sizes: Variant = spec.get("size", [])
	var least := DEFAULT_LEAST
	var most := DEFAULT_MOST
	if sizes is Array and sizes.size() == 2 and Level._tile(sizes[0]) != null and Level._tile(sizes[1]) != null:
		least = Level._tile(sizes[0])
		most = Level._tile(sizes[1])
	least = least.max(Vector2i(2, 2))
	most = most.max(least)
	var count := rng.randi_range(mini(lo, hi), maxi(lo, hi))
	var taken: Array[Rect2i] = []
	for anchor: Dictionary in anchors:
		taken.append((anchor["rect"] as Rect2i).grow(ROOM_GAP))
	var rooms: Array[Dictionary] = []
	var barrow := not depth.is_empty()
	var tower := str(config.get("style", "")) == "tower"  # 659: small rooms only, no great hall in a tower's floor.
	var halls_wanted := HALLS if not old and not barrow and not tower and count >= 4 else 0
	for attempt in count * 40:
		if rooms.size() >= count:
			break
		var hall := rooms.size() < halls_wanted
		var size := Vector2i(rng.randi_range(least.x, most.x), rng.randi_range(least.y, most.y))
		if hall:
			size = Vector2i(rng.randi_range(most.x, most.x + 2), rng.randi_range(least.y + 1, least.y + 2))
			if rng.randf() < 0.5:
				size = Vector2i(size.y, size.x)
		# Barrow: where the room falls says what it is; a passage grave in
		# the middle band is narrow and long (a cell under the least wide,
		# up to four over the most long; 541 amended), a cavern below is
		# grown in a box two cells bigger each way than a tomb's.
		var band := 0
		if barrow:
			band = _band_of(depth, Vector2i(rng.randi_range(1, map.size.x - 2), rng.randi_range(1, map.size.y - 2)))
			if band == 1:
				size = Vector2i(rng.randi_range(maxi(least.x - 1, 2), least.x), rng.randi_range(most.y + 1, most.y + 4))
				if rng.randf() < 0.5:
					size = Vector2i(size.y, size.x)
			elif band == 2:
				size += Vector2i(2, 2)
		if size.x > map.size.x - 2 or size.y > map.size.y - 2:
			continue
		var rect := Rect2i(Vector2i(rng.randi_range(1, map.size.x - size.x - 1), rng.randi_range(1, map.size.y - size.y - 1)), size)
		var centre := rect.position + rect.size / 2
		if barrow and _band_of(depth, centre) != band:
			continue  # Fell in another band than it was shaped for.
		if not _in_footprint(map, rect):
			continue  # Outside the tower's outline (659).
		var clear := true
		for other in taken:
			if rect.intersects(other):
				clear = false
				break
		if not clear:
			continue
		var cells: Dictionary[Vector2i, bool] = {}
		if old or (barrow and band == 2):
			cells = _grow_cavern(rect, rng)
		else:
			for cell in Level.rect_cells(rect):
				if hall and _pillar(rect, cell):
					continue
				cells[cell] = true
		for cell: Vector2i in cells:
			Tools.carve(map, cell, carved)
		taken.append(rect.grow(ROOM_GAP))
		var kind := "hall" if hall else "room"
		if barrow:
			kind = ["room", "grave", "cavern"][band]
		rooms.append({"cells": cells, "rect": rect, "centre": centre, "kind": kind, "doors": [], "band": band, "name": ""})
	return rooms


## Whether [param cell] of a great hall [param rect] is a pillar: blocks
## two cells square on a grid five apart, two cells in from every wall
## (a row down a hall, a grid in a wider one), so no gap between them or
## to a wall is under two cells (612; before it, single cells every other
## cell left one-wide ways all through a hall).
static func _pillar(rect: Rect2i, cell: Vector2i) -> bool:
	var offset := cell - rect.position - Vector2i(2, 2)
	if offset.x < 0 or offset.y < 0 or offset.x % PILLAR_PITCH > 1 or offset.y % PILLAR_PITCH > 1:
		return false
	var block := offset - Vector2i(offset.x % PILLAR_PITCH, offset.y % PILLAR_PITCH) + Vector2i(2, 2)  # The block's near corner, from the room's.
	return block.x + 1 <= rect.size.x - 3 and block.y + 1 <= rect.size.y - 3


## A cavern grown from [param rect]'s middle: cells added beside cells it
## has, inside the rectangle, until it holds about two thirds of it.
static func _grow_cavern(rect: Rect2i, rng: RandomNumberGenerator) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	var centre := rect.position + rect.size / 2
	cells[centre] = true
	var edge: Array[Vector2i] = [centre]
	var wanted := maxi(rect.size.x * rect.size.y * 2 / 3, 3)
	var guard := 0
	while cells.size() < wanted and guard < wanted * 20:
		guard += 1
		var from: Vector2i = edge[rng.randi_range(0, edge.size() - 1)]
		var next := from + DIRECTIONS[rng.randi_range(0, 3)]
		if cells.has(next) or not rect.has_point(next):
			continue
		cells[next] = true
		edge.append(next)
	return cells


# --- Ways between them ---------------------------------------------------------------

## Which nodes are joined, as pairs of indices: a minimum spanning tree
## over the centres (Prim's, by walking distance), then "loops" extra
## ways as a share of the nodes, drawn among the shortest left over.
static func _ways(nodes: Array[Dictionary], config: Dictionary, rng: RandomNumberGenerator, trunk: Array = []) -> Array[Array]:
	var out: Array[Array] = []
	var n := nodes.size()
	if n < 2:
		return out
	var in_tree: Dictionary[int, bool] = {0: true}
	# A trunk (806 (c)): its two ends joined first, the tree grown from both.
	if trunk.size() == 2:
		in_tree = {int(trunk[0]): true, int(trunk[1]): true}
		out.append([int(trunk[0]), int(trunk[1])])
	while in_tree.size() < n:
		var best := -1
		var best_pair: Array = []
		for i: int in in_tree:
			for j in n:
				if in_tree.has(j):
					continue
				var d := Tools.distance(nodes[i]["centre"], nodes[j]["centre"])
				if best < 0 or d < best:
					best = d
					best_pair = [i, j]
		in_tree[best_pair[1]] = true
		out.append(best_pair)
	var loops := float(config.get("loops", DEFAULT_LOOPS))
	var extra := roundi(clampf(loops, 0.0, 1.0) * n)
	if extra <= 0:
		return out
	var rest: Array[Array] = []
	for i in n:
		for j in range(i + 1, n):
			if out.any(func(way: Array) -> bool: return way[0] == i and way[1] == j or way[0] == j and way[1] == i):
				continue
			rest.append([i, j, Tools.distance(nodes[i]["centre"], nodes[j]["centre"])])
	rest.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2] if a[2] != b[2] else [a[0], a[1]] < [b[0], b[1]])
	var pool := rest.slice(0, mini(rest.size(), extra * 2))
	Tools.shuffle(pool, rng)
	for way in pool.slice(0, mini(pool.size(), extra)):
		out.append([way[0], way[1]])
	return out


## A corridor from [param a] to [param b]: out of each through its exit
## nearest the other (_exit), straight with one bend (dwarven; two cells
## wide when neither end is a plain room) or a crooked walk (old), carved
## through the rock, never through an anchor. Dwarven rooms get a door on
## the edge the corridor comes in by, and remember the cell inside it.
## Barrow (541 amended), and dwarven with "ways" (613): the way is three
## (or "ways") cells wide, a brush along
## the path (which also rounds a crooked walk's kinks), except inside
## [param tomb_rings], the ring round each shallow tomb, so a tomb is
## entered by its one door cell; the path's own cells alone are
## corridor cells (torches, monsters and blind ways go by the centre).
static func _carve_way(map: LevelMap, template: LevelMap, anchors: Array, a: Dictionary, b: Dictionary, old: bool,
		rng: RandomNumberGenerator, carved: Dictionary[Vector2i, bool], corridors: Dictionary[Vector2i, bool], paths: Dictionary[Vector2i, bool],
		depth: Dictionary, tomb_rings: Array[Rect2i] = [], brush := 1) -> void:
	var exit: Variant = _exit(map, template, anchors, a, b["centre"])
	var entry: Variant = _exit(map, template, anchors, b, a["centre"])
	if exit == null or entry == null:
		return
	var from: Vector2i = exit[0] + exit[1]
	var to: Vector2i = entry[0] + entry[1]
	# Barrow: a way to or from anything below the shallow band is crooked
	# and has no door; the town's tombs near the top are cut square.
	var barrow := not depth.is_empty()
	var crooked: bool = old or (barrow and (int(a.get("band", 0)) > 0 or int(b.get("band", 0)) > 0))
	var path: Array[Vector2i]
	if crooked:
		path = _crooked(map, anchors, from, to, rng)
	else:
		path = Tools.l_path(from, to, rng.randf() < 0.5)
		if path.any(func(cell: Vector2i) -> bool: return Level.in_anchors(anchors, cell)):
			path = Tools.path_around(map, anchors, from, to)  # Round a walled anchor in the way.
	var brushed: bool = barrow or (not old and brush > 0)  # The brush: barrow, or dwarven with "ways" (613).
	var wide: bool = not old and not barrow and not brushed  # 612: two wide into a plain room too.
	var last := from
	for cell in path:
		paths[cell] = true  # Every cell it runs through, a room's too (612: a door there).
		_carve_corridor(map, anchors, cell, carved, corridors)
		if wide:
			# The cell beside it, across the way it runs.
			var step := cell - last
			var beside := cell + (Vector2i(0, 1) if step.x != 0 else Vector2i(1, 0))
			_carve_corridor(map, anchors, beside, carved, corridors)
		if brushed:
			_carve_brush(map, anchors, cell, carved, tomb_rings, brush)
		last = cell
	if not crooked:
		for end: Array in [[a, exit], [b, entry]]:
			var node: Dictionary = end[0]
			if node["kind"] == "anchor":
				continue  # Its border is the template's.
			var inside: Vector2i = end[1][0]
			map.set_edge(Terrain.edge_key(inside, end[1][1]), "door")
			node["doors"].append(inside)


## The cells within [param brush] of [param cell] carved (541 amended: a
## way three wide; 580: five on the deep), never the map's rim, an anchor,
## or a shallow tomb's ring [param tomb_rings] (its door cell alone leads
## in). Not corridor cells.
static func _carve_brush(map: LevelMap, anchors: Array, cell: Vector2i, carved: Dictionary[Vector2i, bool], tomb_rings: Array[Rect2i],
		brush := 1) -> void:
	# Ring by ring out from the path cell, a cell carved only beside one
	# already floor nearer in: a wider brush never leaves a cell cut off
	# behind a tomb's ring or an anchor's wall (580).
	for r in range(1, brush + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var at := cell + Vector2i(dx, dy)
				if at.x <= 0 or at.y <= 0 or at.x >= map.size.x - 1 or at.y >= map.size.y - 1 or not Tools.rock(map, anchors, at):
					continue
				if tomb_rings.any(func(ring: Rect2i) -> bool: return ring.has_point(at)):
					continue
				var joined := false
				for direction in DIRECTIONS:
					var near := at + direction
					if maxi(absi(near.x - cell.x), absi(near.y - cell.y)) < r and map.walkable(near) and not Level.in_anchors(anchors, near):
						joined = true
						break
				if joined:
					Tools.carve(map, at, carved)


static func _carve_corridor(map: LevelMap, anchors: Array, cell: Vector2i, carved: Dictionary[Vector2i, bool],
		corridors: Dictionary[Vector2i, bool]) -> void:
	if not Tools.rock(map, anchors, cell):
		return
	if map.cell(cell) == "void":
		corridors[cell] = true
	Tools.carve(map, cell, carved)


## Where [param node] is left toward [param toward]: [the cell inside, the
## direction out], the cell of its own whose next cell out is rock outside
## the node (and, for an anchor, an open edge of the template between) and
## nearest where the way goes; null if it has none.
static func _exit(map: LevelMap, template: LevelMap, anchors: Array, node: Dictionary, toward: Vector2i) -> Variant:
	var best: Variant = null
	var best_d := 0
	for cell in Tools.sorted_cells(node["cells"]):
		for direction in DIRECTIONS:
			var out := cell + direction
			if node["cells"].has(out) or (node["rect"] as Rect2i).has_point(out):
				continue
			if not Tools.rock(map, anchors, out):
				continue
			if node["kind"] == "anchor" and template.edge(Terrain.edge_key(cell, direction)) == "wall":
				continue
			var d := Tools.distance(out, toward)
			if best == null or d < best_d:
				best = [cell, direction]
				best_d = d
	return best


## A crooked way from [param from] to [param to]: each step toward where it
## goes with chance LEAN, else any way, never into an anchor; finished
## straight when the walk has wandered long enough.
static func _crooked(map: LevelMap, anchors: Array, from: Vector2i, to: Vector2i, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from]
	var at := from
	var limit := 6 * (Tools.distance(from, to) + 4)
	var steps := 0
	while at != to and steps < limit:
		steps += 1
		var d := to - at
		var direction: Vector2i
		if rng.randf() < LEAN and d != Vector2i.ZERO:
			if absi(d.x) > absi(d.y) or (absi(d.x) == absi(d.y) and rng.randf() < 0.5):
				direction = Vector2i(signi(d.x), 0)
			else:
				direction = Vector2i(0, signi(d.y))
		else:
			direction = DIRECTIONS[rng.randi_range(0, 3)]
		var next := at + direction
		if not map.in_bounds(next) or Level.in_anchors(anchors, next):
			continue
		at = next
		path.append(at)
	if at != to:
		path.append_array(Tools.path_around(map, anchors, at, to).slice(1))  # Round the anchors, never through.
	return path


## Each room of [param rooms] that has doors (a square-cut room or hall, a
## shallow tomb) walled where a way or another room touches its border
## without a door (612): a floor cell outside its rect beside a border
## cell gets a wall edge between, so its doors are its only ways in and a
## way carved along its side stays a way; its own alcoves ([param ends],
## the blind ways' cells) stay open to it, and a way that runs through it
## ([param paths], a path cell inside beside one outside) gets a door
## there, counted among its doors. A room with no door (a cavern, a passage
## grave) opens where it is touched, as before. With [param only], the
## cells the widening carved, those alone are looked at (a join-up's way
## in stays open). Returns the ring of rock cells outside every walled
## room, which the widening avoids.
static func _wall_rooms(map: LevelMap, rooms: Array[Dictionary], ends: Array[Vector2i], paths: Dictionary[Vector2i, bool],
		only: Dictionary[Vector2i, bool] = {}) -> Dictionary[Vector2i, bool]:
	var ring: Dictionary[Vector2i, bool] = {}
	for room in rooms:
		if (room["doors"] as Array).is_empty():
			continue
		var rect: Rect2i = room["rect"]
		for cell in Tools.sorted_cells(room["cells"]):
			for direction in DIRECTIONS:
				var out := cell + direction
				if rect.has_point(out) or out in ends or (not only.is_empty() and not only.has(out)):
					continue
				if not map.walkable(out):
					ring[out] = true
					continue
				var key := Terrain.edge_key(cell, direction)
				if map.edge(key) == "door":
					continue
				if paths.has(cell) and paths.has(out):
					map.set_edge(key, "door")
					room["doors"].append(cell)
				else:
					map.set_edge(key, "wall")
	return ring


## Every lone door into a room made two edges wide (725): the edge beside
## it along the room's wall, from the room cell beside its own to the cell
## beside the one outside, made a door too, on whichever side the room and
## the way go on (the outside cell carved from rock if it is not floor, off
## the rim and out of every anchor); a door with a door beside it already
## is left. Client3D draws each pair as one door.double (403's pairing) and
## World opens and shuts them together (World.door_partner). The cells it
## carved.
static func _pair_doors(map: LevelMap, anchors: Array, rooms: Array[Dictionary], carved: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, bool]:
	var opened: Dictionary[Vector2i, bool] = {}
	for room in rooms:
		var cells: Dictionary = room["cells"]
		for inside: Vector2i in Tools.sorted_cells(cells):
			for direction in DIRECTIONS:
				var outside := inside + direction
				if cells.has(outside) or map.edge(Terrain.edge_key(inside, direction)) != "door":
					continue
				var along := Vector2i(direction.y, direction.x)
				if map.edge(Terrain.edge_key(inside + along, direction)) == "door" or map.edge(Terrain.edge_key(inside - along, direction)) == "door":
					continue  # Already two wide.
				var best := Vector2i.ZERO
				for side: Vector2i in [along, -along]:
					var beside := outside + side
					if not cells.has(inside + side) or map.edge(Terrain.edge_key(outside, side)) != "clear":
						continue
					if map.walkable(beside):
						best = side
						break
					if best == Vector2i.ZERO and map.cell(beside) == "void" and Tools.rock(map, anchors, beside) \
							and beside.x > 0 and beside.y > 0 and beside.x < map.size.x - 1 and beside.y < map.size.y - 1:
						best = side
				if best == Vector2i.ZERO:
					continue
				if not map.walkable(outside + best):
					Tools.carve(map, outside + best, carved)
					opened[outside + best] = true
				map.set_edge(Terrain.edge_key(inside + best, direction), "door")
				room["doors"].append(inside + best)
	return opened


# --- Blind ways, torches, markers ------------------------------------------------------

## Ways that go nowhere, so the halls are never quite the same: dwarven,
## an alcove a cell deep off about half the rooms; old, a few crooked ways
## wandering off a corridor into the rock, four to ten cells, touching
## nothing. Returns their end cells (where a chest may sit).
static func _blind_ways(map: LevelMap, anchors: Array, rooms: Array[Dictionary], corridors: Dictionary[Vector2i, bool], old: bool,
		rng: RandomNumberGenerator, carved: Dictionary[Vector2i, bool], depth: Dictionary) -> Array[Vector2i]:
	var ends: Array[Vector2i] = []
	var barrow := not depth.is_empty()
	# Barrow: no alcove cells (725, Jeff: "too many 1 tile niches"): its
	# niches are wall pieces, the first hall's (608) and the Ossuary's cut
	# along its galleries (Regen.niches_of). Dwarven: a bay two cells wide
	# off about half the rooms, never a lone cell.
	if not old and not barrow:
		for room in rooms:
			if rng.randf() < 0.5:
				continue
			var wanted := 1
			var border: Array[Vector2i] = []
			var rect: Rect2i = room["rect"]
			for cell in Tools.sorted_cells(room["cells"]):
				if cell.x == rect.position.x or cell.y == rect.position.y or cell.x == rect.end.x - 1 or cell.y == rect.end.y - 1:
					border.append(cell)
			Tools.shuffle(border, rng)
			var placed := 0
			for cell in border:
				if placed >= wanted:
					break
				for direction in DIRECTIONS:
					var out := cell + direction
					if rect.has_point(out) or not _lonely(map, anchors, out, cell, carved):
						continue
					# Two wide (725): the bay's other cell beside it along the
					# wall, off a room cell too.
					var along := Vector2i(direction.y, direction.x)
					var pair := Vector2i(-1, -1)
					for side: Vector2i in [along, -along]:
						if room["cells"].has(cell + side) and _bay_cell(map, anchors, out + side, [out, cell + side]):
							pair = out + side
							break
					if pair == Vector2i(-1, -1):
						continue
					Tools.carve(map, out, carved)
					Tools.carve(map, pair, carved)
					ends.append(out)
					ends.append(pair)
					placed += 1
					break
		if not barrow:
			return ends
	# Old, and the barrow's deep band: crooked blind ways off the corridors.
	var starts := Tools.sorted_cells(corridors)
	if barrow:
		starts = starts.filter(func(cell: Vector2i) -> bool: return _band_of(depth, cell) == 2)
	if starts.is_empty():
		return _deepest_first(depth, ends) if barrow else ends
	for k in maxi(2, rooms.size() / 2):
		var at: Vector2i = starts[rng.randi_range(0, starts.size() - 1)]
		var direction := DIRECTIONS[rng.randi_range(0, 3)]
		var length := rng.randi_range(2, BLIND_SHORT) if barrow else rng.randi_range(4, BLIND_LONG)
		var last := at
		# Two wide (725): each cell of the walk with the one on its left.
		for step in length:
			if rng.randf() > 0.7:
				direction = DIRECTIONS[rng.randi_range(0, 3)]
			var next := last + direction
			if not _lonely(map, anchors, next, last, carved):
				break
			Tools.carve(map, next, carved)
			var beside := next + Vector2i(direction.y, -direction.x)
			if beside.x > 0 and beside.y > 0 and beside.x < map.size.x - 1 and beside.y < map.size.y - 1 					and map.cell(beside) == "void" and Tools.rock(map, anchors, beside):
				Tools.carve(map, beside, carved)
			last = next
		if last != at:
			ends.append(last)
	return _deepest_first(depth, ends) if barrow else ends


## Whether [param at] may be a bay's second cell (725): rock off the rim,
## in no anchor, touching nothing walkable but the cells in [param beside].
static func _bay_cell(map: LevelMap, anchors: Array, at: Vector2i, beside: Array) -> bool:
	if not Tools.rock(map, anchors, at) or map.walkable(at) or at.x == 0 or at.y == 0 or at.x == map.size.x - 1 or at.y == map.size.y - 1:
		return false
	for direction in DIRECTIONS:
		if map.walkable(at + direction) and not (at + direction) in beside:
			return false
	return true


## Whether [param at] is rock that touches nothing carved but [param from]
## (so carving it makes a dead end, not a loop), outside every anchor.
static func _lonely(map: LevelMap, anchors: Array, at: Vector2i, from: Vector2i, carved: Dictionary[Vector2i, bool]) -> bool:
	if not Tools.rock(map, anchors, at) or map.walkable(at) or at.x == 0 or at.y == 0 or at.x == map.size.x - 1 or at.y == map.size.y - 1:
		return false
	for direction in DIRECTIONS:
		var next := at + direction
		if next != from and (map.walkable(next) or Level.in_anchors(anchors, next)):
			return false
	return true


## The marker a style's lights are laid as, when not "torch" (659
## amended: the dark tower's cold lamps).
const LIGHTS := {"tower": "lamp_cold"}


## Dwarven light: a [param light] (a torch) by each doorway, and one every
## TORCH_EVERY corridor cells, never beside an anchor. 725 (Jeff: "the
## torches are always put in front of door ways"): never on a door's cell,
## within two of it along the wall, or straight in from it (door_line); a room's stands on a plain wall run inside it, the nearest
## clear one to its door, one for each doorway (a pair is one).
static func _torches(map: LevelMap, anchors: Array, rooms: Array[Dictionary], corridors: Dictionary[Vector2i, bool], depth: Dictionary, light := "torch") -> void:
	# Barrow: the town's tombs are lit, the shallow band alone.
	var barrow := not depth.is_empty()
	var kept := door_line(map)
	for room in rooms:
		if barrow and int(room["band"]) > 0:
			continue
		var lit: Dictionary[Vector2i, bool] = {}
		for door: Vector2i in room["doors"]:
			if lit.has(door):
				continue
			for direction in DIRECTIONS:
				lit[door + direction] = true  # Its pair's cell: one torch for both.
			var spot: Variant = _by_wall_near(map, room["cells"], door, kept)
			if spot != null and not _beside_anchor(anchors, spot):
				map.set_cell(spot, light)
				kept[spot] = true
	var i := 0
	for cell in Tools.sorted_cells(corridors):
		if barrow and _band_of(depth, cell) > 0:
			continue
		i += 1
		# Barrow: the way is three wide, so the torch stands by its wall.
		var spot := _by_wall(map, cell) if barrow else cell
		if i % TORCH_EVERY != 0 or map.cell(spot) != FLOOR or _beside_anchor(anchors, spot) or kept.has(spot):
			continue
		map.set_cell(spot, light)


## The cells no torch stands on (725): each door edge's two cells, the
## two cells either side of them along the door's wall, and one more
## straight in from the door on each side (its line, where the way through
## it runs).
static func door_line(map: LevelMap) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for key: Vector3i in map.edges:
		if map.edges[key] != "door":
			continue
		var sides := Terrain.edge_cells(key)
		var across: Vector2i = sides[1] - sides[0]
		var along := Vector2i(across.y, across.x)
		for at: Vector2i in [sides[0], sides[0] - across, sides[1], sides[1] + across]:
			out[at] = true
		for cell: Vector2i in sides:
			for step in [1, 2]:
				out[cell + along * step] = true
				out[cell - along * step] = true
	return out


## The floor cell of [param cells] (a room) nearest [param door] that
## touches a wall (a shut edge, or rock beside it) and is in no door's
## line ([param kept]); null if there is none.
static func _by_wall_near(map: LevelMap, cells: Dictionary, door: Vector2i, kept: Dictionary[Vector2i, bool]) -> Variant:
	var best: Variant = null
	var best_d := 0
	for cell: Vector2i in Tools.sorted_cells(cells):
		if kept.has(cell) or map.cell(cell) != FLOOR:
			continue
		var by_wall := false
		for direction in DIRECTIONS:
			var key := Terrain.edge_key(cell, direction)
			if map.edge(key) == "wall" or not map.walkable(cell + direction):
				by_wall = map.edge(key) != "door"
				if by_wall:
					break
		if not by_wall:
			continue
		var d := Tools.distance(cell, door)
		if best == null or d < best_d:
			best = cell
			best_d = d
	return best


## A floor cell beside [param cell] that touches rock (a wall to stand a
## torch by), else [param cell] itself.
static func _by_wall(map: LevelMap, cell: Vector2i) -> Vector2i:
	for direction in DIRECTIONS:
		var beside := cell + direction
		if map.cell(beside) != FLOOR:
			continue
		for further in DIRECTIONS:
			if not map.walkable(beside + further):
				return beside
	return cell


static func _beside_anchor(anchors: Array, cell: Vector2i) -> bool:
	for direction in DIRECTIONS:
		if Level.in_anchors(anchors, cell + direction):
			return true
	return false


## The markers the block asks for: "chests" on the blind ways' ends first,
## then room corners, then any room cell; "crates" in rooms; "monsters"
## {kind: count}, brutes in the great halls first, every kind in rooms and
## corridors after, never beside an anchor. A kind the legend has no colour
## for is skipped.
static func _markers(map: LevelMap, anchors: Array, rooms: Array[Dictionary], corridors: Dictionary[Vector2i, bool],
		ends: Array[Vector2i], config: Dictionary, rng: RandomNumberGenerator, depth: Dictionary) -> void:
	var barrow := not depth.is_empty()
	var room_cells: Array[Vector2i] = []
	var hall_cells: Array[Vector2i] = []
	var corners: Array[Vector2i] = []
	for room in rooms:
		var cells := Tools.sorted_cells(room["cells"])
		if room["kind"] == "hall":
			hall_cells.append_array(cells)
		else:
			room_cells.append_array(cells)
		var rect: Rect2i = room["rect"]
		for corner: Vector2i in [rect.position, Vector2i(rect.end.x - 1, rect.position.y), Vector2i(rect.position.x, rect.end.y - 1), rect.end - Vector2i.ONE]:
			if room["cells"].has(corner):
				corners.append(corner)
	var corridor_cells := Tools.sorted_cells(corridors)
	Tools.shuffle(room_cells, rng)
	Tools.shuffle(hall_cells, rng)
	Tools.shuffle(corners, rng)
	Tools.shuffle(corridor_cells, rng)
	# Barrow: the grave goods lie deepest (the niches deepest first, then
	# the deepest corners); the dead are spread a third to each depth band,
	# deepest first within a band (decision 631: six at the far end left the
	# Ossuary's first half empty), unless "near" sends a kind to an anchor
	# (the robbers to the altar) or the layer has one band (580: layers 1 and 3).
	if barrow:
		corners = _deepest_first(depth, corners)
		room_cells = _deepest_first(depth, room_cells)
	var chest_spots: Array[Vector2i] = ends.duplicate()
	chest_spots.append_array(corners)
	# 813 amended (4): nothing laid on the forge's plates or by its cart.
	var plated: Dictionary = map.extras.get("plate_cells", {})
	if not plated.is_empty():
		room_cells.assign(room_cells.filter(func(cell: Vector2i) -> bool: return not plated.has(cell)))
		corridor_cells.assign(corridor_cells.filter(func(cell: Vector2i) -> bool: return not plated.has(cell)))
		chest_spots.assign(chest_spots.filter(func(cell: Vector2i) -> bool: return not plated.has(cell)))
	chest_spots.append_array(room_cells)
	_lay(map, anchors, "chest", int(config.get("chests", 0)), chest_spots)
	_lay(map, anchors, "crate", int(config.get("crates", 0)), room_cells)
	var everywhere: Array[Vector2i] = room_cells.duplicate()
	everywhere.append_array(corridor_cells)
	Tools.shuffle(everywhere, rng)
	if barrow:
		# The dead stand on open floor alone (631 amended, dungeon's side;
		# Jeff on v0.1.172: "skeletons still spawning in niches"): never an
		# alcove, a grave or a cell along a wall.
		everywhere = _deepest_first(depth, everywhere.filter(func(cell: Vector2i) -> bool: return _open_floor(map, cell)))
	var counts: Variant = config.get("monsters", {})
	if not counts is Dictionary:
		return
	var near: Variant = config.get("near", {})
	var kinds: Array = counts.keys()
	kinds.sort()
	for kind: String in kinds:
		var spots: Array[Vector2i] = []
		if kind == "brute":
			spots.append_array(hall_cells)
		spots.append_array(everywhere)
		var sent: bool = barrow and near is Dictionary and near.has(kind)
		if sent:
			for anchor: Dictionary in anchors:
				if str(anchor.get("name", "")) == str(near[kind]):
					var rect: Rect2i = anchor["rect"]
					spots = _nearest_first(rect.position + rect.size / 2, spots)
		var count := int(counts[kind])
		var apart := int((config.get("apart", {}) as Dictionary).get(kind, 0)) if config.get("apart") is Dictionary else 0
		if barrow and not sent and int(depth.get("fixed_band", -1)) < 0:
			count -= _lay_by_band(map, anchors, "monster_" + kind, count, spots, depth, apart)
		_lay(map, anchors, "monster_" + kind, count, spots, apart)


## Whether [param cell] is open floor (631 amended, dungeon's side): floor
## with floor on all eight sides and no wall or door on its own four edges,
## so a body laid there stands clear of every wall, niche and grave.
static func _open_floor(map: LevelMap, cell: Vector2i) -> bool:
	if map.cell(cell) != FLOOR:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var near := cell + Vector2i(dx, dy)
			if near != cell and not map.walkable(near):
				return false
	for direction in DIRECTIONS:
		if map.edge(Terrain.edge_key(cell, direction)) != "clear":
			return false
	return true


## [param count] markers [param marker] on the first free floor cells of
## [param spots] (in their order), none beside an anchor; how many were laid.
## With [param apart] (the block's "apart": {kind: cells}; 714, dungeon's
## side (4), the coordinator: the band spread over the rooms), no marker
## within that many cells (Chebyshev) of another of its kind while any
## spot further off is left; then the nearer ones, as before.
static func _lay(map: LevelMap, anchors: Array, marker: String, count: int, spots: Array[Vector2i], apart := 0) -> int:
	if count <= 0 or not map.colours.has(marker):
		return 0
	var laid := 0
	var placed: Array[Vector2i] = []
	for cell: Vector2i in map.cells:
		if map.cells[cell] == marker:
			placed.append(cell)
	for gap in ([apart, 0] if apart > 0 else [0]):
		for cell in spots:
			if laid >= count:
				return laid
			if map.cell(cell) != FLOOR or _beside_anchor(anchors, cell):
				continue
			if gap > 0 and placed.any(func(other: Vector2i) -> bool: return maxi(absi(other.x - cell.x), absi(other.y - cell.y)) < gap):
				continue
			map.set_cell(cell, marker)
			placed.append(cell)
			laid += 1
	return laid


## The dead spread over the depth bands (decision 631): [param count]
## markers [param marker] a third to each of Regen.BANDS' three bands, the
## deeper bands taking the odd ones, each band's [param spots] deepest
## first; how many were laid (a band short of free cells lays fewer, and
## the caller lays the rest deepest first).
static func _lay_by_band(map: LevelMap, anchors: Array, marker: String, count: int, spots: Array[Vector2i], depth: Dictionary, apart := 0) -> int:
	var by_band: Array[Array] = [[], [], []]
	for cell in spots:
		by_band[_band_of(depth, cell)].append(cell)
	var laid := 0
	for band in 3:
		var share := count / 3 + (1 if band >= 3 - count % 3 else 0)
		var cells: Array[Vector2i] = []
		cells.assign(by_band[band])
		laid += _lay(map, anchors, marker, share, _deepest_first(depth, cells), apart)
	return laid


# --- The hold's rooms (806 (c)) ---------------------------------------------------------

## The uses a hold's rooms are given (806 (c), the coordinator's plan; Jeff:
## "no room should be empty"), by the walk from the "entrance" anchor: the
## first room a guardroom, the deepest a store, the armoury, the cold forge
## and the relief hall nearest the walk's middle; the first great hall a
## pillared hall, the second the relief hall when there is one; any room
## left over a guardroom (a rack, its set piece). Every chest stands by a
## guard; the armoury and store are wings (finds off the way, layout_sense).
const HOLD_USES: Array[String] = ["guardroom", "armoury", "cold_forge", "relief_hall", "store", "pillared_hall"]
## Enemy-ai's rooms (806 (c)): [use, kind, count, idle].
const HOLD_GUARDS: Array[Array] = [["armoury", "brute", 1, {"mode": "guard"}], ["store", "imp", 1, {"mode": "guard"}],
	["guardroom", "imp", 2, {"mode": "guard"}], ["cold_forge", "imp", 1, {"mode": "gather"}],
	["pillared_hall", "imp", 2, {"mode": "wander", "radius": 3}]]
## A chest's guard stands within this many cells of it.
const GUARD_NEAR := 3


## The hold (806 (c)): uses given, rooms furnished and lit, chests and
## their guards laid (map.extras["rows"]); the block's config with what is
## left for _markers (chests and monsters it laid taken off).
static func _hold(map: LevelMap, anchors: Array, rooms: Array[Dictionary], nodes: Array[Dictionary], config: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var plan := {"buildings": [], "decor": [], "entities": [], "carvings": [], "laid_rooms": [], "plates": [], "secrets": []}
	var start := Vector2i.ZERO
	var entrance := str(config.get("entrance", ""))
	for node in nodes:
		if node["kind"] == "anchor" and (entrance.is_empty() or node["name"] == entrance):
			start = node["centre"]
			break
	var walk := _walk_from(map, start)
	for index in rooms.size():
		var room := rooms[index]
		room["id"] = "room_%d" % (index + 1)
		var least := 1 << 30
		for cell: Vector2i in room["cells"]:
			least = mini(least, int(walk.get(cell, 1 << 30)))
		room["walk"] = least
	var heart := str(config.get("heart", ""))
	var spine: Array[Vector2i] = []
	var heart_rect := Rect2i()
	for node in nodes:
		if node["kind"] == "anchor" and node["name"] == heart:
			spine = _path_to(map, start, node["centre"])
			heart_rect = node["rect"]
	var off := _off_spine(map, spine)
	var steps := _room_steps(map, rooms, spine)
	for index in rooms.size():
		var room := rooms[index]
		var nearest := 1 << 30
		for cell: Vector2i in room["cells"]:
			nearest = mini(nearest, int(off.get(cell, 1 << 30)))
		room["off"] = nearest
		room["steps"] = int(steps.get(index, 99))
	_hold_uses(rooms)
	var kept := door_line(map)
	var chests := int(config.get("chests", 0))
	var left_monsters: Dictionary = (config.get("monsters", {}) as Dictionary).duplicate() if config.get("monsters") is Dictionary else {}
	var lines: Array = (config.get("carvings", []) as Array).duplicate()
	Tools.shuffle(lines, rng)
	var words := lines.filter(func(line: Variant) -> bool: return line is Dictionary and not str(line.get("cut", "")).is_empty())
	var looks := lines.filter(func(line: Variant) -> bool: return line is Dictionary and str(line.get("cut", "")).is_empty())
	var stores := rooms.filter(func(room: Dictionary) -> bool: return room["use"] == "store").size()
	var ordered := rooms.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) < int(b["walk"]))
	for room: Dictionary in ordered:
		var use: String = room["use"]
		var main: Variant = null
		if use == "guardroom":
			main = _against_wall(map, room, kept, "building.weapon_rack", 2, plan, 1)
		elif use == "armoury":
			main = _against_wall(map, room, kept, "building.weapon_rack", 2, plan, 2)
			_against_wall(map, room, kept, "building.weapon_rack", 2, plan, 2)
			if chests > 0 and _hold_chest(map, room, kept, str(config.get("armoury_cache", config.get("cache", ""))), plan):
				chests -= 1
		elif use == "cold_forge":
			main = _against_wall(map, room, kept, "building.set_cold_forge", 2, plan, 1)
			# 813 amended (4): the cold forge woken, two at once.
			if main != null:
				_coop_forge(map, room, kept, config, plan)
		elif use == "relief_hall":
			main = _on_wall(map, room, kept, "relief", plan, looks.pop_front() if not looks.is_empty() else {})
			if not words.is_empty():
				_on_wall(map, room, kept, "carving", plan, words.pop_front())
		elif use == "store":
			if chests > 0 and _hold_chest(map, room, kept, str(config.get("cache", "")), plan):
				chests -= 1
				main = room["chest"]
		elif use == "pillared_hall":
			if chests > 0 and stores < 2 and _hold_chest(map, room, kept, str(config.get("cache", "")), plan):
				chests -= 1
				main = room["chest"]
		# A room its piece fits nowhere in still holds something: a rack on
		# any wall that takes one, else a carving's look on its back wall.
		if main == null and not room.has("chest") and use != "relief_hall":
			main = _against_wall(map, room, kept, "building.weapon_rack", 2, plan, 1)
		if main == null and not room.has("chest") and int(room.get("things", 0)) == 0:
			main = _on_wall(map, room, kept, "relief", plan, {})
		if main is Vector2i:
			room["main"] = main
		# The coordinator: each use's main piece lit, so no room reads as a dark box.
		if main is Vector2i:
			var spot: Variant = _by_wall_near(map, room["cells"], main, kept)
			if spot != null and Tools.distance(spot, main) <= 4 and not _beside_anchor(anchors, spot):
				map.set_cell(spot, "torch")
				kept[spot] = true
	# Enemy-ai's guards: by the chest where the room has one, else on its
	# open floor; facing the room's door, or at the forge.
	var guard_done := {}
	# The heart's approach (the coordinator, 806 (c): the forge is a refuge,
	# its hoard the reward for the fight before it): an imp on guard by the
	# walk's last cells before the heart, facing back up the way.
	var approach_first := true
	for row: Array in HOLD_GUARDS:
		# The approach guard after the chests' own, before the rooms'.
		if approach_first and row[0] == "guardroom":
			approach_first = false
			if heart_rect.size != Vector2i.ZERO and int(left_monsters.get("imp", 0)) > 0:
				left_monsters["imp"] = int(left_monsters["imp"]) - _approach_guard(map, anchors, spine, heart_rect, plan)
				heart_rect = Rect2i()
		for room: Dictionary in ordered:
			if room["use"] != row[0] or guard_done.has(room["use"]):
				continue
			# Every store its guard; the other uses' first room alone.
			if room["use"] != "store":
				guard_done[room["use"]] = true
			var kind: String = row[1]
			var count := mini(int(row[2]), int(left_monsters.get(kind, 0)))
			var laid := _hold_guards(map, anchors, room, kind, count, row[3], plan)
			left_monsters[kind] = int(left_monsters.get(kind, 0)) - laid
	# A chest with no guard yet (a second store, a leftover): the nearest imp left.
	for room: Dictionary in ordered:
		if room.has("chest") and not room.get("guarded", false) and int(left_monsters.get("imp", 0)) > 0:
			left_monsters["imp"] = int(left_monsters["imp"]) - _hold_guards(map, anchors, room, "imp", 1, {"mode": "guard"}, plan)
	for anchor: Variant in config.get("anchors", []):
		if not anchor is Dictionary:
			continue
		var given: Variant = anchor.get("rect")
		var rect := Rect2i()
		if given is Rect2i:
			rect = given
		elif given is Array and given.size() == 4:
			rect = Rect2i(int(given[0]), int(given[1]), int(given[2]), int(given[3]))
		else:
			continue
		if true:
			var named := {"id": str(anchor.get("name", "")), "use": str(anchor.get("use", anchor.get("name", ""))),
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
			# An anchor the walk to the heart need not pass (the template's own
			# set piece, the ambush) is a wing of its own (the spine rule).
			if named["id"] != str(config.get("entrance", "")) and named["id"] != str(config.get("heart", "")):
				named["wing"] = named["id"]
			plan["laid_rooms"].append(named)
	for room: Dictionary in ordered:
		var cells: Array = []
		for cell in Tools.sorted_cells(room["cells"]):
			cells.append([cell.x, cell.y])
		var laid := {"id": room["id"], "use": room["use"], "cells": cells}
		# A find or a sight off the way is a wing (the coordinator, 806 (c)).
		if room["use"] in ["armoury", "store", "relief_hall"]:
			laid["wing"] = "finds"
		plan["laid_rooms"].append(laid)
	map.extras["rows"] = plan
	var left := config.duplicate()
	left["chests"] = chests
	left["monsters"] = left_monsters
	return left


# --- The cold forge woken (813 amended (4)) ------------------------------------------------

## The cold forge woken (813 amended (4), the coordinator's approval of
## coop_forge.md): the hold's second co-op room, 813's plates in the cold
## forge's room. A treadle bellows on a cell beside the forge and an iron
## lever on a cell against a far wall (FORGE_APART apart at least), held at
## once (World.plate_held, each FORGE_NEED kg at least: physics' "need", so
## an imp or an empty crate holds neither) wake the forge (Main's solve:
## the shutter's door opened for the generation; the client lights the
## forge from it). The shutter is a door on the edge into an alcove behind
## the wall beside the forge (a sealed store; its chest the block's
## "forge_cache", 808: each player's find, the latecomer's too). A cart a
## cell off the bellows, the cell past it free to push from: a lone
## player's stand-in. Written as level.json "plates" {id, kind "forge",
## cells, pieces, need, forge, door, room} and a "secrets" row of kind
## "mechanism" (voice's three clues, vague to plain; found once the set is
## solved, Main.secret_found). Laid only where the block says "coop_forge":
## true (the coordinator: off in play till art-kit's pieces and
## environment's flare are in, then switched on with a still). Whether it
## was laid.
const FORGE_APART := 3
const FORGE_NEED := 50
## How far from the forge the store may be when its own wall has no room.
const FORGE_STORE_NEAR := 6
const FORGE_CLUES: Array[String] = ["The forge is cold, but its bellows still look sound.",
	"There's an iron handle on the far wall, set like a lever.",
	"It would take one working the bellows and another holding the lever down, both at once."]
## The store's place line (lore: no "smith" a player reads).
const FORGE_PLACE := "the forge's sealed store"
static func _coop_forge(map: LevelMap, room: Dictionary, kept: Dictionary, config: Dictionary, plan: Dictionary) -> bool:
	var cache := str(config.get("forge_cache", ""))
	if not config.get("coop_forge", false) or cache.is_empty() or (plan["buildings"] as Array).is_empty():
		return false
	var forge: Dictionary = plan["buildings"].back()
	if str(forge.get("slot", "")) != "building.set_cold_forge":
		return false
	var rect: Rect2i = Level.building_rect(forge)
	var inward := Vector2i(int(forge["facing"][0]), int(forge["facing"][1]))
	var back := -inward
	var run := Vector2i(absi(back.y), absi(back.x))
	var lines := door_line(map)
	var cells: Dictionary = room["cells"]
	var free := func(cell: Vector2i) -> bool:
		return cells.has(cell) and map.cell(cell) == FLOOR and not lines.has(cell) and not rect.has_point(cell)
	var first := rect.position
	var last := rect.end - Vector2i.ONE
	# The store: in the forge's wall beside it, else (that wall backed by a
	# way) in the room's nearest other wall, FORGE_STORE_NEAR at most.
	var spots: Array = []
	for step in range(1, 5):
		for side: int in [1, -1]:
			spots.append([(last if side > 0 else first) + run * side * step, back])
	var others: Array = []
	for cell in Tools.sorted_cells(cells):
		for way in DIRECTIONS:
			if way != back and not cells.has(cell + way) and Tools.distance(cell, first) <= FORGE_STORE_NEAR:
				others.append([cell, way])
	others.sort_custom(func(a: Array, b: Array) -> bool: return Tools.distance(a[0], first) < Tools.distance(b[0], first))
	spots.append_array(others)
	for spot: Array in spots:
		var before: Vector2i = spot[0]
		var wall: Vector2i = spot[1]
		var alcove := before + wall
		if not free.call(before) or map.walkable(alcove) or map.edge(Terrain.edge_key(before, wall)) == "door" \
				or not _alcove_fits(map, alcove, before):
			continue
		var pair := _forge_pair(map, room, kept, rect, before, alcove, free)
		if pair.is_empty():
			continue
		map.set_cell(alcove, "chest")
		for direction in DIRECTIONS:
			map.set_edge(Terrain.edge_key(alcove, direction), "door" if alcove + direction == before else "wall")
		plan["entities"].append({"at": [alcove.x, alcove.y], "props": {"cache": cache, "cache_place": FORGE_PLACE}})
		map.set_cell(pair["cart"], "cart")
		var plates: Dictionary = map.extras.get("plate_cells", {})
		for cell: Vector2i in [before, pair["cart"], pair["from"], pair["bellows"], pair["lever"]]:
			kept[cell] = true
			plates[cell] = true
		map.extras["plate_cells"] = plates
		var bellows: Vector2i = pair["bellows"]
		var lever: Vector2i = pair["lever"]
		plan["plates"].append({"id": "forge", "kind": "forge", "cells": [[bellows.x, bellows.y], [lever.x, lever.y]],
			"pieces": ["bellows", "lever"], "need": FORGE_NEED, "forge": [rect.position.x, rect.position.y],
			"door": [before.x, before.y, wall.x, wall.y], "room": room["id"]})
		plan["secrets"].append({"id": "forge_mechanism", "kind": "mechanism", "plates": "forge", "room": room["id"],
			"clues": FORGE_CLUES.duplicate()})
		room["coop"] = true
		room["things"] = int(room.get("things", 0)) + 3
		return true
	return false


## The forge's bellows, lever and cart: the bellows on a free cell beside
## [param rect] (the forge), the end away from the store's [param before]
## first, with a cell off it for the cart and the one past that to push
## from; the lever on a free cell against a wall, out of [param kept], the
## farthest from the bellows and FORGE_APART at least: {bellows, lever,
## cart, from}, or {}.
static func _forge_pair(map: LevelMap, room: Dictionary, kept: Dictionary, rect: Rect2i, before: Vector2i, alcove: Vector2i,
		free: Callable) -> Dictionary:
	var ring: Array[Vector2i] = []
	for cell in Level.rect_cells(rect.grow(1)):
		if rect.has_point(cell) or (cell.x != clampi(cell.x, rect.position.x, rect.end.x - 1) and cell.y != clampi(cell.y, rect.position.y, rect.end.y - 1)):
			continue
		if free.call(cell) and cell != before:
			ring.append(cell)
	ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Tools.distance(a, before) > Tools.distance(b, before))
	var taken := [before, alcove]
	for bellows in ring:
		for direction in DIRECTIONS:
			var cart := bellows + direction
			var from := cart + direction
			if not free.call(cart) or not free.call(from) or cart in taken or from in taken:
				continue
			var best: Variant = null
			for cell in Tools.sorted_cells(room["cells"]):
				if not free.call(cell) or kept.has(cell) or cell in taken or cell in [bellows, cart, from]:
					continue
				var gap := cell - bellows
				if absi(gap.x) + absi(gap.y) < FORGE_APART or Tools.distance(cell, before) < 2:
					continue
				var walled := false
				for way in DIRECTIONS:
					walled = walled or (not map.walkable(cell + way) and not room["cells"].has(cell + way))
				if walled and (best == null or Tools.distance(cell, bellows) > Tools.distance(best, bellows)):
					best = cell
			if best != null:
				return {"bellows": bellows, "lever": best, "cart": cart, "from": from}
	return {}


## Whether [param alcove] is rock off the map's edge with no way beside it
## but [param before], the cell it opens off (the crypt's vault's test).
static func _alcove_fits(map: LevelMap, alcove: Vector2i, before: Vector2i) -> bool:
	if map.walkable(alcove) or alcove.x < 1 or alcove.y < 1 or alcove.x >= map.size.x - 1 or alcove.y >= map.size.y - 1:
		return false
	for direction in DIRECTIONS:
		var near := alcove + direction
		if near != before and map.walkable(near):
			return false
	return true


## Steps from [param start] over walkable floor, through doors, never
## through a wall edge.
static func _walk_from(map: LevelMap, start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		for direction in DIRECTIONS:
			var next := cell + direction
			if dist.has(next) or not map.walkable(next) or map.edge(Terrain.edge_key(cell, direction)) == "wall":
				continue
			dist[next] = int(dist[cell]) + 1
			queue.append(next)
	return dist


## The cells of a shortest walk from [param from] to [param to] (doors
## open, walls shut), [param from] first; [] where none.
static func _path_to(map: LevelMap, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var parent := {from: from}
	var queue: Array[Vector2i] = [from]
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		if cell == to:
			break
		for direction in DIRECTIONS:
			var next := cell + direction
			if parent.has(next) or not map.walkable(next) or map.edge(Terrain.edge_key(cell, direction)) == "wall":
				continue
			parent[next] = cell
			queue.append(next)
	var out: Array[Vector2i] = []
	if not parent.has(to):
		return out
	var at := to
	while at != from:
		out.push_front(at)
		at = parent[at]
	out.push_front(from)
	return out


## Each room's steps off [param spine] as layout_sense counts them: 0
## where the walk runs through it, else the rooms entered on the way to it
## from the spine (its own counted): index -> steps.
static func _room_steps(map: LevelMap, rooms: Array[Dictionary], spine: Array[Vector2i]) -> Dictionary:
	var room_of := {}
	for index in rooms.size():
		for cell: Vector2i in rooms[index]["cells"]:
			room_of[cell] = index
	var cost := {}
	var front: Array[Vector2i] = []
	for cell in spine:
		cost[cell] = 0
		front.append(cell)
	# 0-1 walk: a step into another room's cells costs one.
	while not front.is_empty():
		var next_front: Array[Vector2i] = []
		var i := 0
		while i < front.size():
			var cell := front[i]
			i += 1
			for direction in DIRECTIONS:
				var next := cell + direction
				if not map.walkable(next) or map.edge(Terrain.edge_key(cell, direction)) == "wall":
					continue
				var step := 1 if room_of.has(next) and room_of.get(next) != room_of.get(cell) else 0
				var c := int(cost[cell]) + step
				if cost.has(next) and int(cost[next]) <= c:
					continue
				cost[next] = c
				if step == 0:
					front.append(next)
				else:
					next_front.append(next)
		front = next_front
	var out := {}
	for cell: Vector2i in room_of:
		if cost.has(cell):
			var index: int = room_of[cell]
			out[index] = mini(int(out.get(index, 99)), int(cost[cell]))
	return out


## Steps from the nearest cell of [param spine] over the floor.
static func _off_spine(map: LevelMap, spine: Array[Vector2i]) -> Dictionary:
	var dist := {}
	var queue: Array[Vector2i] = []
	for cell in spine:
		dist[cell] = 0
		queue.append(cell)
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		for direction in DIRECTIONS:
			var next := cell + direction
			if dist.has(next) or not map.walkable(next) or map.edge(Terrain.edge_key(cell, direction)) == "wall":
				continue
			dist[next] = int(dist[cell]) + 1
			queue.append(next)
	return dist


## An imp on guard on the heart's approach: the open floor cell nearest
## the last cells of [param spine] before it enters [param heart_rect]
## (APPROACH steps back along it at most), outside every anchor, facing
## back up the walk. How many were laid (0 or 1).
const APPROACH := 8
static func _approach_guard(map: LevelMap, anchors: Array, spine: Array[Vector2i], heart_rect: Rect2i, plan: Dictionary) -> int:
	if not map.colours.has("monster_imp"):
		return 0
	var enter := -1
	for index in spine.size():
		if heart_rect.has_point(spine[index]):
			enter = index
			break
	if enter <= 0:
		return 0
	var before := spine.slice(maxi(0, enter - APPROACH), enter)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for cell: Vector2i in before:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var at := cell + Vector2i(dx, dy)
				if map.cell(at) != FLOOR or not _open_floor(map, at) or Level.in_anchors(anchors, at) or _beside_anchor(anchors, at):
					continue
				var d := Tools.distance(at, spine[enter])
				if d < best_d:
					best = at
					best_d = d
	if best.x < 0:
		return 0
	map.set_cell(best, "monster_imp")
	var back: Vector2i = spine[maxi(0, enter - APPROACH)] - best
	var face := Vector2i(signi(back.x), 0) if absi(back.x) >= absi(back.y) else Vector2i(0, signi(back.y))
	plan["entities"].append({"at": [best.x, best.y], "facing": [face.x, face.y], "idle": {"mode": "guard"}})
	return 1


## Each room's "use" (HOLD_USES; the class doc of _hold).
static func _hold_uses(rooms: Array[Dictionary]) -> void:
	var halls := rooms.filter(func(room: Dictionary) -> bool: return room["kind"] == "hall")
	var plain := rooms.filter(func(room: Dictionary) -> bool: return room["kind"] != "hall")
	halls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) < int(b["walk"]))
	plain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) < int(b["walk"]))
	var wanted: Array[String] = []
	# The first great hall the pillared hall; any other joins the rest (the
	# relief hall where it stays free, else a find off the way).
	if not halls.is_empty():
		halls[0]["use"] = "pillared_hall"
	var second: Variant = halls[1] if halls.size() > 1 else null
	for k in range(1, halls.size()):
		plain.append(halls[k])
	plain.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) < int(b["walk"]))
	if plain.is_empty():
		return
	plain[0]["use"] = "guardroom"
	# The finds off the way (the spine rule's wings): the store the room
	# farthest off the spine in the deeper half, the armoury the next
	# farthest off; a tie goes to the deeper.
	var rest := plain.slice(1)
	var half := float(int(plain[plain.size() - 1]["walk"]) + int(plain[0]["walk"])) / 2.0
	var by_off := func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["steps"]) != int(b["steps"]):
			return int(a["steps"]) > int(b["steps"])
		return int(a["off"]) > int(b["off"]) if int(a["off"]) != int(b["off"]) else int(a["walk"]) > int(b["walk"])
	var deep := rest.filter(func(room: Dictionary) -> bool: return float(room["walk"]) >= half)
	if deep.is_empty():
		deep = rest.duplicate()
	deep.sort_custom(by_off)
	if not deep.is_empty():
		deep[0]["use"] = "store"
		rest.erase(deep[0])
	rest.sort_custom(by_off)
	if not rest.is_empty():
		rest[0]["use"] = "armoury"
		rest.remove_at(0)
	# A further room two or more steps off the spine is a store too (a find
	# off the way, its chest the hall's).
	var extra_stores := 0
	while not rest.is_empty() and int(rest[0]["steps"]) >= 2 and extra_stores < 1:
		rest[0]["use"] = "store"
		rest.remove_at(0)
		extra_stores += 1
	if second != null and second in rest:
		second["use"] = "relief_hall"
		rest.erase(second)
	else:
		wanted.append("relief_hall")
	var middle := rest
	var far := half
	middle.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(int(a["walk"]) - far) < absf(int(b["walk"]) - far))
	wanted.push_front("cold_forge")
	for room: Dictionary in middle:
		room["use"] = wanted.pop_front() if not wanted.is_empty() else "guardroom"


## A building [param slot] [param along] cells long laid flush against a
## wall of [param room] (its back to the rock, facing in), as near the
## middle of the wall across from the room's first door as it fits, then
## any wall: floor two cells deep before it, and along the wall either the
## room's corner or two cells of floor (612: no one-cell way). Its entry in
## plan["buildings"] (with [param variant]), its cells kept; the cell before
## its middle (what its light is laid by), or null where it fits nowhere.
static func _against_wall(map: LevelMap, room: Dictionary, kept: Dictionary, slot: String, along: int, plan: Dictionary,
		variant := 1) -> Variant:
	for spot: Array in _wall_spots(map, room, kept, along):
		var cells: Array[Vector2i] = []
		cells.assign(spot[0])
		var inward: Vector2i = spot[1]
		var entry := {"slot": slot, "at": [cells[0].x, cells[0].y], "facing": [inward.x, inward.y], "variant": variant}
		var top_left := cells[0]
		for cell in cells:
			top_left = Vector2i(mini(top_left.x, cell.x), mini(top_left.y, cell.y))
		entry["at"] = [top_left.x, top_left.y]
		var rect: Variant = Level.building_rect(entry)
		if not rect is Rect2i or Level.rect_cells(rect).size() != cells.size() or Level.rect_cells(rect).any(func(cell: Vector2i) -> bool: return not cell in cells):
			continue
		for cell in cells:
			kept[cell] = true
			for direction in DIRECTIONS:
				kept[cell + direction] = true
		plan["buildings"].append(entry)
		room["things"] = int(room.get("things", 0)) + 1
		return cells[cells.size() / 2] + inward
	return null


## The wall runs of [param room] a piece [param along] cells long fits
## against: [[cells], inward], the wall across from its first door first,
## each wall's middle first.
static func _wall_spots(map: LevelMap, room: Dictionary, kept: Dictionary, along: int) -> Array:
	var cells: Dictionary = room["cells"]
	var rect: Rect2i = room["rect"]
	var centre := rect.position + rect.size / 2
	var back := Vector2i.ZERO
	if not (room["doors"] as Array).is_empty():
		var door: Vector2i = room["doors"][0]
		var off := door - centre
		back = Vector2i(-signi(off.x), 0) if absi(off.x) * rect.size.y > absi(off.y) * rect.size.x else Vector2i(0, -signi(off.y))
	var walls: Array[Vector2i] = []
	if back != Vector2i.ZERO:
		walls.append(back)
	for direction in DIRECTIONS:
		if not direction in walls:
			walls.append(direction)
	var out: Array = []
	for wall in walls:
		var run_way := Vector2i(absi(wall.y), absi(wall.x))
		var runs: Array = []
		for cell in Tools.sorted_cells(cells):
			if cells.has(cell + wall) or map.walkable(cell + wall) or map.edge(Terrain.edge_key(cell, wall)) == "door":
				continue
			var piece: Array[Vector2i] = []
			var fits := true
			for k in along:
				var at := cell + run_way * k
				if not cells.has(at) or kept.has(at) or map.cell(at) != FLOOR or cells.has(at + wall) or map.walkable(at + wall) \
						or map.edge(Terrain.edge_key(at, wall)) == "door":
					fits = false
					break
				# Two cells of floor before it.
				for depth_in in [1, 2]:
					if not cells.has(at - wall * depth_in) or map.cell(at - wall * depth_in) != FLOOR:
						fits = false
				piece.append(at)
			if not fits:
				continue
			# Along the wall either end: the room's corner, or two cells of floor.
			for pair: Array in [[piece[0] - run_way, piece[0] - run_way * 2], [piece[piece.size() - 1] + run_way, piece[piece.size() - 1] + run_way * 2]]:
				if cells.has(pair[0]) and not cells.has(pair[1]):
					fits = false
			if fits:
				runs.append([piece, -wall, Tools.distance(piece[0], centre)])
		runs.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
		out.append_array(runs)
	return out


## A wall piece of decor [param kind] on [param room]'s back wall (the
## first door's far side), the floor cell nearest its middle with rock
## behind, out of the doors' lines; its words [param line] ({cut, look,
## fact}: voice's, lore's facts) in plan["carvings"] when it has any. The
## floor cell before it, or null.
static func _on_wall(map: LevelMap, room: Dictionary, kept: Dictionary, kind: String, plan: Dictionary, line: Dictionary) -> Variant:
	for spot: Array in _wall_spots(map, room, kept, 1):
		var cell: Vector2i = spot[0][0]
		var wall: Vector2i = -(spot[1] as Vector2i)
		if plan["decor"].any(func(row: Array) -> bool: return row[0] == cell.x and row[1] == cell.y):
			continue
		plan["decor"].append([cell.x, cell.y, wall.x, wall.y, kind, 1])
		kept[cell] = true
		if not line.is_empty():
			var row := {"at": [cell.x, cell.y], "side": [wall.x, wall.y]}
			for key: String in ["cut", "look", "fact"]:
				if line.has(key):
					row[key] = line[key]
			plan["carvings"].append(row)
		room["things"] = int(room.get("things", 0)) + 1
		return cell
	return null


## The block's cache chest (808: each player's find, never empty) by
## [param room]'s back wall: the chest marker and its entity row {at,
## props: {cache}}, room["chest"]. Whether it was laid.
static func _hold_chest(map: LevelMap, room: Dictionary, kept: Dictionary, cache: String, plan: Dictionary) -> bool:
	if cache.is_empty():
		return false
	for spot: Array in _wall_spots(map, room, kept, 1):
		var cell: Vector2i = spot[0][0]
		map.set_cell(cell, "chest")
		kept[cell] = true
		plan["entities"].append({"at": [cell.x, cell.y], "props": {"cache": cache}})
		room["chest"] = cell
		room["things"] = int(room.get("things", 0)) + 1
		return true
	return false


## [param count] monsters [param kind] in [param room] (enemy-ai's idle
## modes, level.json "idle" on each entity row): by its chest (within
## GUARD_NEAR) where it has one, else on its open floor nearest its
## middle; facing the room's first door, a "gather" one round the room's
## main piece. How many were laid.
static func _hold_guards(map: LevelMap, anchors: Array, room: Dictionary, kind: String, count: int, idle: Dictionary,
		plan: Dictionary) -> int:
	if count <= 0 or not map.colours.has("monster_" + kind):
		return 0
	var rect: Rect2i = room["rect"]
	var focus: Vector2i = room.get("chest", room.get("main", rect.position + rect.size / 2))
	var spots: Array[Vector2i] = []
	for cell in Tools.sorted_cells(room["cells"]):
		if _open_floor(map, cell) and not _beside_anchor(anchors, cell) and not map.extras.get("plate_cells", {}).has(cell):
			spots.append(cell)
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Tools.distance(a, focus) < Tools.distance(b, focus))
	if room.has("chest"):
		spots = spots.filter(func(cell: Vector2i) -> bool: return maxi(absi(cell.x - focus.x), absi(cell.y - focus.y)) <= GUARD_NEAR)
	var door: Vector2i = room["doors"][0] if not (room["doors"] as Array).is_empty() else focus
	var laid := 0
	for cell in spots:
		if laid >= count:
			break
		if map.cell(cell) != FLOOR:
			continue
		map.set_cell(cell, "monster_" + kind)
		var row := {"at": [cell.x, cell.y], "idle": idle.duplicate()}
		# A chest in a room of wanderers (the pillared hall's, enemy-ai): the
		# first stands guard beside it, facing the way in; the rest wander.
		if laid == 0 and room.has("chest") and str(idle.get("mode", "")) == "wander":
			row["idle"] = {"mode": "guard"}
		var off := door - cell
		if off != Vector2i.ZERO:
			var face := Vector2i(signi(off.x), 0) if absi(off.x) >= absi(off.y) else Vector2i(0, signi(off.y))
			row["facing"] = [face.x, face.y]
		if str(idle.get("mode", "")) == "gather":
			row["idle"]["point"] = [focus.x, focus.y]
		plan["entities"].append(row)
		laid += 1
	if laid > 0 and room.has("chest"):
		room["guarded"] = true
	return laid
