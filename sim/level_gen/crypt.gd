extends RefCounted
## The "crypt" generator (806 amended, the crypt's layout; Jeff: "what the
## barrows is right now is a better crypt under the temple"; the
## coordinator's crypt design): the upper crypt laid from a reason, under the
## layout rules (sim/layout_sense.gd). The same contract as labyrinth:
## static generate(template, config, seed) -> LevelMap, the anchors' cells,
## edges and heights the template's, the rest made here, the same seed the
## same map.
##
## The crypt is a town's burial place, laid as one:
##   the processional  one way, "ways" cells wide (5), from the "entrance"
##                     anchor (The First Hall) to the "heart" anchor (the
##                     farthest from the entrance unless the block names one),
##                     straight runs with a bend or two, torches paired along
##                     its walls: the spine (at most 1.6 times the straight
##                     line, the walk only ever toward the heart);
##   galleries         side ways three wide off the processional, each ended
##                     by a tomb's door, so no way runs out on nothing;
##   rooms             each set in the rock beside the processional or a
##                     gallery with one door (two edges) onto it and walled
##                     all round, so every room is one step off the spine at
##                     most. Each has a use, named in the map's "laid_rooms"
##                     (layout_sense reads them), and something in it that
##                     shows the use once it is cleared:
##     family_tomb     a sarcophagus (building.grave) or two, burial niches in
##                     its walls, a carving (the block's "carvings": a family's
##                     words) on its back wall;
##     ossuary         one, the biggest room about the middle of the walk:
##                     niches all round and bones heaped on the floor;
##     chapel_of_rest  one, on the processional itself, nearest the middle:
##                     a bier (building.burial_table), lights, a carving
##                     (the coordinator: a quiet room still has its point);
##                     no monster is laid in it;
##     sealed_vault    one, the room farthest walked off a gallery: a cache
##                     chest (the block's "cache") by its back wall.
## The other anchors (The Altar Room, the niche) are joined to the
## processional by short ways three wide. Chests ("chests", the vault's
## first, then the farthest tombs) are caches of the block's "cache" table,
## each with a monster of the first "guard" kind in its room (Jeff: "keep
## them guarded"); the rest of the monsters lie nearest their "near" anchor
## (the robbers' side: their camp), "apart" as the block says.
##
## What the generation lays besides the map's cells and edges goes to Regen
## by rows_of(map): "decor", "entities", "buildings", "niches",
## "carvings" ([{at, side, cut, look, fact}], the words of each carving) and
## "laid_rooms" ([{id, use, cells | rect}]).

const Tools := preload("res://sim/level_gen/gen_tools.gd")
const Labyrinth := preload("res://sim/level_gen/labyrinth.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLOOR := "stone"
## The processional's width unless the block says ("ways", an odd number).
const DEFAULT_WAYS := 5
## A room's size: across its door's wall (least, most), and deep.
const ROOM_ACROSS: Array[int] = [5, 8]
const ROOM_DEEP: Array[int] = [5, 8]
## The ossuary is laid at least this big (across x deep).
const OSSUARY_LEAST := 30
## Galleries: how long (cells), and how far apart along the processional.
const GALLERY_LENGTH: Array[int] = [8, 18]
const GALLERY_PITCH: Array[int] = [7, 10]
## Rock kept between two rooms, or a room and a way it has no door on.
const ROOM_GAP := 1
## Rock kept between the map's rim and anything carved.
const RIM := 2
## A pair of torches every so many cells along the processional.
const TORCH_EVERY := 8
## How many bend points the processional may take.
const BENDS := 2
## A gallery this long or more may branch, each side by this chance.
const BRANCH_FROM := 10
const BRANCH_CHANCE := 0.5
## Floor kept this far off a room's sides and back (no way wraps it).
const ROOM_CLEAR := 1

const USES: Array[String] = ["family_tomb", "ossuary", "chapel_of_rest", "sealed_vault"]


static func generate(template: LevelMap, config: Dictionary, seed: int) -> LevelMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var given: Array = config.get("anchors", [])
	var anchors := Labyrinth._set_in_rock(template, given)
	var map := template.copy()
	Tools.clear_outside(map, anchors)
	Labyrinth._move_hidden(map, Labyrinth.niche_plan(config, seed))
	var carved: Dictionary[Vector2i, bool] = {}
	var plan := {"rooms": [], "ways": {}, "decor": [], "entities": [], "buildings": [], "niches": [], "carvings": [],
		"laid_rooms": [], "processional": [], "ends": []}
	var nodes := Labyrinth._anchor_nodes(template, given, {})
	if nodes.is_empty():
		return map
	var entrance := _named(nodes, str(config.get("entrance", "")), 0)
	var heart := _heart(nodes, entrance, str(config.get("heart", "")))
	var brush := maxi(int(config.get("ways", DEFAULT_WAYS)), 3) / 2
	# The processional, from the entrance's way out to the heart's.
	var out_of: Variant = Labyrinth._exit(map, template, anchors, nodes[entrance], nodes[heart]["centre"])
	var into: Variant = Labyrinth._exit(map, template, anchors, nodes[heart], nodes[entrance]["centre"])
	if out_of == null or into == null:
		return map
	var from: Vector2i = out_of[0] + out_of[1]
	var to: Vector2i = into[0] + into[1]
	var path := _processional(map, anchors, from, to, brush, rng)
	plan["processional"] = path
	_carve_way(map, anchors, path, brush, carved, plan["ways"])
	# The other anchors joined to it, three wide.
	for index in nodes.size():
		if index == entrance or index == heart:
			continue
		# Its way out nearest the entrance, to the processional's nearest
		# cell: entered from the near side, so its far side is no long walk.
		var node: Dictionary = nodes[index]
		var exit: Variant = Labyrinth._exit(map, template, anchors, node, nodes[entrance]["centre"])
		if exit == null:
			continue
		var start: Vector2i = exit[0] + exit[1]
		var nearest := _nearest(plan["ways"], start)
		_carve_way(map, anchors, Tools.path_around(map, anchors, start, nearest), 1, carved, plan["ways"])
	# Galleries off the processional and out of the entrance's other doors
	# (a branch off a gallery's middle now and then), then the rooms along
	# every way.
	var runs := _runs(path)
	var galleries: Array = []
	for run: Dictionary in runs:
		galleries.append_array(_galleries(map, anchors, run, brush, rng, carved, plan))
	for node: Dictionary in nodes:
		var rect: Rect2i = node["rect"]
		if rect.size.x <= Labyrinth.NICHE_MOST or rect.size.y <= Labyrinth.NICHE_MOST:
			continue  # A niche keeps its one mouth.
		for way in DIRECTIONS:
			var door: Variant = Labyrinth._exit(map, template, anchors, node, (node["centre"] as Vector2i) + way * 200)
			if door == null or door[1] != way:
				continue
			var gallery := _gallery(map, anchors, door[0] + door[1], way, rng, carved, plan)
			if not gallery.is_empty():
				galleries.append(gallery)
	for gallery: Dictionary in galleries.duplicate():
		galleries.append_array(_branches(map, anchors, gallery, rng, carved, plan))
	for run: Dictionary in runs:
		_rooms_along(map, anchors, run, brush, rng, carved, plan, true)
	for gallery: Dictionary in galleries:
		_rooms_along(map, anchors, gallery, 1, rng, carved, plan, false)
	_trim_galleries(map, galleries, carved, plan)
	# Where a gallery that took no room stood, rooms on the processional.
	for run: Dictionary in runs:
		_rooms_along(map, anchors, run, brush, rng, carved, plan, true)
	# Anything the anchors left apart joined up, single runs widened; rooms
	# walled again where that carved beside them.
	Tools.join_up(map, anchors, carved)
	Tools.join_all(map, anchors, carved)
	var ring := _room_ring(map, plan["rooms"])
	var room_cells := {}
	for room: Dictionary in plan["rooms"]:
		room_cells.merge(room["cells"])
	Tools.widen(map, anchors, carved, ring)
	for pass_number in 3:
		var cleared := Tools.clear_pinches(map, anchors, carved, ring, room_cells)
		if Tools.fill_nooks(map, anchors, room_cells).is_empty() and cleared.is_empty():
			break
	for room: Dictionary in plan["rooms"]:
		_wall_room(map, room)
	_uses(map, anchors, entrance, nodes, plan)
	_furnish(map, anchors, config, rng, plan)
	_torches(map, anchors, brush, plan)
	_monsters(map, anchors, config, rng, plan)
	_laid_rooms(given, plan)
	map.extras["rows"] = {"decor": plan["decor"], "entities": plan["entities"], "buildings": plan["buildings"],
		"niches": plan["niches"], "carvings": plan["carvings"], "laid_rooms": plan["laid_rooms"]}
	# The ways, and what the generation stood in the rooms: Regen's moss and
	# webs keep off them (647; a patch under a sarcophagus is on no floor).
	var clear: Dictionary = plan["ways"].duplicate()
	for entry: Dictionary in plan["buildings"]:
		for cell in Level.rect_cells(Level.building_rect(entry)):
			clear[cell] = true
	for row: Array in plan["decor"]:
		clear[Vector2i(row[0], row[1])] = true
	for row: Array in plan["niches"]:
		clear[Vector2i(row[0], row[1])] = true
	map.extras["paths"] = clear
	return map


## The first hall's niches and hidden door (608), as the labyrinth's barrow
## lays them: Regen moves the link by it.
static func niche_plan(config: Dictionary, seed: int) -> Dictionary:
	return Labyrinth.niche_plan(config, seed)


## What the generation lays besides cells and edges, for Regen to add to
## the generated level.json: {section: rows}.
static func rows_of(map: LevelMap) -> Dictionary:
	return (map.extras.get("rows", {}) as Dictionary).duplicate(true)


# --- The processional ------------------------------------------------------------------

static func _named(nodes: Array[Dictionary], name: String, fallback: int) -> int:
	for index in nodes.size():
		if not name.is_empty() and nodes[index]["name"] == name:
			return index
	return fallback


## The heart: the anchor [param name], else the one whose centre lies
## farthest from the entrance's.
static func _heart(nodes: Array[Dictionary], entrance: int, name: String) -> int:
	var named := _named(nodes, name, -1)
	if named >= 0:
		return named
	var best := entrance
	var best_d := -1
	for index in nodes.size():
		var d := Tools.distance(nodes[index]["centre"], nodes[entrance]["centre"])
		if index != entrance and d > best_d:
			best = index
			best_d = d
	return best


## The processional's path from [param from] to [param to]: only ever
## toward [param to] (so its walk is the straight line's x and y and no
## more), straight runs with up to BENDS turns, the one whose cells all lie
## in the rock with [param brush] cells of it clear of the anchors and the
## rim; the rng picks among those that fit. Round the anchors when none does.
static func _processional(map: LevelMap, anchors: Array, from: Vector2i, to: Vector2i, brush: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var tries: Array[Array] = []
	tries.append(Tools.l_path(from, to, true))
	tries.append(Tools.l_path(from, to, false))
	for i in 12:
		var mid_x := rng.randi_range(mini(from.x, to.x), maxi(from.x, to.x))
		var mid_y := rng.randi_range(mini(from.y, to.y), maxi(from.y, to.y))
		if rng.randf() < 0.5:
			tries.append(_join([from, Vector2i(mid_x, from.y), Vector2i(mid_x, to.y), to]))
		else:
			tries.append(_join([from, Vector2i(from.x, mid_y), Vector2i(to.x, mid_y), to]))
	var fits: Array[Array] = []
	for path: Array in tries:
		if _clear_path(map, anchors, path, brush, from, to):
			fits.append(path)
	if fits.is_empty():
		for path: Array in tries:
			if _clear_path(map, anchors, path, 0, from, to):
				fits.append(path)
	if fits.is_empty():
		return Tools.path_around(map, anchors, from, to)
	var out: Array[Vector2i] = []
	out.assign(fits[rng.randi_range(0, fits.size() - 1)])
	return out


## The cells of straight runs through [param corners], each corner once.
static func _join(corners: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = [corners[0]]
	for i in range(1, corners.size()):
		var at: Vector2i = out[out.size() - 1]
		var goal: Vector2i = corners[i]
		while at != goal:
			at += Vector2i(signi(goal.x - at.x), 0) if at.x != goal.x else Vector2i(0, signi(goal.y - at.y))
			out.append(at)
	return out


## Whether every cell of [param path] may be carved and lies [param brush]
## cells clear of the anchors and the rim, but near its ends (where it meets
## the anchors it joins).
static func _clear_path(map: LevelMap, anchors: Array, path: Array, brush: int, from: Vector2i, to: Vector2i) -> bool:
	for cell: Vector2i in path:
		if not Tools.rock(map, anchors, cell):
			return false
		if cell.x < RIM or cell.y < RIM or cell.x >= map.size.x - RIM or cell.y >= map.size.y - RIM:
			return false
		if Tools.distance(cell, from) <= brush or Tools.distance(cell, to) <= brush:
			continue
		for dy in range(-brush, brush + 1):
			for dx in range(-brush, brush + 1):
				if Level.in_anchors(anchors, cell + Vector2i(dx, dy)):
					return false
	return true


## [param path] carved [param brush] cells either side, its cells counted
## in [param ways] (the corridor floor).
static func _carve_way(map: LevelMap, anchors: Array, path: Array, brush: int, carved: Dictionary[Vector2i, bool], ways: Dictionary) -> void:
	for cell: Vector2i in path:
		if not Tools.rock(map, anchors, cell):
			continue
		Tools.carve(map, cell, carved)
		ways[cell] = true
	for cell: Vector2i in path:
		var before := carved.size()
		var had := carved.duplicate()
		Labyrinth._carve_brush(map, anchors, cell, carved, [], brush)
		if carved.size() != before:
			for at: Vector2i in carved:
				if not had.has(at):
					ways[at] = true


## The straight runs of [param path]: [{cells, along: its step, across}].
static func _runs(path: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < path.size() - 1:
		var along: Vector2i = path[i + 1] - path[i]
		var cells: Array[Vector2i] = [path[i]]
		while i < path.size() - 1 and path[i + 1] - path[i] == along:
			i += 1
			cells.append(path[i])
		out.append({"cells": cells, "along": along, "across": Vector2i(along.y, along.x)})
	return out


static func _nearest(cells: Dictionary, to: Vector2i) -> Vector2i:
	var best := to
	var best_d := -1
	for cell: Vector2i in Tools.sorted_cells(cells):
		var d := Tools.distance(cell, to)
		if best_d < 0 or d < best_d:
			best = cell
			best_d = d
	return best


# --- Galleries and rooms ---------------------------------------------------------------

## Galleries off [param run] (a processional run [param brush] either side
## of its cells): every GALLERY_PITCH cells, to one side or the other, a way
## three wide straight out into the rock, as long as fits up to the draw,
## with room left at its end for a tomb. Carved; each {cells, along,
## across, tip}.
static func _galleries(map: LevelMap, anchors: Array, run: Dictionary, brush: int, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool], plan: Dictionary) -> Array:
	var out: Array = []
	var cells: Array = run["cells"]
	var across: Vector2i = run["across"]
	var at := rng.randi_range(3, 5)
	while at < cells.size() - 3:
		var sides: Array[Vector2i] = [across, -across]
		if rng.randf() < 0.5:
			sides.reverse()
		for side in sides:
			var gallery := _gallery(map, anchors, cells[at] + side * (brush + 1), side, rng, carved, plan)
			if not gallery.is_empty():
				out.append(gallery)
		at += rng.randi_range(GALLERY_PITCH[0], GALLERY_PITCH[1])
	return out


## A gallery three wide from [param root] along [param side], as long as
## fits up to the draw: carved, {cells, along, across, tip}; {} when not
## even the least length fits.
static func _gallery(map: LevelMap, anchors: Array, root: Vector2i, side: Vector2i, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool], plan: Dictionary) -> Dictionary:
	var length := rng.randi_range(GALLERY_LENGTH[0], GALLERY_LENGTH[1])
	while length >= GALLERY_LENGTH[0]:
		if _gallery_fits(map, anchors, root, side, length):
			break
		length -= 1
	if length < GALLERY_LENGTH[0]:
		return {}
	var line: Array[Vector2i] = []
	for i in length:
		line.append(root + side * i)
	_carve_way(map, anchors, line, 1, carved, plan["ways"])
	return {"cells": line, "along": side, "across": Vector2i(side.y, side.x), "tip": line[line.size() - 1]}


## Branches off [param gallery]'s middle, one to a side at most, each a
## gallery of its own (still the one corridor: their rooms are a step off
## the spine as the gallery's are).
static func _branches(map: LevelMap, anchors: Array, gallery: Dictionary, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool], plan: Dictionary) -> Array:
	var out: Array = []
	var line: Array = gallery["cells"]
	if line.size() < BRANCH_FROM:
		return out
	var across: Vector2i = gallery["across"]
	for side: Vector2i in [across, -across]:
		if rng.randf() >= BRANCH_CHANCE:
			continue
		var at: int = rng.randi_range(line.size() / 3, line.size() * 2 / 3)
		var branch := _gallery(map, anchors, (line[at] as Vector2i) + side * 2, side, rng, carved, plan)
		if not branch.is_empty():
			out.append(branch)
	return out


## Whether a gallery three wide from [param root] [param length] cells
## along [param side], with a tomb's depth beyond its tip, lies in plain
## rock off the rim, a cell of rock all round it (but where it leaves the
## processional).
static func _gallery_fits(map: LevelMap, anchors: Array, root: Vector2i, side: Vector2i, length: int) -> bool:
	var across := Vector2i(side.y, side.x)
	for i in range(0, length + ROOM_DEEP[0] + 1):
		for j in range(-2 - ROOM_ACROSS[0] / 2, 3 + ROOM_ACROSS[0] / 2):
			if i < length and absi(j) > 2:
				continue
			var cell := root + side * i + across * j
			if cell.x < RIM or cell.y < RIM or cell.x >= map.size.x - RIM or cell.y >= map.size.y - RIM:
				return false
			if not Tools.rock(map, anchors, cell) or map.walkable(cell):
				return false
	return true


## Rooms along [param run] (a way's straight run, [param brush] cells
## either side of its centre line): on each side, a room after a room,
## each set in the rock with its near wall on the way's edge; a gallery's
## tip gets the tomb that ends it first. Carved and walled, a door pair in
## the middle of the near wall. On the processional the first room laid
## beside its middle is marked to be the chapel of rest.
static func _rooms_along(map: LevelMap, anchors: Array, run: Dictionary, brush: int, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool], plan: Dictionary, processional: bool) -> void:
	var cells: Array = run["cells"]
	var along: Vector2i = run["along"]
	var across: Vector2i = run["across"]
	if not processional:
		var tip: Vector2i = run["tip"]
		var wide := rng.randi_range(ROOM_ACROSS[0], ROOM_ACROSS[1])
		var deep := rng.randi_range(ROOM_DEEP[0], ROOM_DEEP[1])
		var start := tip + along - across * (wide / 2)
		_try_room(map, anchors, start, across, along, wide, deep, carved, plan, {"gallery": true, "tip": true})
	for side: Vector2i in [across, -across]:
		# Off a gallery, clear of the way it leaves (ROOM_CLEAR).
		var at := 1 if processional else ROOM_CLEAR + 1
		while at < cells.size() - 1:
			var wide := rng.randi_range(ROOM_ACROSS[0], ROOM_ACROSS[1])
			var deep := rng.randi_range(ROOM_DEEP[0], ROOM_DEEP[1])
			if at + wide > cells.size() - 1:
				wide = cells.size() - 1 - at
			if wide < ROOM_ACROSS[0]:
				break
			var start: Vector2i = cells[at] + side * (brush + 1)
			# The room's own frame: x along the way, y out from it.
			if _try_room(map, anchors, start, along, side, wide, deep, carved, plan, {"gallery": not processional, "processional": processional}):
				at += wide + ROOM_GAP + 1
			else:
				at += 1


## A room [param wide] cells along [param x_way] and [param deep] along
## [param y_way] from [param start], its near wall (the y = 0 row's back)
## on the way: laid if every cell of it and a ROOM_GAP ring (but its near
## side) is rock outside the anchors and the rim. Whether it was.
static func _try_room(map: LevelMap, anchors: Array, start: Vector2i, x_way: Vector2i, y_way: Vector2i, wide: int, deep: int,
		carved: Dictionary[Vector2i, bool], plan: Dictionary, tags: Dictionary) -> bool:
	var cells: Dictionary[Vector2i, bool] = {}
	for y in range(-ROOM_CLEAR, deep + ROOM_CLEAR):
		for x in range(-ROOM_CLEAR, wide + ROOM_CLEAR):
			var cell := start + x_way * x + y_way * y
			if y < 0:
				continue  # The near side: the way itself.
			if map.walkable(cell):
				return false  # Floor this near its sides or back: a way would wrap it.
			var ring := maxi(maxi(-x, x - wide + 1), y - deep + 1)
			if ring > ROOM_GAP:
				continue
			if cell.x < RIM or cell.y < RIM or cell.x >= map.size.x - RIM or cell.y >= map.size.y - RIM:
				return false
			if not Tools.rock(map, anchors, cell):
				return false
			if x >= 0 and x < wide and y < deep:
				cells[cell] = true
	# Its door: the near wall's middle two cells, onto the way's floor.
	var doors: Array[Vector2i] = []
	for x: int in ([wide / 2 - 1, wide / 2] if wide >= 4 else [wide / 2]):
		var inside: Vector2i = start + x_way * x
		if map.walkable(inside - y_way):
			doors.append(inside)
	if doors.is_empty():
		return false
	for cell: Vector2i in cells:
		Tools.carve(map, cell, carved)
	var room := {"cells": cells, "doors": doors, "out": -y_way, "x_way": x_way, "start": start, "wide": wide, "deep": deep,
		"use": "", "id": "room_%d" % plan["rooms"].size()}
	room.merge(tags)
	_wall_room(map, room)
	plan["rooms"].append(room)
	return true


## [param room]'s border walled where it touches other floor, but its door
## edges.
static func _wall_room(map: LevelMap, room: Dictionary) -> void:
	var cells: Dictionary = room["cells"]
	var out_way: Vector2i = room["out"]
	for cell: Vector2i in Tools.sorted_cells(cells):
		for direction in DIRECTIONS:
			var next := cell + direction
			if cells.has(next) or not map.walkable(next):
				continue
			var key := Terrain.edge_key(cell, direction)
			if direction == out_way and cell in room["doors"]:
				map.set_edge(key, "door")
			else:
				map.set_edge(key, "wall")


## The rock cells round every room (the widening keeps off them).
static func _room_ring(map: LevelMap, rooms: Array) -> Dictionary[Vector2i, bool]:
	var ring: Dictionary[Vector2i, bool] = {}
	for room: Dictionary in rooms:
		for cell: Vector2i in room["cells"]:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var near := cell + Vector2i(dx, dy)
					if not room["cells"].has(near) and not map.walkable(near):
						ring[near] = true
	return ring


## A gallery whose end is no room's door (its tip tomb didn't fit) is
## filled back from its tip to its last door, so no way runs out on
## nothing.
static func _trim_galleries(map: LevelMap, galleries: Array, carved: Dictionary[Vector2i, bool], plan: Dictionary) -> void:
	var doors := {}
	for room: Dictionary in plan["rooms"]:
		for door: Vector2i in room["doors"]:
			doors[door + room["out"]] = true
	for gallery: Dictionary in galleries:
		var line: Array = gallery["cells"]
		var across: Vector2i = gallery["across"]
		var keep := 0
		for i in line.size():
			for j in range(-1, 2):
				if doors.has(line[i] + across * j):
					keep = i + 1
			if doors.has(line[i] + gallery["along"]):
				keep = i + 1
		if keep == line.size():
			continue
		if keep > 0:
			# Its end, where the roots came down and the rest fell in.
			plan["ends"].append({"cell": (line[0] as Vector2i) + gallery["along"] * (keep - 1), "along": gallery["along"], "across": across})
		# Past the last door, rock: to a cell past its tip, which the brush
		# carved too (left, it is an island the joining up runs a way to).
		var along: Vector2i = gallery["along"]
		for i in range(keep, line.size() + 1):
			for j in range(-1, 2):
				var cell: Vector2i = (line[0] as Vector2i) + along * i + across * j
				map.set_cell(cell, "void")
				plan["ways"].erase(cell)
				carved.erase(cell)  # Else the joining up carves it again.
				for direction in DIRECTIONS:
					map.set_edge(Terrain.edge_key(cell, direction), "clear")


# --- Uses -------------------------------------------------------------------------------

## Each room's use: the chapel of rest the processional room nearest the
## walk's middle; the sealed vault the gallery room farthest walked; the
## ossuary the biggest left about the middle third; the rest family tombs.
static func _uses(map: LevelMap, anchors: Array, entrance: int, nodes: Array[Dictionary], plan: Dictionary) -> void:
	var rooms: Array = plan["rooms"]
	if rooms.is_empty():
		return
	var walk := _walk(map, (nodes[entrance]["centre"] as Vector2i))
	var far := 1
	for room: Dictionary in rooms:
		room["walk"] = int(walk.get(room["doors"][0], 0))
		far = maxi(far, room["walk"])
	var free := rooms.duplicate()
	var by_middle := func(a: Dictionary, b: Dictionary) -> bool:
		return absi(int(a["walk"]) * 2 - far) < absi(int(b["walk"]) * 2 - far)
	# Room for the bier, three across, two cells clear all round: on the
	# processional if one has it, else off a gallery, else the processional's.
	var fits := func(room: Dictionary) -> bool: return room["wide"] >= 7 and room["deep"] >= 6
	var chapel := free.filter(func(room: Dictionary) -> bool: return room.get("processional", false) and fits.call(room))
	if chapel.is_empty():
		chapel = free.filter(fits)
	if chapel.is_empty():
		chapel = free.filter(func(room: Dictionary) -> bool: return room.get("processional", false))
	chapel.sort_custom(by_middle)
	if not chapel.is_empty():
		chapel[0]["use"] = "chapel_of_rest"
		free.erase(chapel[0])
	var vault := free.filter(func(room: Dictionary) -> bool: return room.get("gallery", false))
	if vault.is_empty():
		vault = free.duplicate()
	vault.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) > int(b["walk"]))
	if not vault.is_empty():
		vault[0]["use"] = "sealed_vault"
		free.erase(vault[0])
	var middle := free.filter(func(room: Dictionary) -> bool:
		return room["walk"] * 3 >= far and room["walk"] * 3 <= far * 2 and room["wide"] * room["deep"] >= OSSUARY_LEAST)
	if middle.is_empty():
		middle = free.filter(func(room: Dictionary) -> bool: return room["wide"] * room["deep"] >= OSSUARY_LEAST)
	middle.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["wide"] * a["deep"] > b["wide"] * b["deep"])
	if not middle.is_empty():
		middle[0]["use"] = "ossuary"
		free.erase(middle[0])
	for room: Dictionary in free:
		room["use"] = "family_tomb"


## Steps from [param start] over the walkable floor, doors open.
static func _walk(map: LevelMap, start: Vector2i) -> Dictionary:
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


# --- What stands in the rooms ------------------------------------------------------------

## Each room furnished by its use (the class doc), the carvings drawn from
## the block's "carvings" in a shuffled order, the vault's chest first of
## "chests" caches.
static func _furnish(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var lines: Array = (config.get("carvings", []) as Array).duplicate()
	Tools.shuffle(lines, rng)
	var rest_lines := lines.filter(func(line: Variant) -> bool: return line is Dictionary and line.get("chapel", false))
	var tomb_lines := lines.filter(func(line: Variant) -> bool: return line is Dictionary and not line.get("chapel", false))
	var kept := Labyrinth.door_line(map)
	var chests := int(config.get("chests", 0))
	var tombs: Array = []
	# The robbers' dig: into the floor of the family tomb walked farthest
	# (nearest their camp) that it fits.
	var by_walk: Array = plan["rooms"].filter(func(room: Dictionary) -> bool: return room["use"] == "family_tomb")
	by_walk.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) > int(b["walk"]))
	for room: Dictionary in by_walk:
		if not _dig(map, room, kept, plan).is_empty():
			room["dug"] = true
			break
	for room: Dictionary in plan["rooms"]:
		var use: String = room["use"]
		if use == "family_tomb":
			tombs.append(room)
			if not room.get("dug", false):
				_sarcophagi(map, room, kept, plan)
			_niches_in(map, room, kept, 2, rng, plan)
			if not tomb_lines.is_empty():
				_carving(map, room, kept, tomb_lines.pop_front(), plan)
		elif use == "ossuary":
			_niches_in(map, room, kept, 2, rng, plan)
			_stacks(map, room, kept, plan)
			_bones(map, room, kept, rng, plan)
		elif use == "chapel_of_rest":
			_bier(map, room, kept, plan)
			if not rest_lines.is_empty():
				_carving(map, room, kept, rest_lines[0], plan)
			_candles(map, room, kept, plan)
		elif use == "sealed_vault":
			_sarcophagi(map, room, kept, plan)
			if chests > 0 and _chest(map, room, kept, config, plan):
				chests -= 1
	tombs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walk"]) > int(b["walk"]))
	for room: Dictionary in tombs:
		if chests <= 0:
			break
		if _chest(map, room, kept, config, plan):
			chests -= 1
	# A tomb the robbers have been at (its chest theirs to guard, or their
	# dig in it): its sarcophagi robbed (art-kit's variant 2, the lid off).
	for room: Dictionary in tombs:
		if room.has("chest") or room.get("dug", false):
			for entry: Dictionary in room.get("pieces", []):
				if entry["slot"] == "building.sarcophagus":
					entry["variant"] = 2
	_roots(map, kept, plan)


## A cell of [param room] by its frame: [param x] along its door wall, [param y] in from it.
static func _at(room: Dictionary, x: int, y: int) -> Vector2i:
	return (room["start"] as Vector2i) + (room["x_way"] as Vector2i) * x - (room["out"] as Vector2i) * y


## Its sarcophagi (building.sarcophagus, sealed): one in the middle of a narrow tomb, two
## side by side in a wide one, each a cell clear of the walls, laid along
## the room's depth, its foot to the door.
static func _sarcophagi(map: LevelMap, room: Dictionary, kept: Dictionary, plan: Dictionary) -> void:
	var wide: int = room["wide"]
	var deep: int = room["deep"]
	if deep < 6:
		# A shallow tomb: the one laid across it, its foot to the side.
		var across := (wide - 2) / 2
		_building(map, room, kept, "building.sarcophagus", [_at(room, across, deep / 2), _at(room, across + 1, deep / 2)], plan, room["x_way"])
		return
	var xs: Array = [wide / 2] if wide < 8 else [wide / 2 - 2, wide / 2 + 1]
	for x: int in xs:
		var y := (deep - 2) / 2
		_building(map, room, kept, "building.sarcophagus", [_at(room, x, y), _at(room, x, y + 1)], plan)


## The bier (building.burial_table's variant 2: a bare slab, a folded
## shroud, a candle stand at each corner) in the chapel's middle, its long
## side across the room.
static func _bier(map: LevelMap, room: Dictionary, kept: Dictionary, plan: Dictionary) -> void:
	var x: int = (room["wide"] - 3) / 2
	var y: int = (room["deep"] - 2) / 2
	var cells: Array[Vector2i] = []
	for dy in 2:
		for dx in 3:
			cells.append(_at(room, x + dx, y + dy))
	var entry := _building(map, room, kept, "building.burial_table", cells, plan)
	if not entry.is_empty():
		entry["variant"] = 2


## The robbers' dig (building.robbers_dig, 2 x 2) in [param room]'s middle,
## its open mouth to the door: the entry, or {} where it does not fit.
static func _dig(map: LevelMap, room: Dictionary, kept: Dictionary, plan: Dictionary) -> Dictionary:
	var x: int = (room["wide"] - 2) / 2
	var y: int = (room["deep"] - 2) / 2
	var cells: Array[Vector2i] = []
	for dy in 2:
		for dx in 2:
			cells.append(_at(room, x + dx, y + dy))
	return _building(map, room, kept, "building.robbers_dig", cells, plan)


## A building laid on [param cells] of [param room] when they are its
## floor, two cells clear of its walls (no way beside it one cell wide)
## and out of every door's line: its entry {slot, at: the footprint's
## top-left, facing: toward the door, or [param facing]}, kept in the
## room's "pieces" too; {} where it does not fit.
static func _building(map: LevelMap, room: Dictionary, kept: Dictionary, slot: String, cells: Array[Vector2i], plan: Dictionary,
		facing: Variant = null) -> Dictionary:
	var top_left := cells[0]
	for cell in cells:
		if not room["cells"].has(cell) or kept.has(cell) or map.cell(cell) != FLOOR:
			return {}
		# Two cells of floor all round it (612: no way one cell wide).
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if not room["cells"].has(cell + Vector2i(dx, dy)):
					return {}
		top_left = Vector2i(mini(top_left.x, cell.x), mini(top_left.y, cell.y))
	var out_way: Vector2i = room["out"] if facing == null else facing
	var entry := {"slot": slot, "at": [top_left.x, top_left.y], "facing": [out_way.x, out_way.y]}
	var rect: Variant = Level.building_rect(entry)
	if not rect is Rect2i:
		return {}
	for cell in Level.rect_cells(rect):
		if not cell in cells:
			return {}
	for cell in cells:
		kept[cell] = true
		for direction in DIRECTIONS:
			kept[cell + direction] = true  # A walk round it, nothing laid hard by.
	plan["buildings"].append(entry)
	room["pieces"] = room.get("pieces", []) + [entry]
	room["things"] = int(room.get("things", 0)) + 1
	return entry


## Burial niches in [param room]'s walls: every [param every]th cell along
## a wall with rock behind it (none in a door's line), shelves ("b") and
## columbarium cells ("d"), a slab now and then.
static func _niches_in(map: LevelMap, room: Dictionary, kept: Dictionary, every: int, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var count := 0
	for cell in Tools.sorted_cells(room["cells"]):
		if kept.has(cell) or map.cell(cell) != FLOOR:
			continue
		for direction in DIRECTIONS:
			var behind := cell + direction
			if room["cells"].has(behind) or map.walkable(behind) or map.edge(Terrain.edge_key(cell, direction)) == "door":
				continue
			if _taken_wall(plan, cell, direction):
				continue
			count += 1
			if count % every != 0:
				continue
			plan["niches"].append([cell.x, cell.y, direction.x, direction.y, "d" if rng.randf() < 0.5 else "b", 2 if rng.randf() < 0.2 else 1])
			break


static func _taken_wall(plan: Dictionary, cell: Vector2i, direction: Vector2i) -> bool:
	for row: Array in plan["niches"]:
		if row[0] == cell.x and row[1] == cell.y and row[2] == direction.x and row[3] == direction.y:
			return true
	for row: Array in plan["decor"]:
		if row[0] == cell.x and row[1] == cell.y and row[2] == direction.x and row[3] == direction.y:
			return true
	return false


## The ossuary's bones heaped on its floor: two or three heaps, clear of
## the walls and doors.
static func _bones(map: LevelMap, room: Dictionary, kept: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var spots: Array[Vector2i] = []
	for cell in Tools.sorted_cells(room["cells"]):
		if kept.has(cell) or not Labyrinth._open_floor(map, cell):
			continue
		spots.append(cell)
	Tools.shuffle(spots, rng)
	var laid: Array[Vector2i] = []
	for cell in spots:
		if laid.size() >= rng.randi_range(2, 3):
			break
		if laid.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < 3):
			continue
		var turn: Vector2i = DIRECTIONS[rng.randi_range(0, 3)]
		plan["decor"].append([cell.x, cell.y, turn.x, turn.y, "bones", rng.randi_range(1, int(Level.DECOR_KINDS["bones"]["variants"]))])
		laid.append(cell)
		kept[cell] = true
	room["things"] = int(room.get("things", 0)) + laid.size()


## Skulls and long bones stacked against the ossuary's walls
## (prop.set_ossuary_stack), on every wall cell its niches left, none in a
## door's line.
static func _stacks(map: LevelMap, room: Dictionary, kept: Dictionary, plan: Dictionary) -> void:
	for cell in Tools.sorted_cells(room["cells"]):
		if kept.has(cell) or map.cell(cell) != FLOOR:
			continue
		for direction in DIRECTIONS:
			var behind := cell + direction
			if room["cells"].has(behind) or map.walkable(behind) or map.edge(Terrain.edge_key(cell, direction)) == "door":
				continue
			if _taken_wall(plan, cell, direction):
				continue
			plan["decor"].append([cell.x, cell.y, direction.x, direction.y, "ossuary_stack", 1])
			room["things"] = int(room.get("things", 0)) + 1
			break


## Candles burning on the chapel's floor before its carving (the light is
## the chapel's two torches).
static func _candles(map: LevelMap, room: Dictionary, kept: Dictionary, plan: Dictionary) -> void:
	for row: Dictionary in plan["carvings"]:
		var cell := Vector2i(int(row["at"][0]), int(row["at"][1]))
		if room["cells"].has(cell) and not kept.has(cell):
			plan["decor"].append([cell.x, cell.y, 0, 0, "candles", 1])
			kept[cell] = true
			return


## Roots come down the end wall of each gallery that ends past its last
## door (the rest of it fell in): its middle cell, else a side one. A wall
## piece, never solid, so a door's line may hold it.
static func _roots(map: LevelMap, kept: Dictionary, plan: Dictionary) -> void:
	for end: Dictionary in plan["ends"]:
		var along: Vector2i = end["along"]
		for j: int in [0, 1, -1]:
			var cell: Vector2i = end["cell"] + end["across"] * j
			if map.cell(cell) != FLOOR or map.walkable(cell + along) or map.edge(Terrain.edge_key(cell, along)) == "door" \
					or _taken_wall(plan, cell, along):
				continue
			plan["decor"].append([cell.x, cell.y, along.x, along.y, "collapse_roots", 1])
			break


## A carving on [param room]'s back wall (the wall across from its door),
## the cell nearest its middle with rock behind: a decor row "carving" and
## its words (the block's carving {cut, look, fact}) in "carvings".
static func _carving(map: LevelMap, room: Dictionary, kept: Dictionary, line: Dictionary, plan: Dictionary) -> void:
	var back: Vector2i = -(room["out"] as Vector2i)
	var deep: int = room["deep"]
	var wide: int = room["wide"]
	var order: Array[int] = []
	for i in wide:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return absi(a * 2 - wide + 1) < absi(b * 2 - wide + 1))
	for x in order:
		var cell := _at(room, x, deep - 1)
		if map.cell(cell) != FLOOR or map.walkable(cell + back) or _taken_wall(plan, cell, back):
			continue
		plan["decor"].append([cell.x, cell.y, back.x, back.y, "carving", 1])
		var row := {"at": [cell.x, cell.y], "side": [back.x, back.y]}
		for key: String in ["cut", "look", "fact"]:
			if line.has(key):
				row[key] = line[key]
		plan["carvings"].append(row)
		room["things"] = int(room.get("things", 0)) + 1
		return


## A cache chest in [param room] by its back wall, beside its middle: the
## chest marker and its entry {at, props: {cache}} (the block's "cache"
## table, rolled per player and generation, 808). Whether it was laid.
static func _chest(map: LevelMap, room: Dictionary, kept: Dictionary, config: Dictionary, plan: Dictionary) -> bool:
	var cache := str(config.get("cache", ""))
	if cache.is_empty():
		return false
	var deep: int = room["deep"]
	var wide: int = room["wide"]
	for x in [wide / 2 - 2, wide / 2 + 1, 1, wide - 2, wide / 2]:
		var cell := _at(room, x, deep - 1)
		if not room["cells"].has(cell) or kept.has(cell) or map.cell(cell) != FLOOR:
			continue
		map.set_cell(cell, "chest")
		kept[cell] = true
		plan["entities"].append({"at": [cell.x, cell.y], "props": {"cache": cache}})
		room["chest"] = cell
		room["things"] = int(room.get("things", 0)) + 1
		return true
	return false


# --- Light and the living --------------------------------------------------------------------

## Torches: a pair along the processional's walls every TORCH_EVERY cells,
## one inside each room by its door (none in the vault, the ossuary dark
## too), never in a door's line.
static func _torches(map: LevelMap, anchors: Array, brush: int, plan: Dictionary) -> void:
	var kept := Labyrinth.door_line(map)
	var path: Array = plan["processional"]
	for run: Dictionary in _runs(path):
		var cells: Array = run["cells"]
		for i in range(TORCH_EVERY / 2, cells.size(), TORCH_EVERY):
			for side: Vector2i in [run["across"], -(run["across"] as Vector2i)]:
				var at: Vector2i = cells[i]
				for step in brush + 2:
					if not map.walkable(at + side):
						break
					at += side
				if map.cell(at) == FLOOR and not kept.has(at) and not Labyrinth._beside_anchor(anchors, at) and not map.walkable(at + side):
					map.set_cell(at, "torch")
					kept[at] = true
	for room: Dictionary in plan["rooms"]:
		if room["use"] == "sealed_vault" or room["use"] == "ossuary":
			continue
		var spot: Variant = Labyrinth._by_wall_near(map, room["cells"], room["doors"][0], kept)
		if spot != null:
			map.set_cell(spot, "torch")
			kept[spot] = true
			if room["use"] == "chapel_of_rest":
				var second: Variant = Labyrinth._by_wall_near(map, room["cells"], room["doors"][room["doors"].size() - 1] + (room["x_way"] as Vector2i) * 2, kept)
				if second != null:
					map.set_cell(second, "torch")


## The monsters: a guard (the block's "guard" kind, else the first kind) in
## each chest's room by the chest, then the rest of each kind nearest its
## "near" anchor, "apart" as the block says; none in the chapel of rest.
static func _monsters(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var counts: Variant = config.get("monsters", {})
	if not counts is Dictionary or (counts as Dictionary).is_empty():
		return
	var left: Dictionary = (counts as Dictionary).duplicate()
	var kinds: Array = left.keys()
	kinds.sort()
	var guard := str(config.get("guard", kinds[0]))
	var quiet := {}
	for room: Dictionary in plan["rooms"]:
		if room["use"] == "chapel_of_rest":
			quiet.merge(room["cells"])
	for room: Dictionary in plan["rooms"]:
		if not room.has("chest") or int(left.get(guard, 0)) <= 0:
			continue
		var spots: Array[Vector2i] = []
		for cell in Tools.sorted_cells(room["cells"]):
			if Labyrinth._open_floor(map, cell):
				spots.append(cell)
		spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Tools.distance(a, room["chest"]) < Tools.distance(b, room["chest"]))
		left[guard] = int(left[guard]) - Labyrinth._lay(map, anchors, "monster_" + guard, 1, spots)
	var floor: Array[Vector2i] = []
	for cell: Vector2i in Tools.sorted_cells(map.cells):
		if map.cell(cell) == FLOOR and not quiet.has(cell) and not Level.in_anchors(anchors, cell) and Labyrinth._open_floor(map, cell):
			floor.append(cell)
	Tools.shuffle(floor, rng)
	var near: Dictionary = config.get("near", {}) if config.get("near") is Dictionary else {}
	var apart: Dictionary = config.get("apart", {}) if config.get("apart") is Dictionary else {}
	for kind: String in kinds:
		var spots: Array[Vector2i] = floor.duplicate()
		var anchor_name := str(near.get(kind, near.get("_all", "")))
		for anchor: Dictionary in anchors:
			if not anchor_name.is_empty() and str(anchor.get("name", "")) == anchor_name:
				var rect: Rect2i = anchor["rect"]
				spots = Labyrinth._nearest_first(rect.position + rect.size / 2, spots)
		Labyrinth._lay(map, anchors, "monster_" + kind, int(left[kind]), spots, int(apart.get(kind, 0)))


## The rooms named for the checker: every room laid {id, use, cells}, and
## the anchors by their names {id, use, rect}.
static func _laid_rooms(given: Array, plan: Dictionary) -> void:
	for anchor: Dictionary in given:
		var rect: Rect2i = anchor["rect"]
		plan["laid_rooms"].append({"id": str(anchor.get("name", "")), "use": str(anchor.get("use", anchor.get("name", ""))),
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	for room: Dictionary in plan["rooms"]:
		var cells: Array = []
		for cell in Tools.sorted_cells(room["cells"]):
			cells.append([cell.x, cell.y])
		plan["laid_rooms"].append({"id": room["id"], "use": room["use"], "cells": cells})
