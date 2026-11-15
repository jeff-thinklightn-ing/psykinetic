extends Node
## Client3D's world map key (decision 822 amended (7)): a level registered
## again with the same bytes (a client's "terrain" message on each crossing)
## is the same key, so the world map is not built again; one cell changed
## builds it with only that level parsed again; a level laid again (a
## regenerating level's new bytes), one put in the edited-level overlay or
## its files saved again, and one let go each change the key: a held map
## never shows a stale world. Prints PASS/FAIL per assertion and quits with
## exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Level.overlay_dir = ports.scratch("world_key_overlay/")
	_clear_overlay()
	_test_same_bytes()
	_test_one_cell()
	await _test_overlay()
	_clear_overlay()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _clear_overlay() -> void:
	var root := ProjectSettings.globalize_path(Level.overlay_dir)
	if not DirAccess.dir_exists_absolute(root):
		return
	for level_name in DirAccess.get_directories_at(root):
		for file in DirAccess.get_files_at(root + level_name):
			DirAccess.remove_absolute(root + level_name + "/" + file)
		DirAccess.remove_absolute(root + level_name)


## Builds of the world map since [param from].
func _built(from: int) -> int:
	return Client3D.world_builds - from


func _test_same_bytes() -> void:
	print("\n== the same bytes registered again: the same key, no build ==")
	Client3D._world_map()
	var builds := Client3D.world_builds
	Client3D._world_map()
	_check(_built(builds) == 0, "asked again with nothing changed: not built")
	var message := BuilderHost.terrain_message("wilds")
	BuilderHost.register_terrain(message)
	var key := Client3D._world_map_key()
	Client3D._world_map()
	_check(_built(builds) == 1, "the wilds registered (a client's first \"terrain\" for it): built once")
	builds = Client3D.world_builds
	for i in 3:
		BuilderHost.register_terrain(message)  # New images each time, the same bytes.
	_check(Client3D._world_map_key() == key, "registered again three times with the same bytes: the same key")
	Client3D._world_map()
	_check(_built(builds) == 0, "and the world map not built again")
	var digest := str(Level._registered["wilds"].get("digest", ""))
	var made: Dictionary = Level._registered["wilds"]
	_check(digest == WorldMap._digest(made["layout"], made["height"], made["config"], made.get("relief")) and not digest.is_empty(),
			"the digest kept is WorldMap's own of what was registered")


func _test_one_cell() -> void:
	print("\n== one cell changed: built, only that level parsed again ==")
	Client3D._world_map()
	var builds := Client3D.world_builds
	var before := WorldMap._read_before.duplicate()
	var made: Dictionary = Level._registered["wilds"]
	var layout: Image = (made["layout"] as Image).duplicate()
	var cell := Vector2i(100, 100)
	var was := layout.get_pixelv(cell)
	layout.set_pixelv(cell, Color(0, 0, 0) if was != Color(0, 0, 0) else Color(0.54, 0.39, 0.25))
	var key := Client3D._world_map_key()
	Level.register("wilds", layout, made["height"], made["config"], made.get("relief"))
	_check(Client3D._world_map_key() != key, "one pixel of the wilds' layout changed: another key")
	Client3D._world_map()
	_check(_built(builds) == 1, "built again")
	var others_kept := true
	for level_name: String in before:
		if level_name != "wilds" and WorldMap._read_before.has(level_name) and not is_same(WorldMap._read_before[level_name], before[level_name]):
			others_kept = false
	_check(others_kept and not is_same(WorldMap._read_before.get("wilds"), before.get("wilds")),
			"only the wilds parsed again (%d levels kept as read)" % (before.size() - 1))
	print("\n== a level laid again (a regenerating level's new bytes) and one let go: another key ==")
	var marked := Regen.marked_levels()
	var laid := marked[0] if not marked.is_empty() else "barrow"
	var source := Level.source(laid)
	var first: Image = (source["layout"] as Image).duplicate()
	var second: Image = first.duplicate()
	second.set_pixel(5, 5, Color(0, 0, 0) if second.get_pixel(5, 5) != Color(0, 0, 0) else Color(0.6, 0.6, 0.6))
	Level.register(laid, first, source["height"], source["config"], source.get("relief"))
	key = Client3D._world_map_key()
	Level.register(laid, second, source["height"], source["config"], source.get("relief"))
	var laid_key := Client3D._world_map_key()
	_check(laid_key != key, "%s laid again with another floor: another key" % laid)
	Level.unregister(laid)
	_check(Client3D._world_map_key() != laid_key, "let go (read from its files again): another key")
	Level.unregister("wilds")


func _test_overlay() -> void:
	print("\n== the edited-level overlay: a level saved there, and saved again, each another key ==")
	var level_name := "barrow"
	var key := Client3D._world_map_key()
	var into := Level.overlay_dir + level_name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(into))
	for file: String in ["layout.png", "height.png", "relief.png", "level.json"]:
		if FileAccess.file_exists(Level.DIR + level_name + "/" + file):
			var bytes := FileAccess.get_file_as_bytes(Level.DIR + level_name + "/" + file)
			var out := FileAccess.open(into + file, FileAccess.WRITE)
			out.store_buffer(bytes)
			out.close()
	var saved := Client3D._world_map_key()
	_check(Level.overlaid(level_name) and saved != key, "the barrow saved in the overlay: another key")
	await get_tree().create_timer(1.2).timeout  # The files' times are in seconds.
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(into + "level.json"))
	config["world_key_test"] = true
	var out := FileAccess.open(into + "level.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(config))
	out.close()
	_check(Client3D._world_map_key() != saved, "its level.json saved again: another key")
	var builds := Client3D.world_builds
	Client3D._world_map()
	_check(_built(builds) == 1, "and the world map built")
