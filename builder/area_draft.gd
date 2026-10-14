class_name AreaDraft
extends RefCounted
## A first draft of a new level beside another (builder mode's new_area,
## decision 205): grass with patches of dirt, a band of forest (void, drawn
## as trees outdoors) round it 3 to 11 cells deep, groves and maybe a pond
## inside, and on the side it joins its neighbour a gap in the forest where
## the way across arrives, so a player walking off the neighbour's edge
## lands on open ground. The same seed makes the same draft.

## The fewest cells a grove or a pond has.
const MIN_GROVE := 12
const MIN_POND := 8
## How far the gap reaches in, and is kept clear round, in cells.
const GAP_DEPTH := 14


## A draft [param size] cells across, joined on its [param side] ("north",
## "east", "south", "west") with the gap centred at [param gate] along that
## edge (a row for east and west, a column for north and south).
static func draft(size: Vector2i, draft_seed: int, side: String, gate: int) -> LevelMap:
	var map := LevelMap.new(size)
	var edge := AreaTools._noise(draft_seed, 0.04)
	var dirt := AreaTools._noise(draft_seed + 1, 0.035)
	var groves := AreaTools._noise(draft_seed + 2, 0.045)
	var ponds := AreaTools._noise(draft_seed + 3, 0.04)
	var gap := func(at: Vector2i) -> bool:
		var along := at.y if side in ["east", "west"] else at.x
		var into := {"west": at.x, "east": size.x - 1 - at.x, "north": at.y, "south": size.y - 1 - at.y}[side] as int
		return absi(along - gate) <= 2 + into / 3 and into < GAP_DEPTH
	for y in size.y:
		for x in size.x:
			var at := Vector2i(x, y)
			var inward := mini(mini(x, y), mini(size.x - 1 - x, size.y - 1 - y))
			if inward > 3 + 8.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5) or gap.call(at):
				map.set_cell(at, "dirt" if dirt.get_noise_2d(x, y) > 0.4 else "grass")
	var grove_cells: Dictionary[Vector2i, bool] = {}
	var pond_cells: Dictionary[Vector2i, bool] = {}
	for at: Vector2i in map.cells.keys():
		if gap.call(at) or _near_gap(at, size, side, gate):
			continue
		if groves.get_noise_2d(at.x, at.y) > 0.5:
			grove_cells[at] = true
		elif ponds.get_noise_2d(at.x, at.y) > 0.62:
			pond_cells[at] = true
	for blob in AreaTools.blobs(grove_cells, MIN_GROVE):
		for at: Vector2i in blob:
			map.set_cell(at, "void")
	for blob in AreaTools.blobs(pond_cells, MIN_POND):
		for at: Vector2i in blob:
			map.set_cell(at, "water")
	# A start where the way arrives, a few cells in (for a level someone joins in).
	map.set_cell(arrival_cell(size, side, gate, 3), "start")
	return map


## The cell [param into] cells in from the [param side] edge at [param gate].
static func arrival_cell(size: Vector2i, side: String, gate: int, into: int) -> Vector2i:
	match side:
		"west":
			return Vector2i(into, gate)
		"east":
			return Vector2i(size.x - 1 - into, gate)
		"north":
			return Vector2i(gate, into)
	return Vector2i(gate, size.y - 1 - into)


static func _near_gap(at: Vector2i, size: Vector2i, side: String, gate: int) -> bool:
	return at.distance_to(arrival_cell(size, side, gate, 0)) < GAP_DEPTH + 4
