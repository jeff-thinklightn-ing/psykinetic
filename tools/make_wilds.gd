extends SceneTree
## Writes levels/wilds, the outdoor map south of the castle (whose link to
## it, at the foot of its road, (16, 23), arriving at the top of the wilds'
## path, is in levels/castle):
##   Godot --headless --path . --script tools/make_wilds.gd
## (A script run has no autoloads, so Godot prints that World is not found
## while compiling what Level depends on; the map is written all the same.)
##
## 256 x 256 cells of grass under the sky, its edge an uneven band of forest
## (the void round the land, drawn as trees: docs/levels.md, outdoor), with
## small groves (void inside the land), patches of dirt and a few ponds.
## A dirt path winds from the castle's link at the top to a farmstead
## stamped from the prefabs (a house, two fenced fields, a well), and on to
## a goblin camp in the north-east. Few monsters: the camp's three imps.
## The same seed makes the same map; touch it up in the editor afterwards.

const SIZE := Vector2i(256, 256)
const SEED := 1014
const FOLDER := "res://levels/wilds/"
const FARMSTEAD := Vector2i(128, 140)
## The fewest cells a grove or a pond has.
const MIN_GROVE := 16
const MIN_POND := 10
const CAMP := Vector2i(196, 78)

var map := LevelMap.new(SIZE)
var config := {"name": "The Wilds", "outdoor": true}
var entries: Array = []
## Cells kept clear of groves and ponds: paths and what is stamped, and round them.
var keep_clear: Dictionary[Vector2i, bool] = {}


func _initialize() -> void:
	var edge := _noise(SEED, 0.02)
	var groves := _noise(SEED + 1, 0.035)
	var dirt := _noise(SEED + 2, 0.03)
	var ponds := _noise(SEED + 3, 0.03)
	# The land: in from the map's border by 4 to 24 cells, unevenly.
	for y in SIZE.y:
		for x in SIZE.x:
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			if inward > 4 + 20.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5):
				map.set_cell(Vector2i(x, y), "dirt" if dirt.get_noise_2d(x, y) > 0.35 else "grass")
	# The way in from the castle: the top of the land straight below the middle.
	var link := Vector2i(SIZE.x / 2, 0)
	while map.cell(link) == "void":
		link.y += 1
	link.y += 1
	var arrival := link + Vector2i(0, 2)
	# Paths: the castle to the farmstead, the farmstead to the camp.
	_path(link, FARMSTEAD + Vector2i(0, -6), 2, SEED + 10)
	_path(FARMSTEAD + Vector2i(14, 0), CAMP + Vector2i(-4, 4), 2, SEED + 11)
	# What is stamped, and the ground round it kept clear.
	_stamp("small_house", FARMSTEAD + Vector2i(-10, -3), 0)
	_stamp("fenced_field", FARMSTEAD + Vector2i(2, -4), 0)
	_stamp("fenced_field", FARMSTEAD + Vector2i(2, 4), 2)
	_stamp("well", FARMSTEAD + Vector2i(-3, 5), 0)
	_stamp("small_house", FARMSTEAD + Vector2i(-12, 8), 1)
	_stamp("campfire_camp", CAMP, 0)
	for cell in [link, arrival]:
		_clear_round(cell, 4)
	# Groves and ponds, away from all that; none smaller than a few cells.
	var grove_cells: Dictionary[Vector2i, bool] = {}
	var pond_cells: Dictionary[Vector2i, bool] = {}
	for y in SIZE.y:
		for x in SIZE.x:
			var at := Vector2i(x, y)
			if map.cell(at) == "void" or keep_clear.has(at):
				continue
			if groves.get_noise_2d(x, y) > 0.45:
				grove_cells[at] = true
			elif ponds.get_noise_2d(x, y) > 0.62:
				pond_cells[at] = true
	for blob in _blobs(grove_cells, MIN_GROVE):
		for at: Vector2i in blob:
			map.set_cell(at, "void")
	for blob in _blobs(pond_cells, MIN_POND):
		for at: Vector2i in blob:
			map.set_cell(at, "water")
	# The link, the starts beside the arrival.
	map.set_cell(link, "link")
	var starts := []
	for dx in [-1, 1, -2, 2]:
		var start := arrival + Vector2i(dx, 0)
		map.set_cell(start, "start")
		starts.append([start.x, start.y])
	config["centre"] = [arrival.x, arrival.y]
	config["starts"] = starts
	config["spawn_points"] = {"from_castle": [arrival.x, arrival.y]}
	config["links"] = [{"at": [link.x, link.y], "to_map": "castle", "to_spawn": "from_wilds"}]
	config["entities"] = entries
	_write(FOLDER, map, config)
	var level := Level.parse(map.to_image(), null, config)
	print("[wilds] %d x %d cells, %d floor, %d things, link at %s; warnings: %s" % [SIZE.x, SIZE.y,
		(level["terrain"]["floor"] as Array).size(), (level["entities"] as Array).size(), link, level["warnings"]])
	quit()


## The cells of [param cells] in joined pieces (four ways), only pieces of
## at least [param least] cells.
static func _blobs(cells: Dictionary[Vector2i, bool], least: int) -> Array[Array]:
	var out: Array[Array] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		var blob: Array[Vector2i] = [start]
		seen[start] = true
		var i := 0
		while i < blob.size():
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = blob[i] + step
				if cells.has(next) and not seen.has(next):
					seen[next] = true
					blob.append(next)
			i += 1
		if blob.size() >= least:
			out.append(blob)
	return out


func _noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise


## A winding dirt path [param width] cells wide from [param from] to
## [param to]: each step goes toward it, swung aside by noise.
func _path(from: Vector2i, to: Vector2i, width: int, noise_seed: int) -> void:
	var swing := _noise(noise_seed, 0.08)
	var at := Vector2(from)
	var steps := 0
	while at.distance_to(Vector2(to)) > 1.0 and steps < 2000:
		steps += 1
		var toward := (Vector2(to) - at).normalized()
		var aside := toward.orthogonal() * swing.get_noise_2d(at.x, at.y) * 1.1
		at += (toward + aside).normalized()
		var cell := Vector2i(roundi(at.x), roundi(at.y))
		for dy in width:
			for dx in width:
				var each := cell + Vector2i(dx, dy)
				if map.in_bounds(each):
					map.set_cell(each, "dirt")
		_clear_round(cell, width + 2)


## Stamps prefab [param prefab_name] turned [param turns] with its top-left
## at [param at]; its entries join the map's.
func _stamp(prefab_name: String, at: Vector2i, turns: int) -> void:
	var prefab := Prefab.rotated(Prefab.load_prefab(prefab_name), turns)
	var changes := Prefab.stamp_changes(prefab, map, at)
	for cell: Vector2i in changes["cells"]:
		map.set_cell(cell, changes["cells"][cell])
	for key: Vector3i in changes["edges"]:
		map.set_edge(key, changes["edges"][key])
	entries.append_array(changes["entries"])
	var size: Vector2i = (prefab["map"] as LevelMap).size
	for y in range(-3, size.y + 3):
		for x in range(-3, size.x + 3):
			keep_clear[at + Vector2i(x, y)] = true
	# The ground under a stamp is land, whatever was there.
	for y in size.y:
		for x in size.x:
			var cell := at + Vector2i(x, y)
			if map.cell(cell) == "void":
				map.set_cell(cell, "grass")


func _clear_round(centre: Vector2i, radius: int) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var at := centre + Vector2i(x, y)
			keep_clear[at] = true
			if map.in_bounds(at) and map.cell(at) == "void":
				map.set_cell(at, "grass")


func _write(folder: String, level_map: LevelMap, level_config: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(path)
	level_map.to_image().save_png(path.path_join("layout.png"))
	LevelMap.ensure_image_import(path.path_join("layout.png"), folder + "layout.png")
	_save_json(folder + "level.json", level_config)


func _save_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	file.close()
