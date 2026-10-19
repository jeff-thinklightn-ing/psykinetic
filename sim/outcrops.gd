class_name Outcrops
extends RefCounted
## A rock outcrop raised out of a map (decision 513), for the editor's area
## fill and the level generators (tools/make_*): an uneven blob of ground
## one or two levels above the ground round it, a slope run up one side (a
## cell a level), its sides against ground of the ramp's own foot or top,
## never a drop (terrain draws no half face beside it), and rocks on its lip
## clear of the slope's mouth. The blob's sides are cliffs: a height step
## with no stair or slope. Only ground is raised; markers, doors and the
## kept cells are left, and a cell beside one stays down. The same seed
## lays the same outcrop. Returns AreaTools' changes and the heights:
## {cells: cell -> meaning ("slope", "rock"), edges: {}, heights: cell ->
## level}, empty if no slope fits (an outcrop with no way up is none).

const SIDES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
const FOUR: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## What a raised cell may be (the ground, and grass grown tall).
const RAISED: Array[String] = ["stone", "grass", "dirt", "tall_grass"]


## An outcrop in the ellipse filling [param rect] of [param map] (a
## LevelMap). [param options]: levels (1 or 2, 2), slope_side (north, east,
## south or west; by the seed if not given, the others tried after if it
## does not fit), rocks (0..1, 0.35: how much of the lip has a rock),
## keep_clear (cell -> anything).
static func lay(map: LevelMap, rect: Rect2i, outcrop_seed: int, options := {}) -> Dictionary:
	var cells: Dictionary[Vector2i, String] = {}
	var edges: Dictionary[Vector3i, String] = {}
	var heights: Dictionary[Vector2i, int] = {}
	var out := {"cells": cells, "edges": edges, "heights": heights}
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	var levels := clampi(int(options.get("levels", 2)), 1, 2)
	var keep_clear: Dictionary = options.get("keep_clear", {})
	# A ring round the blob as wide as the slope's run is long, in the area.
	var inner := area.grow(-levels)
	if inner.size.x < 2 or inner.size.y < 2:
		return out
	var random := RandomNumberGenerator.new()
	random.seed = outcrop_seed
	var wobble := FastNoiseLite.new()
	wobble.seed = outcrop_seed
	wobble.frequency = 0.2
	wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var base := int(map.heights.get(area.get_center(), 0))
	var top: Dictionary[Vector2i, bool] = {}
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var at := Vector2i(x, y)
			if AreaTools._ellipse(inner, at) < 0.85 + 0.3 * wobble.get_noise_2d(x, y) and _raisable(map, at, base, keep_clear):
				top[at] = true
	var pieces := AreaTools.blobs(top, 1)
	if pieces.is_empty():
		return out
	var biggest: Array = pieces[0]
	for piece in pieces:
		if piece.size() > biggest.size():
			biggest = piece
	top.clear()
	for at: Vector2i in biggest:
		top[at] = true
	var sides: Array = SIDES.keys()
	var first := str(options.get("slope_side", sides[random.randi() % sides.size()]))
	sides.erase(first)
	sides.push_front(first)
	var run: Array[Vector2i] = []
	var out_way := Vector2i.ZERO
	for side: String in sides:
		out_way = SIDES.get(side, Vector2i(0, 1))
		run = _slope_run(map, area, top, out_way, levels, base, keep_clear)
		if not run.is_empty():
			break
	if run.is_empty():
		return out
	# The cell the slope climbs to, and the ramp's sides kept at its foot's
	# height: no raised cell beside it.
	var mouth: Vector2i = run[0] - out_way
	var across := Vector2i(absi(out_way.y), absi(out_way.x))
	for cell in run:
		top.erase(cell + across)
		top.erase(cell - across)
	for at: Vector2i in top:
		heights[at] = base + levels
	for i in run.size():
		cells[run[i]] = "slope"
		heights[run[i]] = base + levels - 1 - i
	# Rocks on the lip: raised cells with a lower one beside them, not at
	# the slope's mouth nor beside it.
	var rocks := clampf(float(options.get("rocks", 0.35)), 0.0, 1.0)
	for at: Vector2i in top:
		var on_lip := FOUR.any(func(step: Vector2i) -> bool: return not top.has(at + step))
		var roll := random.randf()
		if on_lip and maxi(absi(at.x - mouth.x), absi(at.y - mouth.y)) > 1 and roll < rocks:
			cells[at] = "rock"
	return out


## Whether [param at] can be raised: ground at the base height, nothing to
## keep clear on it or beside it, no door on its edges.
static func _raisable(map: LevelMap, at: Vector2i, base: int, keep_clear: Dictionary) -> bool:
	if map.cell(at) not in RAISED or int(map.heights.get(at, 0)) != base or keep_clear.has(at):
		return false
	for step in FOUR + [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var by: Vector2i = at + step
		if keep_clear.has(by) or map.cell(by) in Level.MARKERS or map.cell(by).begins_with("monster_") or map.cell(by) == "stair":
			return false
	for step in FOUR:
		if map.edge(Terrain.edge_key(at, step)) == "door":
			return false
	return true


## The slope's cells out from the blob on the [param out] side, from the
## one under its lip down to its foot ([param levels] of them), from the
## raised cell furthest that way in the blob's middle row or column; empty
## if they are not all ground at the base height in the area, or the foot beyond them
## is not walkable.
static func _slope_run(map: LevelMap, area: Rect2i, top: Dictionary[Vector2i, bool], out: Vector2i, levels: int, base: int, keep_clear: Dictionary) -> Array[Vector2i]:
	var middle := Vector2.ZERO
	for at: Vector2i in top:
		middle += Vector2(at)
	middle /= top.size()
	var lip := Vector2i(-1, -1)
	var best := -INF
	for at: Vector2i in top:
		var along := float(at.x * out.x + at.y * out.y)
		var off := absf((Vector2(at) - middle).dot(Vector2(absi(out.y), absi(out.x))))
		if off < 1.0 and along > best:
			best = along
			lip = at
	if lip == Vector2i(-1, -1):
		return []
	var run: Array[Vector2i] = []
	for i in levels:
		var cell := lip + out * (i + 1)
		if not area.has_point(cell) or not _raisable(map, cell, base, keep_clear):
			return []
		run.append(cell)
	if not map.walkable(run[-1] + out):
		return []
	return run
