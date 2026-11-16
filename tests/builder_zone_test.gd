extends Node
## Builder mode in a running game (a host, --builder-stub): a player asks
## for an area, gets the proposal, accepts it; the level is saved to the
## overlay, the zone is rebuilt from it with the player where they were,
## and the terrain message carries it to clients; undo takes it back; a
## player not allowed to build is refused; the console's builder, builder
## export and builder drop.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const BO := 2
const BO_ID := "b0b0b0b0-0000-4000-8000-0000000000b0"
var OVERLAY: String = preload("res://tests/test_ports.gd").scratch("builder_zone_test_levels/")
const AREA := [3, 3, 9, 6]

var _failures := 0
var _main: Node
var _heard: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17798)
	Net.companions = false
	Net.state_path = ""
	Net.builder_stub = true
	Level.overlay_dir = OVERLAY
	_remove_tree(ProjectSettings.globalize_path(OVERLAY))
	_remove_tree(ProjectSettings.globalize_path(BuilderHost.laying_dir()))
	Net.message_received.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "builder":
			_heard.append(data))
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()

	await _test_ask_and_accept()
	await _test_world_map_given()
	_test_spot_taken_up()
	_test_terrain_message()
	_test_world_map_window()
	await _test_refused()
	await _test_undo()
	await _test_flooded()
	await _test_spots_only()
	await _test_stale_proposal()
	await _test_laid_off_frame()
	await _test_laying_refusals()
	_test_recover_overlays()
	await _test_new_area()
	_test_console()
	_test_overlay_kinds()
	await _test_panel_keys()
	await _test_home_gives_way()
	await _test_first_spots_save()
	await _test_view_settled()
	await _test_threaded_soak()
	await _test_asking_focus()  # Last: its walk wakes the room's imps.

	_remove_tree(ProjectSettings.globalize_path(OVERLAY))
	_remove_tree(ProjectSettings.globalize_path(BuilderHost.laying_dir()))
	Level.overlay_dir = Level.OVERLAY
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The stub's chest: the middle of the area's middle third.
func _chest_cell() -> Vector2i:
	var area := Rect2i(AREA[0], AREA[1], AREA[2], AREA[3])
	var middle := Rect2i(area.position + area.size / 3, (area.size / 3).max(Vector2i.ONE))
	return middle.position + middle.size / 2


func _test_ask_and_accept() -> void:
	print("\n== a host asks, sees the proposal, accepts ==")
	_check(_main._builder != null, "builder mode is on (the stub)")
	var host := _player(Net.local_id)
	_check(host != null and host.zone == "test_room", "the host is in the test room")
	var host_tile := host.tile
	_main._on_command(host, "builder", {"op": "ask", "area": AREA, "text": "a chest to find"})
	var proposal := await _wait_for("proposal")
	_check(proposal.get("area") == AREA, "the proposal comes back for the area asked (%s)" % [proposal.get("area")])
	var cells: Array = proposal.get("cells", [])
	var chest := _chest_cell()
	_check(cells.any(func(cell: Array) -> bool: return Vector2i(cell[0], cell[1]) == chest and cell[2] == "chest"),
			"with the chest in it, for the ghost (%d cells)" % cells.size())
	_check("(Stub)" in str(proposal.get("summary", "")), "and what was made: %s" % proposal.get("summary"))
	_check(not Level.overlaid("test_room"), "nothing is saved yet")

	var boot_map: WorldMap = _main._world_map
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	# 197 amended (1): Main's world map, the one the residents' places are read from each sync, is the new one.
	var fresh := WorldMap.build()
	var held: Dictionary = _main._world_map.areas.get("test_room", {}) if _main._world_map != null else {}
	var built: Dictionary = fresh.areas.get("test_room", {})
	var same := ["floor", "places", "buildings", "spots", "links"].all(func(key: String) -> bool: return str(held.get(key)) == str(built.get(key)))
	_check(_main._world_map != null and _main._world_map != boot_map and not held.is_empty() and same
		and (World.forage == null or World.forage.world_map == _main._world_map),
		"accepted: Main holds a new world map, as a fresh one built on the saved files reads, and the forage reads it too")
	_check(Level.overlaid("test_room"), "accepted: the level is saved to the overlay (%s)" % ProjectSettings.globalize_path(OVERLAY))
	_check(FileAccess.file_exists(OVERLAY + "test_room/level.json"), "level.json too: the overlay is a whole level")
	var level := Level.load_level("test_room")
	var chests: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec["tile"] == chest)
	_check(chests.size() == 1 and chests[0]["props"].get("shop", false), "the game reads the chest from it, a shop counter's (the test room is no dungeon: 807 amended (4))")
	var was := World.enter_named("test_room")
	var live := World.get_entities().filter(func(entity: GridEntity) -> bool: return entity is Chest and entity.tile == chest)
	World.enter(was)
	_check(live.size() == 1, "the zone was rebuilt: the chest is there")
	_check(live.size() == 1 and Net.interest._where.has(live[0].get_instance_id()),
		"and the rebuilt chest is in the interest index, so it is sent to those near it (decision 217)")
	var after := _player(Net.local_id)
	_check(after != null and after.tile == host_tile, "and the host is where they were (%s)" % [after.tile if after else "-"])


## 197 amended (1): the places a sync hands a resident after an accept no longer list the spot it holds
## (taken up): it lets it go and picks again, never standing on it or walking to its cell.
func _test_spot_taken_up() -> void:
	print("\n== a resident on a spot an accept took up picks again ==")
	var a := {"use": "square", "cell": Vector2i(4, 4), "face": Vector2i(5, 4), "pose": "stand", "town": "", "trade": "", "pair": ""}
	var b := a.duplicate()
	b["cell"] = Vector2i(8, 6)
	b["face"] = Vector2i(9, 6)
	var square := Rect2i(3, 3, 9, 6)
	var body := Resident.new()
	body.doing = Resident.Doing.SQUARE
	body.tile = Vector2i(4, 4)
	body.places = {"square": square, "spots": {"square": [a, b]}}
	body._spot = a
	body._goal = a["cell"]
	body.take_places({"square": square, "spots": {"square": [a.duplicate(), b.duplicate()]}})
	_check(body._spot == a and body._goal == a["cell"], "its spot still listed (a fresh copy, as each sync makes): kept")
	body.take_places({"square": square, "spots": {"square": [b.duplicate()]}})
	_check(body._spot != a and body._goal != a["cell"], "its spot taken up: let go, another picked (%s, goal %s)" % [body._spot, body._goal])
	body._spot = b
	body._goal = b["cell"]
	var turned := b.duplicate()
	turned["face"] = Vector2i(8, 7)
	body.take_places({"square": square, "spots": {"square": [turned]}})
	_check(body._spot != b, "its spot changed (turned): picked again (%s)" % [body._spot])
	body.free()


## 867 amended (2): spots alone accepted on a level with no overlay yet (as every level on the box is until
## a builder's first accept there) write the whole overlay, the images as they were read, without the two
## parses save() makes (the ledges traced again, the report); a second such accept writes level.json alone.
func _test_first_spots_save() -> void:
	print("
== spots alone on a level not yet edited: every file, as read, no parse ==")
	await _host_home()
	_check(not Level.overlaid("test_room"), "after builder drop, test_room has no overlay")
	var before := Level.source("test_room")
	var ledges: Variant = before["config"].get("ledges")
	_main._builder.test_turns = [[{"name": "spot", "input": {"at": [4, 4], "use": "square", "face": [5, 4], "town": "test"}}], "A spot."]
	_main._on_command(_player(Net.local_id), "builder", {"op": "ask", "area": AREA, "text": "a spot"})
	await _wait_for("proposal")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	var after := Level.source("test_room")
	var report: String = _main._builder.docs["test_room"].report
	_check(Level.overlaid("test_room") and _saved_unparsed(report),
		"accepted: the overlay is written whole, saved without a parse (%s)" % report)
	_check(_saved_unparsed("saved user://tests_companions-floor/builder_zone_test/x/test_room/layout.png (31 x 35 cells)")
		and not _saved_unparsed("saved user://tests_builder/builder_zone_test/x/test_room/layout.png (31 x 35 cells, 275 floor, 3 things)")
		and not _saved_unparsed("could not save user://tests_builder/x/layout.png (31 x 35 cells)"),
		"the report's check reads its words after the path: a checkout named with \"floor\" passes, a parse's counts and a failed save do not")
	# The images as the level reads them. Since 867 amended (5) a spots-only first save writes the layout
	# the level was read from (not LevelMap.to_image's, RGBA8 with its own corner and fill pixels), so its
	# pixels equal the source's; what each cell, edge, height and relief value reads as must agree too.
	var read := func(made: Dictionary) -> LevelMap:
		var map := LevelMap.from_image(made["layout"], made["config"])
		if made.get("height") != null:
			map.read_heights(made["height"])
		map.read_relief(made.get("relief"))
		return map
	var was_map: LevelMap = read.call(before)
	var now_map: LevelMap = read.call(after)
	var differ := 0
	var a := (before["layout"] as Image).duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	var b := (after["layout"] as Image).duplicate() as Image
	b.convert(Image.FORMAT_RGBA8)
	for y in mini(a.get_height(), b.get_height()):
		for x in mini(a.get_width(), b.get_width()):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				differ += 1
	print("    layout pixels: source format %d, saved format %d, %d pixels differ as RGBA" % [
		(before["layout"] as Image).get_format(), (after["layout"] as Image).get_format(), differ])
	_check(differ == 0 and a.get_size() == b.get_size(),
		"867 amended (5): the layout written is the image the level was read from, pixel for pixel (no LevelMap.to_image; %d differ)" % differ)
	# What the game reads (Level.parse on both pictures, as decision 147's round trip in editor_test does):
	# the cells, the edges as walls, doors and open, the things, starts and links. The LevelMap difference
	# is printed for information: to_image keeps no edge on the outer east and south border, which Level.parse
	# makes an outline wall beside a walkable cell however it is painted (147 amended (1)).
	var cells_differ: Array[String] = []
	for at: Vector2i in was_map.cells:
		if now_map.cells.get(at, "-") != was_map.cells[at]:
			cells_differ.append("%s source %s saved %s" % [at, was_map.cells[at], now_map.cells.get(at, "-")])
	for at: Vector2i in now_map.cells:
		if not was_map.cells.has(at):
			cells_differ.append("%s source - saved %s" % [at, now_map.cells[at]])
	var edges_differ: Array[String] = []
	for key: Vector3i in was_map.edges:
		if now_map.edges.get(key, "-") != was_map.edges[key]:
			edges_differ.append("%s source %s saved %s" % [key, was_map.edges[key], now_map.edges.get(key, "-")])
	for key: Vector3i in now_map.edges:
		if not was_map.edges.has(key):
			edges_differ.append("%s source - saved %s" % [key, now_map.edges[key]])
	print("    LevelMap (information): cells source %d, saved %d, %d differ; edges source %d, saved %d, %d differ" % [
		was_map.cells.size(), now_map.cells.size(), cells_differ.size(), was_map.edges.size(), now_map.edges.size(), edges_differ.size()])
	for line in (cells_differ + edges_differ).slice(0, 50):
		print("      " + line)
	var parsed_was := Level.parse(before["layout"], before.get("height"), before["config"], before.get("relief"))
	var parsed_now := Level.parse(after["layout"], after.get("height"), after["config"], after.get("relief"))
	var differs: Array[String] = []
	for key: String in ["floor", "fire", "water", "kinds", "stairs", "edges", "heights"]:
		if str(parsed_was["terrain"][key]) != str(parsed_now["terrain"][key]):
			differs.append(key)
	for key: String in ["entities", "starts", "links"]:
		if str(parsed_was[key]) != str(parsed_now[key]):
			differs.append(key)
	_check(differs.is_empty(), "its layout reads in the game as the source's: cells, walls and doors, things, starts, links (%d floor, %d edges%s)" % [
		(parsed_now["terrain"]["floor"] as Array).size(), (parsed_now["terrain"]["edges"] as Dictionary).size(),
		"" if differs.is_empty() else "; differ: " + ", ".join(differs)])
	_check(str(was_map.heights) == str(now_map.heights) and was_map.relief == now_map.relief and (before.get("height") == null) == (after.get("height") == null),
		"its heights and relief read as the source's (%d heights, %d relief values)" % [now_map.heights.size(), now_map.relief.size()])
	_check(str(after["config"].get("ledges")) == str(ledges) and (after["config"].get("spots", []) as Array).size() == 1,
		"its ledges as they were, and the spot in level.json")
	var layout_md5 := FileAccess.get_md5(OVERLAY + "test_room/layout.png")
	_main._builder.sessions.clear()  # A fresh session, taking the new stub.
	_main._builder.test_turns = [[{"name": "spot", "input": {"at": [9, 7], "use": "square", "face": [9, 6], "town": "test"}}], "Another."]
	_main._on_command(_player(Net.local_id), "builder", {"op": "ask", "area": AREA, "text": "another spot"})
	await _wait_for("proposal")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	_check(FileAccess.get_md5(OVERLAY + "test_room/layout.png") == layout_md5 and _main._builder.docs["test_room"].report.ends_with("level.json")
		and (Level.source("test_room")["config"].get("spots", []) as Array).size() == 2,
		"a second spots accept writes level.json alone, both spots in it (%s)" % _main._builder.docs["test_room"].report)
	_main._builder.test_turns = []
	# 867 amended (5)'s other branch: a first save with a cell changed encodes the map's own image.
	BuilderHost.remove_overlay("test_room")
	var doc := MapDoc.from_level("test_room")
	var cell := Vector2i(6, 6)
	var was_cell := doc.map.cell(cell)
	doc.apply_changes({"cells": {cell: "dirt" if was_cell != "dirt" else "grass"}})
	_check(doc.save(false), "a first save with a changed cell (%s)" % doc.report)
	var saved := Image.load_from_file(ProjectSettings.globalize_path(OVERLAY + "test_room/layout.png"))
	var from_map := doc.map.to_image()
	saved.convert(Image.FORMAT_RGBA8)
	from_map.convert(Image.FORMAT_RGBA8)
	_check(saved.get_data() == from_map.get_data() and LevelMap.from_image(saved, doc.config).cell(cell) != was_cell,
		"a changed cell: the layout encoded from the map as before, the cell changed in it")
	doc.apply_changes({"config": {"spots": []}})
	_check(doc.save_config() and doc.report.ends_with("level.json"),
		"after it, a config-only save writes level.json alone, never the images it was read from (%s)" % doc.report)
	BuilderHost.remove_overlay("test_room")


func _test_terrain_message() -> void:
	print("\n== the terrain message ==")
	var message := BuilderHost.terrain_message("test_room")
	_check(not (message["layout"] as PackedByteArray).is_empty() and message["name"] == "test_room", "it carries the edited layout.png")
	var overlay := Level.overlay_dir
	Level.overlay_dir = "user://nowhere/"
	var before := Level.load_level("test_room")
	_check(not before["entities"].any(func(spec: Dictionary) -> bool: return spec["tile"] == _chest_cell()), "a client's own copy has no chest")
	_check(BuilderHost.register_terrain(message), "a client reads the message")
	var after := Level.load_level("test_room")
	_check(after["entities"].any(func(spec: Dictionary) -> bool: return spec["tile"] == _chest_cell()), "and its test room has the chest now")
	Level.unregister("test_room")
	Level.overlay_dir = overlay


## A joined client's world map window after a live change (197 amended (2)):
## a level the server sent is registered (BuilderHost.register_terrain), and
## the window's next open builds its graph again and reads the new name;
## opened with nothing changed it keeps the graph it has.
func _test_world_map_window() -> void:
	print("\n== the world map window after a live change: built again on its next open ==")
	var panel: WorldMapPanel = _main.world_map_panel
	_check(panel != null, "Main has its world map window")
	if panel == null:
		return
	panel.open()
	var first := panel.world
	_check(panel.place_words("wilds/square_fire") == "the square's fire", "the wilds' square fire by its own name (%s)" % panel.place_words("wilds/square_fire"))
	panel.close()
	panel.open()
	_check(panel.world == first, "opened again with nothing changed: the graph it had, not built again")
	panel.close()
	var source := Level.source("wilds")
	var config: Dictionary = (source["config"] as Dictionary).duplicate(true)
	config["places"]["square_fire"]["name"] = "Chapel Green"
	Level.register("wilds", source["layout"], source["height"], config, source["relief"])
	_check(panel.place_words("wilds/square_fire") == "the square's fire",
		"before the next open the HUD's words read the graph as built (no level read each frame)")
	panel.open()
	_check(panel.world != first and panel.place_words("wilds/square_fire") == "Chapel Green" and panel.boxes().has("wilds"),
		"the wilds changed live: the next open builds again and reads Chapel Green, the wilds' box laid out (%s)" % panel.place_words("wilds/square_fire"))
	panel.close()
	Level.unregister("wilds")
	panel.open()
	_check(panel.place_words("wilds/square_fire") == "the square's fire", "its registration gone, the next open reads the level's own name again")
	panel.close()


func _test_refused() -> void:
	print("\n== a player not allowed to build ==")
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	_check(bo != null and not _main._builder.allowed(BO, BO_ID), "Bo is in, not one of --builders")
	_main._on_command(bo, "builder", {"op": "ask", "area": AREA, "text": "a castle"})
	await get_tree().process_frame
	_check(not _main._builder.sessions.has(BO), "Bo's request is refused")
	Net.builders = PackedStringArray([BO_ID])
	_check(_main._builder.allowed(BO, BO_ID), "named in --builders, Bo may")
	Net.builders = PackedStringArray()


func _test_undo() -> void:
	print("\n== undo ==")
	_main._on_command(_player(Net.local_id), "builder", {"op": "undo"})
	await _wait_for("undone")
	var level := Level.load_level("test_room")
	_check(not level["entities"].any(func(spec: Dictionary) -> bool: return spec["tile"] == _chest_cell()), "Ctrl+Z: the chest is gone from the level")
	var was := World.enter_named("test_room")
	var live := World.get_entities().filter(func(entity: GridEntity) -> bool: return entity is Chest and entity.tile == _chest_cell())
	World.enter(was)
	_check(live.is_empty(), "and from the zone")


## Jeff's first live run: a pond over where a player stood put him at the
## level's start, across the map.
func _test_flooded() -> void:
	print("
== water over where the host stands: out to the nearest ground ==")
	var host := _player(Net.local_id)
	World._relocate(host, Vector2i(7, 6))
	_main._builder.test_turns = [[{"name": "paint", "input": {"ground": "water", "rects": [{"x": 5, "y": 4, "w": 5, "h": 5}]}}], "A pond."]
	_main._on_command(host, "builder", {"op": "ask", "area": [4, 3, 8, 6], "text": "a pond"})
	await _wait_for("proposal")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	var after := _player(Net.local_id)
	var tile: Vector2i = after.tile if after else Vector2i(-1, -1)
	_check(after != null and World.is_walkable(tile) and World.distance(tile, Vector2i(7, 6)) <= 3,
			"the host is on the shore, %d from where they stood (%s), not at a start" % [World.distance(tile, Vector2i(7, 6)), tile])
	_main._builder.test_turns = []
	_main._on_command(_player(Net.local_id), "builder", {"op": "undo"})
	await _wait_for("undone")
	var near := Vector2i(-1, -1)
	for cell: Vector2i in _main._terrain["floor"]:
		# Not a link's cell: _relocate onto one takes the link, a frame later (867 amended (3); (1, 1) to sample).
		if World.is_free(cell) and not World.is_link_cell(cell) and _main._nearest_hostile_distance(cell) <= _main.SPAWN_SAFE_DISTANCE:
			near = cell
			break
	World._relocate(_player(Net.local_id), near)
	_main.reload_zone("test_room")
	var stayed := _player(Net.local_id)
	_check(near != Vector2i(-1, -1) and stayed != null and stayed.tile == near,
			"a rebuild leaves a host standing near a monster where they are (%s, %s)" % [near, stayed.tile if stayed else "-"])


## The host back in the test room, on a cell picked from the level: _test_flooded leaves them on (1, 1),
## the link to sample, which they take a frame or more on (saturn's runs). Waits for any move under way to
## land first, travels back if it took them away, then stands them on the cell found and asserts it.
## While a row steps the world long (933's soak, the walk while he types), the room's imps reach the
## host whatever his home: on saturn under a suite's load economy's landing (11-15) had him downed in the
## soak and his bleed-out end free his body in _test_asking_focus's walk (a script error on me.tile). On,
## he holds HARDY_HP, more than the imps take in a row; off, his own max_hp again, whole.
const HARDY_HP := 1000000
var _kept_max_hp := 0
## The host's first downing from the first _hardy on (World.entity_downed): {by, tick}, {} none; read
## into a lost body's failure line (the coordinator's ask), so a next time is read from the log.
var _host_downed := {}


func _on_host_downed(entity: GridEntity, source: GridEntity, _ticks: int) -> void:
	if _host_downed.is_empty() and entity == _player(Net.local_id):
		_host_downed = {"by": source.name if is_instance_valid(source) else "nothing named", "tick": World.tick}


## Where the host's downing came, for a failure line: "downed by X at step N of the walk (tick T)",
## "... before the walk began (tick T)", or "never downed".
func _downed_said(walk_from_tick: int) -> String:
	if _host_downed.is_empty():
		return "never downed"
	var at: int = _host_downed["tick"]
	return "downed by %s %s (tick %d)" % [_host_downed["by"],
		"at step %d of the walk" % (at - walk_from_tick) if at >= walk_from_tick else "before the walk began", at]


func _hardy(on: bool) -> void:
	if not World.entity_downed.is_connected(_on_host_downed):
		World.entity_downed.connect(_on_host_downed)
	var host := _player(Net.local_id)
	if host == null:
		return
	if on:
		if _kept_max_hp == 0:
			_kept_max_hp = host.max_hp
		host.max_hp = HARDY_HP
		host.hp = HARDY_HP
	elif _kept_max_hp > 0:
		host.max_hp = _kept_max_hp
		host.hp = _kept_max_hp
		_kept_max_hp = 0


func _host_home() -> void:
	for i in 6:
		await get_tree().process_frame
	if _player(Net.local_id).zone != "test_room":
		_main.travel(Net.local_id, "test_room", "")
		for i in 6:
			await get_tree().process_frame
	var home := _home_cell()
	_check(home != Vector2i(-1, -1), "a home cell in the test room: floor, free, no link, off the edge, off the spots' cells (%s)" % [home])
	World._relocate(_player(Net.local_id), home)
	_player(Net.local_id).hp = _player(Net.local_id).max_hp
	for i in 3:
		await get_tree().process_frame
	var host := _player(Net.local_id)
	_check(host.zone == "test_room" and host.tile == home, "the host in the test room at %s (%s at %s)" % [home, host.zone, host.tile])


## The test room's floor cell nearest (10, 6) that is free, no link's and no neighbour of one, with floor on
## its four sides (off the level's edge), further than SPAWN_SAFE_DISTANCE from a hostile, and none of the
## cells the spots sections lay or paint; (-1, -1) if none.
func _home_cell() -> Vector2i:
	var links: Array[Vector2i] = []
	for link: Dictionary in _main.level.get("links", []):
		links.append(link["tile"])
	var floor := {}
	for cell: Vector2i in _main._terrain["floor"]:
		floor[cell] = true
	var kept := [Vector2i(4, 4), Vector2i(5, 4), Vector2i(9, 7), Vector2i(9, 6), Vector2i(10, 5)]
	var best := Vector2i(-1, -1)
	for cell: Vector2i in floor:
		# Off the edge: floor on all four sides, so no step from it leaves the level.
		if not World.is_free(cell) or cell in kept or not [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN].all(
				func(side: Vector2i) -> bool: return floor.has(cell + side)):
			continue
		if links.any(func(at: Vector2i) -> bool: return World.distance(at, cell) <= 1):
			continue
		if _main._nearest_hostile_distance(cell) <= _main.SPAWN_SAFE_DISTANCE:
			continue  # Out of the imps' way: a host beaten down mid-section is a test of something else.
		if best == Vector2i(-1, -1) or World.distance(cell, Vector2i(10, 6)) < World.distance(best, Vector2i(10, 6)):
			best = cell
	return best


## 867 amended (2): a proposal of spots alone is saved as level.json and put into the running world's map,
## with no layout.png written, no zone rebuilt and no world map built; what it leaves is what the whole
## way (a fresh map on the saved files, the level read again) reads. Spots with a paint take the whole way.
func _test_spots_only() -> void:
	print("
== spots alone: level.json saved, the spots put in, no rebuild ==")
	await _host_home()
	var host := _player(Net.local_id)
	var layout := OVERLAY + "test_room/layout.png"
	var layout_md5 := FileAccess.get_md5(layout)
	var map: WorldMap = _main._world_map
	var chest_was := World.get_entities().filter(func(entity: GridEntity) -> bool: return entity is Chest)
	_main._builder.test_turns = [[{"name": "spot", "input": {"at": [4, 4], "use": "square", "face": [5, 4], "town": "test"}},
		{"name": "spot", "input": {"at": [9, 7], "use": "work", "face": [9, 6], "trade": "cook", "town": "test"}}], "Two spots."]
	_main._on_command(host, "builder", {"op": "ask", "area": AREA, "text": "two spots"})
	await _wait_for("proposal")
	_check(_main._builder.sessions.values()[0].spots_only(), "the proposal is spots alone")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	var held: Array = _main._world_map.areas["test_room"].get("spots", [])
	_check(held.size() == 2 and held.any(func(spot: Dictionary) -> bool: return spot["cell"] == Vector2i(9, 7) and spot["trade"] == "cook"),
		"accepted: the running world map holds the two spots (%s)" % [held])
	_check(_main._world_map == map and FileAccess.get_md5(layout) == layout_md5,
		"with no world map built and layout.png not written")
	var chest_now := World.get_entities().filter(func(entity: GridEntity) -> bool: return entity is Chest)
	_check(chest_now == chest_was, "and no zone rebuilt: the same chest node stands")
	var fresh: Array = WorldMap.build().areas["test_room"]["spots"]
	_check(str(fresh) == str(held) and str(Level.load_level("test_room")["spots"]) == str(held),
		"what it holds is what the whole way reads: a map built fresh on the saved files, the level read again")
	_check(_main.admin_command("reload all").begins_with("no open zone"), "and the console's reload all sees the level as read")
	_main._builder.sessions.clear()  # A fresh session, taking the new stub: the same area would keep the last one's.
	_main._builder.test_turns = [[{"name": "spot", "input": {"at": [4, 4], "remove": true}},
		{"name": "paint", "input": {"ground": "grass", "rects": [{"x": 10, "y": 5, "w": 1, "h": 1}]}}], "A spot gone, some grass."]
	_main._on_command(_player(Net.local_id), "builder", {"op": "ask", "area": AREA, "text": "one spot fewer and some grass"})
	await _wait_for("proposal")
	_check(not _main._builder.sessions.values()[0].spots_only(), "spots with a paint: not spots alone")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	held = _main._world_map.areas["test_room"].get("spots", [])
	_check(_main._world_map != map and held.size() == 1 and held[0]["cell"] == Vector2i(9, 7),
		"accepted the whole way: a new world map, the one spot left (%s)" % [held])
	_main._builder.test_turns = []


## 867 amended (2): every session on a zone shares its doc, and a proposal is what its working copy
## differs from the doc at Enter: one made before another builder's accept would lay its cells and its whole
## level.json keys (the spots) back over that change. It is refused, saying why, and nothing is laid.
## On a doc of its own, so the host's level is left as the other tests have it.
func _test_stale_proposal() -> void:
	print("
== a proposal made before another builder's accept here is refused ==")
	var doc := MapDoc.from_level("test_room")
	var area := Rect2i(AREA[0], AREA[1], AREA[2], AREA[3])
	var first := BuilderSession.new(doc, area, "test_room", StubClaude.new([[{"name": "spot", "input": {"at": [4, 4], "use": "square", "face": [5, 4], "town": "test"}}], "A spot."]))
	await first.ask("a spot")
	var second := BuilderSession.new(doc, area, "test_room", StubClaude.new([[{"name": "paint", "input": {"ground": "rock", "rects": [{"x": 4, "y": 4, "w": 1, "h": 1}]}}], "Rock."]))
	await second.ask("rock where the spot is")
	_check(first.spots_only() and not second.spots_only(), "one proposes a spot alone, the other rock on its cell")
	var rocked := second.accept()
	_check(rocked, "the rock is accepted first (%s)" % second.refused)
	var rock := doc.map.cell(Vector2i(4, 4))
	var spots_before := str(doc.config.get("spots"))
	_check(not first.accept() and first.refused == BuilderSession.STALE_SAYS,
		"then the spot's accept is refused, saying why (%s)" % first.refused)
	_check(doc.map.cell(Vector2i(4, 4)) == rock and str(doc.config.get("spots")) == spots_before,
		"and nothing of it is laid: the rock stays, no spot on it")
	first.discard()
	_check(first.based_on == doc.revision, "discarded (its copy taken afresh), it builds on the rock")


## A fresh session asking to paint [param at] with [param ground], its proposal come.
func _ask_paint(at: Vector2i, ground: String) -> void:
	_main._builder.sessions.clear()
	_main._builder.test_turns = [[{"name": "paint", "input": {"ground": ground, "rects": [{"x": at.x, "y": at.y, "w": 1, "h": 1}]}}], "Painted."]
	_main._on_command(_player(Net.local_id), "builder", {"op": "ask", "area": AREA, "text": "paint"})
	await _wait_for("proposal")


## The folders left beside the overlay (BuilderHost.laying_dir).
func _laying_left() -> Array:
	var dir := ProjectSettings.globalize_path(BuilderHost.laying_dir())
	return Array(DirAccess.get_directories_at(dir)) if DirAccess.dir_exists_absolute(dir) else []


## 956: an accept laid off the server's frame: frame A starts its worker; the level parsed once in all and
## read back once, by the worker; the files, the doc, the zone and the world map agree after; nothing left
## beside the overlay. The stale check made again at frame B, and a second rename that fails, each leave
## the files and the doc as they were.
func _test_laid_off_frame() -> void:
	print("\n== 956: an accept laid off the server's frame ==")
	var builder: BuilderHost = _main._builder
	var at := Vector2i(6, 5)
	await _ask_paint(at, "dirt")
	var parses := Level.parses
	var reads := Level.folder_reads
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	_check(builder.laying.has("test_room"), "accepted: being laid, its worker started (frame A)")
	var answer := await _wait_for("accepted")
	_check(answer.get("state") == "accepted", "and accepted when laid (frame B)")
	_check(Level.parses - parses == 1, "the level parsed once for the whole accept (%d)" % (Level.parses - parses))
	_check(int(builder.last_laid.get("reads_in_b", -1)) == 0 and int(builder.last_laid.get("parses_in_b", -1)) == 0,
		"frame B read no level from disk and parsed none (%s reads, %s parses; %d level reads in all, the host's own client's among them)" % [
			builder.last_laid.get("reads_in_b"), builder.last_laid.get("parses_in_b"), Level.folder_reads - reads])
	_check(builder.laying.is_empty() and _laying_left().is_empty(), "nothing being laid, no folder left beside the overlay (%s)" % [_laying_left()])
	var doc: MapDoc = builder.docs["test_room"]
	var on_disk := MapDoc.open(OVERLAY + "test_room/")
	_check(on_disk.map.cell(at) == doc.map.cell(at) and str(on_disk.config) == str(JSON.parse_string(doc.source_text)),
		"the doc is what the files hold (the cell, the config as written)")
	_check(Level.load_level("test_room")["terrain"]["kinds"].get(at) == _main._terrain["kinds"].get(at),
		"the zone was reloaded from what the files hold")
	_check(str(WorldMap._read_before.get("test_room", {}).get("key", "")) == Level.files_key("test_room"),
		"the world map kept the worker's read, keyed to the files written")
	var figures: Dictionary = builder.last_laid
	_check(figures.has("frame_a") and figures.has("worker") and figures.has("frame_b") and figures.has("longest"),
		"its frames logged (frame A %.1f ms, worker %.0f ms, longest frame meanwhile %.1f ms, frame B %.1f ms; logged, not held to)" % [
			figures.get("frame_a", 0.0), figures.get("worker", 0.0), figures.get("longest", 0.0), figures.get("frame_b", 0.0)])

	print("\n== 956: the stale check again at frame B (a write slipped past the busy mark) ==")
	await _ask_paint(Vector2i(7, 5), "dirt")
	var key := Level.files_key("test_room")
	builder.test_between = func(_job: Dictionary) -> void: doc.revision += 1
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	answer = await _wait_for("accepted")
	builder.test_between = Callable()
	_check(answer.get("error") == BuilderSession.STALE_SAYS, "refused as a stale ask is (%s)" % answer.get("error", answer.get("state")))
	_check(Level.files_key("test_room") == key and _laying_left().is_empty(), "its files as they were, nothing left beside them")

	print("\n== 956: the second rename fails (a folder held open on Windows) ==")
	await _ask_paint(Vector2i(7, 5), "dirt")
	key = Level.files_key("test_room")
	var revision := doc.revision
	builder.fail_rename_from = ProjectSettings.globalize_path(BuilderHost.laying_dir() + "test_room.new")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	answer = await _wait_for("accepted")
	builder.fail_rename_from = ""
	_check(str(answer.get("error", "")).begins_with("could not save"), "the builder told it could not be saved (%s)" % answer.get("error", answer.get("state")))
	_check(Level.files_key("test_room") == key and doc.revision == revision and _laying_left().is_empty(),
		"the old files put back, the doc as it was, nothing left beside them (files %s, revision %d to %d, left %s)" % [
			"the same" if Level.files_key("test_room") == key else "changed", revision, doc.revision, _laying_left()])


## 956: one writer a zone. While an accept is laid, an undo and another builder's accept (one making a
## new level beyond an edge, which keeps today's path) are refused as busy and leave nothing behind; a
## quit while one is laid joins its worker and leaves the level whole.
func _test_laying_refusals() -> void:
	print("\n== 956: one writer a zone while an accept is laid ==")
	var builder: BuilderHost = _main._builder
	await _ask_paint(Vector2i(8, 5), "dirt")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	_check(builder.laying.has("test_room"), "an accept being laid")
	_heard.clear()
	_main._on_command(_player(Net.local_id), "builder", {"op": "undo"})
	var undo_heard: Dictionary = _heard.back() if not _heard.is_empty() else {}
	_heard.clear()
	_check(undo_heard.get("error") == BuilderHost.LAYING_SAYS, "an undo meanwhile refused as busy (%s)" % undo_heard.get("error", undo_heard.get("state")))
	var other := BuilderSession.new(builder.docs["test_room"], Rect2i(AREA[0], AREA[1], AREA[2], AREA[3]), "test_room", StubClaude.new([]))
	other.new_area = {"name": "zt_beyond", "title": "Beyond", "side": "east", "size": Vector2i(8, 8), "seed": 1, "gate": 2}
	builder.sessions[BO] = other
	builder._session_zone[BO] = "test_room"
	builder._accept(BO, BO_ID)
	_check(not builder.created.has("zt_beyond") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OVERLAY + "zt_beyond"))
		and not _laying_left().has("zt_beyond.new") and builder.laying.size() == 1,
		"another builder's accept of a new level beyond an edge refused as busy, nothing of it written")
	builder.sessions.erase(BO)
	builder._session_zone.erase(BO)
	await _wait_for("accepted")
	_check(builder.laying.is_empty() and _laying_left().is_empty(), "the first laid, nothing left beside the overlay")

	print("\n== 956: a quit while an accept is laid ==")
	await _ask_paint(Vector2i(9, 5), "dirt")
	var key := Level.files_key("test_room")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	builder.finish_laying()
	var whole := Level.load_level("test_room")
	_check(builder.laying.is_empty() and _laying_left().is_empty() and not whole.is_empty(),
		"its worker joined, nothing left beside the overlay, the level whole (%s)" % ("the new files" if Level.files_key("test_room") != key else "the old files"))
	# Not quitting after all: the doc and the zone read again from the files, the session let go.
	builder.docs.erase("test_room")
	builder.sessions.clear()
	_main.reload_zone("test_room")


## 956: what an accept stopped in the middle of leaves, put right at boot: an old folder with none in the
## overlay put back; a new one beside a level in the overlay, and one alone, removed.
func _test_recover_overlays() -> void:
	print("\n== 956: a stopped accept's folders put right at boot ==")
	var laying := ProjectSettings.globalize_path(BuilderHost.laying_dir())
	var overlay := ProjectSettings.globalize_path(OVERLAY)
	for name: String in ["zt_rec.old", "test_room.new", "zt_lone.new"]:
		DirAccess.make_dir_recursive_absolute(laying.path_join(name))
		FileAccess.open(laying.path_join(name).path_join("level.json"), FileAccess.WRITE).store_string(JSON.stringify({"name": name}))
	var key := Level.files_key("test_room")
	BuilderHost.recover_overlays()
	_check(FileAccess.file_exists(overlay.path_join("zt_rec/level.json")), "an old folder with none in the overlay: put back")
	_check(Level.files_key("test_room") == key and _laying_left().is_empty(), "a new folder beside the level's own, and one alone: removed, the level as it was")
	BuilderHost.remove_folder(overlay.path_join("zt_rec"))


func _test_new_area() -> void:
	print("
== a new area beyond the east edge, walked into, taken back ==")
	_main._builder.test_turns = [[{"name": "new_area", "input": {"side": "east", "width": 24, "height": 24, "name": "Cellar Fields", "seed": 2}}],
		"A way east to the Cellar Fields."]
	var host := _player(Net.local_id)
	var area := [25, 10, 6, 6]
	_main._on_command(host, "builder", {"op": "ask", "area": area, "text": "somewhere new to the east"})
	var proposal := await _wait_for("proposal")
	_check(proposal.get("new_area", {}).get("name") == "cellar_fields" and proposal["new_area"]["footprint"] == [31, 0, 24, 24],
			"the proposal: a new level, cellar_fields, past the east edge (%s)" % [proposal.get("new_area")])
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	_check(Level.overlaid("cellar_fields") and "cellar_fields" in Level.names(), "accepted: the new level is in the overlay, and among the levels")
	var world := WorldMap.build()
	var exit := Vector2i(30, 13)
	var way := world.crossing("test_room", exit, Vector2i(1, 0))
	_check(way.get("to") == "cellar_fields", "walking east off %s leads there (%s)" % [exit, way])
	var problems := world.problems().filter(func(problem: String) -> bool: return "cellar_fields" in problem)
	_check(problems.is_empty(), "and the world map finds nothing wrong with it (%s)" % [problems])
	var zone_level := Level.load_level("test_room")
	_check(Vector2i(30, 13) in (zone_level["terrain"]["floor"] as Array), "the way out reaches the edge")

	_check(_main.travel(Net.local_id, "cellar_fields", "", {"side": "east", "cell": exit + Vector2i(1, 0)}), "the host walks across")
	for i in 4:
		await get_tree().process_frame
	var there := _player(Net.local_id)
	_check(there != null and there.zone == "cellar_fields", "and is in the new level (%s at %s)" % [there.zone if there else "-", there.tile if there else "-"])
	_main._on_command(there, "builder", {"op": "undo"})
	await get_tree().process_frame
	var refused: int = _main._builder.docs["test_room"].undo_steps.size()
	_check(Level.overlaid("cellar_fields") and refused > 0, "undo from inside it is refused: someone is there")
	_main.travel(Net.local_id, "test_room", "")
	for i in 4:
		await get_tree().process_frame
	_heard.clear()
	_main._on_command(_player(Net.local_id), "builder", {"op": "undo"})
	await _wait_for("undone")
	_check(not Level.overlaid("cellar_fields") and not Level.load_level("test_room").get("neighbours", {}).has("east"),
			"back home, undo takes the way, the neighbour and the level away")
	_main._builder.test_turns = []


func _test_console() -> void:
	print("\n== the console ==")
	_check("$" in _main.admin_command("builder") and "test_room" in _main.admin_command("builder"), "builder: how it is, the edited levels")
	var exported: String = _main.admin_command("builder export")
	_check("layout.png -> levels/test_room/layout.png" in exported and "level.json" in exported, "builder export: where each file goes")
	_check(_main.admin_command("reload all").begins_with("no open zone"), "reload all: nothing changed on disk, nothing reloaded")
	var json := Level.overlay_dir + "test_room/level.json"
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json))
	config["name"] = "The Test Room, edited by hand"
	FileAccess.open(json, FileAccess.WRITE).store_string(JSON.stringify(config, "	"))
	var reloaded: String = _main.admin_command("reload all")
	_check(reloaded.begins_with("test_room reloaded from") and _main.level.get("display_name", "") == "The Test Room, edited by hand",
		"reload all: a level edited on disk is read again, no restart (%s)" % reloaded)
	_check(_main.admin_command("reload all").begins_with("no open zone"), "and only once")
	_check(_main.admin_command("reload test_room").begins_with("test_room reloaded"), "reload <zone>: that one, changed or not")
	_check(_main.admin_command("reload nowhere").contains("not open"), "reload of a zone not open: says so")
	_check("dropped" in _main.admin_command("builder drop test_room") and not Level.overlaid("test_room"), "builder drop: the repo's level again")
	_check("usage" in _main.admin_command("builder drop nothing_here"), "builder drop of a level not edited: how to use it")


## 199 amended (2): the overlay's two kinds named apart. A generation the regenerator laid (Regen.write,
## a "regenerate" block in its level.json) reads as a plain line at boot and is listed as laid, never as
## one to copy into levels/; a level edited in the game keeps its warning and its export lines. The rule
## is Regen.write's own: it writes over the laid one and refuses the edit.
func _test_overlay_kinds() -> void:
	print("\n== the overlay's laid generations and in-game edits, named apart (199 amended (2)) ==")
	var block := {"generator": "maze", "every_days": 3, "anchors": []}
	var layout := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	Level.keep_template("zt_laid", {"layout": layout, "height": null, "config": {"regenerate": block}})
	var laid_ok := Regen.write("zt_laid", {"layout": layout, "height": null, "config": {"regenerate": block, "generation": 3}})
	var edit_dir := ProjectSettings.globalize_path(Level.overlay_dir + "zt_edit")
	DirAccess.make_dir_recursive_absolute(edit_dir)
	layout.save_png(edit_dir.path_join("layout.png"))
	FileAccess.open(Level.overlay_dir + "zt_edit/level.json", FileAccess.WRITE).store_string(JSON.stringify({"name": "Edited in the game"}))
	_check(laid_ok and Level.overlaid("zt_laid") and Level.overlaid("zt_edit"), "a generation laid by Regen.write and an edit, both in the overlay")
	var kinds := BuilderHost.overlay_kinds()  # An earlier row's new level may stand there too.
	var laid: Array = kinds["laid"]
	var edited: Array = kinds["edited"]
	_check("zt_laid" in laid and "zt_laid" not in edited and "zt_edit" in edited and "zt_edit" not in laid,
		"overlay_kinds: each in its own kind (%s)" % [kinds])
	var summary := "edited levels: %s; laid generations: %s" % [", ".join(edited), ", ".join(laid)]
	var lines := BuilderHost.boot_lines()
	var mark := Regen.template_mark("zt_laid").left(8)
	var laid_line := lines.filter(func(line: Dictionary) -> bool: return "zt_laid" in line["text"])
	var edit_line := lines.filter(func(line: Dictionary) -> bool: return "zt_edit" in line["text"])
	_check(laid_line.size() == 1 and not laid_line[0]["warn"] and (laid_line[0]["text"] as String).begins_with(
		"[builder] zt_laid is a laid generation (generation 3), from the template of %s, written " % mark),
		"boot: the laid generation a plain line, its number and template (%s)" % (laid_line[0]["text"] if laid_line.size() == 1 else "none"))
	_check(edit_line.size() == 1 and edit_line[0]["warn"] and "(edited in the game)" in edit_line[0]["text"], "boot: the edit warned as before")
	var said: String = _main.admin_command("builder")
	_check(said.ends_with(summary), "builder: the two kinds named apart (%s)" % said.right(80))
	var exported: String = _main.admin_command("builder export")
	_check(exported.contains("-> levels/zt_edit/layout.png") and not exported.contains("-> levels/zt_laid/")
		and exported.ends_with("laid generations, the regenerator's, not to copy: " + ", ".join(laid)),
		"builder export: the edit's files to copy, the generation named not to copy (%s)" % exported.right(80))
	_check(_main.admin_command("builder drop nothing_here").contains(summary), "builder drop's usage: both kinds")
	_check(Regen.write("zt_laid", {"layout": layout, "height": null, "config": {"regenerate": block, "generation": 4}}),
		"Regen.write: lays over the one named laid")
	_check(not Regen.write("zt_edit", {"layout": layout, "height": null, "config": {"regenerate": block}}),
		"Regen.write: refuses the one named edited (its warning above)")
	for level_name: String in ["zt_laid", "zt_edit"]:
		BuilderHost.remove_overlay(level_name)
		Level.unregister(level_name)
		Level._templates.erase(level_name)
	Regen.forget()
	var after := BuilderHost.overlay_kinds()
	_check("zt_laid" not in (after["laid"] as Array) and "zt_edit" not in (after["edited"] as Array), "and both gone after")


## Whether a MapDoc report says a save without a parse: "saved <path> (W x H cells)", where one with a
## parse adds ", N floor, N things". Its words after the path are read, never the path: the path holds
## the checkout's name, and companions' saturn take ran in "companions-floor" (2026-11-14).
static func _saved_unparsed(report: String) -> bool:
	if not report.begins_with("saved "):
		return false
	var words := report.substr(report.rfind(" ("))
	return RegEx.create_from_string("^ \\(\\d+ x \\d+ cells\\)$").search(words) != null


## The builder panel's keys on the host's own client (885 amended (1)), through the viewport as a
## keyboard sends them: an answer comes cut down, the box without the keys; Tab opens it whole, the box
## taking them; Esc from the empty box cuts it down again, the proposal kept; Esc with words in the box
## clears them; Tab in the box cuts it down; Esc cut down discards, as before.
func _test_panel_keys() -> void:
	print("\n== the builder panel's keys: cut down while he reads, Tab whole, Esc back ==")
	var ui: BuilderUI = _main._builder_ui
	_check(ui != null, "the host's client has builder mode")
	if ui == null:
		return
	_main._builder.sessions.clear()
	_main._builder.test_turns = [[{"name": "spot", "input": {"at": [4, 4], "use": "square", "face": [5, 4], "town": "test"}}], "A spot."]
	ui.test_ask("%d,%d,%d,%d:a spot" % AREA)
	await _wait_for("proposal")
	for i in 2:
		await get_tree().process_frame
	var panel := ui.panel
	_check(ui.state == "proposal" and panel.visible and panel.has_answer() and not panel.full and not ui.is_typing(),
		"the answer cut down, the box without the keys (state %s, full %s, typing %s)" % [ui.state, panel.full, ui.is_typing()])
	get_viewport().push_input(_key(KEY_TAB))
	_check(panel.full and ui.is_typing(), "Tab: whole, the box takes the keys (full %s, typing %s)" % [panel.full, ui.is_typing()])
	get_viewport().push_input(_key(KEY_ESCAPE, true))
	get_viewport().push_input(_key(KEY_TAB, true))
	_check(panel.full and ui.is_typing() and ui.state == "proposal", "a held key's echo in the box: nothing (full %s, typing %s)" % [panel.full, ui.is_typing()])
	get_viewport().push_input(_key(KEY_ESCAPE))
	_check(not panel.full and ui.state == "proposal" and not ui.is_typing(), "Esc from the empty box: cut down again, the proposal kept (%s)" % ui.state)
	get_viewport().push_input(_key(KEY_TAB))
	panel.box.text = "bigg"
	get_viewport().push_input(_key(KEY_ESCAPE))
	_check(panel.full and panel.box.text.is_empty() and ui.state == "proposal", "Esc with words in the box: the words gone, still whole")
	get_viewport().push_input(_key(KEY_TAB))
	_check(not panel.full and ui.state == "proposal", "Tab in the box: cut down, the talk log left closed")
	get_viewport().push_input(_key(KEY_ESCAPE))
	_check(ui.state == "asking" and panel.box.visible, "Esc cut down: discarded, as before, the box asking again (%s)" % ui.state)
	await _wait_for("discarded")
	await get_tree().process_frame
	var typing_before := ui.is_typing()
	get_viewport().push_input(_key(KEY_TAB))
	_check(typing_before and ui.is_typing() and panel.box.has_focus() and ui.state == "asking",
		"Tab while he asks: the box keeps the keys, the focus not moved off it (typing %s then %s)" % [typing_before, ui.is_typing()])
	ui.escape()
	ui.toggle()
	_main._builder.test_turns = []


## 885 amended (1) with ui's Main.open_window_rects (802 amended (15)): the pack open, the right home
## gives way before the pane is drawn, whatever the area's outline.
func _test_home_gives_way() -> void:
	print("\n== the pack open: the right home gives way to it, chosen before the pane is drawn ==")
	var ui: BuilderUI = _main._builder_ui
	if ui == null or _main.pack_panel == null:
		_check(false, "the host's client has builder mode and a pack")
		return
	var was_open: bool = _main.pack_panel.is_visible_in_tree()
	if not was_open:
		_main.toggle_pack()
	await get_tree().process_frame
	var holder := ui.panel.get_parent_control()
	var screen := holder.size if holder != null else ui.panel.get_viewport_rect().size
	# The room a right-home pane may take: full, WIDTH wide, to the screen's foot (choose_home's reach).
	var reach := BuilderPanel.home_rect("right", Vector2(BuilderPanel.WIDTH, screen.y - BuilderPanel.RIGHT_TOP - BuilderPanel.FOOT_ROOM), screen)
	var rects: Array[Rect2] = _main.open_window_rects()
	_check(_main.pack_panel.is_visible_in_tree() and rects.any(func(rect: Rect2) -> bool: return rect.intersects(reach)),
		"the pack open: Main's open windows meet the right home's reach (%s against %s)" % [rects, reach])
	var under_left: Array = [Vector2(300, 400), Vector2(600, 500)]
	var pane := Vector2(BuilderPanel.NARROW, BuilderUI.BRIEF_HEIGHT)
	_check(BuilderUI.choose_home(under_left, pane, screen, []) == "right" and BuilderUI.choose_home(under_left, pane, screen, rects) == "left",
		"an outline under the left home: right with nothing open, left with Main's rects while the pack is open")
	ui.test_ask("%d,%d,%d,%d:" % AREA)
	await get_tree().process_frame
	var bare := BuilderUI.choose_home(ui.outline_points(), Vector2(BuilderPanel.NARROW, BuilderUI.BRIEF_HEIGHT), screen, [])
	_check(ui.state == "asking" and ui.panel.home == "left",
		"a new area with the pack open: the left home (%s; with nothing open it would be %s)" % [ui.panel.home, bare])
	ui.escape()
	if ui.active:
		ui.toggle()
	if not was_open and _main.pack_panel.is_visible_in_tree():
		_main.toggle_pack()


## ui-design's joined stills (2026-11-14): --test-builder asked while the camera still came in, so the
## pane took one home asking and the other at the answer. It now waits for the view to rest on him.
func _test_view_settled() -> void:
	print("\n== --test-builder waits for the camera to rest on the player ==")
	var ui: BuilderUI = _main._builder_ui
	var me: Player = _main._local_player()
	if ui == null or me == null:
		_check(false, "the host's client has builder mode and a player")
		return
	_check(_main._client3d != null or ui.view_settled(me), "without a 3D view (headless): asked at once")
	# Whether the camera follows him, tick by tick, as Client3D.camera_on would say (the test has no view).
	var reset := func() -> void:
		ui._view_ticks = 0
		ui._view_still = 0
		ui._pose_anchor = []
	reset.call()
	# stills5-7: the camera parked at the level's middle, then coming in, then on him.
	var early := 0
	for i in 40:
		if ui.settle_step(false):
			early += 1
	var on_after := -1
	for i in BuilderUI.VIEW_STILL_TICKS + 5:
		if ui.settle_step(true):
			on_after = i + 1
			break
	_check(early == 0 and on_after == BuilderUI.VIEW_STILL_TICKS,
		"the camera not yet on him: never settled (%d); on him, settled on the %dth tick running (%d)" % [early, BuilderUI.VIEW_STILL_TICKS, on_after])
	reset.call()
	var broken := -1
	var looks := [true, true, false]
	for i in BuilderUI.VIEW_STILL_TICKS + 2:
		looks.append(true)
	for i in looks.size():
		if ui.settle_step(looks[i]):
			broken = i + 1
			break
	_check(broken == 3 + BuilderUI.VIEW_STILL_TICKS, "a tick off him starts the count again (settled on look %d)" % broken)
	reset.call()
	# stills11: an ease's tail creeping under EYE_STILL a tick never settles; the camera at rest then does.
	var creep := -1
	for i in 60:
		var pose := [Vector3(0.0, 10.0, 0.0), Vector3.FORWARD, 12.0 + i * BuilderUI.EYE_STILL * 0.4, 75.0]
		if ui.settle_step(true, pose):
			creep = i
			break
	var rest := -1
	for i in BuilderUI.VIEW_STILL_TICKS + 5:
		if ui.settle_step(true, [Vector3(0.0, 10.0, 0.0), Vector3.FORWARD, 13.0, 75.0]):
			rest = i + 1
			break
	_check(creep == -1 and rest == BuilderUI.VIEW_STILL_TICKS,
		"a camera creeping %.3f a tick (under %.2f) never settles in 60 ticks; at rest, on the %dth tick (%d, %d)" % [
			BuilderUI.EYE_STILL * 0.4, BuilderUI.EYE_STILL, BuilderUI.VIEW_STILL_TICKS, creep, rest])
	reset.call()
	var capped := -1
	for i in BuilderUI.VIEW_WAIT_TICKS + 5:
		if ui.settle_step(false):
			capped = i + 1
			break
	_check(capped == BuilderUI.VIEW_WAIT_TICKS, "a camera never on him: asked after the cap, %d ticks (%d)" % [BuilderUI.VIEW_WAIT_TICKS, capped])
	reset.call()
	await get_tree().process_frame
	# ui-design's joined stills quit at a moment of the builder's: the two flags are read, either form.
	var kept := [Net.test_exit_after_ask, Net.test_exit_after_answer]
	Net._parse_args(["--test-exit-after-ask=2", "--test-exit-after-answer", "3.5"])
	_check(Net.test_exit_after_ask == 2.0 and Net.test_exit_after_answer == 3.5,
		"--test-exit-after-ask=2 and --test-exit-after-answer 3.5 are read (%s, %s)" % [Net.test_exit_after_ask, Net.test_exit_after_answer])
	Net.test_exit_after_ask = kept[0]
	Net.test_exit_after_answer = kept[1]


## The coordinator's question on ui-design's asking still (2026-11-14): right after the drag, does the
## typing box hold the keys, and does a walk ordered then go on or stop, and by which line of Main.
func _test_asking_focus() -> void:
	print("\n== asking: the box has the keys the frame after the drag; a walk waits while he types ==")
	var ui: BuilderUI = _main._builder_ui
	var me: Player = _main._local_player()
	_check(ui != null and me != null, "the host's client has builder mode and its own player")
	if ui == null or me == null:
		return
	_hardy(true)
	var from := me.tile
	var to := Vector2i(-1, -1)
	for step: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
		if not World.walk_path(from, from + step, me).is_empty():
			to = from + step
			break
	ui.test_ask("%d,%d,%d,%d:" % AREA)
	await get_tree().process_frame
	_check(ui.state == "asking" and ui.panel.visible and ui.panel.box.visible and ui.panel.box.has_focus() and ui.is_typing() and _main.is_typing(),
		"the frame after the drag: asking, the box shown and holding the focus (has_focus %s, BuilderUI typing %s, Main typing %s)"
		% [ui.panel.box.has_focus(), ui.is_typing(), _main.is_typing()])
	var own: Variant = _main._free_own(me)
	print("    (information) the own body free: %s; walk from %s to %s" % [own != null, from, to])
	if own != null and to.x >= 0:
		_check(_main._free_intent(me, own) == Vector2.ZERO, "Main._free_intent: ZERO while Main.is_typing() (its first line): no way meant, so no step")
		_main._move_click(me, to, false)
		var walk_from_tick := World.tick
		for i in 60:
			World.step()
			await get_tree().process_frame
		if not is_instance_valid(me):
			_check(false, "the host's body still there after 60 steps (gone: %s)" % _downed_said(walk_from_tick))
			return
		var held := me.tile
		_check(held == from, "a walk ordered while he types waits: still at %s after 60 steps (at %s)" % [from, held])
		print("    (information) the route kept while he types: %d cells" % (_main._free["path"] as Array).size())
		ui.panel.box.release_focus()
		for i in 120:
			World.step()
			await get_tree().process_frame
		if is_instance_valid(me):
			print("    (information) the box let go: at %s (from %s), the route %d cells, Main typing %s" % [me.tile, from, (_main._free["path"] as Array).size(), _main.is_typing()])
	_hardy(false)
	ui.escape()
	if ui.active:
		ui.toggle()


func _key(code: Key, echo := false) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	key.echo = echo
	return key


func _wait_for(state: String) -> Dictionary:
	for i in 300:
		for heard in _heard:
			if heard.get("state") == state or heard.get("state") == "error":
				_heard.clear()
				if heard.get("state") == "error":
					print("    error: %s" % heard.get("error"))
				return heard
		World.step()
		await get_tree().process_frame
	print("    no \"%s\" came" % state)
	return {}


func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) else null


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## 933 (the coordinator's soak row): several asks in a row through the host, the world stepping each frame
## while they run (_wait_for), a town's plot laid as the second goes out, inline (--builder-inline) and then
## on a worker: every answer the same. An engine error or a script error anywhere fails the scene (run.sh).
func _test_threaded_soak() -> void:
	print("\n== asks in a row on a worker, the town ticking, a plot laid meanwhile: the answers as inline (933) ==")
	await _host_home()
	if World.clearing == null:
		_check(false, "the host has the town's clearing (plots)")
		return
	var turns := [
		[[{"name": "paint", "input": {"ground": "grass", "rects": [{"x": 10, "y": 5, "w": 1, "h": 1}]}}], "Grass."],
		[[{"name": "spot", "input": {"at": [4, 4], "use": "square", "face": [5, 4], "town": "test"}}], "A spot."],
		[[{"name": "paint", "input": {"ground": "dirt", "rects": [{"x": 9, "y": 5, "w": 1, "h": 1}]}},
			{"name": "spot", "input": {"at": [9, 7], "use": "work", "face": [9, 6], "trade": "cook", "town": "test"}}], "Dirt and a cook."],
		[[{"name": "paint", "input": {"ground": "grass", "rects": [{"x": 6, "y": 6, "w": 2, "h": 1}]}}], "More grass."],
	]
	var plot := Rect2i(14, 12, 2, 2)
	_hardy(true)
	var kept_inline := Net.builder_inline
	var kept_state: String = _main._builder_ui.state if _main._builder_ui != null else ""
	var said := {}
	for inline: bool in [true, false]:
		Net.builder_inline = inline
		_main._builder.sessions.clear()
		var answers: Array[String] = []
		for i in turns.size():
			_main._builder.sessions.clear()  # A fresh session takes the new turns: one kept replays its first.
			_main._builder.test_turns = turns[i]
			_heard.clear()
			_main._on_command(_player(Net.local_id), "builder", {"op": "ask", "area": AREA, "text": "ask %d" % i})
			if i == 1:
				World.clearing.lay_plot("test_room", "test", "house", plot, Vector2i(0, 1))
			var heard := await _wait_for("proposal")
			answers.append(str(heard))
		World.clearing.unplot("test_room", plot)
		said[inline] = answers
		_main._builder.sessions.clear()
	Net.builder_inline = kept_inline
	_main._builder.test_turns = []
	_hardy(false)
	# The answers reached the host's own panel too, as proposals of sessions cleared above: put it
	# back here, with no discard sent (an empty ask after would read as an accept, "Nothing to do").
	var ui: BuilderUI = _main._builder_ui
	if ui != null and ui.state != kept_state:
		ui._reset()
	var all_came := (said[false] as Array).all(func(answer: String) -> bool: return answer.contains("\"proposal\""))
	var own := func(answer: String, words: String) -> bool: return answer.contains(words)
	all_came = all_came and own.call(said[false][1], "A spot.") and own.call(said[false][2], "Dirt and a cook.") and own.call(said[false][3], "More grass.")
	_check(all_came and str(said[false]) == str(said[true]),
		"%d asks in a row, each answer on a worker as inline (%s)" % [turns.size(), "same" if str(said[false]) == str(said[true]) else str(said[false]).left(300)])


## 933: the world map the host hands each ask (Main's, BuilderSession.world_map_of) gives the session's
## answers a fresh WorldMap.build() gives: the other towns' stockpiles (town_ids) and the names a milestone
## may carry (reachable_names), now, after an accept in the zone and after a regeneration's write (both of
## which have Main adopt a new map). No worker ever builds one.
func _test_world_map_given() -> void:
	print("\n== the host's world map in place of a fresh build: the same towns and names (933) ==")
	await _host_home()
	var zone_doc: MapDoc = MapDoc.from_level("test_room")
	var area := Rect2i(AREA[0], AREA[1], AREA[2], AREA[3])
	# Run early: the test room's overlay as later sections leave it has a link marker going nowhere, past which
	# neither map reaches a name.
	var compare := func(when: String) -> void:
		var given := BuilderSession.new(zone_doc, area, "test_room", StubClaude.new([]))
		given.world_map_of = func() -> WorldMap: return _main._world_map
		var built := BuilderSession.new(zone_doc, area, "test_room", StubClaude.new([]))
		var towns := given.town_ids()
		var built_towns := built.town_ids()
		var names := BuilderSession.reachable_names(_main._world_map)
		var fresh_names := BuilderSession.reachable_names(WorldMap.build())
		_check(_main._world_map != null and str(towns) == str(built_towns) and str(names) == str(fresh_names) and not names.is_empty(),
			"%s: the host's map gives the towns and the names a fresh build gives (%d and %d towns, %d and %d names)" % [
				when, towns.size(), built_towns.size(), names.size(), fresh_names.size()])
		given.world_map_of = Callable()
	compare.call("at the start")
	var map_before: WorldMap = _main._world_map
	_main._builder.sessions.clear()
	_main._builder.test_turns = [[{"name": "paint", "input": {"ground": "grass", "rects": [{"x": 5, "y": 7, "w": 1, "h": 1}]}}], "Grass."]
	_main._on_command(_player(Net.local_id), "builder", {"op": "ask", "area": AREA, "text": "grass"})
	await _wait_for("proposal")
	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	_main._builder.test_turns = []
	_check(_main._world_map != map_before, "the accept had Main adopt a new map")
	compare.call("after an accept in the zone")
	var shifting := Regen.marked_levels()
	shifting.sort()
	var level_name := shifting[0] if not shifting.is_empty() else ""
	map_before = _main._world_map
	var laid: String = _main._regenerate_now(level_name) if level_name != "" else "no shifting level"
	_check(laid.contains("laid again") and _main._world_map != map_before, "a regeneration's write (%s) had Main adopt a new map" % laid)
	compare.call("after a regeneration's write")
	_main._on_command(_player(Net.local_id), "builder", {"op": "undo"})
	await _wait_for("undone")
