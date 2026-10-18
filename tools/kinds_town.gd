extends Node
## Writes "kinds_town", a street of the building kinds (decision 488) drawn
## by BuildingComposer (decision 489), into the edited-level overlay: twenty
## buildings in two rows either side of a dirt street on grass, small and
## large, one of them ruined, an imp beside each for scale; outdoors at noon.
## For the composer's frame number and the review sheet, with map_bench:
##   APPDATA=<a temp folder> godot --headless --path . --scene res://tools/kinds_town.tscn
##   APPDATA=<the same> godot --path . --scene res://tools/map_bench.tscn -- --map=kinds_town ...
## Run it only with APPDATA set to a temp folder: the overlay is user://,
## which every worktree's tests read otherwise.

const NAME := "kinds_town"
const STREET := ["house_small", "l_house_small", "cottage_small", "hut_small", "round_hut_small", "barn_small",
	"house_leanto_small", "inn_small", "two_storey_small", "hall_small"]
const FAR_SIDE := ["house_large", "house_wing_small", "longhouse_small", "stable_small", "mill_small",
	"watchtower_small", "temple_small", "cottage_large", "healers_hut_small", "house_small"]
## The one ruin: the far side's last.
const RUIN := 19
const GAP := 1


func _ready() -> void:
	_make.call_deferred()


func _make() -> void:
	if not OS.get_environment("APPDATA").to_lower().contains("temp"):
		push_error("kinds_town: set APPDATA to a temp folder first (the overlay is shared)")
		get_tree().quit(1)
		return
	var rows: Array = [STREET, FAR_SIDE]
	var width := 0
	var depths: Array[int] = []
	for row: Array in rows:
		var across := 0
		var deep := 0
		for each: String in row:
			var piece: LevelMap = Prefab.load_prefab(Prefab.KIND_PREFIX + each)["map"]
			across += piece.size.x + GAP
			deep = maxi(deep, piece.size.y)
		width = maxi(width, across)
		depths.append(deep)
	var street_y := depths[0] + 2
	var size := Vector2i(width + 4, street_y + 4 + depths[1] + 2)
	var map := LevelMap.new(size)
	for y in size.y:
		for x in size.x:
			map.set_cell(Vector2i(x, y), "dirt" if y >= street_y and y < street_y + 3 else "grass")
	map.set_cell(Vector2i(2, street_y + 1), "start")
	var config := {"name": "Kinds town", "outdoor": true, "buildings": []}
	var index := 0
	for r in rows.size():
		var x := 2
		for each: String in rows[r]:
			# Both rows face the street: the near one as built (front south),
			# the far one turned half round (front north).
			var prefab := Prefab.load_prefab(Prefab.KIND_PREFIX + each)
			if r == 1:
				prefab = Prefab.rotated(prefab, 2)
			var piece: LevelMap = prefab["map"]
			var at := Vector2i(x, street_y - piece.size.y if r == 0 else street_y + 3)
			var changes := Prefab.stamp_changes(prefab, map, at, config)
			for cell: Vector2i in changes["cells"]:
				map.set_cell(cell, changes["cells"][cell])
			for key: Vector3i in changes["edges"]:
				map.set_edge(key, changes["edges"][key])
			config.merge(changes.get("config", {}), true)
			if index == RUIN:
				(config["buildings"] as Array)[-1]["ruined"] = true
			# An imp for scale, by the building's corner on the street side.
			var imp := Vector2i(x, street_y if r == 0 else street_y + 2)
			if map.cell(imp) == "dirt":
				map.set_cell(imp, "monster_imp")
			x += piece.size.x + GAP
			index += 1
	var folder := ProjectSettings.globalize_path(Level.overlay_dir + NAME)
	DirAccess.make_dir_recursive_absolute(folder)
	map.to_image().save_png(folder.path_join("layout.png"))
	var json := FileAccess.open(folder.path_join("level.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify(config, "\t", false) + "\n")
	json.close()
	var level := Level.parse(map.to_image(), null, config)
	print("[kinds_town] %s: %d x %d cells, %d buildings, warnings: %s" % [folder, size.x, size.y,
		(level["buildings"] as Array).size(), level["warnings"]])
	get_tree().quit()
