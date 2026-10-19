class_name HeightTools
extends RefCounted
## Tools that change a map's heights (height.png: 0 to Level.MAX_HEIGHT a
## cell) and the stairs between them: raise or lower cells, level them, a
## hill, a stair onto a ledge, a flight of stairs. Each takes the map as it
## is and returns the changes it would make, {heights: cell -> level,
## cells: cell -> meaning, edges: edge key -> kind}, without making them
## (MapDoc.apply_changes lays them as one undo step; builder mode shows them
## as a ghost first), and "reason" when it could not (no changes then) or
## "warnings" for what it made that may not be wanted. Void cells take no
## height (Level.parse ignores it); water and fire do.
##
## Level.parse's rule for a stair: it climbs toward the walkable neighbour
## exactly one level up with no edge between, the first of N, E, S, W if
## there are two (with a warning). So a stair here is given its high
## neighbour, the edge between opened, and a wall on any other side one
## level up (a flight cut into a cliff), so it climbs only the way it was
## made to (decision 356).

const FOUR: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## How many cells ledge_warnings looks through from a cell before it calls
## the ground round it open.
const REACH := 1500


static func _changes() -> Dictionary:
	var heights: Dictionary[Vector2i, int] = {}
	var cells: Dictionary[Vector2i, String] = {}
	var edges: Dictionary[Vector3i, String] = {}
	return {"heights": heights, "cells": cells, "edges": edges}


static func _no(reason: String) -> Dictionary:
	var out := _changes()
	out["reason"] = reason
	return out


## [param at]'s height with [param changes] laid over [param map].
static func height_of(map: LevelMap, at: Vector2i, changes := {}) -> int:
	return int(changes.get("heights", {}).get(at, map.heights.get(at, 0)))


static func _cell(map: LevelMap, at: Vector2i, changes: Dictionary) -> String:
	return str(changes.get("cells", {}).get(at, map.cell(at)))


static func _edge(map: LevelMap, key: Vector3i, changes: Dictionary) -> String:
	return str(changes.get("edges", {}).get(key, map.edge(key)))


static func _walkable(map: LevelMap, at: Vector2i, changes: Dictionary) -> bool:
	return map.in_bounds(at) and _cell(map, at, changes) not in ["void", "water", "rock"]


## Sets [param at]'s height in [param out] (clamped), unless it is void or
## already that.
static func _put(map: LevelMap, out: Dictionary, at: Vector2i, level: int) -> void:
	if not map.in_bounds(at) or _cell(map, at, out) == "void":
		return
	level = clampi(level, 0, Level.MAX_HEIGHT)
	if level != int(map.heights.get(at, 0)):
		out["heights"][at] = level
	else:
		out["heights"].erase(at)


## Every cell of [param cells] (each once, however often listed) raised by
## [param by] levels (lowered if negative).
static func raise(map: LevelMap, cells: Array[Vector2i], by: int) -> Dictionary:
	var out := _changes()
	var seen: Dictionary[Vector2i, bool] = {}
	for at in cells:
		if not seen.has(at):
			seen[at] = true
			_put(map, out, at, int(map.heights.get(at, 0)) + by)
	return out


## Every cell of [param cells] set to height [param to].
static func level(map: LevelMap, cells: Array[Vector2i], to: int) -> Dictionary:
	var out := _changes()
	for at in cells:
		_put(map, out, at, to)
	return out


## A hill on the disc of [param radius] round [param centre]: terraced
## rings one level each, up to [param top] levels above the lowest ground
## under it (no more levels than the radius, so every ring is a cell wide),
## never lowering higher ground; and a flight of stairs from its foot to
## its top up each side in [param stairs] (directions out from the middle).
static func hill(map: LevelMap, centre: Vector2i, radius: int, top: int, stairs: Array[Vector2i] = []) -> Dictionary:
	var out := _changes()
	radius = maxi(1, radius)
	top = clampi(top, 1, maxi(1, radius))
	var disc: Dictionary[Vector2i, int] = {}
	var base := Level.MAX_HEIGHT
	var ring := (radius + 0.5) / top
	for y in range(centre.y - radius, centre.y + radius + 1):
		for x in range(centre.x - radius, centre.x + radius + 1):
			var at := Vector2i(x, y)
			var distance := Vector2(at - centre).length()
			if distance > radius + 0.5 or not map.in_bounds(at) or map.cell(at) == "void":
				continue
			disc[at] = clampi(top - int(floor(distance / ring)), 1, top)
			base = mini(base, int(map.heights.get(at, 0)))
	if disc.is_empty():
		return _no("the hill at %s is all void or off the map" % centre)
	for at: Vector2i in disc:
		_put(map, out, at, maxi(int(map.heights.get(at, 0)), base + disc[at]))
	var warnings: Array[String] = []
	for side: Vector2i in stairs:
		if side not in FOUR:
			continue
		var made := 0
		# From the foot inward: a cell one level below the next one in is its stair.
		for k in range(radius + 1, 0, -1):
			var low := centre + side * k
			var high := low - side
			if not _walkable(map, low, out) or not _walkable(map, high, out):
				continue
			var rise := height_of(map, high, out) - height_of(map, low, out)
			if rise == 1:
				_make_stair(map, out, low, -side)
				made += 1
			elif rise > 1:
				warnings.append("the stair up the %s side at %s would climb %d levels: none there" % [_side_name(side), low, rise])
		if made == 0:
			warnings.append("no stair up the %s side (blocked or off the map)" % _side_name(side))
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


## A stair at [param at] climbing toward [param dir] (one of FOUR): the cell
## beyond is set a level above it; beside a ledge more than a level up, a
## flight onto it, a stair a level, ending at [param at] and starting as
## many cells back.
static func stair(map: LevelMap, at: Vector2i, dir: Vector2i) -> Dictionary:
	var out := _changes()
	if dir not in FOUR:
		return _no("a stair climbs north, east, south or west")
	var up := at + dir
	if not _walkable(map, at, out) or not _walkable(map, up, out):
		return _no("a stair at %s needs ground there and beyond it" % at)
	var low := height_of(map, at)
	var high := height_of(map, up)
	if high > low + 1:
		return flight(map, at - dir * (high - low - 1), up)
	if high <= low:
		if low + 1 > Level.MAX_HEIGHT:
			return _no("%s is at the top height (%d): nothing above it" % [at, Level.MAX_HEIGHT])
		_put(map, out, up, low + 1)
	_make_stair(map, out, at, dir)
	return out


## A flight from [param from] straight to [param to] (a row or a column),
## one stair a cell climbing a level each from [param from]'s height, and
## [param to] the landing at the top.
static func flight(map: LevelMap, from: Vector2i, to: Vector2i) -> Dictionary:
	var out := _changes()
	if from == to or (from.x != to.x and from.y != to.y):
		return _no("a flight runs along a row or a column, from one cell to another")
	var dir := (to - from).sign()
	var steps := absi(to.x - from.x) + absi(to.y - from.y)
	var start := height_of(map, from)
	if start + steps > Level.MAX_HEIGHT:
		return _no("a flight of %d from height %d would go above %d" % [steps, start, Level.MAX_HEIGHT])
	for k in steps + 1:
		if not _walkable(map, from + dir * k, out):
			return _no("%s on the flight is not ground" % (from + dir * k))
	for k in steps + 1:
		_put(map, out, from + dir * k, start + k)
	for k in steps:
		_make_stair(map, out, from + dir * k, dir)
	return out


## Makes [param at] a stair climbing toward [param dir] in [param out]
## (heights already set): the edge that way opened, a wall on every other
## side a level up, so the stair climbs only the way it was made to.
static func _make_stair(map: LevelMap, out: Dictionary, at: Vector2i, dir: Vector2i) -> void:
	out["cells"][at] = "stair"
	var key := Terrain.edge_key(at, dir)
	if _edge(map, key, out) != "clear":
		out["edges"][key] = "clear"
	var level := height_of(map, at, out)
	for side in FOUR:
		if side == dir or not _walkable(map, at + side, out) or height_of(map, at + side, out) != level + 1:
			continue
		var beside := Terrain.edge_key(at, side)
		if _edge(map, beside, out) == "clear":
			out["edges"][beside] = "wall"


## Where the stair (or slope, maps' 513) at [param at] climbs to
## (Level.parse's rule), or Vector2i.ZERO if it is neither or climbs nowhere.
static func climbs(map: LevelMap, at: Vector2i) -> Vector2i:
	if map.cell(at) not in ["stair", "slope"]:
		return Vector2i.ZERO
	var level := int(map.heights.get(at, 0))
	for side in FOUR:
		if map.walkable(at + side) and int(map.heights.get(at + side, 0)) == level + 1 and map.edge(Terrain.edge_key(at, side)) == "clear":
			return side
	return Vector2i.ZERO


## Whether a walker gets from [param a] to its neighbour [param b] on
## [param map]: both ground, no wall, the same height or a stair between.
static func steps(map: LevelMap, a: Vector2i, b: Vector2i) -> bool:
	if not map.walkable(a) or not map.walkable(b) or map.edge(Terrain.edge_key(a, b - a)) == "wall":
		return false
	var rise := int(map.heights.get(b, 0)) - int(map.heights.get(a, 0))
	return rise == 0 or (rise == 1 and climbs(map, a) == b - a) or (rise == -1 and climbs(map, b) == a - b)


## For each of [param cells] (things, starts, buildings) on [param map]:
## a line if it stands on a patch of ground that ledges cut off from bigger
## ground beyond them, with no stair to or from it (walls or forest closing
## in are not ledges). Ground open past REACH cells is never cut off.
static func ledge_warnings(map: LevelMap, cells: Array[Vector2i]) -> Array[String]:
	var out: Array[String] = []
	var told: Dictionary[Vector2i, bool] = {}
	for start in cells:
		if told.has(start) or not map.walkable(start):
			continue
		var patch := _patch(map, start)
		var seen: Dictionary = patch["cells"]
		for at: Vector2i in seen:
			told[at] = true
		if patch["climbs"] or seen.size() >= REACH or (patch["beyond"] as Array).is_empty():
			continue
		# Cut off only from bigger ground: the ground round a pillar is not.
		var biggest := 0
		var looked: Dictionary[Vector2i, bool] = {}
		for next: Vector2i in patch["beyond"]:
			if looked.has(next):
				continue
			var other := _patch(map, next)
			biggest = maxi(biggest, (other["cells"] as Dictionary).size())
			for at: Vector2i in other["cells"]:
				looked[at] = true
			if biggest > seen.size():
				break
		if biggest > seen.size():
			out.append("%s is on a patch of %d cells at height %d with ledges round it and no stair to it" % [
				start, seen.size(), int(map.heights.get(start, 0))])
	return out


## The ground a walker reaches from [param start] (up to REACH cells):
## {cells, beyond: the cells across a ledge from it, climbs: whether it
## takes a stair to another height}.
static func _patch(map: LevelMap, start: Vector2i) -> Dictionary:
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var queue: Array[Vector2i] = [start]
	var beyond: Array[Vector2i] = []
	var climbs_out := false
	while not queue.is_empty() and seen.size() < REACH:
		var at: Vector2i = queue.pop_back()
		for side in FOUR:
			var next := at + side
			if seen.has(next) or not map.walkable(next):
				continue
			if steps(map, at, next):
				if int(map.heights.get(next, 0)) != int(map.heights.get(at, 0)):
					climbs_out = true
				seen[next] = true
				queue.append(next)
			elif map.edge(Terrain.edge_key(at, side)) != "wall":
				beyond.append(next)
	return {"cells": seen, "beyond": beyond, "climbs": climbs_out}


static func _side_name(side: Vector2i) -> String:
	return {Vector2i(0, -1): "north", Vector2i(1, 0): "east", Vector2i(0, 1): "south", Vector2i(-1, 0): "west"}.get(side, str(side))
