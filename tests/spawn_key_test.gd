extends Node
## Level entities by their marker cell (decision 433): a snapshot keeps each
## one's key beside its slot, so a level that gains an entity before others
## (moving their slots) still brings every saved one back as itself, its
## dead slot's timer and its far record too, and the new one spawns; one
## whose marker the level lost comes back as saved, holding no slot; a
## snapshot from before keys loads by its slots as it did; one the level
## says became something else (decision 471) is handed over, not spawned.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const LEVEL := "spawn_key_test"
const WIDTH := 16
const HEIGHT := 5
## The markers of the level as it was saved; GAINED is the one it gains,
## listed in level.json (so first in Level's order: every slot moves).
const MARKERS := {Vector2i(1, 2): "start", Vector2i(4, 2): "crate", Vector2i(6, 2): "chest",
	Vector2i(8, 2): "monster_imp", Vector2i(10, 2): "monster_imp", Vector2i(12, 2): "crate"}
const GAINED := Vector2i(3, 0)

var _failures := 0
var _main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	_register(false)
	Net.port = preload("res://tests/test_ports.gd").of(17851)
	Net.companions = false
	Net.state_path = ""
	Net.map_name = LEVEL
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	var path: String = preload("res://tests/test_ports.gd").scratch_path("spawn_key_world.json")
	var saved := _saved_world(path)
	_test_a_gained_entity_moves_nobody(path, saved)
	_test_a_lost_marker(path, saved)
	_test_an_old_snapshot_by_slots(path, saved)
	_test_stock_tops_up_once(path, saved)
	_test_became(path, saved)
	DirAccess.remove_absolute(path)
	Net.state_path = ""
	Level.unregister(LEVEL)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The level, as saved or with GAINED (a chest, props {"temple": true}),
## or without the marker at [param lost].
func _register(gained: bool, lost := Vector2i(-1, -1), stock: Array = [], became := {}) -> void:
	Level.unregister(LEVEL)
	var markers := MARKERS.duplicate()
	markers.erase(lost)
	for key: String in became:
		markers.erase(Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1))))
	var entries: Array = []
	if not stock.is_empty():
		entries.append({"at": [6, 2], "props": {"slots": stock, "stock": stock}})
	if gained:
		markers[GAINED] = "chest"
		entries.append({"at": [GAINED.x, GAINED.y], "props": {"temple": true}})
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(WIDTH * 2 + 1, HEIGHT * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("void"))
	var ground: Color = colour.call(Level.GROUNDS[0])
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			image.set_pixel(x * 2, y * 2, colour.call(markers[cell]) if markers.has(cell) else ground)
			if x + 1 < WIDTH:
				image.set_pixel(x * 2 + 1, y * 2, ground)
			if y + 1 < HEIGHT:
				image.set_pixel(x * 2, y * 2 + 1, ground)
	Level.register(LEVEL, image, null, {"name": "Spawn keys", "entities": entries, "became": became})


## The world saved, then made to tell its entities apart: each level entity
## moved to a cell of its own on row 4 (x = its marker's x), Imp1 dead (a
## respawn timer) and Imp2 kept as a far record. The snapshot as written.
func _saved_world(path: String) -> Dictionary:
	print("\n== a save keeps each level entity's key beside its slot ==")
	Net.state_path = path
	_main._save_state()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var zone: Dictionary = data["zones"][LEVEL]
	var keys := (zone["entities"] as Array).map(func(entry: Dictionary) -> String: return str(entry.get("spawn_key", "")))
	_check(keys.size() == MARKERS.size() - 1 and "4,2" in keys and "10,2" in keys and not "" in keys,
			"every level entity saved with its marker cell as key (%s)" % [keys])
	var kept: Array = []
	for entry: Dictionary in zone["entities"]:
		var home: String = entry["spawn_key"]
		var x := int(home.get_slice(",", 0))
		entry["tile"] = [x, 4]
		if home == "8,2":
			zone["respawns"] = [{"spawn": entry["spawn"], "spawn_key": home, "ticks_left": 9999}]
		elif home == "10,2":
			zone["records"] = [{"entry": entry, "route": [], "route_index": 0, "route_step": 1}]
		else:
			kept.append(entry)
	zone["entities"] = kept
	return data


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func _test_a_gained_entity_moves_nobody(path: String, data: Dictionary) -> void:
	print("\n== the level gains an entity before the rest: every saved one comes back as itself ==")
	_write(path, data)
	_register(true)
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	_check(at.get(Vector2i(4, 4)) is Pushable and at.get(Vector2i(12, 4)) is Pushable and at.get(Vector2i(6, 4)) is Chest
			and not (at[Vector2i(6, 4)] as Chest).temple,
			"the crates and the chest back where they were left, each its own kind (%s)" % [_names(at)])
	var gained: Variant = at.get(GAINED)
	_check(gained is Chest and (gained as Chest).temple, "the gained chest spawned new, its props its own")
	var imp_slot := _slot_keyed("8,2")
	_check(imp_slot >= 0 and _main._dead_since.has(imp_slot) and not at.has(Vector2i(8, 4)) and not at.has(Vector2i(8, 2)),
			"Imp1 still dead, its timer on its own slot (%d), not spawned" % imp_slot)
	# The host stands near: Imp2's record is made again at once, as itself.
	var imp: Variant = at.get(Vector2i(10, 4))
	_check(imp is Monster and imp.spawn_spec["spawn_key"] == "10,2" and _main._alive_slots.get(_slot_keyed("10,2")) == imp,
			"Imp2's record made again as Imp2, on its own slot")
	_check(_main._alive_slots.size() == 5 and _main._alive_slots.keys().all(func(slot: int) -> bool:
				return _main._alive_slots[slot].spawn_spec["spawn_key"] == _main._key_of(slot)),
			"each living one holds the slot of its key (%d alive)" % _main._alive_slots.size())


func _test_a_lost_marker(path: String, data: Dictionary) -> void:
	print("\n== the level loses a marker: its saved entity comes back as saved, holding no slot ==")
	_write(path, data)
	_register(false, Vector2i(12, 2))
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	var crate: Variant = at.get(Vector2i(12, 4))
	_check(crate is Pushable and not crate.spawn_spec.has("spawn") and not crate.spawn_spec.has("spawn_key")
			and not _main._alive_slots.values().has(crate),
			"Crate2 where it was left, with no slot or key, in no slot (%s)" % [_names(at)])
	_check(at.get(Vector2i(4, 4)) is Pushable and at.get(Vector2i(6, 4)) is Chest and _main._alive_slots.size() == 3
			and _main._alive_slots.keys().all(func(slot: int) -> bool: return _main._alive_slots[slot].spawn_spec["spawn_key"] == _main._key_of(slot)),
			"the rest on their own slots (%d alive)" % _main._alive_slots.size())


func _test_an_old_snapshot_by_slots(path: String, data: Dictionary) -> void:
	print("\n== a snapshot from before keys loads by its slots, as it did ==")
	var old: Dictionary = data.duplicate(true)
	var zone: Dictionary = old["zones"][LEVEL]
	for entry: Dictionary in zone["entities"]:
		entry.erase("spawn_key")
	for respawn: Dictionary in zone["respawns"]:
		respawn.erase("spawn_key")
	for record: Dictionary in zone["records"]:
		record["entry"].erase("spawn_key")
	_write(path, old)
	_register(false)
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	_check(at.get(Vector2i(4, 4)) is Pushable and at.get(Vector2i(12, 4)) is Pushable and at.get(Vector2i(6, 4)) is Chest
			and not at.has(GAINED) and _main._dead_since.has(_slot_keyed("8,2")),
			"by slot: each where it was left, Imp1 dead (%s)" % [_names(at)])
	var imp: Variant = at.get(Vector2i(10, 4))
	_check(imp is Monster and imp.spawn_spec["spawn_key"] == "10,2",
			"the old record made again by its slot, with its key now for the next save")


func _test_stock_tops_up_once(path: String, data: Dictionary) -> void:
	print("\n== a level chest's stock reaches a saved world once (decision 468: Jeff's practice bow) ==")
	_write(path, data)
	_register(false, Vector2i(-1, -1), ["bow", "arrows"])
	_main._load_level(LEVEL)
	_main._start_level(true)
	var chest: Variant = _by_tile().get(Vector2i(6, 4))
	_check(chest is Chest and chest.spawn_spec["spawn_key"] == "6,2" and "bow" in chest.slots and "arrows" in chest.slots
			and World.items.id_of(World.slot_uids(chest)[chest.slots.find("bow")]) == "bow",
			"the saved chest, found by its key though the listed entry moved it up the order, gets a bow and arrows (%s)" % [chest.slots if chest is Chest else null])
	_check(chest is Chest and chest.spawn_spec["props"].get("stocked") == ["bow", "arrows"], "and remembers it was given them")
	var slots: PackedStringArray = chest.slots.duplicate()
	slots[slots.find("bow")] = ""
	World.set_slots(chest, slots, World.slot_uids(chest))
	_main._save_state()
	_main._load_level(LEVEL)
	_main._start_level(true)
	chest = _by_tile().get(Vector2i(6, 4))
	_check(chest is Chest and not "bow" in chest.slots and "arrows" in chest.slots and chest.spawn_spec["props"].get("stocked") == ["bow", "arrows"],
			"the bow taken and the world saved: loaded again, it does not come back (%s)" % [chest.slots if chest is Chest else null])


func _test_became(path: String, data: Dictionary) -> void:
	print("\n== level entities that became something else (decision 471): handed over once, not spawned ==")
	_write(path, data)
	# Imp1 dead (a timer), Imp2 a far record, Crate2 alive: all three became.
	_register(false, Vector2i(-1, -1), [], {"8,2": "imp_one", "10,2": "imp_two", "12,2": "crate_two"})
	_main.became_handed.clear()
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	var handed: Array = _main.became_handed.map(func(each: Dictionary) -> String: return each["id"])
	handed.sort()
	_check(handed == ["crate_two", "imp_two"], "the record and the living one handed over, once each (%s)" % [handed])
	var crate: Dictionary = _main.became_handed.filter(func(each: Dictionary) -> bool: return each["id"] == "crate_two")[0]["entry"]
	_check(crate["tile"] == Vector2i(12, 4) and crate["name"] == "Crate2" and int(crate["hp"]) > 0,
			"with where it was, its name and hp (%s)" % [crate])
	_check(not at.has(Vector2i(10, 4)) and not at.has(Vector2i(12, 4)) and not at.has(Vector2i(8, 4))
			and World.record_list().is_empty() and _main._dead_since.is_empty(),
			"none of them spawned, kept as a record, or waiting to respawn (%s)" % [_names(at)])
	_check(at.get(Vector2i(4, 4)) is Pushable and at.get(Vector2i(6, 4)) is Chest and _main._alive_slots.size() == 2,
			"the rest back as ever")
	var old: Dictionary = data.duplicate(true)
	for entry: Dictionary in old["zones"][LEVEL]["entities"]:
		entry.erase("spawn_key")
	_write(path, old)
	_register(false, Vector2i(-1, -1), [], {"12,2": "crate2"})
	_main.became_handed.clear()
	_main._load_level(LEVEL)
	_main._start_level(true)
	_check(_main.became_handed.size() == 1 and _main.became_handed[0]["id"] == "crate2" and not _by_tile().has(Vector2i(12, 4)),
			"from before keys, by its name")


## The level entity with [param key] in Main's table now: its slot, or -1.
func _slot_keyed(key: String) -> int:
	return _main._slot_for(-1, key)


func _by_tile() -> Dictionary:
	var out := {}
	for entity in World.get_entities():
		if entity.spawned and not entity is Player:
			out[entity.tile] = entity
	return out


func _names(at: Dictionary) -> Array:
	return at.keys().map(func(tile: Vector2i) -> String: return "%s@%s" % [at[tile].name, tile])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
