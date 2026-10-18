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
## and anchors, a door where a corridor meets a room, torches along the
## ways and inside the doors, alcoves off the rooms. "old" (the older
## labyrinths below, lore's third style): caverns grown from a seed cell,
## crooked ways by a walk biased toward where they go, blind ways wandering
## off into the rock, no doors, no torches (dark: lanterns matter). Both:
## the anchors and rooms are joined by a minimum spanning tree over their
## centres plus a share of extra ways for loops, then joined up wherever
## the anchors cut the map apart.
##
## The block's own keys (Level.regenerate_from passes them): "style"
## ("dwarven" unless "old"), "rooms": {"count": [lo, hi], "size": [[w, h]
## least, [w, h] most]}, "loops": the extra ways as a share of the nodes
## (0.2), "monsters": {kind: count} (brutes in the halls first, the rest in
## rooms and corridors), "chests": n (alcoves and blind ways first, then
## room corners), "crates": n (in rooms).

const Tools := preload("res://sim/level_gen/gen_tools.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLOOR := "stone"
const DEFAULT_COUNT: Array[int] = [6, 10]
const DEFAULT_LEAST := Vector2i(3, 3)
const DEFAULT_MOST := Vector2i(7, 7)
const DEFAULT_LOOPS := 0.2
## Great halls a dwarven level gets, when it has rooms enough.
const HALLS := 2
## A torch every so many corridor cells, dwarven.
const TORCH_EVERY := 8
## How far a crooked way leans toward where it goes.
const LEAN := 0.65


static func generate(template: LevelMap, config: Dictionary, seed: int) -> LevelMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchors: Array = config.get("anchors", [])
	var old := str(config.get("style", "dwarven")) == "old"
	var map := template.copy()
	Tools.clear_outside(map, anchors)
	var carved: Dictionary[Vector2i, bool] = {}
	var nodes := _anchor_nodes(template, anchors)
	var rooms := _place_rooms(map, anchors, config, old, rng, carved)
	nodes.append_array(rooms)
	var corridors: Dictionary[Vector2i, bool] = {}
	for way in _ways(nodes, config, rng):
		_carve_way(map, template, anchors, nodes[way[0]], nodes[way[1]], old, rng, carved, corridors)
	var ends := _blind_ways(map, anchors, rooms, corridors, old, rng, carved)
	Tools.join_up(map, anchors, carved)
	if not old:
		_torches(map, anchors, rooms, corridors)
	_markers(map, anchors, rooms, corridors, ends, config, rng)
	return map


# --- Nodes: anchors and rooms --------------------------------------------------------

## Each anchor as a node: {cells (its walkable cells), rect, centre, kind
## "anchor", doors: []}.
static func _anchor_nodes(template: LevelMap, anchors: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for anchor: Dictionary in anchors:
		var rect: Rect2i = anchor["rect"]
		var cells: Dictionary[Vector2i, bool] = {}
		for cell in Level.rect_cells(rect):
			if template.walkable(cell):
				cells[cell] = true
		out.append({"cells": cells, "rect": rect, "centre": rect.position + rect.size / 2, "kind": "anchor", "doors": []})
	return out


## Rooms placed at random in the rock, a cell of rock at least between
## any two and from the anchors and the map's edge: "count" of them (a
## draw between lo and hi), each "size" between least and most. Dwarven:
## rectangles, the first HALLS of them great halls (wider, a row of pillars
## down the middle, kind "hall"); old: caverns, a blob grown inside the
## rectangle. Each a node {cells, rect, centre, kind, doors}.
static func _place_rooms(map: LevelMap, anchors: Array, config: Dictionary, old: bool, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool]) -> Array[Dictionary]:
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
		taken.append((anchor["rect"] as Rect2i).grow(1))
	var rooms: Array[Dictionary] = []
	var halls_wanted := HALLS if not old and count >= 4 else 0
	for attempt in count * 40:
		if rooms.size() >= count:
			break
		var hall := rooms.size() < halls_wanted
		var size := Vector2i(rng.randi_range(least.x, most.x), rng.randi_range(least.y, most.y))
		if hall:
			size = Vector2i(rng.randi_range(most.x, most.x + 2), rng.randi_range(least.y + 1, least.y + 2))
			if rng.randf() < 0.5:
				size = Vector2i(size.y, size.x)
		if size.x > map.size.x - 2 or size.y > map.size.y - 2:
			continue
		var rect := Rect2i(Vector2i(rng.randi_range(1, map.size.x - size.x - 1), rng.randi_range(1, map.size.y - size.y - 1)), size)
		var clear := true
		for other in taken:
			if rect.intersects(other):
				clear = false
				break
		if not clear:
			continue
		var cells: Dictionary[Vector2i, bool] = {}
		if old:
			cells = _grow_cavern(rect, rng)
		else:
			for cell in Level.rect_cells(rect):
				if hall and _pillar(rect, cell):
					continue
				cells[cell] = true
		for cell: Vector2i in cells:
			Tools.carve(map, cell, carved)
		taken.append(rect.grow(1))
		rooms.append({"cells": cells, "rect": rect, "centre": rect.position + rect.size / 2, "kind": "hall" if hall else "room", "doors": []})
	return rooms


## Whether [param cell] of a great hall [param rect] is a pillar: inside
## its border ring, every other cell both ways (a row of pillars down a
## hall two cells deep inside, a grid in a wider one).
static func _pillar(rect: Rect2i, cell: Vector2i) -> bool:
	var offset := cell - rect.position
	if offset.x == 0 or offset.y == 0 or offset.x == rect.size.x - 1 or offset.y == rect.size.y - 1:
		return false
	return offset.x % 2 == 0 and offset.y % 2 == 0


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
static func _ways(nodes: Array[Dictionary], config: Dictionary, rng: RandomNumberGenerator) -> Array[Array]:
	var out: Array[Array] = []
	var n := nodes.size()
	if n < 2:
		return out
	var in_tree: Dictionary[int, bool] = {0: true}
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
static func _carve_way(map: LevelMap, template: LevelMap, anchors: Array, a: Dictionary, b: Dictionary, old: bool,
		rng: RandomNumberGenerator, carved: Dictionary[Vector2i, bool], corridors: Dictionary[Vector2i, bool]) -> void:
	var exit: Variant = _exit(map, template, anchors, a, b["centre"])
	var entry: Variant = _exit(map, template, anchors, b, a["centre"])
	if exit == null or entry == null:
		return
	var from: Vector2i = exit[0] + exit[1]
	var to: Vector2i = entry[0] + entry[1]
	var path: Array[Vector2i]
	if old:
		path = _crooked(map, anchors, from, to, rng)
	else:
		path = Tools.l_path(from, to, rng.randf() < 0.5)
	var wide: bool = not old and a["kind"] != "room" and b["kind"] != "room"
	var last := from
	for cell in path:
		_carve_corridor(map, anchors, cell, carved, corridors)
		if wide:
			# The cell beside it, across the way it runs.
			var step := cell - last
			var beside := cell + (Vector2i(0, 1) if step.x != 0 else Vector2i(1, 0))
			_carve_corridor(map, anchors, beside, carved, corridors)
		last = cell
	if not old:
		for end: Array in [[a, exit], [b, entry]]:
			var node: Dictionary = end[0]
			if node["kind"] == "anchor":
				continue  # Its border is the template's.
			var inside: Vector2i = end[1][0]
			map.set_edge(Terrain.edge_key(inside, end[1][1]), "door")
			node["doors"].append(inside)


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
		path.append_array(Tools.l_path(at, to, rng.randf() < 0.5).slice(1))
	return path


# --- Blind ways, torches, markers ------------------------------------------------------

## Ways that go nowhere, so the halls are never quite the same: dwarven,
## an alcove a cell deep off about half the rooms; old, a few crooked ways
## wandering off a corridor into the rock, four to ten cells, touching
## nothing. Returns their end cells (where a chest may sit).
static func _blind_ways(map: LevelMap, anchors: Array, rooms: Array[Dictionary], corridors: Dictionary[Vector2i, bool], old: bool,
		rng: RandomNumberGenerator, carved: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var ends: Array[Vector2i] = []
	if not old:
		for room in rooms:
			if rng.randf() < 0.5:
				continue
			var border: Array[Vector2i] = []
			var rect: Rect2i = room["rect"]
			for cell in Tools.sorted_cells(room["cells"]):
				if cell.x == rect.position.x or cell.y == rect.position.y or cell.x == rect.end.x - 1 or cell.y == rect.end.y - 1:
					border.append(cell)
			Tools.shuffle(border, rng)
			for cell in border:
				var placed := false
				for direction in DIRECTIONS:
					var out := cell + direction
					if rect.has_point(out) or not _lonely(map, anchors, out, cell, carved):
						continue
					Tools.carve(map, out, carved)
					ends.append(out)
					placed = true
					break
				if placed:
					break
		return ends
	var starts := Tools.sorted_cells(corridors)
	if starts.is_empty():
		return ends
	for k in maxi(2, rooms.size() / 2):
		var at: Vector2i = starts[rng.randi_range(0, starts.size() - 1)]
		var direction := DIRECTIONS[rng.randi_range(0, 3)]
		var length := rng.randi_range(4, 10)
		var last := at
		for step in length:
			if rng.randf() > 0.7:
				direction = DIRECTIONS[rng.randi_range(0, 3)]
			var next := last + direction
			if not _lonely(map, anchors, next, last, carved):
				break
			Tools.carve(map, next, carved)
			last = next
		if last != at:
			ends.append(last)
	return ends


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


## Dwarven light: a torch on the cell inside each door, and one every
## TORCH_EVERY corridor cells, never beside an anchor.
static func _torches(map: LevelMap, anchors: Array, rooms: Array[Dictionary], corridors: Dictionary[Vector2i, bool]) -> void:
	for room in rooms:
		for cell: Vector2i in room["doors"]:
			if map.cell(cell) == FLOOR:
				map.set_cell(cell, "torch")
	var i := 0
	for cell in Tools.sorted_cells(corridors):
		i += 1
		if i % TORCH_EVERY != 0 or map.cell(cell) != FLOOR or _beside_anchor(anchors, cell):
			continue
		map.set_cell(cell, "torch")


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
		ends: Array[Vector2i], config: Dictionary, rng: RandomNumberGenerator) -> void:
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
	var chest_spots: Array[Vector2i] = ends.duplicate()
	chest_spots.append_array(corners)
	chest_spots.append_array(room_cells)
	_lay(map, anchors, "chest", int(config.get("chests", 0)), chest_spots)
	_lay(map, anchors, "crate", int(config.get("crates", 0)), room_cells)
	var everywhere: Array[Vector2i] = room_cells.duplicate()
	everywhere.append_array(corridor_cells)
	Tools.shuffle(everywhere, rng)
	var counts: Variant = config.get("monsters", {})
	if not counts is Dictionary:
		return
	var kinds: Array = counts.keys()
	kinds.sort()
	for kind: String in kinds:
		var spots: Array[Vector2i] = []
		if kind == "brute":
			spots.append_array(hall_cells)
		spots.append_array(everywhere)
		_lay(map, anchors, "monster_" + kind, int(counts[kind]), spots)


## [param count] markers [param marker] on the first free floor cells of
## [param spots] (in their order), none beside an anchor.
static func _lay(map: LevelMap, anchors: Array, marker: String, count: int, spots: Array[Vector2i]) -> void:
	if count <= 0 or not map.colours.has(marker):
		return
	var laid := 0
	for cell in spots:
		if laid >= count:
			return
		if map.cell(cell) != FLOOR or _beside_anchor(anchors, cell):
			continue
		map.set_cell(cell, marker)
		laid += 1
