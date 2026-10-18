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

const Tools := preload("res://sim/level_gen/gen_tools.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Doorways an anchor gets: one, or two when it has room for them.
const DOORWAYS_MOST := 2


static func generate(template: LevelMap, config: Dictionary, seed: int) -> LevelMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchors: Array = config.get("anchors", [])
	var map := template.copy()
	Tools.clear_outside(map, anchors)
	var carved: Dictionary[Vector2i, bool] = {}
	_carve_maze(map, anchors, rng, carved)
	for anchor: Dictionary in anchors:
		_open_doorways(map, template, anchor, anchors, rng, carved)
	Tools.join_up(map, anchors, carved)
	_lay_monsters(map, anchors, config.get("monsters", {}), rng, carved)
	return map


## A perfect maze on the odd cells outside the anchors, carved from every
## node not reached yet (the anchors may cut the grid into parts).
static func _carve_maze(map: LevelMap, anchors: Array, rng: RandomNumberGenerator, carved: Dictionary[Vector2i, bool]) -> void:
	var nodes: Array[Vector2i] = []
	for y in range(1, map.size.y, 2):
		for x in range(1, map.size.x, 2):
			if Tools.rock(map, anchors, Vector2i(x, y)):
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
		Tools.carve(map, start, carved)
		while not stack.is_empty():
			var here: Vector2i = stack.back()
			var options: Array[Vector2i] = []
			for direction in DIRECTIONS:
				var next := here + direction * 2
				var between := here + direction
				if Tools.rock(map, anchors, next) and Tools.rock(map, anchors, between) and not visited.has(next):
					options.append(direction)
			if options.is_empty():
				stack.pop_back()
				continue
			var direction: Vector2i = options[rng.randi_range(0, options.size() - 1)]
			Tools.carve(map, here + direction, carved)
			Tools.carve(map, here + direction * 2, carved)
			visited[here + direction * 2] = true
			stack.append(here + direction * 2)


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
			if rect.has_point(outside) or not Tools.rock(map, anchors, outside):
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
		while Tools.rock(map, anchors, at) and steps < 3:
			if carved.has(at):
				break
			Tools.carve(map, at, carved)
			at += direction
			steps += 1


## Monster markers, [param counts] of each kind, on the carved cells: dead
## ends first (a corridor cell with one walkable neighbour), the rest after,
## never beside an anchor. A kind the legend has no colour for is skipped.
static func _lay_monsters(map: LevelMap, anchors: Array, counts: Dictionary, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool]) -> void:
	if counts.is_empty():
		return
	var ends: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for at in Tools.sorted_cells(carved):
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
	Tools.shuffle(ends, rng)
	Tools.shuffle(rest, rng)
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
