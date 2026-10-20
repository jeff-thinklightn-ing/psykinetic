class_name Relief
## The ground's height as a field (decision 525): one elevation per cell,
## in metres, row by row over the level's cells. Outdoors a level may give
## it in relief.png (beside layout.png, one pixel a cell: centimetres as
## R * 256 + G, since Godot's PNG loader keeps 8 bits a channel); with
## none it is derived from the whole levels (height.png), a level
## LEVEL_M, so a level with no relief.png walks, falls and sees as before.
##
## The rules here are static, over a field and its size, so the sim
## (World, WorldRoutes), the views and the tools share one of each:
## cliff_between (a step too steep to walk), step (World.height_step's
## answer), corner_heights (the ground's corners, per side of a cliff),
## flat (a building's pad).

## What one whole level (height.png's) is, in metres.
const LEVEL_M := 0.5
## The most an orthogonal step may rise or fall and still be walked; more
## is a cliff. Under LEVEL_M, so a whole level's step stays a cliff.
const WALK_RISE := 0.45
## The most a stair or slope climbs in its own direction.
const STAIR_RISE := 0.5
## A building's cells lie within this of each other (its pad).
const PAD_FLAT := 0.05
## A pond's shore stands at least this over its surface.
const SHORE_LIP := 0.1
## Sight in metres: from an eye this high over the viewer's ground to this
## high over the seen one's.
const EYE_M := 1.5
const AIM_M := 1.0
## A climb at WALK_RISE takes 1 + UPHILL_PACE as long as on the flat.
const UPHILL_PACE := 0.5
## The highest a relief.png holds (65535 cm).
const MAX_M := 655.35
## What two heights read from centimetres may differ by and still be one.
const EPSILON := 0.001


## [param field]'s elevation at [param cell] ([param size] its cells), 0
## off the map.
static func at(field: PackedFloat32Array, size: Vector2i, cell: Vector2i) -> float:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or field.is_empty():
		return 0.0
	return field[cell.y * size.x + cell.x]


## Whether a step between ground at [param a] and at [param b] metres is
## too steep to walk (a cliff): more than WALK_RISE between orthogonal
## neighbours, WALK_RISE * sqrt 2 on a [param diagonal].
static func cliff_between(a: float, b: float, diagonal := false) -> bool:
	return absf(b - a) > (WALK_RISE * sqrt(2.0) if diagonal else WALK_RISE) + EPSILON


## A step from [param from] in [param direction] over [param field], as
## World.height_step says it: 0 walkable (gentle, or a stair in
## [param stairs] climbing that way up to STAIR_RISE), n > 0 a drop of
## about n levels off a ledge, n < 0 a ledge about n levels up. A diagonal
## is walked only when it and both of its orthogonal routes are.
static func step(field: PackedFloat32Array, size: Vector2i, stairs: Dictionary, from: Vector2i, direction: Vector2i) -> int:
	var here := at(field, size, from)
	var there := at(field, size, from + direction)
	var rise := there - here
	if direction.x != 0 and direction.y != 0:
		var by_x := at(field, size, from + Vector2i(direction.x, 0))
		var by_y := at(field, size, from + Vector2i(0, direction.y))
		if not cliff_between(here, there, true) and not cliff_between(here, by_x) and not cliff_between(by_x, there) \
				and not cliff_between(here, by_y) and not cliff_between(by_y, there):
			return 0
		return -levels(rise) if absf(rise) >= LEVEL_M * 0.5 else -1
	if not cliff_between(here, there):
		return 0
	if rise > 0.0 and rise <= STAIR_RISE + EPSILON and stairs.get(from, Vector2i.ZERO) == direction:
		return 0
	if rise < 0.0 and -rise <= STAIR_RISE + EPSILON and stairs.get(from + direction, Vector2i.ZERO) == -direction:
		return 0
	return -levels(rise)


## [param rise] metres in whole levels, at least one either way (a fall's
## hurt counts these, FALL_IMPACT_PER_LEVEL each).
static func levels(rise: float) -> int:
	var count := maxi(1, roundi(absf(rise) / LEVEL_M))
	return count if rise > 0.0 else -count


## How many times as long a step rising [param rise] metres takes (1 down
## or on the flat; a [param diagonal]'s rise spread over its length).
static func pace(rise: float, diagonal := false) -> float:
	var slope := rise / sqrt(2.0) if diagonal else rise
	if slope <= EPSILON or slope > WALK_RISE + EPSILON:
		return 1.0
	return 1.0 + UPHILL_PACE * slope / WALK_RISE


## The four corners of [param cell]'s ground, in GROUND_CORNERS order
## ((0, 0), (1, 0), (0, 1), (1, 1) from its top-left): each the mean of
## the cells meeting at that corner that are joined to this one round the
## ring of four (this, its x neighbour, the one across, its y neighbour)
## by steps that are no cliff (cliff_between), either way round. Each side
## of a cliff keeps corners of its own, a ledge's face tapers to nothing
## where the ring is cut once, and two cells joined walkably always agree
## on the corner they share (they are in the same part of its ring).
static func corner_heights(field: PackedFloat32Array, size: Vector2i, cell: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(4)
	var i := 0
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var ring: Array[Vector2i] = [cell, cell + Vector2i(corner.x, 0), cell + corner, cell + Vector2i(0, corner.y)]
		var heights := PackedFloat32Array()
		var on := PackedByteArray()
		for spot in ring:
			heights.append(at(field, size, spot))
			on.append(1 if on_map(size, spot) else 0)
		# Link k joins ring[k] and ring[k + 1] (round to the start).
		var open := PackedByteArray()
		for k in 4:
			var other := (k + 1) % 4
			open.append(1 if on[k] == 1 and on[other] == 1 and not cliff_between(heights[k], heights[other]) else 0)
		var joined := PackedByteArray([1, 0, 0, 0])
		var k := 0
		while k < 3 and open[k] == 1:
			k += 1
			joined[k] = 1
		k = 0
		while k > -3 and open[(k + 3) % 4] == 1:
			k -= 1
			joined[(k + 4) % 4] = 1
		var sum := 0.0
		var count := 0
		for m in 4:
			if joined[m] == 1:
				sum += heights[m]
				count += 1
		out[i] = sum / count
		i += 1
	return out


static func on_map(size: Vector2i, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## Whether [param cells] of [param field] lie within [param tolerance]
## metres of each other (a building's pad).
static func flat(field: PackedFloat32Array, size: Vector2i, cells: Array, tolerance := PAD_FLAT) -> bool:
	if cells.is_empty():
		return true
	var low := INF
	var high := -INF
	for cell: Vector2i in cells:
		var height := at(field, size, cell)
		low = minf(low, height)
		high = maxf(high, height)
	return high - low <= tolerance + EPSILON


## The field of whole levels [param heights] (cell -> level, 0 left out)
## over [param size] cells: LEVEL_M a level.
static func derived(heights: Dictionary, size: Vector2i) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	for cell: Vector2i in heights:
		if on_map(size, cell):
			field[cell.y * size.x + cell.x] = int(heights[cell]) * LEVEL_M
	return field


## The whole levels of [param field] (cell -> its elevation in levels,
## rounded; 0 left out), for what still reads whole levels (World.height_at).
static func whole_levels(field: PackedFloat32Array, size: Vector2i) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for y in size.y:
		for x in size.x:
			var level := roundi(field[y * size.x + x] / LEVEL_M)
			if level != 0:
				out[Vector2i(x, y)] = level
	return out


## relief.png read: its field, or an empty one if [param image] is not
## [param size] (said in [param warnings]).
static func read(image: Image, size: Vector2i, warnings: Array[String]) -> PackedFloat32Array:
	if image.get_size() != size:
		warnings.append("relief.png is %s, the level %s cells: relief ignored" % [image.get_size(), size])
		return PackedFloat32Array()
	var rgb := image
	if image.get_format() != Image.FORMAT_RGB8:
		rgb = image.duplicate()
		rgb.convert(Image.FORMAT_RGB8)
	var bytes := rgb.get_data()
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	for i in field.size():
		field[i] = (bytes[i * 3] * 256 + bytes[i * 3 + 1]) * 0.01
	return field


## [param field] as relief.png's image (RGB8, centimetres in R and G).
static func image(field: PackedFloat32Array, size: Vector2i) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 3)
	for i in size.x * size.y:
		var cm := clampi(roundi(field[i] * 100.0), 0, 65535)
		bytes[i * 3] = cm >> 8
		bytes[i * 3 + 1] = cm & 255
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, bytes)


# --- Laying relief (the editor's fill, the level tools) --------------------------

## The steepest step Relief.lay and the brush leave between walkable
## neighbours: under WALK_RISE, so rounding to centimetres keeps it walked.
const LAY_SLOPE := 0.4
## How far under its banks Relief.lay sinks a stream's surface.
const STREAM_DEPTH := 0.4
const FOUR: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SIDES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
## Relief.lay's "kinds": the ground it paints, and by what (metres a step,
## a crest's height over the cells round it).
const GROUND_KINDS: Array[String] = ["grass", "dirt", "stone"]
const ROCK_STEP := 0.34
const DIRT_STEP := 0.24
const CREST := 0.3
const CREST_REACH := 3
const KIND_WANDER := 0.04


## Hills, valleys and ridges laid over [param rect] of [param map] (a
## LevelMap), for the editor's "relief" area fill and the level tools.
## [param options]:
## - base (metres; the area's mean if not given): the ground's middle;
## - amplitude (4): how far the roll goes either way of it;
## - scale (36): the roll's width in cells;
## - octaves (3): the roll's detail (fewer, smoother);
## - ridges: [[Vector2i, ...], ...], polylines a ridge runs along, ridge_height
##   (amplitude * 1.5) over the roll at its crest, ridge_width (10 cells) out;
##   an entry may be {line, height, width} of its own (a knoll: one point);
## - valleys: [[Vector2i, ...], ...], polylines a valley runs along, its
##   floor valley_depth (amplitude) under base and valley_floor (0) cells
##   out either side, falling valley_fall (0) metres from the line's first
##   point to its last, the ground eased down to it valley_width (12) out
##   (a stream finds it, all along);
## - tilt (Vector2, metres a cell): the whole area leaning, so water runs
##   one way;
## - plateaus: [{rect: Rect2i, height, faces, spur}], raised that many
##   metres over the ground round them, their faces ("north", "east",
##   "south", "west"; all if not given) cliffs left steep, their other sides
##   falling away walkably, no steeper than spur (LAY_SLOPE) metres a cell;
## - keep_flat: [Rect2i], pads levelled with a one-cell apron (pad);
## - streams (1): how many streams run down the valleys to the area's edge,
##   each width (1 or 2) cells wide; min_flow (area / 60): the fewest cells
##   that drain into a stream's source;
## - keep_clear (cell -> anything): cells left as they are;
## - kinds (false): the ground's kinds set by slope and height too (_kinds).
## Everything else is slope-limited to LAY_SLOPE a step, so walked. Only
## the map's walkable cells are changed (what stands on them goes up and
## down with them; void, water and keep_clear left). The same seed
## lays the same ground. Returns {relief: cell -> metres, cells: cell ->
## "water" (the streams; with kinds, the ground's meanings too), streams: [[Vector2i, ...]] (each from its source to
## its mouth, for level.json "streams")}.
static func lay(map: LevelMap, rect: Rect2i, lay_seed: int, options := {}) -> Dictionary:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, map.size))
	var out := {"relief": {}, "cells": {}, "streams": []}
	if area.size.x < 3 or area.size.y < 3:
		return out
	var field := map.relief_field()
	var size := map.size
	var keep_clear: Dictionary = options.get("keep_clear", {})
	var ground: Dictionary[Vector2i, bool] = {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			if map.walkable(at) and map.cell(at) != "water" and not keep_clear.has(at):
				ground[at] = true
	if ground.is_empty():
		return out
	var base := float(options.get("base", _mean(field, size, ground.keys())))
	var amplitude := float(options.get("amplitude", 4.0))
	var roll := FastNoiseLite.new()
	roll.seed = lay_seed
	roll.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	roll.fractal_type = FastNoiseLite.FRACTAL_FBM
	roll.fractal_octaves = clampi(int(options.get("octaves", 3)), 1, 6)
	roll.frequency = 1.0 / maxf(4.0, float(options.get("scale", 36.0)))
	var ridges: Array = options.get("ridges", [])
	var ridge_height := float(options.get("ridge_height", amplitude * 1.5))
	var ridge_width := maxf(2.0, float(options.get("ridge_width", 10.0)))
	var valleys: Array = options.get("valleys", [])
	var valley_depth := float(options.get("valley_depth", amplitude))
	var valley_width := maxf(2.0, float(options.get("valley_width", 12.0)))
	var valley_floor := clampf(float(options.get("valley_floor", 0.0)), 0.0, valley_width - 1.0)
	var valley_fall := float(options.get("valley_fall", 0.0))
	var tilt: Vector2 = options.get("tilt", Vector2.ZERO)
	var middle := Vector2(area.get_center())
	var heights := {}
	for at: Vector2i in ground:
		var height := base + amplitude * roll.get_noise_2d(at.x, at.y) + tilt.dot(Vector2(at) - middle)
		var crest := 0.0
		for ridge: Variant in ridges:
			var line: Array = ridge["line"] if ridge is Dictionary else ridge
			var high := float(ridge.get("height", ridge_height)) if ridge is Dictionary else ridge_height
			var wide := float(ridge.get("width", ridge_width)) if ridge is Dictionary else ridge_width
			var near := _distance_to_line(at, line)
			if near < wide:
				crest = maxf(crest, high * (1.0 - smoothstep(0.0, wide, near)))
		height += crest
		# A valley: its floor (valley_floor cells out from its line) falling
		# valley_fall metres from its first point to its last under the
		# ground's middle, the ground eased down to it across valley_width.
		for line: Array in valleys:
			var where := _along_line(at, line)
			if where.x < valley_width:
				var floor_at := base - valley_depth + valley_fall * (0.5 - where.y)
				height = lerpf(height, floor_at, 1.0 - smoothstep(valley_floor, valley_width, where.x))
		heights[at] = height
	# Plateaus: raised over what is round them, fixed, their sides left steep.
	var fixed: Dictionary[Vector2i, bool] = {}
	var cliff_side: Dictionary[Vector2i, bool] = {}
	var faces: Dictionary[Vector3i, bool] = {}
	for plateau: Dictionary in options.get("plateaus", []):
		var top: Rect2i = plateau["rect"]
		var cells: Array = ground.keys().filter(func(at: Vector2i) -> bool: return top.has_point(at))
		if cells.is_empty():
			continue
		var level := _mean_of(heights, cells) + float(plateau.get("height", 3.0))
		var sides: Array = plateau.get("faces", SIDES.keys())
		# Its other sides fall away no steeper than "spur" metres a cell.
		var spur := float(plateau.get("spur", LAY_SLOPE))
		for at: Vector2i in ground:
			if top.has_point(at):
				continue
			var nearest := Vector2i(clampi(at.x, top.position.x, top.end.x - 1), clampi(at.y, top.position.y, top.end.y - 1))
			var off := at - nearest
			var faced := (off.x < 0 and "west" in sides) or (off.x > 0 and "east" in sides) 					or (off.y < 0 and "north" in sides) or (off.y > 0 and "south" in sides)
			if not faced:
				heights[at] = maxf(float(heights[at]), level - spur * Vector2(off).length())
		for at: Vector2i in cells:
			heights[at] = level
			fixed[at] = true
			for side: String in sides:
				var out_of: Vector2i = at + SIDES.get(side, Vector2i.ZERO)
				if not top.has_point(out_of):
					faces[Terrain.edge_key(at, SIDES[side])] = true
	for pad_rect: Rect2i in options.get("keep_flat", []):
		var cells: Array = ground.keys().filter(func(at: Vector2i) -> bool: return pad_rect.grow(1).has_point(at))
		if cells.is_empty():
			continue
		var level := _mean_of(heights, cells)
		for at: Vector2i in cells:
			heights[at] = level
			fixed[at] = true
	_limit(heights, fixed, cliff_side, LAY_SLOPE, faces)
	# Streams down the valleys: water follows the lowest way out of the area.
	var flow := _flow(heights, area)
	var taken: Dictionary[Vector2i, bool] = {}
	var min_flow := int(options.get("min_flow", maxi(8, ground.size() / 60)))
	# A stream keeps to a valley's floor where it can.
	var floors: Dictionary[Vector2i, bool] = {}
	for at: Vector2i in heights:
		for line: Array in valleys:
			if _along_line(at, line).x <= valley_floor + 1.0:
				floors[at] = true
	for i in int(options.get("streams", 1)):
		var path := _stream_path(flow, heights, area, min_flow, taken, floors)
		if path.size() < 4:
			break
		var wide := clampi(int(options.get("width", 1)), 1, 2)
		_carve(heights, path, wide, out["cells"], taken)
		out["streams"].append(path)
	if not out["streams"].is_empty():
		# The ground round the water walked again; the water and its banks kept.
		for at: Vector2i in out["cells"]:
			fixed[at] = true
			cliff_side[at] = true
			for direction in FOUR:
				if heights.has(at + direction):
					fixed[at + direction] = true
		_limit(heights, fixed, cliff_side, LAY_SLOPE, faces)
	# relief.png holds nothing under 0 m: the whole of it lifted if it dips.
	var lowest := 0.0
	for at: Vector2i in heights:
		lowest = minf(lowest, heights[at])
	for at: Vector2i in heights:
		out["relief"][at] = snappedf(heights[at] - lowest, 0.01)
	if options.get("kinds", false):
		_kinds(map, heights, out["cells"], lay_seed)
	return out


## The ground's kinds by its slope and height (Relief.lay's "kinds",
## decision 525 amended), into [param cells] for the cells of
## [param heights] that are ground (stone, grass or dirt) and not water: by
## the biggest step to an orthogonal neighbour, stone from ROCK_STEP up,
## bare dirt from DIRT_STEP up or on a crest (CREST over the mean of the
## cells within CREST_REACH), grass in the hollows and on gentle ground; a
## cell beside the water its dirt bank. The thresholds wander a little
## (KIND_WANDER, by the seed) so the bands are no contour lines.
static func _kinds(map: LevelMap, heights: Dictionary, cells: Dictionary, lay_seed: int) -> void:
	var wander := FastNoiseLite.new()
	wander.seed = lay_seed + 1
	wander.frequency = 0.15
	wander.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	for at: Vector2i in heights:
		if cells.has(at) or map.cell(at) not in GROUND_KINDS:
			continue
		var here: float = heights[at]
		var step := 0.0
		var bank := false
		for direction in FOUR:
			var next := at + direction
			if cells.get(next, "") == "water":
				bank = true
			elif heights.has(next):
				step = maxf(step, absf(float(heights[next]) - here))
		var sum := 0.0
		var count := 0
		for y in range(-CREST_REACH, CREST_REACH + 1):
			for x in range(-CREST_REACH, CREST_REACH + 1):
				var near := at + Vector2i(x, y)
				if heights.has(near) and not cells.get(near, "") == "water":
					sum += float(heights[near])
					count += 1
		var shift := KIND_WANDER * wander.get_noise_2d(at.x, at.y)
		if step >= ROCK_STEP + shift:
			cells[at] = "stone"
		elif bank or step >= DIRT_STEP + shift or here - sum / maxi(1, count) >= CREST + shift:
			cells[at] = "dirt"
		else:
			cells[at] = "grass"


## Cells [param rect] of [param map] levelled at their mean, and the ring
## [param apron] cells round it too, for a building's pad (decision 525):
## {relief: cell -> metres}. Only walkable ground is changed.
static func pad(map: LevelMap, rect: Rect2i, apron := 1) -> Dictionary:
	var field := map.relief_field()
	var cells: Array = []
	var grown := rect.grow(apron).intersection(Rect2i(Vector2i.ZERO, map.size))
	for y in range(grown.position.y, grown.end.y):
		for x in range(grown.position.x, grown.end.x):
			if map.walkable(Vector2i(x, y)) and map.cell(Vector2i(x, y)) != "water":
				cells.append(Vector2i(x, y))
	var inside := cells.filter(func(at: Vector2i) -> bool: return rect.has_point(at))
	var level := snappedf(_mean(field, map.size, inside if not inside.is_empty() else cells), 0.01)
	var changes := {}
	for at: Vector2i in cells:
		changes[at] = level
	return {"relief": changes}


static func _mean(field: PackedFloat32Array, size: Vector2i, cells: Array) -> float:
	if cells.is_empty():
		return 0.0
	var sum := 0.0
	for at: Vector2i in cells:
		sum += at(field, size, at)
	return sum / cells.size()


static func _mean_of(heights: Dictionary, cells: Array) -> float:
	var sum := 0.0
	for at: Vector2i in cells:
		sum += float(heights[at])
	return sum / maxi(1, cells.size())


## How far [param at] is from the polyline [param line] (cells), and how
## far along it the nearest point lies (0 at its first point, 1 at its
## last), as (distance, along).
static func _along_line(at: Vector2i, line: Array) -> Vector2:
	var point := Vector2(at)
	if line.size() == 1:
		return Vector2(point.distance_to(Vector2(line[0])), 0.0)
	var total := 0.0
	for i in range(1, line.size()):
		total += Vector2(line[i]).distance_to(Vector2(line[i - 1]))
	var best := INF
	var along := 0.0
	var walked := 0.0
	for i in range(1, line.size()):
		var a := Vector2(line[i - 1])
		var b := Vector2(line[i])
		var nearest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var near := point.distance_to(nearest)
		if near < best:
			best = near
			along = (walked + a.distance_to(nearest)) / maxf(total, 0.001)
		walked += a.distance_to(b)
	return Vector2(best, along)


## How far [param at] is from the polyline [param line] (cells).
static func _distance_to_line(at: Vector2i, line: Array) -> float:
	var best := INF
	var point := Vector2(at)
	for i in line.size():
		var a := Vector2(line[i])
		if line.size() == 1:
			return point.distance_to(a)
		if i == 0:
			continue
		var b := Vector2(line[i - 1])
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best


## [param heights] made walkable: no two orthogonal neighbours differ by
## more than [param slope], but across one of [param faces] (edge keys) or
## between a cliff_side cell and one that is not. The fixed cells keep
## their heights: the ground is first brought down to within slope a step
## of them, then raised wherever it falls away faster than slope from a
## neighbour (raster passes each way, again until nothing moves: a
## distance transform, so a peak broadens rather than a hollow digging in).
static func _limit(heights: Dictionary, fixed: Dictionary, cliff_side: Dictionary, slope: float, faces: Dictionary = {}) -> void:
	if heights.is_empty():
		return
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	for at: Vector2i in heights:
		low = low.min(at)
		high = high.max(at)
	var size := high - low + Vector2i.ONE
	var h := PackedFloat32Array()
	h.resize(size.x * size.y)
	# 0 not a cell, 1 free, 2 fixed; bit 4 cliff_side.
	var kind := PackedByteArray()
	kind.resize(size.x * size.y)
	# Whether a step east (bit 1) or south (bit 2) from the cell is open.
	var open := PackedByteArray()
	open.resize(size.x * size.y)
	for at: Vector2i in heights:
		var i := (at.y - low.y) * size.x + at.x - low.x
		h[i] = heights[at]
		kind[i] = (2 if fixed.has(at) else 1) | (4 if cliff_side.has(at) else 0)
	for at: Vector2i in heights:
		var i := (at.y - low.y) * size.x + at.x - low.x
		for bit in [1, 2]:
			var next: Vector2i = at + (Vector2i(1, 0) if bit == 1 else Vector2i(0, 1))
			if heights.has(next) and cliff_side.has(at) == cliff_side.has(next) 					and not faces.has(Terrain.edge_key(at, Vector2i(1, 0) if bit == 1 else Vector2i(0, 1))):
				open[i] |= bit
	# Down to within slope a step of the fixed cells (their own upper bound).
	var bound := PackedFloat32Array()
	bound.resize(h.size())
	for i in h.size():
		bound[i] = h[i] if kind[i] & 3 == 2 else INF
	_sweep(bound, kind, open, size, slope, false)
	for i in h.size():
		if kind[i] & 3 == 1:
			h[i] = minf(h[i], bound[i])
	# Then up wherever the ground falls away too fast.
	_sweep(h, kind, open, size, slope, true)
	for at: Vector2i in heights:
		heights[at] = h[(at.y - low.y) * size.x + at.x - low.x]


## Raster passes over [param h] ([param size]) until nothing moves: each
## free cell (kind 1) raised to its open neighbours' less [param slope]
## ([param up]), or brought down to theirs plus it (not [param up]).
static func _sweep(h: PackedFloat32Array, kind: PackedByteArray, open: PackedByteArray, size: Vector2i, slope: float, up: bool) -> void:
	for round_count in 64:
		var moved := false
		for backward in [false, true]:
			for row in size.y:
				var y := size.y - 1 - row if backward else row
				for column in size.x:
					var x := size.x - 1 - column if backward else column
					var i := y * size.x + x
					if kind[i] & 3 != 1:
						continue
					var best := h[i]
					# West and north neighbours forward; east and south back.
					if backward:
						if x + 1 < size.x and open[i] & 1:
							best = maxf(best, h[i + 1] - slope) if up else minf(best, h[i + 1] + slope)
						if y + 1 < size.y and open[i] & 2:
							best = maxf(best, h[i + size.x] - slope) if up else minf(best, h[i + size.x] + slope)
					else:
						if x > 0 and open[i - 1] & 1:
							best = maxf(best, h[i - 1] - slope) if up else minf(best, h[i - 1] + slope)
						if y > 0 and open[i - size.x] & 2:
							best = maxf(best, h[i - size.x] - slope) if up else minf(best, h[i - size.x] + slope)
					if absf(best - h[i]) > 0.0001:
						h[i] = best
						moved = true
		if not moved:
			return


## Where water runs over [param heights] in [param area]: cell -> the
## neighbour it drains to (none at the area's edge, where it leaves),
## found over the hollows filled (a priority flood from the edge), and each
## cell's count of cells draining through it ("count").
static func _flow(heights: Dictionary, area: Rect2i) -> Dictionary:
	var filled := {}
	var down := {}
	var open: Array = []  # [height, order, cell], kept sorted lowest last
	var order := 0
	for at: Vector2i in heights:
		var edge := at.x == area.position.x or at.y == area.position.y or at.x == area.end.x - 1 or at.y == area.end.y - 1
		if not edge:
			for direction in FOUR:
				if not heights.has(at + direction):
					edge = true
		if edge:
			filled[at] = float(heights[at])
			open.append([float(heights[at]), order, at])
			order += 1
	open.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0] or p[0] == q[0] and p[1] > q[1])
	var visit: Array[Vector2i] = []
	while not open.is_empty():
		var top: Array = open.pop_back()
		var at: Vector2i = top[2]
		visit.append(at)
		for direction in FOUR:
			var next := at + direction
			if not heights.has(next) or filled.has(next):
				continue
			filled[next] = maxf(float(heights[next]), float(filled[at]) + 0.0001)
			down[next] = at
			var entry := [float(filled[next]), order, next]
			order += 1
			var index := open.bsearch_custom(entry, func(p: Array, q: Array) -> bool: return p[0] > q[0] or p[0] == q[0] and p[1] > q[1])
			open.insert(index, entry)
	var count := {}
	for at: Vector2i in heights:
		count[at] = 1
	for i in range(visit.size() - 1, -1, -1):
		var at := visit[i]
		if down.has(at):
			count[down[at]] = int(count[down[at]]) + int(count[at])
	return {"down": down, "count": count}


## The stream draining most of [param flow] not yet [param taken]: from its
## source (the last cell up it with min_flow draining through) to its mouth
## at the area's edge, keeping to [param floors] (a valley's) where a
## branch up does.
static func _stream_path(flow: Dictionary, heights: Dictionary, area: Rect2i, min_flow: int, taken: Dictionary, floors: Dictionary = {}) -> Array[Vector2i]:
	var down: Dictionary = flow["down"]
	var count: Dictionary = flow["count"]
	var mouth := Vector2i(-1, -1)
	for at: Vector2i in heights:
		if not down.has(at) and not taken.has(at) and (mouth.x < 0 or int(count[at]) > int(count[mouth])):
			mouth = at
	var path: Array[Vector2i] = []
	if mouth.x < 0 or int(count[mouth]) < min_flow:
		return path
	var ups := {}
	for at: Vector2i in down:
		(ups.get_or_add(down[at], []) as Array).append(at)
	var at := mouth
	while true:
		path.append(at)
		var best := Vector2i(-1, -1)
		for up: Vector2i in ups.get(at, []):
			if taken.has(up) or int(count[up]) < min_flow:
				continue
			# A valley's floor first, then the most water.
			var better := best.x < 0 or floors.has(up) and not floors.has(best) 					or floors.has(up) == floors.has(best) and int(count[up]) > int(count[best])
			if better:
				best = up
		if best.x < 0:
			break
		at = best
	path.reverse()
	return path


## [param path] made water in [param heights] (and [param cells]), each
## cell's surface STREAM_DEPTH under its ground and never over the one
## upstream, [param wide] 2 adding the lower side cell; its banks raised to
## SHORE_LIP over it where they were not.
static func _carve(heights: Dictionary, path: Array[Vector2i], wide: int, cells: Dictionary, taken: Dictionary) -> void:
	var surface := INF
	var wet: Array[Vector2i] = []
	for i in path.size():
		var at := path[i]
		surface = minf(surface, float(heights[at]) - STREAM_DEPTH)
		var these: Array[Vector2i] = [at]
		if wide == 2:
			var along := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).sign()
			var side := Vector2i(along.y, along.x)
			var left := at + side
			var right := at - side
			var pick := left if heights.has(left) and (not heights.has(right) or heights[left] <= heights[right]) else right
			if heights.has(pick) and not path.has(pick):
				these.append(pick)
		for cell in these:
			heights[cell] = surface
			cells[cell] = "water"
			taken[cell] = true
			wet.append(cell)
	for cell in wet:
		for direction in FOUR:
			var bank := cell + direction
			if heights.has(bank) and not cells.has(bank) and float(heights[bank]) < float(heights[cell]) + SHORE_LIP + 0.05:
				heights[bank] = float(heights[cell]) + SHORE_LIP + 0.05
