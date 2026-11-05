extends RefCounted
## Layout sense (decision 806; Jeff, 2026-11-04: "they still feel sloppy and
## doesn't make sense, like a door leading to a hallway that wraps around a
## room, doors that lead to dead ends, rooms that don't have purposes"): the
## rules an interior is laid under, as one check every generator's levels
## and every laid interior go through (level_test). No class_name: preload it.
##
## check(level, rooms, options) -> [{rule, cell, what}], level as Level.parse
## or Level.load_level gives it. [param rooms] is what the level says its
## rooms are, each {id, use, rect: [x, y, w, h] | cells: [[x, y], ...]} (a
## generator's "rooms", buildings' "rooms" and "passages"); empty, the rooms
## are found by shape: floor where a clear square one cell wider than the
## level's ways fits ([param options] "ways", default 3) is a room, the rest
## corridor. The rules:
##   door      every door leads to a room or a through-route: never a stub
##             corridor, never a closet with one door and nothing in it;
##   purpose   every room has a purpose: a use when the level names its
##             rooms, and something standing in it besides monsters, lights
##             and dressing (its purpose still shows once it is cleared);
##   wrap      no corridor rings a room, or runs along two of its sides;
##   dead_end  a dead end holds something (a niche, a chest, a seam, a stair,
##             a link); a monster alone does not count;
##   spine     the walk from the start to the heart is at most SPINE_DETOUR
##             times the straight line, and every room is on it or one step
##             off it (a room given a "wing" is measured from its wing);
##   loop      a loop passes through two rooms or more: never a corridor
##             ring round plain rock;
##   chest     (Jeff: "all chests in the game should have some item in them,
##             if theres no item to put in, then no chest"; "an empty chest
##             is like an anti-reward"; "chests use only for dungeons and keep
##             them guarded") a chest gives something (a cache's table, a
##             loot table rolled into it, or items laid in it), stands only
##             in a dungeon ([param options] "dungeon"), and has a monster in
##             its room or within GUARD_REACH steps. A chest with a role of its
##             own (props "role": an offering altar, a commission's drop) is
##             not loot and is left out; a depot, shop, locker or temple too.
## options: "ways" (the level's way width, cells), "heart" (Vector2i: the
## spine's far end; else the regenerate block's farthest anchor, else the
## farthest floor), "anchors" (the regenerate block's), "config" (level.json,
## for its niches and decor rows when [param level] lacks them).

const RULES: Array[String] = ["door", "purpose", "wrap", "dead_end", "spine", "loop", "chest"]
## How near (steps) a monster must stand to guard a chest outside its room.
const GUARD_REACH := 8
## The longest a spine may walk against the straight line.
const SPINE_DETOUR := 1.6
## A corridor runs along a room's side when it covers this share of it,
## within WRAP_BAND cells of it.
const WRAP_SHARE := 0.6
const WRAP_BAND := 2
## The least a rock island must be to make a loop (smaller is a wall stub
## or a pillar).
const STUB_DEEP := 3
const LOOP_ROCK := 3
## Decor kinds that are lights.
const LIGHT_WORDS: Array[String] = ["lamp", "torch", "sconce", "brazier", "candle", "lantern"]
## Decor that is a sight in itself (Jeff, 11-04: "a visual point of interest"):
## a set piece, not scattered props (webs, moss, beams).
const SIGHT_WORDS: Array[String] = ["fallen", "statue", "altar", "shrine", "sarcophag", "collapse", "carving", "relief", "set_"]
const WAYS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]


## The faults of [param level]: see the class doc.
static func check(level: Dictionary, rooms: Array = [], options: Dictionary = {}) -> Array:
	var lay := _lay(level, rooms, options)
	var faults: Array = []
	_purpose(lay, faults)
	_wraps(lay, faults)
	_doors(lay, faults)
	_dead_ends(lay, faults)
	_loops(lay, faults)
	_spine(lay, options, faults)
	_chests(level, lay, options, faults)
	return faults


## Only the chest rule (a level with no interior to judge: the wilds, a town).
static func check_chests(level: Dictionary, options: Dictionary = {}) -> Array:
	var faults: Array = []
	_chests(level, _lay(level, [], options), options, faults)
	return faults


## How many faults of each rule, every rule named (0 when clean).
static func counts(faults: Array) -> Dictionary:
	var out := {}
	for rule in RULES:
		out[rule] = 0
	for fault: Dictionary in faults:
		out[fault["rule"]] = int(out.get(fault["rule"], 0)) + 1
	return out


# --- The level read into floor, steps, rooms, corridors and what stands where.

static func _lay(level: Dictionary, rooms: Array, options: Dictionary) -> Dictionary:
	var terrain: Dictionary = level.get("terrain", {})
	var floor := {}
	for cell: Vector2i in terrain.get("floor", []):
		floor[cell] = true
	for cell: Vector2i in terrain.get("water", []):
		floor.erase(cell)
	var lay := {"floor": floor, "edges": terrain.get("edges", {}), "relief": terrain.get("relief", PackedFloat32Array()),
		"relief_size": terrain.get("relief_size", Vector2i.ZERO), "stairs": terrain.get("stairs", {}),
		"size": level.get("size", Vector2i.ZERO), "named": not rooms.is_empty()}
	var low := Vector2i(1 << 20, 1 << 20)
	var high := -low
	for cell: Vector2i in floor:
		low = low.min(cell)
		high = high.max(cell)
	lay["low"] = low
	lay["high"] = high
	lay["rock"] = _rock_pieces(lay)
	var pillars := {}
	for piece: Array in lay["rock"]:
		if piece.size() <= int(options.get("pillars", 0)):
			for cell: Vector2i in piece:
				pillars[cell] = true
	lay["pillars"] = pillars
	# Rooms: named, else by shape.
	var room_of := {}
	var uses := {}
	var wings := {}
	if rooms.is_empty():
		_rooms_by_shape(lay, int(options.get("ways", 3)), room_of)
	else:
		var id := 0
		for room: Variant in rooms:
			if not room is Dictionary:
				continue
			id += 1
			uses[id] = str((room as Dictionary).get("use", ""))
			if (room as Dictionary).has("wing"):
				wings[id] = str(room["wing"])
			for cell in _room_cells(room):
				if floor.has(cell):
					room_of[cell] = id
	lay["room_of"] = room_of
	lay["uses"] = uses
	lay["wings"] = wings
	# Corridors: the rest of the floor, by component.
	var corridor_of := {}
	var corridor := 0
	for cell: Vector2i in floor:
		if room_of.has(cell) or corridor_of.has(cell):
			continue
		corridor += 1
		for found in _fill(lay, cell, func(c: Vector2i) -> bool: return not room_of.has(c)):
			corridor_of[found] = corridor
	lay["corridor_of"] = corridor_of
	# Nodes: a room is its id, a corridor 1000 + its number; joined where a
	# step crosses from one to another.
	var adjacent := {}
	for cell: Vector2i in floor:
		var u := _node(lay, cell)
		for way in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other: Vector2i = cell + way
			if floor.has(other) and _steps(lay, cell, way):
				var v := _node(lay, other)
				if u != v:
					(adjacent.get_or_add(u, {}) as Dictionary)[v] = true
					(adjacent.get_or_add(v, {}) as Dictionary)[u] = true
	lay["adjacent"] = adjacent
	lay["things"] = _things(level, options)
	var held := {}
	for thing: Dictionary in lay["things"]:
		var node := _node_at(lay, thing["cell"])
		if node != 0:
			(held.get_or_add(node, {}) as Dictionary)[thing["kind"]] = true
	lay["held"] = held
	return lay


static func _room_cells(room: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rect: Variant = room.get("rect")
	if rect is Array and (rect as Array).size() == 4:
		for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
			for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
				out.append(Vector2i(x, y))
	elif rect is Rect2i:
		for y in range((rect as Rect2i).position.y, (rect as Rect2i).end.y):
			for x in range((rect as Rect2i).position.x, (rect as Rect2i).end.x):
				out.append(Vector2i(x, y))
	for cell: Variant in room.get("cells", []):
		if cell is Vector2i:
			out.append(cell)
		elif cell is Array and (cell as Array).size() >= 2:
			out.append(Vector2i(int(cell[0]), int(cell[1])))
	return out


## Whether one may step from [param from] along orthogonal [param way]: both
## floor, no wall on the edge (a door is a way), no cliff.
static func _steps(lay: Dictionary, from: Vector2i, way: Vector2i) -> bool:
	if not lay["floor"].has(from + way):
		return false
	if int(lay["edges"].get(Terrain.edge_key(from, way), Terrain.Edge.OPEN)) == Terrain.Edge.WALL:
		return false
	var relief: PackedFloat32Array = lay["relief"]
	if not relief.is_empty():
		return Relief.step(relief, lay["relief_size"], lay["stairs"], from, way) == 0
	return true


static func _door(lay: Dictionary, from: Vector2i, way: Vector2i) -> bool:
	return int(lay["edges"].get(Terrain.edge_key(from, way), Terrain.Edge.OPEN)) == Terrain.Edge.DOOR


## The floor reached from [param start] by steps through cells [param keep] allows.
static func _fill(lay: Dictionary, start: Vector2i, keep: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = [start]
	var seen := {start: true}
	var at := 0
	while at < out.size():
		var cell := out[at]
		at += 1
		for way in WAYS:
			var next := cell + way
			if seen.has(next) or not _steps(lay, cell, way) or not keep.call(next):
				continue
			seen[next] = true
			out.append(next)
	return out


static func _node(lay: Dictionary, cell: Vector2i) -> int:
	if lay["room_of"].has(cell):
		return int(lay["room_of"][cell])
	if lay["corridor_of"].has(cell):
		return 1000 + int(lay["corridor_of"][cell])
	return 0


## The node at [param cell], or beside it when it is a wall's (a niche, a
## wall lamp stand on the wall's cell or the floor before it).
static func _node_at(lay: Dictionary, cell: Vector2i) -> int:
	var node := _node(lay, cell)
	if node != 0:
		return node
	for way in WAYS:
		node = _node(lay, cell + way)
		if node != 0:
			return node
	return 0


## Rooms by shape: every clear square of side ways + 1 (all floor, no wall
## or cliff inside it), the union of them, joined by steps; a piece smaller
## than a room is corridor, a sliver of corridor a room's.
static func _rooms_by_shape(lay: Dictionary, ways: int, room_of: Dictionary) -> void:
	var k := ways + 1
	var floor: Dictionary = lay["floor"]
	var low: Vector2i = lay["low"]
	var high: Vector2i = lay["high"]
	var clear := {}
	for y in range(low.y, high.y - k + 2):
		for x in range(low.x, high.x - k + 2):
			var fits := true
			for dy in k:
				for dx in k:
					var cell := Vector2i(x + dx, y + dy)
					if not _solid(lay, cell) or (dx < k - 1 and not _open(lay, cell, Vector2i(1, 0))) \
							or (dy < k - 1 and not _open(lay, cell, Vector2i(0, 1))):
						fits = false
						break
				if not fits:
					break
			if fits:
				for dy in k:
					for dx in k:
						if floor.has(Vector2i(x + dx, y + dy)):
							clear[Vector2i(x + dx, y + dy)] = true
	var least := maxi(24, k * k + 4)
	var id := 0
	var done := {}
	for cell: Vector2i in clear:
		if done.has(cell):
			continue
		var piece := _fill_through(lay, cell, clear)
		for c in piece:
			done[c] = true
		if piece.size() < least:
			continue
		id += 1
		for c in piece:
			room_of[c] = id
	# Slivers the squares leave in a room's corners join it.
	var seen := {}
	for cell: Vector2i in floor:
		if room_of.has(cell) or seen.has(cell):
			continue
		var piece := _fill(lay, cell, func(c: Vector2i) -> bool: return not room_of.has(c))
		for c in piece:
			seen[c] = true
		if piece.size() >= 4:
			continue
		var near := 0
		for c in piece:
			for way in WAYS:
				if room_of.has(c + way) and _steps(lay, c, way):
					near = room_of[c + way]
		if near != 0:
			for c in piece:
				room_of[c] = near


## Floor, or a pillar (a rock piece no bigger than [param options] "pillars"
## cells, inside the floor: a hall's columns), counted as floor for finding rooms.
static func _solid(lay: Dictionary, cell: Vector2i) -> bool:
	return lay["floor"].has(cell) or lay["pillars"].has(cell)


static func _open(lay: Dictionary, from: Vector2i, way: Vector2i) -> bool:
	if lay["pillars"].has(from) or lay["pillars"].has(from + way):
		return _solid(lay, from + way)
	return _steps(lay, from, way)


## The cells of [param keep] reached from [param start], stepping past a
## pillar's corner as round it.
static func _fill_through(lay: Dictionary, start: Vector2i, keep: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = [start]
	var seen := {start: true}
	var at := 0
	while at < out.size():
		var cell := out[at]
		at += 1
		for way in AROUND:
			var next := cell + way
			if seen.has(next) or not keep.has(next):
				continue
			if way.x != 0 and way.y != 0:
				if not (lay["pillars"].has(cell + Vector2i(way.x, 0)) or lay["pillars"].has(cell + Vector2i(0, way.y))):
					continue
			elif not _steps(lay, cell, way):
				continue
			seen[next] = true
			out.append(next)
	return out


## The pieces of rock inside the floor's frame, each an Array of cells; the
## one touching the frame (the outside) is left out.
static func _rock_pieces(lay: Dictionary) -> Array:
	var low: Vector2i = lay["low"] - Vector2i.ONE
	var high: Vector2i = lay["high"] + Vector2i.ONE
	var floor: Dictionary = lay["floor"]
	var seen := {}
	var out := []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var start := Vector2i(x, y)
			if floor.has(start) or seen.has(start):
				continue
			var piece: Array[Vector2i] = [start]
			seen[start] = true
			var outside := false
			var at := 0
			while at < piece.size():
				var cell := piece[at]
				at += 1
				if cell.x <= low.x or cell.y <= low.y or cell.x >= high.x or cell.y >= high.y:
					outside = true
				for way in WAYS:
					var next := cell + way
					if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
						continue
					if not floor.has(next) and not seen.has(next):
						seen[next] = true
						piece.append(next)
			if not outside:
				out.append(piece)
	return out


## What stands in the level: [{cell, kind, what}], kind purpose | monster |
## light | dressing | sight | start | link.
static func _things(level: Dictionary, options: Dictionary) -> Array:
	var out: Array = []
	var terrain: Dictionary = level.get("terrain", {})
	for spec: Dictionary in level.get("entities", []):
		var at: Variant = spec.get("tile")
		if not at is Vector2i:
			continue
		var monster: bool = spec.has("home") or spec.has("named")
		out.append({"cell": at, "kind": "monster" if monster else "purpose", "what": str(spec.get("name", spec.get("kind", "thing")))})
	for link: Dictionary in level.get("links", []):
		if link.get("tile") is Vector2i:
			out.append({"cell": link["tile"], "kind": "link", "what": "link to " + str(link.get("to_map", ""))})
	for start: Variant in level.get("starts", []):
		if start is Vector2i:
			out.append({"cell": start, "kind": "start", "what": "start"})
	for building: Dictionary in level.get("buildings", []):
		if building.get("cell") is Vector2i:
			out.append({"cell": building["cell"], "kind": "purpose", "what": str(building.get("slot", building.get("kind", "building")))})
	var places: Variant = level.get("places", {})
	if places is Dictionary:
		for key: Variant in places:
			var place: Variant = places[key]
			if place is Dictionary and (place as Dictionary).get("cell") is Vector2i:
				out.append({"cell": place["cell"], "kind": "purpose", "what": "place " + str(key)})
	for niche: Dictionary in terrain.get("niches", []):
		if niche.get("cell") is Vector2i:
			out.append({"cell": niche["cell"], "kind": "purpose", "what": "niche"})
	for row: Dictionary in terrain.get("decor", []):
		if row.get("cell") is Vector2i:
			var kind := str(row.get("kind", ""))
			var light := LIGHT_WORDS.any(func(word: String) -> bool: return kind.contains(word))
			var sight := SIGHT_WORDS.any(func(word: String) -> bool: return kind.contains(word))
			out.append({"cell": row["cell"], "kind": "light" if light else ("sight" if sight else "dressing"), "what": kind})
	for key in ["torches", "lanterns", "lamps"]:
		for cell: Variant in terrain.get(key, []):
			if cell is Vector2i:
				out.append({"cell": cell, "kind": "light", "what": key})
	for cell: Variant in terrain.get("stairs", {}):
		if cell is Vector2i:
			out.append({"cell": cell, "kind": "purpose", "what": "stair"})
	return out


static func _holds(lay: Dictionary, node: int) -> bool:
	var held: Dictionary = lay["held"].get(node, {})
	return held.has("purpose") or held.has("sight") or held.has("link") or held.has("start")


static func _centre(cells: Array) -> Vector2i:
	var sum := Vector2i.ZERO
	for cell: Vector2i in cells:
		sum += cell
	var mid := Vector2(sum) / maxf(1.0, cells.size())
	var best: Vector2i = cells[0] if not cells.is_empty() else Vector2i.ZERO
	for cell: Vector2i in cells:
		if Vector2(cell).distance_squared_to(mid) < Vector2(best).distance_squared_to(mid):
			best = cell
	return best


static func _cells_of(lay: Dictionary, node: int) -> Array:
	var out: Array = []
	for cell: Vector2i in lay["floor"]:
		if _node(lay, cell) == node:
			out.append(cell)
	return out


static func _room_ids(lay: Dictionary) -> Array:
	var ids := {}
	for cell: Vector2i in lay["room_of"]:
		ids[lay["room_of"][cell]] = true
	var out := ids.keys()
	out.sort()
	return out


# --- The rules.

static func _purpose(lay: Dictionary, faults: Array) -> void:
	for room: int in _room_ids(lay):
		var cells := _cells_of(lay, room)
		if cells.is_empty():
			continue
		if lay["named"] and str(lay["uses"].get(room, "")).is_empty():
			faults.append({"rule": "purpose", "cell": _centre(cells), "what": "a room with no use"})
		elif not _holds(lay, room) and not (lay["held"].get(room, {}) as Dictionary).has("monster") and not (lay["held"].get(room, {}) as Dictionary).has("sight"):
			# Jeff, 11-04: "no room should be empty ... a reward, a visual point of
			# interest, an enemy, a npc, chest, loot, secret, lore exposition,
			# transition to a new area. anything but an empty square."
			var held: Dictionary = lay["held"].get(room, {})
			faults.append({"rule": "purpose", "cell": _centre(cells),
				"what": "an empty room%s" % (" (only %s)" % ", ".join(held.keys()) if not held.is_empty() else "")})


static func _wraps(lay: Dictionary, faults: Array) -> void:
	var corridors := {}
	for cell: Vector2i in lay["corridor_of"]:
		(corridors.get_or_add(lay["corridor_of"][cell], []) as Array).append(cell)
	for room: int in _room_ids(lay):
		var cells := _cells_of(lay, room)
		var box := Rect2i(cells[0], Vector2i.ONE)
		for cell: Vector2i in cells:
			box = box.expand(cell).expand(cell + Vector2i.ONE)
		var wrapped := false
		for corridor: int in corridors:
			var mine := {}
			for cell: Vector2i in corridors[corridor]:
				mine[cell] = true
			var sides := 0
			# Each side: the band of cells outside it, and how much of its
			# length the corridor covers there.
			for side in 4:
				var along := box.size.x if side < 2 else box.size.y
				if along < 4:
					continue
				var covered := 0
				for i in along:
					for d in range(1, WRAP_BAND + 1):
						var cell: Vector2i
						match side:
							0: cell = Vector2i(box.position.x + i, box.position.y - d)
							1: cell = Vector2i(box.position.x + i, box.end.y - 1 + d)
							2: cell = Vector2i(box.position.x - d, box.position.y + i)
							_: cell = Vector2i(box.end.x - 1 + d, box.position.y + i)
						if mine.has(cell):
							covered += 1
							break
				if covered >= WRAP_SHARE * along:
					sides += 1
			if sides >= 2:
				wrapped = true
				faults.append({"rule": "wrap", "cell": _centre(cells), "what": "a corridor runs along %d of this room's sides" % sides})
				break
		if wrapped:
			continue


static func _doors(lay: Dictionary, faults: Array) -> void:
	var done := {}
	for cell: Vector2i in lay["floor"]:
		for way in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not _door(lay, cell, way) or not lay["floor"].has(cell + way):
				continue
			for side: Vector2i in [cell, cell + way]:
				var node := _node(lay, side)
				if node == 0 or done.has(node):
					continue
				var ways_out: int = (lay["adjacent"].get(node, {}) as Dictionary).size()
				if ways_out <= 1 and not _holds(lay, node):
					done[node] = true
					faults.append({"rule": "door", "cell": side,
						"what": "a door to %s" % ("a stub" if node >= 1000 else "a closet with nothing in it")})


## How many cells deep [param cells] (a corridor) run from the floor
## outside them: 1 for a row along a room's side.
static func _depth(lay: Dictionary, cells: Array) -> int:
	var inside := {}
	for cell: Vector2i in cells:
		inside[cell] = true
	var dist := {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in cells:
		for way in WAYS:
			if lay["floor"].has(cell + way) and not inside.has(cell + way) and _steps(lay, cell, way):
				dist[cell] = 1
				queue.append(cell)
				break
	var at := 0
	var most := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		most = maxi(most, dist[cell])
		for way in WAYS:
			var next := cell + way
			if inside.has(next) and not dist.has(next) and _steps(lay, cell, way):
				dist[next] = int(dist[cell]) + 1
				queue.append(next)
	return most


static func _dead_ends(lay: Dictionary, faults: Array) -> void:
	# A corridor joined to one node or none: a stub.
	var stubs := {}
	var corridors := {}
	for cell: Vector2i in lay["corridor_of"]:
		(corridors.get_or_add(1000 + int(lay["corridor_of"][cell]), []) as Array).append(cell)
	for node: int in corridors:
		if (lay["adjacent"].get(node, {}) as Dictionary).size() <= 1:
			stubs[node] = true
			# A bulge in a room's rough side (a mine's) is no way anywhere:
			# a stub counts from STUB_DEEP cells in.
			if not _holds(lay, node) and _depth(lay, corridors[node]) >= STUB_DEEP:
				var held: Dictionary = lay["held"].get(node, {})
				faults.append({"rule": "dead_end", "cell": _centre(corridors[node]),
					"what": "a stub holding %s" % ("only a monster" if held.has("monster") else "nothing")})
	# The ends of a corridor's spurs: its thinned line's tips, away from any
	# room, start or link.
	var line := _thin(lay["corridor_of"])
	var near := {}
	for cell: Vector2i in lay["room_of"]:
		near[cell] = true
	for thing: Dictionary in lay["things"]:
		if thing["kind"] in ["link", "start"]:
			near[thing["cell"]] = true
	var tips: Array[Vector2i] = []
	for cell: Vector2i in line:
		if stubs.has(1000 + int(lay["corridor_of"][cell])):
			continue
		var neighbours := 0
		for way in AROUND:
			if line.has(cell + way):
				neighbours += 1
		if neighbours != 1:
			continue
		var close := false
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				if near.has(cell + Vector2i(dx, dy)):
					close = true
		if close or tips.any(func(t: Vector2i) -> bool: return absi(t.x - cell.x) <= 3 and absi(t.y - cell.y) <= 3):
			continue
		tips.append(cell)
		var holds := ""
		var monster := false
		for thing: Dictionary in lay["things"]:
			if Vector2(thing["cell"]).distance_to(Vector2(cell)) <= 3.5 and lay["corridor_of"].has(thing["cell"]):
				if thing["kind"] == "purpose":
					holds = thing["what"]
				elif thing["kind"] == "monster":
					monster = true
		if holds.is_empty():
			faults.append({"rule": "dead_end", "cell": cell, "what": "a dead end holding %s" % ("only a monster" if monster else "nothing")})


## Zhang-Suen thinning of the cells in [param cells] (corridor floor).
static func _thin(cells: Dictionary) -> Dictionary:
	var on := cells.duplicate()
	var changed := true
	while changed:
		changed = false
		for step in 2:
			var drop: Array[Vector2i] = []
			for cell: Vector2i in on:
				var p: Array[int] = []
				for way in [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
						Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]:
					p.append(1 if on.has(cell + way) else 0)
				var b := 0
				var a := 0
				for i in 8:
					b += p[i]
					if p[i] == 0 and p[(i + 1) % 8] == 1:
						a += 1
				if b < 2 or b > 6 or a != 1:
					continue
				if step == 0 and (p[0] * p[2] * p[4] != 0 or p[2] * p[4] * p[6] != 0):
					continue
				if step == 1 and (p[0] * p[2] * p[6] != 0 or p[0] * p[4] * p[6] != 0):
					continue
				drop.append(cell)
			for cell in drop:
				on.erase(cell)
			if not drop.is_empty():
				changed = true
	return on


static func _loops(lay: Dictionary, faults: Array) -> void:
	for piece: Array in lay["rock"]:
		if piece.size() < LOOP_ROCK or lay["pillars"].has(piece[0]):
			continue
		if true:
			var rooms := {}
			var corridor := false
			var heights := {}
			for cell in piece:
				for way in AROUND:
					var node := _node(lay, cell + way)
					if node != 0 and not (lay["relief"] as PackedFloat32Array).is_empty():
						heights[snappedf(Relief.at(lay["relief"], lay["relief_size"], cell + way), 0.25)] = true
					if lay["stairs"].has(cell + way):
						heights[-99.0] = true
					if node >= 1000:
						corridor = true
					elif node > 0:
						rooms[node] = true
			# A ring that climbs (a pit's way out, a stair round a ledge) goes
			# somewhere: only a ring on one level is a loop with no meaning.
			if not corridor or rooms.size() >= 2 or heights.size() > 1:
				continue
			faults.append({"rule": "loop", "cell": _centre(piece), "what": "a loop round %d cells of plain rock, through %d rooms" % [piece.size(), rooms.size()]})


static func _spine(lay: Dictionary, options: Dictionary, faults: Array) -> void:
	var floor: Dictionary = lay["floor"]
	if floor.is_empty():
		return
	var start: Vector2i = floor.keys()[0]
	for thing: Dictionary in lay["things"]:
		if thing["kind"] == "start":
			start = thing["cell"]
			break
	# Distances from the start, by steps.
	var dist := {start: 0}
	var prev := {}
	var queue: Array[Vector2i] = [start]
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		for way in WAYS:
			var next := cell + way
			if not dist.has(next) and _steps(lay, cell, way):
				dist[next] = int(dist[cell]) + 1
				prev[next] = cell
				queue.append(next)
	var heart: Variant = options.get("heart")
	if not heart is Vector2i:
		var best := -1
		for anchor: Variant in options.get("anchors", []):
			if not anchor is Dictionary:
				continue
			var rect: Variant = (anchor as Dictionary).get("rect")
			if rect is Rect2i:
				rect = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			if not rect is Array:
				continue
			for cell in _room_cells({"rect": rect}):
				if dist.has(cell) and int(dist[cell]) > best:
					best = dist[cell]
					heart = cell
		if not heart is Vector2i:
			for cell: Vector2i in dist:
				if int(dist[cell]) > best:
					best = dist[cell]
					heart = cell
	if not dist.has(heart):
		faults.append({"rule": "spine", "cell": heart, "what": "the heart can't be walked to from the start"})
		return
	var walked: int = dist[heart]
	var straight := Vector2(start).distance_to(Vector2(heart))
	if straight > 0.0 and walked > SPINE_DETOUR * straight:
		faults.append({"rule": "spine", "cell": heart, "what": "the walk to the heart is %.1f times the straight line" % (walked / straight)})
	# The spine's rooms, and each room's steps off them through the rooms.
	var on := {}
	var cell: Vector2i = heart
	while true:
		var node := _node(lay, cell)
		if node != 0:
			on[node] = true
		if not prev.has(cell):
			break
		cell = prev[cell]
	var depth := {}
	var queue2: Array = []
	for node: int in on:
		if node < 1000:
			depth[node] = 0
			queue2.append(node)
		else:
			for room: int in lay["adjacent"].get(node, {}):
				if room < 1000 and not depth.has(room):
					depth[room] = 1
					queue2.append(room)
	var through := func(room: int) -> Array:
		var out := []
		for next: int in lay["adjacent"].get(room, {}):
			if next < 1000:
				out.append(next)
			else:
				for beyond: int in lay["adjacent"].get(next, {}):
					if beyond < 1000 and beyond != room:
						out.append(beyond)
		return out
	at = 0
	while at < queue2.size():
		var room: int = queue2[at]
		at += 1
		for next: int in through.call(room):
			if not depth.has(next):
				depth[next] = int(depth[room]) + 1
				queue2.append(next)
	for room: int in _room_ids(lay):
		if lay["wings"].has(room):
			continue
		if not depth.has(room) or int(depth[room]) > 1:
			faults.append({"rule": "spine", "cell": _centre(_cells_of(lay, room)),
				"what": "a room %s steps off the spine" % (str(depth[room]) if depth.has(room) else "unreached")})


static func _chests(level: Dictionary, lay: Dictionary, options: Dictionary, faults: Array) -> void:
	var monsters: Array[Vector2i] = []
	for thing: Dictionary in lay["things"]:
		if thing["kind"] == "monster":
			monsters.append(thing["cell"])
	for spec: Dictionary in level.get("entities", []):
		if spec.get("script") != Level.CHEST or not spec.get("tile") is Vector2i:
			continue
		var props: Dictionary = spec.get("props", {})
		if props.has("role") or props.get("depot", false) or props.get("shop", false) or props.get("locker", false) or props.get("temple", false):
			continue
		var at: Vector2i = spec["tile"]
		var name := str(spec.get("name", "chest"))
		var gives := not str(props.get("cache", "")).is_empty()
		for slot: Variant in props.get("slots", []):
			if not str(slot).is_empty():
				gives = true
		if not gives:
			faults.append({"rule": "chest", "cell": at, "what": "%s gives nothing" % name})
		if not options.get("dungeon", false):
			faults.append({"rule": "chest", "cell": at, "what": "%s outside a dungeon" % name})
			continue
		var room := _node_at(lay, at)
		var guarded := false
		var near := {at: 0}
		var queue: Array[Vector2i] = [at]
		var i := 0
		while i < queue.size() and not guarded:
			var cell := queue[i]
			i += 1
			if cell in monsters:
				guarded = true
				break
			if int(near[cell]) >= GUARD_REACH:
				continue
			for way in WAYS:
				var next := cell + way
				if not near.has(next) and _steps(lay, cell, way):
					near[next] = int(near[cell]) + 1
					queue.append(next)
		if not guarded and room != 0 and room < 1000:
			for cell in monsters:
				if _node(lay, cell) == room:
					guarded = true
		if not guarded:
			faults.append({"rule": "chest", "cell": at, "what": "%s unguarded" % name})
