extends RefCounted
## The "maze" generator (decision 465): corridors between a regenerating
## level's anchors. Every generator is a script here, sim/level_gen/<name>.gd,
## with a static generate(template, config, seed) -> LevelMap; Regen loads
## it by the name level.json's "regenerate" gives.
##
## The anchors' cells, edges and heights are the template's, untouched.
## Outside them the map is cleared to rock (void) and a perfect maze is
## carved in it, one cell wide, with the recursive backtracker on the odd
## cells; each anchor gets a doorway or two where its floor meets the
## outside through an open edge (a wall pixel on the anchor's side seals
## that side); the maze is then joined up wherever the anchors cut it
## apart. Monster markers (config "monsters": {kind: count}) go on dead
## ends first, then any corridor cell. The same seed gives the same map.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLOOR := "stone"
## Doorways an anchor gets: one, or two when it has room for them.
const DOORWAYS_MOST := 2


static func generate(template: LevelMap, config: Dictionary, seed: int) -> LevelMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchors: Array = config.get("anchors", [])
	var map := template.copy()
	_clear_outside(map, anchors)
	var carved: Dictionary[Vector2i, bool] = {}
	_carve_maze(map, anchors, rng, carved)
	for anchor: Dictionary in anchors:
		_open_doorways(map, template, anchor, anchors, rng, carved)
	_join_up(map, anchors, carved)
	_lay_monsters(map, anchors, config.get("monsters", {}), rng, carved)
	return map


## Everything outside [param anchors] goes: cells, heights, and the edges
## between two outside cells (an edge on an anchor's border is the anchor's).
static func _clear_outside(map: LevelMap, anchors: Array) -> void:
	for at: Vector2i in map.cells.keys():
		if not Level.in_anchors(anchors, at):
			map.cells.erase(at)
	for at: Vector2i in map.heights.keys():
		if not Level.in_anchors(anchors, at):
			map.heights.erase(at)
	for key: Vector3i in map.edges.keys():
		var sides := Terrain.edge_cells(key)
		if not Level.in_anchors(anchors, sides[0]) and not Level.in_anchors(anchors, sides[1]):
			map.edges.erase(key)


## Whether [param at] may be carved: in bounds and in no anchor.
static func _free(map: LevelMap, anchors: Array, at: Vector2i) -> bool:
	return map.in_bounds(at) and not Level.in_anchors(anchors, at)


## A perfect maze on the odd cells outside the anchors, carved from every
## node not reached yet (the anchors may cut the grid into parts).
static func _carve_maze(map: LevelMap, anchors: Array, rng: RandomNumberGenerator, carved: Dictionary[Vector2i, bool]) -> void:
	var nodes: Array[Vector2i] = []
	for y in range(1, map.size.y, 2):
		for x in range(1, map.size.x, 2):
			if _free(map, anchors, Vector2i(x, y)):
				nodes.append(Vector2i(x, y))
	var visited: Dictionary[Vector2i, bool] = {}
	# The first node is drawn at random; every later part starts from its
	# first unvisited node, in order, so the draw stays reproducible.
	if nodes.is_empty():
		return
	var first: Vector2i = nodes[rng.randi_range(0, nodes.size() - 1)]
	var starts: Array[Vector2i] = [first]
	starts.append_array(nodes)
	for start in starts:
		if visited.has(start):
			continue
		var stack: Array[Vector2i] = [start]
		visited[start] = true
		_carve(map, start, carved)
		while not stack.is_empty():
			var here: Vector2i = stack.back()
			var options: Array[Vector2i] = []
			for direction in DIRECTIONS:
				var next := here + direction * 2
				var between := here + direction
				if _free(map, anchors, next) and _free(map, anchors, between) and not visited.has(next):
					options.append(direction)
			if options.is_empty():
				stack.pop_back()
				continue
			var direction: Vector2i = options[rng.randi_range(0, options.size() - 1)]
			_carve(map, here + direction, carved)
			_carve(map, here + direction * 2, carved)
			visited[here + direction * 2] = true
			stack.append(here + direction * 2)


static func _carve(map: LevelMap, at: Vector2i, carved: Dictionary[Vector2i, bool]) -> void:
	map.set_cell(at, FLOOR)
	carved[at] = true


## [param anchor]'s doorways: its walkable border cells whose outside
## neighbour is free and whose edge between is open in [param template],
## drawn at random; the outside cell is carved, and on from it in the same
## direction until the carving meets the maze (two cells at most: every
## other row and column of the maze is a passage).
static func _open_doorways(map: LevelMap, template: LevelMap, anchor: Dictionary, anchors: Array, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool]) -> void:
	var rect: Rect2i = anchor["rect"]
	var candidates: Array[Array] = []  # [cell, direction]
	for cell in Level.rect_cells(rect):
		if not template.walkable(cell):
			continue
		for direction in DIRECTIONS:
			var outside := cell + direction
			if rect.has_point(outside) or not _free(map, anchors, outside):
				continue
			if template.edge(Terrain.edge_key(cell, direction)) == "wall":
				continue
			candidates.append([cell, direction])
	if candidates.is_empty():
		return
	var wanted := mini(DOORWAYS_MOST, candidates.size())
	var sides_used: Dictionary[Vector2i, bool] = {}
	for i in wanted:
		# Each doorway on a side of its own while there are sides left.
		var picks := candidates.filter(func(each: Array) -> bool: return not sides_used.has(each[1]))
		if picks.is_empty():
			picks = candidates
		var pick: Array = picks[rng.randi_range(0, picks.size() - 1)]
		candidates.erase(pick)
		var direction: Vector2i = pick[1]
		sides_used[direction] = true
		var at: Vector2i = pick[0] + direction
		var steps := 0
		while _free(map, anchors, at) and steps < 3:
			if carved.has(at):
				break
			_carve(map, at, carved)
			at += direction
			steps += 1


## Joins the parts of the map the anchors cut apart: while two walkable
## parts hold anchor cells, the nearest pair of their cells is joined by a
## corridor, straight then turned, carved through the rock outside the
## anchors (an anchor cell in its way is stepped over, the anchor's own
## floor carrying the way, or not: Regen's flood fill is the judge).
static func _join_up(map: LevelMap, anchors: Array, carved: Dictionary[Vector2i, bool]) -> void:
	for attempt in 16:
		var parts := _parts(map, anchors)
		if parts.size() < 2:
			return
		var best_a := Vector2i.ZERO
		var best_b := Vector2i.ZERO
		var best := -1
		for cell_a: Vector2i in parts[0]:
			for cell_b: Vector2i in parts[1]:
				var d := absi(cell_a.x - cell_b.x) + absi(cell_a.y - cell_b.y)
				if best < 0 or d < best:
					best = d
					best_a = cell_a
					best_b = cell_b
		# Along x then along y, carving what is outside every anchor.
		var at := best_a
		while at.x != best_b.x:
			at.x += signi(best_b.x - at.x)
			if _free(map, anchors, at):
				_carve(map, at, carved)
		while at.y != best_b.y:
			at.y += signi(best_b.y - at.y)
			if _free(map, anchors, at):
				_carve(map, at, carved)


## The walkable parts of [param map] that hold anchor cells, each the
## cells of it, flood filled through open and door edges; the biggest first.
static func _parts(map: LevelMap, anchors: Array) -> Array[Array]:
	var seen: Dictionary[Vector2i, bool] = {}
	var parts: Array[Array] = []
	for anchor: Dictionary in anchors:
		for start in Level.rect_cells(anchor["rect"]):
			if seen.has(start) or not map.walkable(start):
				continue
			var part: Array[Vector2i] = []
			var queue: Array[Vector2i] = [start]
			seen[start] = true
			while not queue.is_empty():
				var here: Vector2i = queue.pop_front()
				part.append(here)
				for direction in DIRECTIONS:
					var next := here + direction
					if seen.has(next) or not map.in_bounds(next) or not map.walkable(next):
						continue
					if map.edge(Terrain.edge_key(here, direction)) == "wall":
						continue
					seen[next] = true
					queue.append(next)
			parts.append(part)
	parts.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return parts


## Monster markers, [param counts] of each kind, on the carved cells: dead
## ends first (a corridor cell with one walkable neighbour), the rest after,
## never beside an anchor. A kind the legend has no colour for is skipped.
static func _lay_monsters(map: LevelMap, anchors: Array, counts: Dictionary, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool]) -> void:
	if counts.is_empty():
		return
	var ends: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for at: Vector2i in carved:
		var beside_anchor := false
		var open := 0
		for direction in DIRECTIONS:
			var next := at + direction
			if Level.in_anchors(anchors, next):
				beside_anchor = true
			if map.walkable(next):
				open += 1
		if beside_anchor:
			continue
		if open <= 1:
			ends.append(at)
		else:
			rest.append(at)
	ends.sort()
	rest.sort()
	_shuffle(ends, rng)
	_shuffle(rest, rng)
	var cells := ends
	cells.append_array(rest)
	var kinds: Array = counts.keys()
	kinds.sort()
	var i := 0
	for kind: String in kinds:
		var marker := "monster_" + kind
		if not map.colours.has(marker):
			continue
		for n in int(counts[kind]):
			if i >= cells.size():
				return
			map.set_cell(cells[i], marker)
			i += 1


static func _shuffle(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cells[i]
		cells[i] = cells[j]
		cells[j] = swap
