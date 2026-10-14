extends Node
## Saves map_bench's dungeon (rooms of 8 with a door in each wall, a torch,
## a crate and MONSTERS monsters per room) as a level in the user://
## overlay, so a real server and real clients can play it. Run it only as
## tools/net_bench.sh does, with APPDATA pointing at a folder of its own:
## the real user:// is shared by every worktree and test.
##   godot --headless --path . --scene res://tools/net_bench_map.tscn -- --size=256 [--monsters=2] [--name=netbench]


func _ready() -> void:
	World.set_process(false)
	var bench: Node = preload("res://tools/map_bench.gd").new()
	var level_name := "netbench"
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=")
		if pair.size() != 2:
			continue
		match pair[0]:
			"size": bench.size = clampi(pair[1].to_int(), 8, 512)
			"monsters": bench.monsters = clampi(pair[1].to_int(), 0, 6)
			"name": level_name = pair[1]
	var folder := Level.overlay_dir + level_name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var image: Image = bench._layout()
	var error := image.save_png(ProjectSettings.globalize_path(folder + "layout.png"))
	var json := FileAccess.open(ProjectSettings.globalize_path(folder + "level.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify({"name": "Net bench"}) + "\n")
	json.close()
	var level := Level.load_level(level_name)
	print("[net bench] %s: %s, %d x %d cells, %d entities, %d doors" % [ProjectSettings.globalize_path(folder), error_string(error), bench.size, bench.size,
		level.get("entities", []).size(), level.get("terrain", {}).get("edges", {}).values().count(Terrain.Edge.DOOR)])
	bench.free()
	get_tree().quit()
