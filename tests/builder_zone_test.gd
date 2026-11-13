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
	Net.message_received.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "builder":
			_heard.append(data))
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()

	await _test_ask_and_accept()
	_test_spot_taken_up()
	_test_terrain_message()
	await _test_refused()
	await _test_undo()
	await _test_flooded()
	await _test_spots_only()
	await _test_stale_proposal()
	await _test_new_area()
	_test_console()
	await _test_first_spots_save()

	_remove_tree(ProjectSettings.globalize_path(OVERLAY))
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
	_check(Level.overlaid("test_room") and _main._builder.docs["test_room"].report.begins_with("saved") and not "floor" in _main._builder.docs["test_room"].report,
		"accepted: the overlay is written whole, saved without a parse (%s)" % _main._builder.docs["test_room"].report)
	# The images as the level reads them: MapDoc writes the layout through LevelMap.to_image (RGBA8, its own
	# corner and fill pixels, as every accept has), the source is the repo's PNG (RGB8), so the bytes differ
	# where nothing reads them; what each cell, edge, height and relief value reads as is what must agree.
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
	print("    layout pixels: source format %d, saved format %d, %d pixels differ as RGBA (corners and fills)" % [
		(before["layout"] as Image).get_format(), (after["layout"] as Image).get_format(), differ])
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
