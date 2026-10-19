class_name TallGrass
extends RefCounted
## Laying tall grass on a map (decision 508), for the editor's area fill and
## the level generators (tools/make_*): patches on open grass by noise (a
## meadow) and a band along the trees (a wood's edge: outdoors a void cell is
## a tree). Only grass ground grows tall; it keeps clear of the cells round
## a marker (a link, a start, a chest...), a door and the cells given. The
## same seed lays the same grass. Returns the changes, as AreaTools does
## ({cells: cell -> "tall_grass", edges: {}}), for one undo step.

const KIND := "tall_grass"
## How big the meadow's patches are (noise frequency, per cell).
const PATCH_FREQUENCY := 0.12
## The chance of a cell of the wood's edge band growing tall.
const EDGE_CHANCE := 0.8
const EIGHT: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const FOUR: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Tall grass over [param rect] of [param map] (a LevelMap). [param options]:
## meadow (0..1, 0.5: how much of the open grass grows tall), edge (cells,
## 2: the band along the trees; 0 none), keep_clear (cell -> anything:
## never grown, nor beside: spawn points, places).
static func lay(map: LevelMap, rect: Rect2i, grass_seed: int, options := {}) -> Dictionary:
	var cells: Dictionary[Vector2i, String] = {}
	var edges: Dictionary[Vector3i, String] = {}
	var out := {"cells": cells, "edges": edges}
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	var meadow := clampf(float(options.get("meadow", 0.5)), 0.0, 1.0)
	var edge := maxi(int(options.get("edge", 2)), 0)
	var keep_clear: Dictionary = options.get("keep_clear", {})
	var noise := FastNoiseLite.new()
	noise.seed = grass_seed
	noise.frequency = PATCH_FREQUENCY
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var random := RandomNumberGenerator.new()
	random.seed = grass_seed
	# Over 1 - 2 meadow, from none at 0 to all at 1.
	var threshold := 1.0 - 2.0 * meadow
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			if map.cell(at) != "grass" or not _clear(map, at, keep_clear):
				continue
			var edge_roll := random.randf()
			if (meadow > 0.0 and noise.get_noise_2d(x, y) > threshold) or (edge > 0 and _near_trees(map, at, edge) and edge_roll < EDGE_CHANCE):
				cells[at] = KIND
	return out


## Nothing to keep clear on or beside [param at]: no marker, no door on its
## edges, no kept cell.
static func _clear(map: LevelMap, at: Vector2i, keep_clear: Dictionary) -> bool:
	if keep_clear.has(at):
		return false
	for step in EIGHT:
		var by := at + step
		var meaning := map.cell(by)
		if keep_clear.has(by) or meaning in Level.MARKERS or meaning.begins_with("monster_") or meaning == "stair":
			return false
	for step in FOUR:
		if map.edge(Terrain.edge_key(at, step)) == "door":
			return false
	return true


## A tree (a void cell on the map) within [param reach] cells of [param at].
static func _near_trees(map: LevelMap, at: Vector2i, reach: int) -> bool:
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var by := at + Vector2i(dx, dy)
			if map.in_bounds(by) and map.cell(by) == "void":
				return true
	return false
