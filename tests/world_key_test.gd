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
	_test_files_key()
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


## Levels read from Level.source by a WorldMap.build of every level, after [param since].
func _reads(since: int) -> int:
	return WorldMap.source_reads - since


## 303 amended (1): WorldMap.build takes a level whose files are unchanged (Level.files_key: the folder and
## each file's MD5) as it was last read, its images neither read nor hashed; a registered level is read
## whole each time; any write to a level's files, the same second or not, and the overlay dropped, read it
## again. The barrow is in the overlay from _test_overlay.
func _test_files_key() -> void:
	print("\n== WorldMap.build: an unchanged level's files neither read nor hashed (303 amended (1)) ==")
	var level_name := "barrow"
	var into := Level.overlay_dir + level_name + "/"
	var registered := 0
	for each in Level.names():
		if Level._registered.has(each):
			registered += 1
	_check(not Level._registered.has(level_name) and Level.overlaid(level_name), "the barrow read from the overlay's files")
	var first := WorldMap.build()
	var since := WorldMap.source_reads
	var kept := WorldMap.build()
	_check(_reads(since) == registered, "built again with nothing changed: only the %d registered levels read (%d)" % [registered, _reads(since)])
	var fresh := WorldMap.new()
	for each in Level.names():
		fresh._read(each, Level.source(each))
	var same := kept.areas.keys() == fresh.areas.keys() and kept._configs.keys() == fresh._configs.keys() and kept.ways.size() == fresh.ways.size()
	for each: String in fresh.areas:
		if kept.areas[each]["floor"] != fresh.areas[each]["floor"] or kept._configs[each] != fresh._configs[each]:
			same = false
	_check(same, "and the map kept the same as one read afresh (%d areas, %d ways)" % [kept.areas.size(), kept.ways.size()])
	_check(kept.problems() == first.problems(), "its problems the same as the first build's (%d)" % first.problems().size())
	WorldMap.build()  # The fresh read above was no file's (key ""): each level keyed again.
	# The same bytes written again: the same MD5s, not read.
	var bytes := FileAccess.get_file_as_bytes(into + "level.json")
	var out := FileAccess.open(into + "level.json", FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()
	since = WorldMap.source_reads
	WorldMap.build()
	_check(_reads(since) == registered, "its level.json written again with the same bytes: not read (%d)" % _reads(since))
	# Two saves of the layout in the same second, one cell each: each read again (a time would miss the second).
	var layout := Image.load_from_file(ProjectSettings.globalize_path(into + "layout.png"))
	var digest_before := str(WorldMap._read_before[level_name]["digest"])
	for i in 2:
		var cell := Vector2i(5 + i, 5)
		layout.set_pixelv(cell, Color(0, 0, 0) if layout.get_pixelv(cell) != Color(0, 0, 0) else Color(0.6, 0.6, 0.6))
		layout.save_png(ProjectSettings.globalize_path(into + "layout.png"))
		since = WorldMap.source_reads
		WorldMap.build()
		var digest_now := str(WorldMap._read_before[level_name]["digest"])
		_check(_reads(since) == registered + 1 and digest_now != digest_before,
				"layout saved again (%d of 2 in one second): the barrow read again, its digest moved" % (i + 1))
		digest_before = digest_now
	# The overlay dropped: read from the pack's files again.
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(into)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(into + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(into))
	since = WorldMap.source_reads
	WorldMap.build()
	_check(not Level.overlaid(level_name) and _reads(since) == registered + 1, "the overlay dropped: the barrow read again from the pack's files")
	since = WorldMap.source_reads
	WorldMap.build()
	_check(_reads(since) == registered, "and kept at the build after")
	# A registered level: read whole every build (its images may be changed in place).
	var source := Level.source(level_name)
	Level.register(level_name, source["layout"], source["height"], source["config"], source.get("relief"))
	since = WorldMap.source_reads
	WorldMap.build()
	WorldMap.build()
	_check(_reads(since) == 2 * (registered + 1), "registered: read at each build (%d)" % _reads(since))
	Level.unregister(level_name)
