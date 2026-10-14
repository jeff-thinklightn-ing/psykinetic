class_name AreaTools
extends RefCounted
## Tools that fill an area of a map in one go: a pond, a grove, a path, a
## fence, a scatter of things. Each takes the map as it is, what it needs
## (an area, points, a size) and a seed, and returns the changes it would
## make, {cells: cell -> meaning, edges: edge key -> kind}, without making
## them: the editor lays them as one undo step (LevelEditor.apply_changes),
## and builder mode can show them as a ghost first. The same seed gives the
## same changes on the same map.
##
## Trees: there is no tree cell. Outdoors, a void cell beside the land is
## drawn as a tree (docs/levels.md, outdoor), so a grove is void cells
## among the ground, one tree each.

const FOUR: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## What scatter can put down; "tree" is a void cell.
const SCATTER_THINGS: Array[String] = ["boulder", "crate", "tree"]
const SIDES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}


static func _changes() -> Dictionary:
	var cells: Dictionary[Vector2i, String] = {}
	var edges: Dictionary[Vector3i, String] = {}
	return {"cells": cells, "edges": edges}


static func _noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise


## How far [param at] is into the ellipse filling [param rect]: 0 at its
## middle, 1 on its rim.
static func _ellipse(rect: Rect2i, at: Vector2i) -> float:
	var centre := Vector2(rect.position) + Vector2(rect.size) / 2.0
	var radius := Vector2(rect.size) / 2.0
	var d := (Vector2(at) + Vector2(0.5, 0.5) - centre) / radius
	return d.length()


## A pond filling [param rect]: an uneven blob of water (one piece), and a
## shore of [param shore_ground] [param shore] cells wide round it, inside
## the area. Water and shore replace whatever was there.
static func pond(map: LevelMap, rect: Rect2i, pond_seed: int, shore := 1, shore_ground := "dirt") -> Dictionary:
	var out := _changes()
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	if area.size.x < 3 or area.size.y < 3:
		return out
	var inner := area.grow(-shore) if area.size.x > shore * 2 + 2 and area.size.y > shore * 2 + 2 else area
	var wobble := _noise(pond_seed, 0.18)
	var water: Dictionary[Vector2i, bool] = {}
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var at := Vector2i(x, y)
			if _ellipse(inner, at) < 0.82 + 0.25 * wobble.get_noise_2d(x, y):
				water[at] = true
	# One piece: the biggest.
	var pieces := blobs(water, 1)
	if pieces.is_empty():
		return out
	var biggest: Array = pieces[0]
	for piece in pieces:
		if piece.size() > biggest.size():
			biggest = piece
	for at: Vector2i in biggest:
		out["cells"][at] = "water"
	# The shore: every cell of the area within [param shore] steps of the water.
	var ring: Array = biggest
	for i in shore:
		var next: Array[Vector2i] = []
		for at: Vector2i in ring:
			for step in FOUR + [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var by: Vector2i = at + step
				if area.has_point(by) and not out["cells"].has(by):
					out["cells"][by] = shore_ground
					next.append(by)
		ring = next
	return out


## A grove filling the ellipse in [param rect]: trees (void cells) scattered
## over its ground, thickest in the middle; [param density] (0..1) how many.
## With [param clearing], a clearing of grass in the middle a third of its
## size. Only walkable ground becomes trees; markers and water are left.
static func grove(map: LevelMap, rect: Rect2i, grove_seed: int, density := 0.5, clearing := false) -> Dictionary:
	var out := _changes()
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	var clumps := _noise(grove_seed, 0.25)
	var random := RandomNumberGenerator.new()
	random.seed = grove_seed
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			var into := _ellipse(area, at)
			if into >= 1.0:
				continue
			if clearing and into < 0.36:
				if map.cell(at) == "void":
					out["cells"][at] = "grass"
				continue
			if map.cell(at) not in Level.GROUNDS:
				continue
			var chance := clampf(density * (1.15 - into * 0.6) + clumps.get_noise_2d(x, y) * 0.35, 0.0, 0.95)
			if random.randf() < chance:
				out["cells"][at] = "void"
	return out


## A path of [param ground] [param width] cells wide through [param points]
## in order, winding between them (swung aside by noise); it crosses
## anything (water and void become path too), and clears the walls and
## doors on its way.
static func path(map: LevelMap, points: Array[Vector2i], path_seed: int, width := 2, ground := "dirt") -> Dictionary:
	var out := _changes()
	if points.is_empty():
		return out
	var swing := _noise(path_seed, 0.08)
	var lay := func(centre: Vector2i) -> void:
		for dy in width:
			for dx in width:
				var each := centre + Vector2i(dx - (width - 1) / 2, dy - (width - 1) / 2)
				if map.in_bounds(each):
					out["cells"][each] = ground
	lay.call(points[0])
	for i in range(1, points.size()):
		var at := Vector2(points[i - 1])
		var to := Vector2(points[i])
		var steps := 0
		while at.distance_to(to) > 0.75 and steps < 4000:
			steps += 1
			var toward := (to - at).normalized()
			# Less swing near the end, so it arrives where it was asked to.
			var near := clampf(at.distance_to(to) / 6.0, 0.0, 1.0)
			at += (toward + toward.orthogonal() * swing.get_noise_2d(at.x, at.y) * 1.1 * near).normalized()
			lay.call(Vector2i(roundi(at.x), roundi(at.y)))
		lay.call(points[i])
	for cell: Vector2i in out["cells"]:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if out["cells"].has(cell + step):
				var key := Terrain.edge_key(cell, step)
				if map.edge(key) != "clear":
					out["edges"][key] = "clear"
	return out


## A fence round [param rect]: a wall on every edge between it and outside
## it, with a gate (a door) in the middle of side [param gate] ("north",
## "east", "south", "west"; "" for none).
static func fence(map: LevelMap, rect: Rect2i, gate := "south") -> Dictionary:
	var out := _changes()
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			for side: String in SIDES:
				var step: Vector2i = SIDES[side]
				if area.has_point(at + step):
					continue
				var key := Terrain.edge_key(at, step)
				if map.edge_in_bounds(key):
					out["edges"][key] = "wall"
	if SIDES.has(gate):
		var step: Vector2i = SIDES[gate]
		var middle := area.position + area.size / 2
		var at := Vector2i(middle.x, area.position.y if step.y < 0 else area.end.y - 1) if step.x == 0 \
				else Vector2i(area.position.x if step.x < 0 else area.end.x - 1, middle.y)
		var key := Terrain.edge_key(at, step)
		if map.edge_in_bounds(key):
			out["edges"][key] = "door"
	return out


## [param things] ("boulder", "crate", "tree") scattered over the walkable
## ground of [param rect], [param density] (0..1) of its cells, no two side
## by side, none on a marker, water or void.
static func scatter(map: LevelMap, rect: Rect2i, scatter_seed: int, things: Array[String], density := 0.05) -> Dictionary:
	var out := _changes()
	var kinds := things.filter(func(thing: String) -> bool: return thing in SCATTER_THINGS)
	if kinds.is_empty():
		return out
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	var random := RandomNumberGenerator.new()
	random.seed = scatter_seed
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			if map.cell(at) not in Level.GROUNDS or random.randf() >= density:
				continue
			if FOUR.any(func(step: Vector2i) -> bool: return out["cells"].has(at + step)):
				continue
			var thing: String = kinds[random.randi() % kinds.size()]
			out["cells"][at] = "void" if thing == "tree" else thing
	return out


## The cells of [param cells] in joined pieces (four ways), only pieces of
## at least [param least] cells.
static func blobs(cells: Dictionary[Vector2i, bool], least: int) -> Array[Array]:
	var out: Array[Array] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		var blob: Array[Vector2i] = [start]
		seen[start] = true
		var i := 0
		while i < blob.size():
			for step in FOUR:
				var next: Vector2i = blob[i] + step
				if cells.has(next) and not seen.has(next):
					seen[next] = true
					blob.append(next)
			i += 1
		if blob.size() >= least:
			out.append(blob)
	return out
