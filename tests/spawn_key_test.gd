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
## The fallen knight's level (747 amended (11)): his marker at KNIGHT_WAS
## when saved, moved past the reach to KNIGHT_NOW (as 747 amended (8) moved
## the barrow's 22 cells, from (38,32) to (39,10)).
const KNIGHT_LEVEL := "spawn_key_knight"
const KNIGHT_WAS := Vector2i(13, 2)
const KNIGHT_NOW := Vector2i(2, 2)
const KNIGHT_LEGEND := {"monster_astral_knight": "#c8d8f0"}
## The knight's marker's facing in KNIGHT_LEVEL (the barrow's faces north, [0, -1]).
const KNIGHT_FACING := Vector2i(0, -1)

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
	_test_a_moved_marker(path, saved)
	_test_a_marker_moved_by_word(path, saved)
	_test_a_moved_locker(path, saved)
	_test_a_moved_knight()
	DirAccess.remove_absolute(path)
	Net.state_path = ""
	Level.unregister(LEVEL)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The level, as saved or with GAINED (a chest, props {"temple": true}),
## or without the marker at [param lost], or with [param moved]'s markers
## (from -> to) moved.
func _register(gained: bool, lost := Vector2i(-1, -1), stock: Array = [], became := {}, moved := {}, moved_markers := {}) -> void:
	Level.unregister(LEVEL)
	var markers := MARKERS.duplicate()
	markers.erase(lost)
	for from: Vector2i in moved:
		markers[moved[from]] = markers[from]
		markers.erase(from)
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
	var config := {"name": "Spawn keys", "entities": entries, "became": became}
	if not moved_markers.is_empty():
		config["moved_markers"] = moved_markers
	Level.register(LEVEL, image, null, config)


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


func _test_a_moved_marker(path: String, data: Dictionary) -> void:
	print("
== a marker moved a cell: its saved entity comes back on it as itself (decision 610) ==")
	_write(path, data)
	# The chest a cell over and down; Crate2 three cells over, past the reach.
	_register(false, Vector2i(-1, -1), [], {}, {Vector2i(6, 2): Vector2i(7, 3), Vector2i(12, 2): Vector2i(15, 2)})
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	var chests := at.values().filter(func(entity: GridEntity) -> bool: return entity is Chest)
	var chest: Variant = at.get(Vector2i(7, 3))
	_check(_main._adopted == 1, "the load counts one moved marker found, for release's journal (%d)" % _main._adopted)
	_check(chests.size() == 1 and chest is Chest and chest.spawn_spec["spawn_key"] == "7,3" and _main._alive_slots.get(_slot_keyed("7,3")) == chest,
			"one chest, on the moved marker's slot and tile, not a stray beside a new one (%s)" % [_names(at)])
	var crate: Variant = at.get(Vector2i(12, 4))
	_check(crate is Pushable and not crate.spawn_spec.has("spawn_key") and at.get(Vector2i(15, 2)) is Pushable,
			"a marker moved past the reach: the saved one as saved, a new one on the marker (%s)" % [_names(at)])


## A marker moved far by the level's word (747 amended (13), the barrow's
## Offering stone out of the Low Hall: level.json "moved_markers"): the saved
## chest, holding a thing, comes back on the new marker as itself, its thing
## in it, at load; and through a re-lay whose anchors hold the new cell and
## not the old, kept by the new cell, not lost; the load counts it.
func _test_a_marker_moved_by_word(path: String, data: Dictionary) -> void:
	print("
== a marker moved far by the level's word: its saved chest on the new marker, its things in it (747 amended (13)) ==")
	var held: Dictionary = data.duplicate(true)
	for entry: Dictionary in held["zones"][LEVEL]["entities"]:
		if str(entry.get("spawn_key", "")) == "6,2":
			entry["slots"] = ["bandaging_kit", "", "", ""]
	var word := {"6,2": [14, 3]}
	_write(path, held)
	_register(false, Vector2i(-1, -1), [], {}, {Vector2i(6, 2): Vector2i(14, 3)}, word)
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	var chests := at.values().filter(func(entity: GridEntity) -> bool: return entity is Chest)
	var chest: Variant = at.get(Vector2i(14, 3))
	_check(chests.size() == 1 and chest is Chest and chest.spawn_spec["spawn_key"] == "14,3" and chest.slots.size() > 0 and chest.slots[0] == "bandaging_kit"
			and _main._alive_slots.get(_slot_keyed("14,3")) == chest,
			"one chest, on the new marker, holding its thing, not a stray where it was saved nor an empty new one (%s)" % [_names(at)])
	# The re-lay: the zone held on the old level, laid again on the new with
	# anchors that hold (14,3) and not the old cell.
	_write(path, held)
	_register(false)
	_main._load_level(LEVEL)
	_main._start_level(true)
	_register(false, Vector2i(-1, -1), [], {}, {Vector2i(6, 2): Vector2i(14, 3)}, word)
	var east := [{"rect": Rect2i(13, 0, 3, HEIGHT), "name": "east"}]
	var sifted := Regen.keep_section({"entities": [{"spec": {"spawn_key": "6,2", "tile": Vector2i(6, 4)}}]}, east, null, Callable(), Regen.moved_markers(LEVEL))
	_check((sifted["kept"]["entities"] as Array).size() == 1 and (Regen.keep_section({"entities": [{"spec": {"spawn_key": "6,2", "tile": Vector2i(6, 4)}}]}, east)["kept"]["entities"] as Array).is_empty(),
			"keep_section keeps an entity keyed by the moved marker's old cell by its new one, and only with the level's word")
	_main._rebuild_regenerated(LEVEL, east)
	World.enter_named(LEVEL)
	at = _by_tile()
	chests = at.values().filter(func(entity: GridEntity) -> bool: return entity is Chest)
	chest = at.get(Vector2i(14, 3))
	_check(chests.size() == 1 and chest is Chest and chest.slots.size() > 0 and chest.slots[0] == "bandaging_kit",
			"and through a re-lay that keeps the new cell, not the old: on the new marker, its thing kept (%s)" % [_names(at)])
	_register(false)
	_main._load_level(LEVEL)


## The knight's level, his marker at [param at], a start at (0, 2).
func _register_knight(at: Vector2i) -> void:
	Level.unregister(KNIGHT_LEVEL)
	var colour := func(meaning: String) -> Color: return Color(str(KNIGHT_LEGEND.get(meaning, Level.LEGEND.get(meaning, "#000000"))))
	var image := Image.create_empty(WIDTH * 2 + 1, HEIGHT * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("void"))
	var ground: Color = colour.call(Level.GROUNDS[0])
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			var meaning := "monster_astral_knight" if cell == at else "start" if cell == Vector2i(0, 2) else ""
			image.set_pixel(x * 2, y * 2, colour.call(meaning) if not meaning.is_empty() else ground)
			if x + 1 < WIDTH:
				image.set_pixel(x * 2 + 1, y * 2, ground)
			if y + 1 < HEIGHT:
				image.set_pixel(x * 2, y * 2 + 1, ground)
	Level.register(KNIGHT_LEVEL, image, null, {"name": "Knight keys", "legend": KNIGHT_LEGEND,
		"entities": [{"at": [at.x, at.y], "facing": [KNIGHT_FACING.x, KNIGHT_FACING.y]}]})


## The knight's level loaded from [param path] as it stands: its knights.
func _knights_loaded() -> Array:
	_main._load_level(KNIGHT_LEVEL)
	_main._start_level(true)
	return _knights()


func _knights() -> Array:
	return World.get_entities().filter(func(entity: GridEntity) -> bool: return entity.spawned and entity is AstralKnight)


func _knight_words(knights: Array) -> String:
	return str(knights.map(func(each: GridEntity) -> String: return "%s@%s key %s" % [each.name, each.tile, each.spawn_spec.get("spawn_key", "-")]))


## Jeff's two knights (747 amended (11), 11-13: "2 copies of sir
## athelstan"): the fallen knight is placed only by his marker, one per
## level. One whose marker has not moved comes back as himself, on his
## slot; one whose marker moved past the reach is dropped, at load,
## through a second restart, at a record's recall and through a re-lay of
## the level, never spawned as saved beside his marker's new one.
func _test_a_moved_knight() -> void:
	print("
== the fallen knight's marker moved far: one knight, on the new marker (747 amended (11)) ==")
	var path: String = preload("res://tests/test_ports.gd").scratch_path("spawn_key_knight.json")
	DirAccess.remove_absolute(path)
	Net.state_path = path
	_register_knight(KNIGHT_WAS)
	_main._load_level(KNIGHT_LEVEL)
	_main._start_level(false)  # Fresh: no save of it yet.
	var knights := _knights()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_WAS, "a fresh level: its one knight on his marker (%s)" % _knight_words(knights))
	var was_name: String = knights[0].name if knights.size() == 1 else ""
	_main._save_state()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	# (c) His marker where it was: he comes back as himself, kept, not dropped.
	knights = _knights_loaded()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_WAS and knights[0].name == was_name
			and knights[0].spawn_spec.get("spawn_key", "") == "%d,%d" % [KNIGHT_WAS.x, KNIGHT_WAS.y] and _main._alive_slots.values().has(knights[0]),
			"his marker unmoved: the saved knight back as himself, holding his slot (%s)" % _knight_words(knights))
	# (a) His marker moved past the reach: one knight, the new marker's.
	_write(path, saved)
	_register_knight(KNIGHT_NOW)
	knights = _knights_loaded()
	var now_key := "%d,%d" % [KNIGHT_NOW.x, KNIGHT_NOW.y]
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW and knights[0].spawn_spec.get("spawn_key", "") == now_key
			and _main._alive_slots.values().has(knights[0]),
			"his marker moved far: one knight, on the new marker and holding its slot; the saved one dropped (%s)" % _knight_words(knights))
	# (b) A second restart on what that load saved: still one.
	_main._save_state()
	knights = _knights_loaded()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW, "and a second restart: still one (%s)" % _knight_words(knights))
	# The box's own save (saturn, 11-13): written after v0.1.214's re-lay, it
	# holds the stray first (no key, "spawn": -1, at the old cell, named as
	# the marker's) and the marker's knight keyed after. One knight, the
	# marker's, on the marker; and through a re-lay, still there.
	var both: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var both_zone: Dictionary = both["zones"][LEVEL]
	var keyed: Dictionary = {}
	for entry: Dictionary in both_zone["entities"]:
		if str(entry.get("spawn_key", "")) == now_key:
			keyed = entry
	var stray: Dictionary = keyed.duplicate(true)
	stray.erase("spawn_key")
	stray["spawn"] = -1
	stray["tile"] = [KNIGHT_WAS.x, KNIGHT_WAS.y]
	if stray.has("home"):
		stray["home"] = [KNIGHT_WAS.x, KNIGHT_WAS.y]
	(both_zone["entities"] as Array).push_front(stray)
	_write(path, both)
	knights = _knights_loaded()
	_check(not keyed.is_empty() and knights.size() == 1 and knights[0].tile == KNIGHT_NOW and knights[0].spawn_spec.get("spawn_key", "") == now_key,
			"the box's save, the stray first and the marker's knight keyed: one knight, on the marker, not the stray in his old room (%s)" % _knight_words(knights))
	_main._rebuild_regenerated(KNIGHT_LEVEL, [{"rect": Rect2i(0, 0, WIDTH, HEIGHT), "name": "all"}])
	World.enter_named(KNIGHT_LEVEL)
	knights = _knights()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW, "and through a re-lay: still one, on the marker (%s)" % _knight_words(knights))
	# The box's save as it was at v0.1.215's deploy (747 amended (13), Jeff 11-14: "astral
	# knight still in wrong room"): a second boot before (11) read the shape above with the
	# name match alone, so the stray took the marker's key at his old cell and the marker's
	# knight came back slotless; that boot's save holds the marker's key at the old cell, a
	# slotless knight on the marker. One knight, on the marker, facing as it does; through a
	# re-lay that keeps the old cell, and a restart after.
	_main._alive_slots.clear()
	var old_read: Dictionary = _main._level_spec_for(stray.duplicate(true))
	_check(old_read.get("spawn_key", "") == now_key, "the name match alone gives the stray the marker's key (%s), as a boot before (11) did" % [old_read.get("spawn_key", "-")])
	var third: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var third_zone: Dictionary = third["zones"][LEVEL]
	var third_list: Array = (third_zone["entities"] as Array).filter(func(entry: Dictionary) -> bool: return not str(entry.get("script", "")).ends_with("astral_knight.gd"))
	var took: Dictionary = keyed.duplicate(true)
	took["tile"] = [KNIGHT_WAS.x, KNIGHT_WAS.y]
	took["facing"] = [1, 0]
	if took.has("home"):
		took["home"] = [KNIGHT_WAS.x, KNIGHT_WAS.y]
	var slotless: Dictionary = keyed.duplicate(true)
	slotless.erase("spawn_key")
	slotless["spawn"] = -1
	third_list.push_front(slotless)
	third_list.push_front(took)
	third_zone["entities"] = third_list
	_write(path, third)
	knights = _knights_loaded()
	var marker_facing: Vector2i = knights[0].facing if knights.size() == 1 else Vector2i.ZERO
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW and knights[0].spawn_spec.get("spawn_key", "") == now_key and marker_facing == KNIGHT_FACING,
			"the save after a second boot before (11), the marker's key at the old cell: one knight, on the marker, facing as it does (%s, facing %s)" % [_knight_words(knights), marker_facing])
	_write(path, third)
	_knights_loaded()
	_main._rebuild_regenerated(KNIGHT_LEVEL, [{"rect": Rect2i(0, 0, WIDTH, HEIGHT), "name": "all"}])
	World.enter_named(KNIGHT_LEVEL)
	knights = _knights()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW, "and through a re-lay that keeps the old cell: on the marker (%s)" % _knight_words(knights))
	_main._save_state()
	knights = _knights_loaded()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW, "and a restart after: on the marker (%s)" % _knight_words(knights))
	_check(Main.knight_on_marker({"script": "res://sim/astral_knight.gd", "spawn_key": "2,2"}) and not Main.knight_on_marker({"script": "res://sim/astral_knight.gd"})
			and not Main.knight_on_marker({"script": "res://sim/monster.gd", "spawn_key": "2,2"}), "only a knight holding his slot is put on his marker")
	# A kept record of the old knight (retired while nobody was near), made again: dropped, not kept.
	var as_record: Dictionary = saved.duplicate(true)
	var zone: Dictionary = as_record["zones"][LEVEL]  # Saved under the zone's name, the test's (Main._start_level's "here").
	var entries: Array = []
	for entry: Dictionary in zone["entities"]:
		if str(entry.get("spawn_key", "")) == "%d,%d" % [KNIGHT_WAS.x, KNIGHT_WAS.y]:
			zone["records"] = [{"entry": entry, "route": [], "route_index": 0, "route_step": 1}]
		else:
			entries.append(entry)
	zone["entities"] = entries
	_write(path, as_record)
	knights = _knights_loaded()
	_main._recall_near(KNIGHT_WAS, 64)
	knights = _knights()
	var kept := World.record_list().filter(func(record: Dictionary) -> bool: return str(record["entry"].get("script", "")).ends_with("astral_knight.gd"))
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW and kept.is_empty(),
			"the old knight kept as a record: made again, he is dropped, not kept again (%s, %d records)" % [_knight_words(knights), kept.size()])
	# (b) A re-lay of the level (the box's 14): the zone held with the old
	# knight, laid again on the moved marker, its whole floor kept.
	_write(path, saved)
	_register_knight(KNIGHT_WAS)
	knights = _knights_loaded()
	_register_knight(KNIGHT_NOW)
	_main._rebuild_regenerated(KNIGHT_LEVEL, [{"rect": Rect2i(0, 0, WIDTH, HEIGHT), "name": "all"}])
	World.enter_named(KNIGHT_LEVEL)
	knights = _knights()
	_check(knights.size() == 1 and knights[0].tile == KNIGHT_NOW, "and laid again over the moved marker: still one, the new marker's (%s)" % _knight_words(knights))
	_check(Main.stray_knight({"script": "res://sim/astral_knight.gd"}) and not Main.stray_knight({"script": "res://sim/astral_knight.gd", "spawn_key": "2,2"})
			and not Main.stray_knight({"script": "res://sim/monster.gd"}), "only a knight holding no slot is a stray")
	DirAccess.remove_absolute(path)
	Level.unregister(KNIGHT_LEVEL)
	_register(false)
	_main._load_level(LEVEL)


## A town's locker whose marker moved past the reach (737: Umbrage's into
## the player's house): its saved chest dropped, not a stray locker beside
## the new one; the load says how many, with no error.
func _test_a_moved_locker(path: String, data: Dictionary) -> void:
	print("\n== a locker's marker moved far: its saved chest dropped, not a stray (737) ==")
	var moved: Dictionary = data.duplicate(true)
	for entry: Dictionary in moved["zones"][LEVEL]["entities"]:
		if str(entry.get("spawn_key", "")) == "6,2":
			entry["props"] = JSON.from_native({"locker": true})
	_write(path, moved)
	_register(false, Vector2i(-1, -1), [], {}, {Vector2i(6, 2): Vector2i(14, 3)})
	_main._load_level(LEVEL)
	_main._start_level(true)
	var at := _by_tile()
	var chests := at.values().filter(func(entity: GridEntity) -> bool: return entity is Chest)
	_check(chests.size() == 1 and at.get(Vector2i(14, 3)) is Chest and not at.has(Vector2i(6, 4)),
			"one chest, the new one on its marker; the saved locker not spawned where it was left (%s)" % [_names(at)])
