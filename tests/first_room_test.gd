extends Node
## A view's first room (782 amended (2); sound's finding, 2026-11-12): a host
## on the wilds makes its 3D view (Main._show_3d) and, with no rebuild, the
## room has what every rebuilt one gets from Main._on_room_built: the
## level's fire places (the square's fire), its night places (the posts'
## braziers, the store's lantern) and the folds as Main reads them. Prints
## PASS/FAIL per assertion and quits with exit code 1 if any assertion
## failed, 0 otherwise.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17972)
	Net.companions = false
	Net.map_name = "wilds"
	Net.state_path = ""
	Level.overlay_dir = ports.scratch("first_room_overlay/")
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	if _main._client3d == null:
		_main._show_3d()  # Headless: as a windowed host makes it at boot.
	for i in 30:
		await get_tree().process_frame
	_test_first_room()
	_test_settled_at_boot()
	_test_shell_roof()
	_test_out_of_shell()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


## Economy's (the coordinator's approval, 11-14): a fresh host on the wilds has
## Snagfin and his like (residents.json's settled) in the town at boot, before
## its first turn at step 300; tours and stills found him only after it.
func _test_settled_at_boot() -> void:
	print("\n== a fresh host's settled are in the town at boot, before its first turn ==")
	var table := Townsfolk.settled()
	_check(not table.is_empty(), "residents.json names the settled (%s)" % [table.keys()])
	for id: String in table:
		var town := str(table[id].get("town", ""))
		_check(World.steps < World.WORLD_TICK_STEPS and not World.production.worker(id).is_empty() and id in World.towns.residents(town),
			"%s a resident of %s at step %d" % [table[id].get("name", id), town, World.steps])


func _test_first_room() -> void:
	print("\n== a view's first room, before any rebuild (782 amended (2)) ==")
	var view: Client3D = _main._client3d
	_check(view != null and view._build_generation == 0, "the view's room is setup's, not a rebuild's (generation %s)" % [view._build_generation if view != null else -1])
	var places: Dictionary = _main.level.get("places", {})
	var fires: Array[Vector2i] = _main.fire_places(places)
	_check(not fires.is_empty() and view.fire_places == fires, "the fire places are the level's (%s, view %s)" % [fires, view.fire_places])
	var night: Array = _main.night_places(places)
	_check(not (night[0] as Array).is_empty() and view._night_posts == night[0], "the night posts are the level's (%d, view %d)" % [(night[0] as Array).size(), view._night_posts.size()])
	_check(not (night[1] as Array).is_empty() and view._night_stores == night[1], "the night stores are the level's (%d, view %d)" % [(night[1] as Array).size(), view._night_stores.size()])
	_check(view._folds == _main.fold_view(), "the folds are Main's (%d, view %d)" % [_main.fold_view().size(), view._folds.size()])


## 811 amended (8) (the coordinator's bar on Jeff's report, 11-15): the Mughouse's footprint is solid but its links and
## door cells, so one on its door cell is in its doorway a step from the crossing: its roof never lifts for him, where a
## walk-in building's does.
func _test_shell_roof() -> void:
	print("
== the Mughouse's roof stays on over its doorway; a walk-in building's lifts ==")
	var view: Client3D = _main._client3d
	var shell: Dictionary = Main.shell_holding(_main.level, Vector2i(179, 208))
	_check(not shell.is_empty() and str(shell.get("code", "")) == "I1", "(179, 208) is the Mughouse's doorway, in its footprint")
	var index: int = view._building_at.get(Vector2i(179, 208), -1)
	_check(index >= 0 and view._shell_at.has(Vector2i(179, 208)) and view._shell_at.size() == Level.building_cells(shell).size(),
		"the view knows the shell's cells (%d)" % view._shell_at.size())
	var other := -1
	var other_cell := Vector2i(-1, -1)
	for cell: Vector2i in view._building_at:
		var at: int = view._building_at[cell]
		if not view._shell_at.has(cell) and view._buildings[at]["roof"] != null:
			other = at
			other_cell = cell
			break
	var points: Array[Vector3] = [view.to_global(Vector3(179, 0, 208))]
	view._update_roofs(points)
	_check(index >= 0 and not view._roofs_off.has(index) and not view._buildings[index]["off"], "on the doorway (179, 208) the Mughouse's roof stays on")
	var walls := view._inside_walls(points, Vector3(0, 0, 1))
	_check(index >= 0 and not walls.keys().any(func(node: Node3D) -> bool: return view._buildings[index]["node"].is_ancestor_of(node)),
		"and none of its walls fade (%d faded)" % walls.size())
	points = [view.to_global(Vector3(other_cell.x, 0, other_cell.y))]
	view._update_roofs(points)
	_check(other >= 0 and view._roofs_off.has(other), "a walk-in building's roof still lifts for one inside it, at %s" % [other_cell])
	view._roofs_off.clear()


## 811 amended (8) (the coordinator's bar 4): anything saved on the Mughouse's footprint, a body or a thing at the server's
## start, a player record at a join, is set outside its door, on floor, off its door and link cells and its footprint.
func _test_out_of_shell() -> void:
	print("
== saved in the Mughouse's shell: set outside its door at the start and at a join ==")
	var shell: Dictionary = Main.shell_holding(_main.level, Vector2i(175, 208))
	var foot := Level.building_cells(shell)
	var doorway: Array[Vector2i] = _main.door_cells(shell)
	var links: Array = _main.level["terrain"]["links_at"]
	var outside := func(cell: Vector2i) -> bool:
		return World.is_walkable(cell) and cell not in foot and cell not in doorway and cell not in links
	_check(Main.shell_holding(_main.level, Vector2i(181, 208)).is_empty() and Main.shell_holding(_main.level, Vector2i(169, 208)).is_empty(),
		"(the shell holds its footprint alone)")
	# A thing saved inside: a cart's entry, its tile in the shell, as a save gives it back.
	var model: GridEntity = null
	for entity: GridEntity in World.zone.entities:
		if str(entity.get_script().resource_path) == Level.CARGO:
			model = entity
			break
	_check(model != null, "(the wilds has a cart to copy)")
	if model != null:
		var entry := Snapshot.parse_entry(Snapshot.entry(model))
		entry["spec"]["tile"] = Vector2i(175, 208)
		entry["spec"]["name"] = "ShellProbeCart"
		entry["spec"].erase("spawn_key")
		entry["spec"].erase("spawn")
		_main._spawn_saved({"entities": [entry]})
		var probe: GridEntity = null
		for entity: GridEntity in World.zone.entities:
			if entity.name == "ShellProbeCart":
				probe = entity
		_check(probe != null and outside.call(probe.tile) and World.distance(probe.tile, Vector2i(181, 208)) <= 2,
			"a cart saved at (175, 208) comes back outside the door, at %s" % [probe.tile if probe else "-"])
		if probe != null:
			World.despawn(probe)
	# A player record inside: he comes back outside.
	var peer := 2
	var id := "b0b0b0b0-0000-4000-8000-0000000000b8"
	_main._admit(peer, id, "Bo")
	var bo: Player = _main._players.get(peer)
	_check(bo != null, "(Bo joins)")
	if bo == null:
		return
	_main._leave(peer, bo, id)
	var record: PlayerRecord = _main._records[id]
	record.tile = Vector2i(175, 208)
	_main._admit(peer, id, "Bo")
	bo = _main._players.get(peer)
	_check(bo != null and outside.call(bo.tile) and World.distance(bo.tile, Vector2i(181, 208)) <= 2,
		"a player whose record stands at (175, 208) joins outside the door, at %s" % [bo.tile if bo else "-"])
	record.tile = Vector2i(185, 200)
	_check(Main.shell_holding(_main.level, record.tile).is_empty() and _main._out_of_shell(record.tile, "player") == record.tile,
		"one saved elsewhere is left where he was")
