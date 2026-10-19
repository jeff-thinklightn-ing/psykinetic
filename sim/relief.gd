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
## this cell and those meeting it at that corner that are joined to it
## walkably (no cliff_between on the way round), so each side of a cliff
## keeps corners of its own and the face between them is the cliff's.
static func corner_heights(field: PackedFloat32Array, size: Vector2i, cell: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(4)
	var here := at(field, size, cell)
	var i := 0
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var by_x := cell + Vector2i(corner.x, 0)
		var by_y := cell + Vector2i(0, corner.y)
		var across := cell + corner
		var sum := here
		var count := 1
		var x_joined := on_map(size, by_x) and not cliff_between(here, at(field, size, by_x))
		var y_joined := on_map(size, by_y) and not cliff_between(here, at(field, size, by_y))
		if x_joined:
			sum += at(field, size, by_x)
			count += 1
		if y_joined:
			sum += at(field, size, by_y)
			count += 1
		if on_map(size, across) and (x_joined and not cliff_between(at(field, size, by_x), at(field, size, across))
				or y_joined and not cliff_between(at(field, size, by_y), at(field, size, across))):
			sum += at(field, size, across)
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
