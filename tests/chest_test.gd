extends Node
## Chests and slots: the test room's chest holds a bandaging kit; it moves
## chest -> a player's slots -> chest through the slots panel's drop, as a
## drag does; World refuses what a hand could not do; two players get at
## the same chest and see the same contents; a click opens a chest beside
## you, and from afar walks you there first; and a restart keeps the chest's
## contents and every player's slots.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const BO := 2
const BO_ID := "b0b0b0b0-0000-4000-8000-0000000000c1"
const KIT := "bandaging_kit"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = 17793
	Net.companions = false
	Net.state_path = OS.get_user_data_dir().path_join("chest_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()

	_test_the_chest()
	await _test_there_and_back()
	_test_refused()
	_test_two_players()
	await _test_restart()
	await _test_click_from_afar()
	await _test_new_in_the_level()

	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_the_chest() -> void:
	print("\n== the test room's chest, and a player's slots ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	_check(chest != null and chest.tile == Vector2i(10, 3), "a chest at (10, 3)")
	_check(chest != null and Array(chest.slots) == [KIT, "", "", ""], "with a bandaging kit in it (%s)" % [Array(chest.slots) if chest else []])
	_check(host != null and Array(host.slots) == ["", "", "", ""], "the player has 4 empty slots (%s)" % [Array(host.slots) if host else []])
	_check(not chest.pushable and not chest.is_breakable() and not chest.is_creature(), "a chest is not pushed, broken or fought")
	var level := Level.load_level("test_room")
	_check(level["warnings"].is_empty(), "the level loads cleanly (%s)" % [level["warnings"]])


func _test_there_and_back() -> void:
	print("\n== the kit: chest -> slots -> chest, by drag and drop ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	var panel: SlotsPanel = _main.slots_panel
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.visible and panel.chest == null, "the slots panel shows the player's slots, no chest")
	_main.toggle_slots()
	await get_tree().process_frame
	_check(not panel.visible, "I hides it")
	_main.toggle_slots()
	await get_tree().process_frame
	_check(panel.visible, "and shows it again")
	_check(World.can_melee(host.tile, chest.tile), "the host, at %s, is beside it" % host.tile)
	_main._click_chest(host, chest)
	await get_tree().process_frame
	_check(panel.chest == chest and panel.shown_in(false, 0) == "Bandages", "a click opens it: the kit in its first slot")
	panel.drop(chest, 0, host, 0)
	_check(Array(host.slots) == [KIT, "", "", ""] and Array(chest.slots) == ["", "", "", ""],
			"dragged to the player's first slot: theirs now, the chest empty (%s, %s)" % [Array(host.slots), Array(chest.slots)])
	await get_tree().process_frame
	_check(panel.shown_in(true, 0) == "Bandages" and panel.shown_in(false, 0) == "", "the panel shows it moved")
	panel.drop(host, 0, host, 3)
	_check(Array(host.slots) == ["", "", "", KIT], "moved along the player's own slots (%s)" % [Array(host.slots)])
	panel.drop(host, 3, chest, 2)
	_check(Array(host.slots) == ["", "", "", ""] and Array(chest.slots) == ["", "", KIT, ""],
			"and back into the chest, its third slot (%s, %s)" % [Array(host.slots), Array(chest.slots)])
	World.try_transfer(host, chest, 2, chest, 0)
	_check(Array(chest.slots) == [KIT, "", "", ""], "and to its first again (%s)" % [Array(chest.slots)])


func _test_refused() -> void:
	print("\n== what a hand could not do, World refuses ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	_check(not World.try_transfer(host, chest, 1, host, 0), "from an empty slot: nothing")
	_check(not World.try_transfer(host, chest, 0, host, 4) and not World.try_transfer(host, chest, -1, host, 0),
			"to or from a slot that is not there: nothing")
	var home := host.tile
	World._relocate(host, Vector2i(6, 1))
	_check(not World.try_transfer(host, chest, 0, host, 0), "from a chest not beside the player: nothing")
	World._relocate(host, home)
	var crate: GridEntity = null
	for entity in World.get_entities():
		if entity.name == "Crate1":
			crate = entity
	_check(not World.reaches(host, crate), "a crate has no slots to reach")
	_check(Array(chest.slots) == [KIT, "", "", ""] and Array(host.slots) == ["", "", "", ""], "nothing moved (%s, %s)" % [Array(chest.slots), Array(host.slots)])


func _test_two_players() -> void:
	print("\n== two players at one chest see the same contents ==")
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	var host := _player(Net.local_id)
	var chest := _chest()
	World._relocate(bo, Vector2i(9, 3))
	_check(World.reaches(bo, chest) and World.reaches(host, chest), "both are beside it")
	_check(not World.reaches(bo, host), "but Bo cannot get at the host's slots")
	# Bo's drag, as it reaches the server: a command from Bo.
	World.command(bo, "transfer", {"from": str(chest.get_path()), "from_slot": 0, "to": str(bo.get_path()), "to_slot": 1})
	_check(Array(bo.slots) == ["", KIT, "", ""] and Array(chest.slots) == ["", "", "", ""], "Bo takes the kit (%s)" % [Array(bo.slots)])
	_main._process(0.0)
	_check(_main.slots_panel.chest == chest and _main.slots_panel.shown_in(false, 0) == "", "the host's open chest shows it gone")
	World.command(host, "transfer", {"from": str(bo.get_path()), "from_slot": 1, "to": str(host.get_path()), "to_slot": 0})
	_check(Array(bo.slots) == ["", KIT, "", ""], "the host cannot take it from Bo's slots")
	World.command(bo, "transfer", {"from": str(bo.get_path()), "from_slot": 1, "to": str(chest.get_path()), "to_slot": 3})
	_check(Array(chest.slots) == ["", "", "", KIT], "Bo puts it back, in the last slot (%s)" % [Array(chest.slots)])
	World.command(host, "transfer", {"from": str(chest.get_path()), "from_slot": 3, "to": str(host.get_path()), "to_slot": 2})
	_check(Array(host.slots) == ["", "", KIT, ""] and _main._records[Net.player_id].slots[2] == KIT,
			"the host takes it, and their record has it at once (%s)" % [Array(host.slots)])
	# Bo walks off: the server keeps their (empty) slots in the record.
	_main._leave(BO, bo, BO_ID)


func _test_restart() -> void:
	print("\n== a restart keeps the chest's contents and the players' slots ==")
	var chest := _chest()
	World.try_transfer(_player(Net.local_id), _player(Net.local_id), 2, _player(Net.local_id), 1)
	_main._admit(BO, BO_ID, "Bo")
	World._relocate(_player(BO), Vector2i(9, 3))
	World.try_transfer(_player(BO), chest, 0, _player(BO), 0)  # Nothing there: refused.
	World.try_transfer(_player(Net.local_id), _player(Net.local_id), 1, chest, 0)
	World.try_transfer(_player(BO), chest, 0, _player(BO), 3)
	_check(Array(_player(BO).slots) == ["", "", "", KIT] and Array(chest.slots) == ["", "", "", ""], "Bo holds the kit, in slot 4")
	_main._save_state()
	var snapshot := Snapshot.load(Net.state_path)
	var saved: Array = snapshot["zones"]["test_room"]["entities"]
	var entry: Dictionary = saved.filter(func(each: Dictionary) -> bool: return each["spec"]["name"] == "Chest1")[0]
	_check(entry["slots"] == ["", "", "", ""], "the snapshot has the chest empty (%s)" % [entry["slots"]])
	var kept := {}
	for record: PlayerRecord in snapshot["players"]:
		kept[record.name] = Array(record.slots)
	_check(kept.get("Bo") == ["", "", "", KIT] and kept.get(Net.player_name) == ["", "", "", ""],
			"and each player's slots (%s)" % [kept])
	remove_child(_main)
	_main.free()
	World.clear_zones()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	chest = _chest()
	_check(chest != null and Array(chest.slots) == ["", "", "", ""], "after the restart the chest is still empty (%s)" % [Array(chest.slots) if chest else []])
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	_check(bo != null and Array(bo.slots) == ["", "", "", KIT], "Bo comes back with the kit (%s)" % [Array(bo.slots) if bo else []])
	_check(Array(_player(Net.local_id).slots) == ["", "", "", ""], "the host with nothing")
	World._relocate(bo, Vector2i(9, 3))
	_check(World.try_transfer(bo, bo, 3, chest, 0) and Array(chest.slots) == [KIT, "", "", ""], "Bo puts it back in the chest")
	_main._save_state()
	remove_child(_main)
	_main.free()
	World.clear_zones()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	chest = _chest()
	_check(chest != null and Array(chest.slots) == [KIT, "", "", ""], "and after another restart it is there (%s)" % [Array(chest.slots) if chest else []])
	_check(_main._records[BO_ID].slots == PackedStringArray(["", "", "", ""]), "and Bo's record is empty")
	# Dying keeps them too.
	World.try_transfer(_player(Net.local_id), chest, 0, _player(Net.local_id), 0)
	World.damage(_player(Net.local_id), 999)
	for i in _main.RESPAWN_TICKS + 1:
		World.step()
	var host := _player(Net.local_id)
	_check(host != null and Array(host.slots) == [KIT, "", "", ""], "a player who dies comes back with their slots (%s)" % [Array(host.slots) if host else []])


func _test_click_from_afar() -> void:
	print("\n== a chest clicked from afar: walk there, then it opens; walk off, it closes ==")
	var host := _player(Net.local_id)
	var chest := _chest()
	var panel: SlotsPanel = _main.slots_panel
	_main.close_chest()
	World._relocate(host, Vector2i(6, 1))
	_main._click_chest(host, chest)
	await get_tree().process_frame
	_check(panel.chest == null and host.has_move_order, "not beside it: not open, walking (to %s)" % host.move_order)
	for i in 40:
		World.step()
		if World.can_melee(host.tile, chest.tile):
			break
	await get_tree().process_frame
	_check(World.can_melee(host.tile, chest.tile) and panel.chest == chest, "beside it at %s: open" % host.tile)
	World._relocate(host, Vector2i(6, 1))
	await get_tree().process_frame
	_check(panel.chest == null, "away from it: closed")


func _test_new_in_the_level() -> void:
	print("\n== a snapshot from before the chest: it is there at once, kit and all ==")
	# The server stops (and saves); its file is then as an older build left it.
	remove_child(_main)
	_main.free()
	World.clear_zones()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Net.state_path))
	var room: Dictionary = data["zones"]["test_room"]
	room["entities"] = (room["entities"] as Array).filter(func(entry: Dictionary) -> bool: return entry["name"] != "Chest1")
	for record: Dictionary in data["players"]:
		record.erase("slots")
	var file := FileAccess.open(Net.state_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var chest := _chest()
	_check(chest != null and chest.tile == Vector2i(10, 3) and Array(chest.slots) == [KIT, "", "", ""],
			"the chest is at (10, 3) with the kit (%s)" % [Array(chest.slots) if chest else "none"])
	_check(not _main._dead_since.has(chest.spawn_spec.get("spawn", -1)) if chest else false, "not waiting to respawn")
	_check(Array(_player(Net.local_id).slots) == ["", "", "", ""], "a record from before slots has four empty ones")


func _chest() -> Chest:
	for entity in World.get_entities():
		if entity is Chest:
			return entity
	return null


func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) and player.spawned else null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
