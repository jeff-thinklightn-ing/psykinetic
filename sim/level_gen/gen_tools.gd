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


## Whether [param at] may be carved: in bounds, in no anchor (rock, or
## carved already) and, when the map carries a footprint (659, the tower:
## extras "footprint", the cells inside the tower's outline), inside it.
static func rock(map: LevelMap, anchors: Array, at: Vector2i) -> bool:
	if not map.in_bounds(at) or Level.in_anchors(anchors, at):
		return false
	return not map.extras.has("footprint") or (map.extras["footprint"] as Dictionary).has(at)


## [param at] is floor now (a marker already there is left), and counted
## in [param carved].
static func carve(map: LevelMap, at: Vector2i, carved: Dictionary[Vector2i, bool]) -> void:
	if map.cell(at) == "void":
		map.set_cell(at, FLOOR)
	carved[at] = true


## The width rule (612, Level.narrow_runs_by) on [param map]: the cells of
## its single-width runs, each with its axis (0 along x, 1 along y);
## empty when every passage is two wide or more.
static func narrow_runs(map: LevelMap) -> Dictionary[Vector2i, int]:
	var cells: Array[Vector2i] = []
	for at: Vector2i in map.cells:
		if map.walkable(at):
			cells.append(at)
	var open := func(cell: Vector2i, direction: Vector2i) -> bool:
		return map.walkable(cell + direction) and map.edge(Terrain.edge_key(cell, direction)) != "wall"
	return Level.narrow_runs_by(cells, open)


## The width rule kept (612): every single-width run on [param map] widened
## to two by carving a cell beside each of its cells, across its axis, where
## the rock allows (never the map's rim or an anchor's cell, and a cell in
## [param avoid], the ring outside a walled room, only when the other side
## cannot be: a run squeezed between anchors stays, and the test says so),
## until none is left or WIDEN_PASSES passes are spent. Carves rock alone,
## so nothing joined comes apart. Returns what it carved.
const WIDEN_PASSES := 6
static func widen(map: LevelMap, anchors: Array, carved: Dictionary[Vector2i, bool], avoid: Dictionary[Vector2i, bool] = {}) -> Dictionary[Vector2i, bool]:
	var widened: Dictionary[Vector2i, bool] = {}
	for pass_number in WIDEN_PASSES:
		var runs := narrow_runs(map)
		if runs.is_empty():
			break
		for cell: Vector2i in sorted_cells(runs):
			var across: Array[Vector2i] = []
			var along := Vector2i(1, 0) if runs[cell] == 0 else Vector2i(0, 1)
			across.assign([Vector2i(0, 1), Vector2i(0, -1)] if runs[cell] == 0 else [Vector2i(1, 0), Vector2i(-1, 0)])
			# Beside the cell before it, if that one was widened: the same side
			# along the run; a side to avoid last.
			for side in across:
				if map.walkable(cell - along + side) and runs.has(cell - along):
					across.erase(side)
					across.push_front(side)
					break
			for side in across.duplicate():
				if avoid.has(cell + side):
					across.erase(side)
					across.append(side)
			for side in across:
				var at := cell + side
				if at.x <= 0 or at.y <= 0 or at.x >= map.size.x - 1 or at.y >= map.size.y - 1:
					continue
				if map.cell(at) != "void" or not rock(map, anchors, at):
					continue
				carve(map, at, carved)
				widened[at] = true
				break
	return widened


## The two-cell rule (725, Jeff: "too many 1 tile niches and 1 tile tight
## turns, often around doors"): the walkable cells of [param map] outside
## [param anchors] that stand in no clear 2 x 2, four walkable cells with no
## edge between them (a wall or a door shuts one): a lone nook, a run one
## wide, a turn or a pocket one cell wide, at a door or anywhere. Sorted.
## The anchors are hand-made and keep their own rules.
static func pinches(map: LevelMap, anchors: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for at: Vector2i in sorted_cells(map.cells):
		if map.walkable(at) and not Level.in_anchors(anchors, at) and not in_clear_square(map, at):
			out.append(at)
	return out


## The corners of the 2 x 2 squares a cell is in, as their top-left cells.
const SQUARES: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]


## Whether [param at] is one of a clear 2 x 2 on [param map] (pinches).
static func in_clear_square(map: LevelMap, at: Vector2i) -> bool:
	for corner in SQUARES:
		if square_clear(map, at + corner):
			return true
	return false


## Whether the 2 x 2 at [param top_left] is four walkable cells with no
## edge shut between them; with [param carvable] (725's clearing), a cell
## that is rock there counts as floor to be.
static func square_clear(map: LevelMap, top_left: Vector2i, carvable := {}) -> bool:
	for cell: Vector2i in square_cells(top_left):
		if not map.walkable(cell) and not carvable.has(cell):
			return false
	for key: Vector3i in square_edges(top_left):
		if map.edge(key) != "clear":
			return false
	return true


static func square_cells(top_left: Vector2i) -> Array[Vector2i]:
	return [top_left, top_left + Vector2i(1, 0), top_left + Vector2i(0, 1), top_left + Vector2i(1, 1)]


## The four edges inside the 2 x 2 at [param top_left].
static func square_edges(top_left: Vector2i) -> Array[Vector3i]:
	return [Terrain.edge_key(top_left, Vector2i(1, 0)), Terrain.edge_key(top_left + Vector2i(0, 1), Vector2i(1, 0)),
		Terrain.edge_key(top_left, Vector2i(0, 1)), Terrain.edge_key(top_left + Vector2i(1, 0), Vector2i(0, 1))]


## The two-cell rule kept (725): each pinch (pinches) cleared by carving
## the rock that makes one of its 2 x 2s whole, the one needing fewest
## cells, never the map's rim or an anchor's cell, and a cell in
## [param avoid] (the ring outside a walled room: a cell carved there is
## walled off it again) last, only for a square holding none of the rooms'
## cells [param inside], until none is left or WIDEN_PASSES passes are
## spent. Carves rock alone, so nothing joined comes apart. Returns what it
## carved; what it could not clear stays, and the test says so.
static func clear_pinches(map: LevelMap, anchors: Array, carved: Dictionary[Vector2i, bool], avoid: Dictionary[Vector2i, bool] = {},
		inside: Dictionary = {}) -> Dictionary[Vector2i, bool]:
	var cleared: Dictionary[Vector2i, bool] = {}
	for pass_number in WIDEN_PASSES:
		var found := pinches(map, anchors)
		if found.is_empty():
			break
		var changed := false
		for at in found:
			if in_clear_square(map, at):
				continue  # Cleared by a neighbour's carving this pass.
			var best: Array[Vector2i] = []
			var best_cost := -1
			for corner in SQUARES:
				var top_left := at + corner
				var missing: Array[Vector2i] = []
				var ok := true
				var in_ring := false
				var in_room := false
				for cell in square_cells(top_left):
					in_room = in_room or inside.has(cell)
					if map.walkable(cell):
						continue
					if cell.x <= 0 or cell.y <= 0 or cell.x >= map.size.x - 1 or cell.y >= map.size.y - 1 \
							or map.cell(cell) != "void" or not rock(map, anchors, cell):
						ok = false
						break
					in_ring = in_ring or avoid.has(cell)
					missing.append(cell)
				# A ring cell only for a square with no room cell in it: the
				# wall it gets against the room then lies outside the square.
				if in_ring and in_room:
					ok = false
				var carvable := {}
				for cell in missing:
					carvable[cell] = true
				if not ok or not square_clear(map, top_left, carvable):
					continue
				var cost := missing.size() + (10 if in_ring else 0)
				if best_cost < 0 or cost < best_cost:
					best = missing
					best_cost = cost
			var best_ok := best_cost >= 0
			if not best_ok:
				continue
			for cell in best:
				carve(map, cell, carved)
				cleared[cell] = true
			changed = true
		if not changed:
			break
	return cleared


## The two-cell rule's last word (725): a pinched cell (pinches) that is a
## dead end, one way out of it, no door on it, and no cell [param keep] names (the
## ways' own path cells) nor a marker, filled with rock again, and the
## cell it opened onto tried next, until none is left: a nook filled can
## part nothing. The cells filled.
static func fill_nooks(map: LevelMap, anchors: Array, keep: Dictionary = {}) -> Array[Vector2i]:
	var filled: Array[Vector2i] = []
	var queue := pinches(map, anchors)
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if not map.walkable(at) or keep.has(at) or map.cell(at) != FLOOR or in_clear_square(map, at):
			continue
		var exits: Array[Vector2i] = []
		var by_door := false
		for direction in DIRECTIONS:
			var edge := map.edge(Terrain.edge_key(at, direction))
			by_door = by_door or edge == "door"
			if map.walkable(at + direction) and edge != "wall":
				exits.append(at + direction)
		if exits.size() != 1 or by_door:
			continue  # A way on, or a door's own cell: never filled.
		map.set_cell(at, "void")
		for direction in DIRECTIONS:
			map.set_edge(Terrain.edge_key(at, direction), "clear")
		filled.append(at)
		if not Level.in_anchors(anchors, exits[0]):
			queue.append(exits[0])
	return filled


## Whether [param at] stands against a tower's outline (659: the map's
## extras "footprint", nothing carved outside it): a cell beside it, or
## across a corner, is outside; such a cell may be pinched by the tower's
## own wall, and the two-cell rule leaves it (725).
static func against_outline(map: LevelMap, at: Vector2i) -> bool:
	if not map.extras.has("footprint"):
		return false
	var inside: Dictionary = map.extras["footprint"]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not inside.has(at + Vector2i(dx, dy)):
				return true
	return false


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


## Every walkable part of [param map], flood filled through open and door
## edges, the biggest first (612: a room or an alcove nothing reaches is a
## part of its own).
static func parts_all(map: LevelMap) -> Array[Array]:
	var seen: Dictionary[Vector2i, bool] = {}
	var out: Array[Array] = []
	for start: Vector2i in sorted_cells(map.cells):
		if seen.has(start) or not map.walkable(start):
			continue
		var part: Array[Vector2i] = [start]
		seen[start] = true
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var at: Vector2i = queue.pop_front()
			for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next := at + direction
				if seen.has(next) or not map.in_bounds(next) or not map.walkable(next) or map.edge(Terrain.edge_key(at, direction)) == "wall":
					continue
				seen[next] = true
				part.append(next)
				queue.append(next)
		out.append(part)
	out.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return out


## Joins every part to the biggest (612; join_up before it joins only the
## parts holding anchors): while two walkable parts stand apart, the
## nearest pair of cells between the biggest and the next is joined by the
## shortest way through the rock and the floor that crosses no wall edge
## and enters no anchor (path_through), carved. A room whose way failed,
## an alcove a wall cut off, join the rest.
static func join_all(map: LevelMap, anchors: Array, carved: Dictionary[Vector2i, bool]) -> void:
	for attempt in 32:
		var found := parts_all(map)
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
		var path := path_through(map, anchors, best_b, best_a)
		if path.size() < 2:
			return  # Nothing joins them: Regen's flood fill is the judge.
		for at in path:
			if rock(map, anchors, at):
				carve(map, at, carved)


## The shortest way from [param from] to [param to] by steps through cells
## in bounds that are no anchor's (but the ends), crossing no wall edge
## (rock has none; a walled room is gone round or entered by its door);
## both ends included, [from] alone when there is none.
static func path_through(map: LevelMap, anchors: Array, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var came: Dictionary[Vector2i, Vector2i] = {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if at == to:
			var path: Array[Vector2i] = [to]
			while path[-1] != from:
				path.append(came[path[-1]])
			path.reverse()
			return path
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + direction
			if came.has(next) or not map.in_bounds(next) or (next != to and not rock(map, anchors, next)) or map.edge(Terrain.edge_key(at, direction)) == "wall":
				continue
			came[next] = at
			queue.append(next)
	return [from]


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
			if next != to and not rock(map, anchors, next):
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
