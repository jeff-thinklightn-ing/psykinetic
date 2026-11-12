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
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


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
