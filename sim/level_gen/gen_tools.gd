extends RefCounted
## What every level generator does the same (decisions 465, 470): clear
## the rock outside the anchors, carve, find the walkable parts the anchors
## sit in and join them up, shuffle with the generation's seed. No
## class_name: the generators preload it.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLOOR := "stone"


## Everything outside [param anchors] goes: cells, heights, and the edges
## between two outside cells (an edge on an anchor's border is the anchor's).
static func clear_outside(map: LevelMap, anchors: Array) -> void:
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


## Whether [param at] may be carved: in bounds and in no anchor (rock, or
## carved already).
static func rock(map: LevelMap, anchors: Array, at: Vector2i) -> bool:
	return map.in_bounds(at) and not Level.in_anchors(anchors, at)


## [param at] is floor now (a marker already there is left), and counted
## in [param carved].
static func carve(map: LevelMap, at: Vector2i, carved: Dictionary[Vector2i, bool]) -> void:
	if map.cell(at) == "void":
		map.set_cell(at, FLOOR)
	carved[at] = true


## The walkable parts of [param map] that hold anchor cells, each the
## cells of it, flood filled through open and door edges; the biggest first.
static func parts(map: LevelMap, anchors: Array) -> Array[Array]:
	var seen: Dictionary[Vector2i, bool] = {}
	var out: Array[Array] = []
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
			out.append(part)
	out.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return out


## Joins the parts the anchors cut apart: while two walkable parts hold
## anchor cells, the nearest pair of their cells is joined by a corridor,
## straight then turned, carved through the rock outside the anchors (an
## anchor cell in its way is stepped over, the anchor's own floor carrying
## the way, or not: Regen's flood fill is the judge).
static func join_up(map: LevelMap, anchors: Array, carved: Dictionary[Vector2i, bool]) -> void:
	for attempt in 16:
		var found := parts(map, anchors)
		if found.size() < 2:
			return
		var best_a := Vector2i.ZERO
		var best_b := Vector2i.ZERO
		var best := -1
		for cell_a: Vector2i in found[0]:
			for cell_b: Vector2i in found[1]:
				var d := absi(cell_a.x - cell_b.x) + absi(cell_a.y - cell_b.y)
				if best < 0 or d < best:
					best = d
					best_a = cell_a
					best_b = cell_b
		var path := l_path(best_a, best_b, true)
		if path.any(func(at: Vector2i) -> bool: return Level.in_anchors(anchors, at) and at != best_a and at != best_b):
			path = path_around(map, anchors, best_a, best_b)  # Round a walled anchor in the way.
		for at in path:
			if rock(map, anchors, at):
				carve(map, at, carved)


## The cells from [param from] to [param to], both included, along x then
## y ([param horizontal_first]) or y then x.
static func l_path(from: Vector2i, to: Vector2i, horizontal_first: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = [from]
	var at := from
	var axes: Array[int] = []
	axes.assign([0, 1] if horizontal_first else [1, 0])
	for axis in axes:
		while at[axis] != to[axis]:
			at[axis] += signi(to[axis] - at[axis])
			out.append(at)
	return out


## A way from [param from] to [param to] through the rock and what is
## carved, round the anchors (A*, Manhattan steps; neither end counts as
## in one): a walled anchor would cut a straight way (decision 541). With
## [param rng] each step costs 1 to 2 by a draw, so the way wanders. Both
## ends included; [from] alone when there is none.
static func path_around(map: LevelMap, anchors: Array, from: Vector2i, to: Vector2i, rng: RandomNumberGenerator = null) -> Array[Vector2i]:
	var open: Array[Vector2i] = [from]
	var came: Dictionary[Vector2i, Vector2i] = {}
	var cost: Dictionary[Vector2i, float] = {from: 0.0}
	var closed: Dictionary[Vector2i, bool] = {}
	while not open.is_empty():
		var best := 0
		var best_f := cost[open[0]] + distance(open[0], to)
		for i in range(1, open.size()):
			var f := cost[open[i]] + distance(open[i], to)
			if f < best_f:
				best_f = f
				best = i
		var at: Vector2i = open[best]
		open.remove_at(best)
		if at == to:
			var path: Array[Vector2i] = [to]
			while path[-1] != from:
				path.append(came[path[-1]])
			path.reverse()
			return path
		closed[at] = true
		for direction in DIRECTIONS:
			var next := at + direction
			if closed.has(next) or not map.in_bounds(next):
				continue
			if next != to and Level.in_anchors(anchors, next):
				continue
			var step := 1.0 if rng == null else 1.0 + rng.randf()
			var through := cost[at] + step
			if cost.has(next) and through >= cost[next]:
				continue
			cost[next] = through
			came[next] = at
			if next not in open:
				open.append(next)
	return [from]


## [param cells] in a random order, by [param rng] (Fisher-Yates), in place.
static func shuffle(cells: Array, rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = cells[i]
		cells[i] = cells[j]
		cells[j] = swap


## [param keyed]'s cell keys, sorted: a set order to draw from.
static func sorted_cells(keyed: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(keyed.keys())
	out.sort()
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
