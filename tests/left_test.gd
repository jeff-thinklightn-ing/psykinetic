extends Node
## The level left by a door, held (decision 822 amended (6)), on a client's
## crossings (Main._enter_level and _repaint as _client_zone makes them, with
## Net.mode a client's around each; the host's own zone and entities left
## as they are). On by default: the wilds left for the barrow held as shown
## (its live level and map), its clean read on a worker only once the
## barrow's room is whole; back out with nothing read and no map made; held
## through a second interior and a quick in and out; a felled cell told
## while away lays the clean read and makes the map again; a changed
## terrain, another generation, none sent, or another plane zone let it go
## and read as ever; --no-held-left (held_left false) is today's path; a
## host holds nothing. Prints PASS/FAIL per assertion and quits with exit
## code 1 if any assertion failed, 0 otherwise.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17940)
	Net.companions = false
	Net.map_name = "test_room"
	Net.state_path = ""
	Level.overlay_dir = ports.scratch("left_overlay/")
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	if _main._client3d == null:
		_main._show_3d()
	await _frames(30)
	await _test_held()
	await _test_changed()
	await _test_let_go()
	_test_host_and_sources()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## A client's crossing into [param zone] (the "map" message's [param generation],
## or none when not [param sent]), as _client_zone loads and paints it; ms.
func _cross(zone: String, generation := 0, sent := true) -> float:
	var mode: int = Net.mode
	Net.mode = Net.Mode.CLIENT
	_main.map_generation = generation
	_main._generation_sent = sent
	var started := Time.get_ticks_usec()
	_main._enter_level(zone)
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	_main._repaint(true)
	Net.mode = mode
	return ms


func _reads(zone: String) -> int:
	return int(_main.level_reads.get(zone, 0))


func _maps(zone: String) -> int:
	return int(_main.maps_made.get(zone, 0))


## Frames until the live room is whole (at most [param most]).
func _room_whole(most := 3000) -> int:
	var frames := 0
	while _main._client3d.building_room and frames < most:
		await get_tree().process_frame
		frames += 1
	return frames


## Frames until the held level's clean read is in (at most [param most]).
func _clean_in(most := 600) -> int:
	var frames := 0
	while not _main._left.is_empty() and (_main._left["clean"] as Dictionary).is_empty() and frames < most:
		await get_tree().process_frame
		frames += 1
	return frames


## A told whole "clearing" for the wilds: [param cells] ([[x, y, stage]]).
func _told(cells: Array) -> void:
	var mode: int = Net.mode
	Net.mode = Net.Mode.CLIENT
	_main._on_clearing({"zone": "wilds", "whole": true, "cells": cells, "plots": []})
	Net.mode = mode


func _test_held() -> void:
	print("\n== on by default: the wilds left by the barrow's breach held as shown; back out, nothing read ==")
	_check(_main.held_left and not "--no-held-left" in OS.get_cmdline_user_args(), "on with no flag passed")
	var first := _cross("wilds")
	_check(_reads("wilds") == 1 and _maps("wilds") == 1 and _main._left.is_empty(),
			"a client's first zone (the join): read and its map made, as ever, nothing held (%.0f ms)" % first)
	await _room_whole()
	var wilds_level: Dictionary = _main.level
	var wilds_image: Image = _main.minimap.image
	var fresh := Level.load_level("wilds")
	_cross("barrow")
	_check(str(_main._left.get("zone", "")) == "wilds" and is_same(_main._left["level"], wilds_level)
			and is_same((_main._left["map"] as Dictionary).get("image"), wilds_image) and _reads("barrow") == 1,
			"into the barrow: the wilds held, its live level and live map (no copy), the barrow read")
	_check(_main._left_task == -1 and _main._client3d.building_room and (_main._left["clean"] as Dictionary).is_empty(),
			"no clean read while the barrow's room builds")
	var frames := await _room_whole()
	_check(not _main._client3d.building_room and (_main._left_task != -1 or not (_main._left["clean"] as Dictionary).is_empty()),
			"the barrow's room whole (%d frames): the clean read started on a worker" % frames)
	frames = await _clean_in()
	var clean: Dictionary = _main._left.get("clean", {})
	_check(str(clean.get("name", "")) == "wilds" and not is_same(clean, wilds_level),
			"the clean read in (%d frames), a level of its own" % frames)
	var ms := _cross("wilds")
	_check(_reads("wilds") == 1 and _maps("wilds") == 1 and is_same(_main.level, wilds_level) and is_same(_main.minimap.image, wilds_image)
			and _main._left.is_empty(),
			"back out: nothing read, no map made, the held level and map shown, nothing held (%.1f ms against %.0f)" % [ms, first])
	_check(_main.level_entities.size() == (fresh["entities"] as Array).size() and str(_main.player_starts) == str(fresh["starts"])
			and _main.level_centre == fresh["centre"] and (_main._fire_places["wilds"] as Array).size() == Level.fires_of(fresh).size()
			and _main._level_stamps.has("wilds") and (_main._terrain["floor"] as Array).size() == (fresh["terrain"]["floor"] as Array).size(),
			"set fresh as a read level is: its entities, starts, centre, fires, stamp; its ground the same")
	print("\n== a quick in and out, and a second interior ==")
	await _room_whole()
	_cross("barrow")
	_cross("wilds")
	_check(_reads("wilds") == 1 and is_same(_main.level, wilds_level), "in and straight out (no frame between): held, nothing read")
	await _room_whole()
	_cross("barrow")
	await _room_whole()
	_cross("barrow_deep")
	await _room_whole()
	_check(str(_main._left.get("zone", "")) == "wilds", "deeper (the barrow's deep): the wilds still held")
	_cross("barrow")
	await _room_whole()
	_cross("wilds")
	_check(_reads("wilds") == 1 and _reads("barrow") == 4 and _reads("barrow_deep") == 1 and is_same(_main.level, wilds_level),
			"barrow, deep, barrow, wilds: the wilds not read (interiors read as ever: barrow %d)" % _reads("barrow"))
	await _room_whole()


## A cell next to the wilds' ground that is not ground (a trunk), for a felling.
func _trunk_cell() -> Vector2i:
	var floor_set := {}
	for cell: Vector2i in _main._terrain["floor"]:
		floor_set[cell] = true
	for cell: Vector2i in _main._terrain["floor"]:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next: Vector2i = cell + step
			if not floor_set.has(next) and next.x > 2 and next.y > 2 and next.x < 250 and next.y < 250:
				return next
	return Vector2i(-1, -1)


func _test_changed() -> void:
	print("\n== felled while away: the clean read laid, the map made again; before it is in, read as ever ==")
	var wilds_level: Dictionary = _main.level
	var cell := _trunk_cell()
	_cross("barrow")
	await _room_whole()
	await _clean_in()
	_told([[cell.x, cell.y, "stump"]])
	var reads := _reads("wilds")
	var maps := _maps("wilds")
	_cross("wilds")
	_check(cell.x >= 0 and _reads("wilds") == reads and _maps("wilds") == maps + 1 and not is_same(_main.level, wilds_level)
			and cell in _main._terrain["floor"] and str(_main._terrain["kinds"].get(cell, "")) == "dirt",
			"a stump told at %s: not read, the clean read laid with it, its map made again" % cell)
	await _room_whole()
	_cross("barrow")
	_told([[cell.x, cell.y, "stump"], [cell.x + 1, cell.y, "stump"]])
	_cross("wilds")
	_check(_reads("wilds") == reads + 1, "changed before the clean read is in: read as ever")
	await _room_whole()


func _test_let_go() -> void:
	print("\n== let go: terrain, generation, none sent, another plane zone; --no-held-left is today's path ==")
	var data := {"layout": PackedByteArray([1, 2]), "height": PackedByteArray(), "config": {"a": 1}}
	var other := data.duplicate(true)
	other["config"] = {"a": 2}
	_check(_main.terrain_hash(data) == _main.terrain_hash(data.duplicate(true)) and _main.terrain_hash(data) != _main.terrain_hash(other),
			"a terrain message's hash: the same bytes the same, another config another")
	var cases: Array = [
		["its terrain changed", func() -> void: _main._terrain_hash["wilds"] = "changed", 0, true],
		["another generation", func() -> void: pass, 1, true],
		["no generation sent", func() -> void: pass, 1, false],
	]
	for each: Array in cases:
		_cross("barrow")
		await _room_whole()
		(each[1] as Callable).call()
		var reads := _reads("wilds")
		_cross("wilds", each[2], each[3])
		_check(_reads("wilds") == reads + 1 and _main._left.is_empty(), "%s: let go, read as ever" % each[0])
		await _room_whole()
	_cross("barrow")
	await _room_whole()
	_check(_main._left.is_empty(), "the wilds loaded with no generation sent: not held when left")
	_cross("wilds", 1)
	await _room_whole()
	_cross("barrow")
	await _room_whole()
	var was_held: bool = str(_main._left.get("zone", "")) == "wilds"
	_cross("held", 1)
	_check(was_held and _main._left.is_empty(), "into another plane zone (held): let go")
	await _room_whole()
	_cross("wilds", 1)
	await _room_whole()
	_main.held_left = false
	_cross("barrow", 1)
	await _room_whole()
	var reads := _reads("wilds")
	var maps := _maps("wilds")
	_cross("wilds", 1)
	_check(_main._left.is_empty() and _reads("wilds") == reads + 1 and _maps("wilds") == maps + 1,
			"--no-held-left: nothing held, read and its map made as ever")
	_main.held_left = true
	await _room_whole()


func _test_host_and_sources() -> void:
	print("\n== a host holds nothing; a lost server lets it go ==")
	var mode: int = Net.mode
	Net.mode = Net.Mode.HOST
	_main.drop_left()
	_main._hold_left("barrow")
	Net.mode = mode
	_check(_main._left.is_empty(), "a host (its zones stay loaded): nothing held")
	var source := FileAccess.get_file_as_string("res://main.gd")
	var at := source.find("func _reconnect() -> void:")
	var body := source.substr(at, source.find("\nfunc ", at + 10) - at)
	_check(at >= 0 and body.contains("drop_left()"), "the reconnect lets the held level go")
	var zone_at := source.find("func _client_zone(zone_name: String) -> void:")
	var zone_body := source.substr(zone_at, source.find("\nfunc ", zone_at + 10) - zone_at)
	_check(zone_body.contains("_enter_level(zone_name)") and zone_body.find("_enter_level") < zone_body.find("_repaint(true)"),
			"_client_zone loads by _enter_level, then paints (the path these rows take)")
