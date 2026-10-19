class_name Streams
extends RefCounted
## Laying a stream across a map (decision 505), for the level generators
## (tools/make_*) and dungeon's runtime ones (Regen): a wavering course of
## water from one cell to another, a few cells wide, with a ford or a bridge
## where a given path crosses it. The same seed lays the same stream.


## Lays a stream on [param map] (a LevelMap) from [param from] to
## [param to] (edge cells, usually). [param options]: seed (int), width (1
## to 3 cells, 2), waver (cells either side of the straight line, 3),
## fords and bridges (lists of paths, each a list of cells: where one
## crosses the stream it gets a ford, or a bridge), keep_dry (cells never
## made water: terrain's canopy over 0.6, a building). Returns {path: the
## course's middle cells in order (level.json "streams" path), bridges:
## [building entries for level.json "buildings"]}.
static func lay(map: LevelMap, from: Vector2i, to: Vector2i, options := {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(options.get("seed", 0))
	var width := clampi(int(options.get("width", 2)), 1, 3)
	var waver := float(options.get("waver", 3.0))
	var keep_dry: Dictionary = options.get("keep_dry", {})
	var phase := rng.randf() * TAU
	var turns := 1.0 + rng.randf() * 1.5
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	var across := Vector2(to - from).orthogonal().normalized()
	var path: Array[Vector2i] = []
	for i in steps + 1:
		var t := float(i) / maxf(steps, 1)
		var middle := Vector2(from).lerp(Vector2(to), t) + across * sin(t * TAU * turns * 0.5 + phase) * waver * sin(t * PI)
		var cell := Vector2i(roundi(middle.x), roundi(middle.y))
		cell = cell.clamp(Vector2i.ZERO, map.size - Vector2i.ONE)
		# Keep the course unbroken: step from the last cell to this one.
		while not path.is_empty() and maxi(absi(cell.x - path[-1].x), absi(cell.y - path[-1].y)) > 1:
			path.append(path[-1] + Vector2i(signi(cell.x - path[-1].x), signi(cell.y - path[-1].y)))
		if path.is_empty() or path[-1] != cell:
			path.append(cell)
	var wet: Dictionary[Vector2i, bool] = {}
	var side := Vector2i(roundi(across.x), roundi(across.y))
	if side == Vector2i.ZERO:
		side = Vector2i(1, 0)
	for cell in path:
		for k in width:
			var at := cell + side * (k - (width - 1) / 2)
			if map.in_bounds(at) and not keep_dry.has(at):
				wet[at] = true
	# The course itself stays water even where keep_dry would dry it, so the
	# path is never broken.
	for cell in path:
		wet[cell] = true
	for cell: Vector2i in wet:
		map.set_cell(cell, "water")
	for crossing: Array in options.get("fords", []):
		for cell: Vector2i in crossing:
			if wet.has(cell):
				map.set_cell(cell, "ford")
	var bridges: Array[Dictionary] = []
	for crossing: Array in options.get("bridges", []):
		var bridge := _bridge_over(crossing, wet)
		if not bridge.is_empty():
			bridges.append(bridge)
	var out_path := []
	for cell in path:
		out_path.append([cell.x, cell.y])
	return {"path": path, "path_json": out_path, "bridges": bridges}


## The cells from point to point of [param points] in order, each beside
## the one before (diagonals too): a stream's course through them.
static func course(points: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for point in points:
		if out.is_empty():
			out.append(point)
			continue
		while out[-1] != point:
			out.append(out[-1] + Vector2i(signi(point.x - out[-1].x), signi(point.y - out[-1].y)))
	return out


## The cells [param width] wide (1 to 3) along [param path]: across each
## step's way, so a stream keeps its width round its bends.
static func widen(path: Array[Vector2i], width: int) -> Array[Vector2i]:
	var out: Dictionary[Vector2i, bool] = {}
	for i in path.size():
		var step := path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]
		var side := Vector2i(1, 0) if absi(step.y) >= absi(step.x) else Vector2i(0, 1)
		for k in clampi(width, 1, 3):
			out[path[i] + side * (k - (clampi(width, 1, 3) - 1) / 2)] = true
	var cells: Array[Vector2i] = []
	cells.assign(out.keys())
	return cells


## The bridge where [param crossing] (a straight path of cells, along x or
## y) first runs over [param wet]: a building entry {slot, at, facing,
## length}, or {} if it never does or is not straight there.
static func _bridge_over(crossing: Array, wet: Dictionary) -> Dictionary:
	var run: Array[Vector2i] = []
	for cell: Vector2i in crossing:
		if wet.has(cell):
			run.append(cell)
		elif not run.is_empty():
			break
	if run.is_empty():
		return {}
	var first := run[0]
	var last := run[-1]
	if first.x != last.x and first.y != last.y:
		return {}
	var facing := Vector2i(1, 0) if first.y == last.y else Vector2i(0, 1)
	var low := first.min(last)
	return {"slot": Level.BRIDGE, "at": [low.x, low.y], "facing": [facing.x, facing.y], "length": run.size()}
