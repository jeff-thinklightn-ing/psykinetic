extends Node
## The far tier hands over to records (decision 352): a monster far from
## everyone long enough is kept as a record on its zone instead of a node,
## and made again as it was when someone comes near; saved with the world,
## and an old snapshot (from before records) loads as it did.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const LEVEL := "far_tier_test"
const WIDTH := 140
const HEIGHT := 7

var _failures := 0
var _main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	Level.register(LEVEL, _layout(), null, {"name": "Far tier", "entities": [
		{"at": [120, 3], "idle": {"mode": "patrol", "route": [[116, 3], [124, 3]]}},
		{"at": [130, 5], "wields": {"right": "dagger"}},
	]})
	Net.port = preload("res://tests/test_ports.gd").of(17797)
	Net.companions = false
	Net.state_path = ""
	Net.map_name = LEVEL
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)

	var old_world := preload("res://tests/test_ports.gd").scratch_path("old_world.json")
	_save_without_records(old_world)
	await _test_far_monsters_become_records()
	_test_records_are_saved_and_loaded()
	_test_records_come_back_as_they_were()
	_test_an_old_snapshot_loads_as_before(old_world)
	_test_a_keeper_takes_its_own()
	_test_a_join_recalls_over_ticks()
	_test_a_stop_right_after_a_save()  # Last: it lets the zones go.

	DirAccess.remove_absolute(preload("res://tests/test_ports.gd").scratch_path("far_world.json"))
	Net.state_path = ""
	Level.unregister(LEVEL)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A strip 140 cells long: the host starts at its west end, a brute, a
## patrolling imp and an imp with a dagger at its east end, 100 and more
## cells off.
func _layout() -> Image:
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(WIDTH * 2 + 1, HEIGHT * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("void"))
	var ground: Color = colour.call(Level.GROUNDS[0])
	var markers := {Vector2i(1, 3): "start", Vector2i(100, 1): "monster_brute",
		Vector2i(120, 3): "monster_imp", Vector2i(130, 5): "monster_imp"}
	for y in HEIGHT:
		for x in WIDTH:
			var cell := Vector2i(x, y)
			image.set_pixel(x * 2, y * 2, colour.call(markers[cell]) if markers.has(cell) else ground)
			if x + 1 < WIDTH:
				image.set_pixel(x * 2 + 1, y * 2, ground)
			if y + 1 < HEIGHT:
				image.set_pixel(x * 2, y * 2 + 1, ground)
	return image


## The world as a build from before records saves it: no "records" in its
## zone (the box's world when this lands).
func _save_without_records(path: String) -> void:
	Net.state_path = path
	_main._save_state()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for zone_name: String in data["zones"]:
		data["zones"][zone_name].erase("records")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	Net.state_path = ""


func _test_far_monsters_become_records() -> void:
	print("\n== monsters far from everyone long enough become records: not dead, not respawned ==")
	var imp := _named("Imp1")
	var armed := _named("Imp2")
	_check(_monsters() == 3 and imp != null and armed != null, "the brute and two imps are there (%d)" % _monsters())
	imp._route_index = 1
	armed.hp -= 3
	var dagger: int = armed.slot_items[Items.RIGHT_HAND]
	_check(dagger != 0 and World.items.id_of(dagger) == "dagger", "Imp2 holds a dagger (%d)" % dagger)
	var lines: int = _main.party_log.size()
	var gone: WeakRef = weakref(imp)
	for i in Main.RETIRE_AFTER_TICKS + 40:
		World.step()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(gone.get_ref() == null, "the node it was is freed, not kept somewhere")
	_check(_monsters() == 0 and World.record_list().size() == 3, "all three kept as records (%d nodes, %d records)" % [
			_monsters(), World.record_list().size()])
	_check(_main._alive_slots.is_empty() and _main._dead_since.is_empty() and _main._recorded_slots().size() == 3,
			"their slots neither alive nor dead, held by the records")
	_check(_main.party_log.size() == lines, "nobody died (%s)" % [_main.party_log.last(3)])
	_check(World.items.at_of(dagger) == "%s/Imp2" % LEVEL, "the dagger is still Imp2's (%s)" % World.items.at_of(dagger))
	for i in Main.RESPAWN_DELAY_TICKS + 20:
		World.step()
	_check(_monsters() == 0 and World.record_list().size() == 3, "and nothing respawns in their place (%d nodes)" % _monsters())


func _test_records_are_saved_and_loaded() -> void:
	print("\n== records are saved with the world, and loaded back as records ==")
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("far_world.json")
	_main._save_state()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Net.state_path))
	var saved: Array = data["zones"][LEVEL].get("records", [])
	_check(saved.size() == 3 and data["zones"][LEVEL]["entities"].size() == 0, "the snapshot has 3 records and no monster nodes")
	_main._start_level(true)
	_check(World.record_list().size() == 3 and _monsters() == 0, "loaded: 3 records, and no slot made again as new (%d nodes)" % _monsters())
	var dagger_holder := ""
	for record: Dictionary in World.record_list():
		if record["entry"]["name"] == "Imp2":
			dagger_holder = World.items.at_of(int(record["entry"]["items"][Items.RIGHT_HAND]))
	_check(dagger_holder == "%s/Imp2" % LEVEL, "the dagger is still Imp2's after the rebuild (%s)" % dagger_holder)
	_main._save_state()
	data = JSON.parse_string(FileAccess.get_file_as_string(Net.state_path))
	_check(data["zones"][LEVEL].get("records", []).size() == 3, "and the first save after loading keeps them")


func _test_records_come_back_as_they_were() -> void:
	print("\n== someone comes near: the records are monsters again, as they were ==")
	var player := _player()
	World._relocate(player, Vector2i(60, 3))
	for i in Main.RETIRE_EVERY_TICKS + 1:
		World.step()
	var imp := _named("Imp1")
	var armed := _named("Imp2")
	_check(_monsters() == 3 and World.record_list().is_empty(), "all three back (%d nodes, %d records)" % [_monsters(), World.record_list().size()])
	_check(imp != null and imp._route_index == 1 and imp.route.size() == 2, "Imp1 goes on with its patrol where it was (waypoint %s)" % [
			imp._route_index if imp != null else -1])
	_check(armed != null and armed.hp == armed.max_hp - 3, "Imp2 has the hp it had (%s)" % [armed.hp if armed != null else -1])
	_check(armed != null and World.items.id_of(armed.slot_items[Items.RIGHT_HAND]) == "dagger"
			and World.items.at_of(armed.slot_items[Items.RIGHT_HAND]) == "%s/Imp2" % LEVEL, "and its dagger, the same one")
	var slots_alive := 0
	for slot: int in _main._alive_slots:
		if is_instance_valid(_main._alive_slots[slot]) and _main._alive_slots[slot].spawned:
			slots_alive += 1
	_check(slots_alive == 3 and _main._recorded_slots().is_empty(), "their slots alive again (%d)" % slots_alive)


func _test_an_old_snapshot_loads_as_before(path: String) -> void:
	print("\n== a snapshot from before records loads with every monster ==")
	Net.state_path = path
	_main._start_level(true)
	_check(_monsters() == 3 and World.record_list().is_empty(), "three monsters, no records (%d)" % _monsters())
	DirAccess.remove_absolute(path)


## A kind with a store of its own (wildlife's herds, W4) registers a keeper
## (World.keepers): the monsters it takes go to it, not to records, and it
## is asked to make what it keeps near whoever comes.
class FakeKeeper:
	var taken: Array[String] = []
	var asked := 0

	func takes(monster: Monster) -> bool:
		return String(monster.name) == "Brute1"

	func retire(monster: Monster) -> void:
		taken.append(String(monster.name))

	func recall_near(_at: Vector2i, _reach: int) -> void:
		asked += 1


func _test_a_keeper_takes_its_own() -> void:
	print("
== a keeper takes the monsters of its kind, records the rest ==")
	var keeper := FakeKeeper.new()
	World.keepers.append(keeper)
	World._relocate(_player(), Vector2i(1, 3))
	var lines: int = _main.party_log.size()
	for i in Main.RETIRE_AFTER_TICKS + 40:
		World.step()
	_check(keeper.taken == ["Brute1"] and World.record_list().size() == 2 and _monsters() == 0,
			"the brute went to the keeper, the imps to records (%s, %d records)" % [keeper.taken, World.record_list().size()])
	_check(_main.party_log.size() == lines and _main._dead_since.is_empty(), "and the brute is not dead either")
	_check(keeper.asked > 0, "the keeper is asked about what it keeps near the player (%d times)" % keeper.asked)
	World.keepers.erase(keeper)


## A player who comes back where records are: those near enough for spawn
## safety at once, the rest queued and made again over the next ticks, and
## counted as records (saved) while they wait.
func _test_a_join_recalls_over_ticks() -> void:
	print("
== a join near records: made again over the next ticks, not all on one ==")
	var record := PlayerRecord.new()
	record.player_id = "fa000000-0000-4000-8000-00000000000f"
	record.name = "Late"
	record.index = 9
	record.zone = LEVEL
	record.tile = Vector2i(100, 3)
	_main._records[record.player_id] = record
	var before := World.record_list().size()
	_main._admit(2000, record.player_id, "Late")
	_check(before == 2 and _monsters() == 0 and World.zone.recalls_due.size() == 2,
			"the two imps, 20 and 30 cells off, wait their turn (%d waiting, %d monsters)" % [World.zone.recalls_due.size(), _monsters()])
	_check(World.record_list().size() == 2, "and are still records, so a save meanwhile keeps them")
	for i in 2:
		World.step()
	_check(_monsters() == 2 and World.zone.recalls_due.is_empty() and World.record_list().is_empty(),
			"a tick or two on, both are back (%d)" % _monsters())


## The snapshot is written on a thread (decision 360): a stop straight after
## a periodic save (systemctl stop: _release_zones) waits for it, then
## writes the last; the file is whole and the newest, no temp file left.
func _test_a_stop_right_after_a_save() -> void:
	print("
== stopped straight after a save on the thread: the file is whole, and the last ==")
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("stop_world.json")
	_main._save_state(false)  # The periodic one, on the thread.
	var busy: bool = _main._saver != null
	_main._save_state(false)  # Another while it may still be busy: skipped, or after it.
	World.step()
	var steps := World.steps
	_main._release_zones()  # As a stop does.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Net.state_path))
	_check(busy and data is Dictionary and data.has("zones") and int(data.get("steps", -1)) == steps,
			"the snapshot is whole and from the stop (steps %s, the world at %d)" % [data.get("steps") if data is Dictionary else "unreadable", steps])
	_check(_main._saver == null and not FileAccess.file_exists(Net.state_path + ".tmp"), "nothing left being written, no temp file")
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""


# --- helpers ------------------------------------------------------------------

func _monsters() -> int:
	var count := 0
	for entity in World.get_entities():
		if entity is Monster and entity.spawned:
			count += 1
	return count


func _named(entity_name: String) -> Monster:
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and String(entity.name) == entity_name:
			return entity
	return null


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
