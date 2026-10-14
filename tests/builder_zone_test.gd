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
const OVERLAY := "user://builder_zone_test_levels/"
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
	_test_terrain_message()
	await _test_refused()
	await _test_undo()
	await _test_new_area()
	_test_console()

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

	_main._on_command(_player(Net.local_id), "builder", {"op": "accept"})
	await _wait_for("accepted")
	_check(Level.overlaid("test_room"), "accepted: the level is saved to the overlay (%s)" % ProjectSettings.globalize_path(OVERLAY))
	_check(FileAccess.file_exists(OVERLAY + "test_room/level.json"), "level.json too: the overlay is a whole level")
	var level := Level.load_level("test_room")
	var chests: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec["tile"] == chest)
	_check(chests.size() == 1 and chests[0]["props"]["slots"][0] == "bandaging_kit", "the game reads the chest from it, a kit inside")
	var was := World.enter_named("test_room")
	var live := World.get_entities().filter(func(entity: GridEntity) -> bool: return entity is Chest and entity.tile == chest)
	World.enter(was)
	_check(live.size() == 1, "the zone was rebuilt: the chest is there")
	var after := _player(Net.local_id)
	_check(after != null and after.tile == host_tile, "and the host is where they were (%s)" % [after.tile if after else "-"])


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
