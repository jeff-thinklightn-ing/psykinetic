extends Node
## Items: the catalog reads every definition from levels/items.json and
## refuses what makes no sense; an ItemBook keeps each instance's carriers
## (time held counted as they let go) and at most five events (where it
## came from kept); in the game a level chest's kit gets its instance when
## first taken, "found" by its first carrier, "given" from one carrier to
## another (a companion moves things as a player does), taken out of and
## put back into slots (the stockpile's way); a restart keeps every
## instance and its history; a save from before instances gets new ones
## ("migrated"); a rebuilt room ends what its chests held as lost; nothing
## leaks from the book.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const BO := 2
const BO_ID := "b0b0b0b0-0000-4000-8000-0000000000c1"
const KIT := "bandaging_kit"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17799)
	Net.companions = false
	Net.state_path = OS.get_user_data_dir().path_join("items_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)

	_test_catalog()
	_test_book()

	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()
	_test_found_and_held()
	_test_given()
	_test_take_and_put()
	await _test_restart()
	await _test_migration()
	_test_rebuild()

	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_catalog() -> void:
	print("\n== the catalog ==")
	_check(not Items.ids().is_empty(), "levels/items.json has %d items" % Items.ids().size())
	var bad := []
	for id: String in Items.ids():
		var item := Items.def(id)
		if item["name"].is_empty() or item["weight"] <= 0.0 or not item["art"].begins_with("item.") \
				or item["hands"] not in [0, 1, 2] or item["kind"] not in ["held", "cell"]:
			bad.append(id)
		if "resource" in item["tags"] and Items.yield_of(id).is_empty():
			bad.append(id + " (a resource yielding nothing)")
	_check(bad.is_empty(), "each has a name, a weight, an item.<id> art slot, hands and a kind (%s)" % [bad])
	_check(Items.name_of(KIT) == "bandaging kit" and Items.short_of(KIT) == "Bandages" and Items.def(KIT)["use"] == "bandage",
			"the bandaging kit is as it was, used to bandage")
	_check(Items.yield_of("ore_sack") == {"ore": 5} and Items.yield_of(KIT).is_empty(), "a sack of ore banks as 5 ore; a kit as nothing")
	_check(Items.tidy([KIT, "no_such_thing"], 3) == PackedStringArray([KIT, "", ""]), "an unknown id is dropped from slots")
	var generated: Variant = JSON.parse_string(FileAccess.get_file_as_string(Items.ART_SLOTS)) if FileAccess.file_exists(Items.ART_SLOTS) else null
	_check(generated is Dictionary and generated == JSON.parse_string(JSON.stringify(Items.art_slots())),
			"%s is current with the catalog (else: tools/items_art_slots.gd)" % Items.ART_SLOTS)
	_check(Items.art_slots()["slots"]["item.wood_bundle"]["sockets"].has("grip_2") \
			and not Items.art_slots()["slots"]["item.bandaging_kit"]["sockets"].has("grip_2"), "two hands, two grips")
	var read := Items.read('{"items": [{"id": "a", "name": "A", "weight": 2}, {"name": "no id"}, {"id": "a", "name": "again"}]}')
	_check(read.keys() == ["a"] and read["a"]["name"] == "A" and read["a"]["hands"] == 1,
			"a catalog with an entry with no id and an id twice: the first a, filled in (%s)" % [read.keys()])


func _test_book() -> void:
	print("\n== a book's history ==")
	var now := [100]
	var book := ItemBook.new(func() -> int: return now[0])
	var uid := book.mint("sword", "stocked", "Chest1", "castle", Vector2i(3, 4))
	_check(book.id_of(uid) == "sword" and book.history(uid)["events"][0]["kind"] == "stocked", "made, stocked in a chest")
	book.place(uid, "player:a", "player:a", "Ann")
	now[0] = 160
	_check(book.held_by(uid, "player:a") == 60, "Ann has held it 60 steps so far (%d)" % book.held_by(uid, "player:a"))
	book.place(uid, "castle/Chest1")
	now[0] = 500
	_check(book.held_by(uid, "player:a") == 60, "in the chest, her time stops")
	book.place(uid, "player:a", "player:a", "Ann")
	now[0] = 510
	_check(book.held_by(uid, "player:a") == 70 and book.history(uid)["carriers"].size() == 1, "back with her, one row, 70")
	for i in 9:
		book.place(uid, "player:%d" % i, "player:%d" % i, "P%d" % i)
		now[0] += 10 + i
	var carriers: Array = book.history(uid)["carriers"]
	_check(carriers.size() == ItemBook.MAX_CARRIERS and carriers.any(func(row: Dictionary) -> bool: return row["who"] == "player:8"),
			"ten carriers: the %d who held it longest are kept, with who has it now" % ItemBook.MAX_CARRIERS)
	_check(not carriers.any(func(row: Dictionary) -> bool: return row["who"] == "player:0"), "the one who held it least is gone")
	for i in 6:
		book.note(uid, "felled", "goblin %d" % i, "castle", Vector2i(i, 0))
	var events: Array = book.history(uid)["events"]
	_check(events.size() == ItemBook.MAX_EVENTS and events[0]["kind"] == "stocked" and events[-1]["what"] == "goblin 5" \
			and events[1]["what"] == "goblin 2", "six more events: five kept, where it came from and the newest four")
	var copy := ItemBook.from_dict(JSON.parse_string(JSON.stringify(book.to_dict())), func() -> int: return now[0])
	_check(copy.history(uid) == book.history(uid), "saved and read back as JSON, the same")
	var other := copy.mint("ore_sack", "built")
	_check(other > uid, "and new uids go on from the saved ones (%d)" % other)
	var last := copy.end(other, "banked", "stockpile")
	_check(not copy.has(other) and last["events"][-1]["kind"] == "banked", "banked: gone from the book, its last event banked")
	_check(copy.orphans([uid]).is_empty() and copy.orphans([]) == [uid], "orphans: none when every holder is counted")


func _test_found_and_held() -> void:
	print("\n== a chest's kit: found, and held ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	_check(chest.slots[0] == KIT and (chest.slot_items.is_empty() or chest.slot_items[0] == 0),
			"the chest's kit has no instance until it is needed")
	_beside(host, chest)
	_check(World.try_transfer(host, chest, 0, host, 0), "the host takes it")
	var uid := host.slot_items[0]
	var history := World.items.history(uid)
	_check(uid != 0 and World.items.id_of(uid) == KIT, "it is an instance now (%d)" % uid)
	_check(history["events"].size() == 2 and history["events"][0]["kind"] == "stocked" and history["events"][1]["kind"] == "found",
			"stocked in the chest, found by the host (%s)" % [history["events"]])
	_check(history["carriers"][0]["who"] == "player:" + Net.player_id and history["at"] == "player:" + Net.player_id,
			"the host carries it, and it is with them")
	World.steps += 100
	_check(World.items.held_by(uid, "player:" + Net.player_id) == 100, "100 steps on, they have held it 100")
	World.try_transfer(host, host, 0, chest, 2)
	World.steps += 40
	_check(World.items.held_by(uid, "player:" + Net.player_id) == 100 and World.items.at_of(uid) == "%s/%s" % [chest.zone, chest.name],
			"back in the chest: it is there, and their time stops")
	World.try_transfer(host, chest, 2, host, 0)
	_check(host.slot_items[0] == uid and World.items.history(uid)["events"].size() == 2, "taken again: the same thing, not found again")


func _test_given() -> void:
	print("\n== given from one carrier to another; a companion does as a player does ==")
	Net.companions = true
	var host := _player(Net.local_id)
	var record: PlayerRecord = _main._records[Net.player_id]
	_main._join_companion(record, host)
	var pet: Companion = _main._companions.get(Net.player_id)
	var uid := host.slot_items[0]
	_check(World.try_transfer(host, host, 0, pet, 1), "the host gives the kit to %s" % pet.name)
	var events: Array = World.items.history(uid)["events"]
	_check(events[-1]["kind"] == "given" and pet.name in str(events[-1]["what"]), "given, to her (%s)" % [events[-1]])
	_check(Array(record.companion.get("items", [])) == [0, uid, 0, 0], "her player's record has its instance")
	World.steps += 20
	_check(World.try_transfer(pet, pet, 1, host, 3), "she hands it back herself")
	_check(World.items.held_by(uid, World.holder_key(pet)) == 20 and host.slot_items[3] == uid, "she held it 20 steps; the host has it")
	_print_history(uid)
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	_check(not World.try_transfer(pet, pet, 0, bo, 0) and not World.reaches(pet, bo), "she cannot reach into Bo's pack")
	_main._leave(BO, bo, BO_ID)


func _test_take_and_put() -> void:
	print("\n== taken out of slots and put back (the stockpile's way) ==")
	var host := _player(Net.local_id)
	var uid := host.slot_items[3]
	_check(World.take_item(host, host, 3) == uid and host.slots[3] == "" and host.slot_items[3] == 0, "taken out: the slot is empty")
	_check(World.items.has(uid) and World.items.at_of(uid) == "", "and it is still in the book, nowhere yet")
	_check(not World.put_item(host, host, 3, 999999), "an unknown thing cannot be put anywhere")
	_check(World.put_item(host, host, 1, uid) and host.slots[1] == KIT and host.slot_items[1] == uid, "put back, in slot 2")
	_check(World.take_item(host, host, 0) == 0, "nothing to take from an empty slot")


func _test_restart() -> void:
	print("\n== a restart keeps every instance and its history ==")
	var host := _player(Net.local_id)
	var uid := host.slot_items[1]
	var history := World.items.history(uid)
	var count := World.items.size()
	_main._save_state()
	await _restart()
	host = _player(Net.local_id)
	_check(host.slots[1] == KIT and host.slot_items[1] == uid, "the host has the same kit (%s)" % [host.slot_items])
	var after := World.items.history(uid)
	_check(after["events"] == history["events"] and after["carriers"].size() == history["carriers"].size(),
			"with its history (%s)" % [after["events"]])
	_check(World.items.size() == count, "the book as big as it was (%d)" % World.items.size())
	_check(World.items.orphans(_all_uids()).is_empty(), "and nothing in it that nobody holds (%s)" % [World.items.orphans(_all_uids())])


func _test_migration() -> void:
	print("\n== a save from before instances ==")
	await _restart(func(data: Dictionary) -> void:
		data.erase("items")
		for zone: Dictionary in data["zones"].values():
			for entry: Dictionary in zone["entities"]:
				entry.erase("items")
		for record: Dictionary in data["players"]:
			record.erase("items")
			if record.get("companion") is Dictionary:
				record["companion"].erase("items"))
	var host := _player(Net.local_id)
	var uid := host.slot_items[1]
	_check(host.slots[1] == KIT and uid != 0, "the host's kit is there, an instance again (%d)" % uid)
	_check(World.items.history(uid)["events"][0]["kind"] == "migrated", "come from the old save (%s)" % [World.items.history(uid)])
	_check(World.items.orphans(_all_uids()).is_empty(), "nothing leaked")


func _test_rebuild() -> void:
	print("\n== a rebuilt room ends what its chests held ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	_beside(host, chest)
	World.try_transfer(host, host, 1, chest, 0)
	var uid := chest.slot_items[0]
	_main._start_level(false, true)
	chest = _chest()
	_check(not World.items.has(uid), "the kit left in the chest is gone from the book")
	_check(chest.slots[0] == KIT and World.slot_uid(chest, 0) != uid, "the rebuilt chest has a new one from the level")
	_check(World.items.orphans(_all_uids()).is_empty(), "nothing leaked (%s)" % [World.items.orphans(_all_uids())])


## A restart; [param edit] (given the snapshot's data) changes the saved
## file between the old server's last save and the new one's load.
func _restart(edit := Callable()) -> void:
	remove_child(_main)
	_main.free()
	World.clear_zones()
	World.items = ItemBook.new()  # Only what the snapshot holds comes back.
	if edit.is_valid():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Net.state_path))
		edit.call(data)
		var file := FileAccess.open(Net.state_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame


func _print_history(uid: int) -> void:
	var history := World.items.history(uid)
	print("    #%d %s, at %s" % [uid, Items.name_of(history["id"]), history["at"]])
	for row: Dictionary in history["carriers"]:
		print("      carried by %s for %d steps%s" % [row["name"], row["held"], " (now)" if row["since"] >= 0 else ""])
	for event: Dictionary in history["events"]:
		print("      step %d: %s %s, %s %s" % [event["step"], event["kind"], event["what"], event["zone"], event["tile"]])


## Every uid anyone holds: entities' slots and the records' (companions
## kept there too).
func _all_uids() -> Array:
	var uids := []
	for entity in World.get_entities():
		uids.append_array(Array(World.slot_uids(entity)))
	for record: PlayerRecord in _main._records.values():
		uids.append_array(Array(record.slot_items))
		uids.append_array(record.companion.get("items", []))
	return uids.filter(func(uid: Variant) -> bool: return int(uid) != 0)


func _beside(entity: GridEntity, chest: Chest) -> void:
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_free(chest.tile + offset) and World.can_melee(chest.tile + offset, chest.tile):
			World._relocate(entity, chest.tile + offset)
			return


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
