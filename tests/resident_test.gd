extends Node
## A companion left in town works there (decision 284): a test town (made in
## code) with a stockpile place the town holds, and a road beside it. Her
## player travels on while she is told to stay on the town's ground: she
## stays, a resident working her trade (her rolled profession's), not
## spawned on the road; her voice is told so; travelling back, she leaves
## her work and follows. Her player leaving the game while she stands there
## does the same, and coming back ends it. Off the town's ground, or not
## told to stay, she goes with them as before.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "rs_town"
const ROAD := "rs_road"
const STORE := "rs_town/store"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17796)
	Net.companions = true
	Net.state_path = preload("res://tests/test_ports.gd").scratch("resident_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_register_levels()
	Net.map_name = TOWN
	await _boot()

	_test_stays_when_told()
	_test_stays_when_left()
	_test_goes_when_not_told()
	_test_legacy_rests_in_town()
	_test_taken_by_raiders()

	remove_child(_main)
	_main.free()
	World.clear_zones()
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	Net.map_name = ""
	Level.unregister(TOWN)
	Level.unregister(ROAD)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## rs_town: 16 x 10 cells of stone in a wall, the start at (2, 2), the store
## (a stockpile the town holds) at (5, 3), radius 2. rs_road: a bare room.
func _register_levels() -> void:
	for level_name: String in [TOWN, ROAD]:
		var rows: Array[String] = []
		for y in 10:
			rows.append("#".repeat(16) if y == 0 or y == 9 else "#" + ".".repeat(14) + "#")
		var spec := {"name": level_name, "centre": [7, 4], "starts": [[2, 2]], "entities": []}
		if level_name == TOWN:
			spec["places"] = {"store": {"at": [5, 3], "kind": "stockpile", "radius": 2, "holder": "town", "name": "the stockpile"}}
		Level.register(level_name, Level.image_from_rows(rows, {Vector2i(2, 2): "start"}), null, spec)


func _boot() -> void:
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var names := Level.names()
	names.append_array([TOWN, ROAD])
	World.holdings.rebind(WorldMap.build(names))
	for i in 3:
		World.step()


func _test_stays_when_told() -> void:
	print("\n== told to stay on the town's ground, she stays and works while her player travels on ==")
	var pet := _companion()
	# Her rolled profession may have no trade (a hunter): this one has.
	_main._records[Net.player_id].companion["traits"]["trade"] = "carpenter"
	_check(pet != null and _trade() != "", "(a companion with a trade: %s, %s)" % [
		pet.name if pet != null else "none", _trade() if pet != null else ""])
	var ground := _town_cell(Vector2i(-1, -1))
	_check(ground.x >= 0, "(a walkable cell of the town's ground: %s)" % ground)
	_put(pet, ground)
	_told_to_stay(pet)
	_check(pet.stays_put(), "HOLD, standing as her player's instruction: she stays put")
	var who := "companion:%s" % _pet_name()
	var trade := _trade()
	_main.travel(Net.local_id, ROAD)
	_check(World.zone.name == ROAD and _companion() == null, "her player is on the road, and she is not with them")
	_check(who in World.towns.residents(STORE) and not World.production.worker(who).is_empty()
		and not World.production.worker(who).get("away", true), "she is one of the town's residents, working (%s)" % [World.towns.residents(STORE)])
	var record: PlayerRecord = _main._records[Net.player_id]
	_check(record.companion.get("resident", {}).get("place", "") == STORE and record.companion["resident"]["trade"] == trade,
		"her record says where she works, and at what (%s)" % [record.companion.get("resident", {})])
	var saved := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(saved.companion.get("resident", {}) == record.companion["resident"], "and keeps it through a save and a load")
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_check(pet != null and pet.tile == ground, "back in the town, she is where she worked (%s)" % [pet.tile if pet != null else "none"])
	_check(World.production.worker(who).get("away", false) and not record.companion.has("resident") and pet.works_as.is_empty(),
		"and leaves her work to go with them, her job waiting")


func _test_stays_when_left() -> void:
	print("\n== her player leaves the game while she stands on the town's ground: she works until they are back ==")
	var pet := _companion()
	_settle(pet)
	_put(pet, _town_cell(pet.tile))
	var who := "companion:%s" % _pet_name()
	_main._on_peer_disconnected(Net.local_id)
	World.step()
	_check(pet.spawned and pet.works_as == _trade() and not World.production.worker(who).get("away", true),
		"she stays, as before, and works as the town's %s" % pet.works_as)
	_check("you stay in this town and work as its %s" % pet.works_as in pet.voice_prompt("test"), "her voice is told where she works")
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	World.step()
	_check(pet.keeper == _player() and pet.works_as.is_empty() and World.production.worker(who).get("away", false),
		"her player back: she follows again, her job waiting")


func _test_goes_when_not_told() -> void:
	print("\n== not told to stay, or off the town's ground: she goes with them ==")
	var pet := _companion()
	_settle(pet)
	_put(pet, _town_cell(Vector2i(-1, -1)))
	_main.travel(Net.local_id, ROAD)
	_check(_companion() != null, "on the town's ground but not told to stay: she goes with them")
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_put(pet, Vector2i(3, 7))
	_told_to_stay(pet)
	_main.travel(Net.local_id, ROAD)
	var record: PlayerRecord = _main._records[Net.player_id]
	_check(_companion() != null and not record.companion.has("resident"), "told to stay off the town's ground: she goes with them")
	_main.travel(Net.local_id, TOWN)


func _test_legacy_rests_in_town() -> void:
	print("
== Wren and Nix rest in town between trips: their player gone from the game, they go to the town ==")
	var record: PlayerRecord = _main._records[Net.player_id]
	var was: String = record.companion["name"]
	record.companion["name"] = "Nix"
	_main.travel(Net.local_id, ROAD)
	var pet := _companion()
	_check(pet != null and World.zone.name == ROAD, "(her player and she are on the road)")
	_main._on_peer_disconnected(Net.local_id)
	_check(not pet.spawned and record.companion.get("resident", {}).get("zone", "") == TOWN and record.companion.get("tile") == null,
		"her player gone, she goes back to the town to rest (%s)" % [record.companion.get("resident", {})])
	var told: Array[String] = []
	var note := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			told.append(str(data.get("text", "")))
	Net.message_received.connect(note)
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	Net.message_received.disconnect(note)
	_check(World.zone.name == ROAD and _companion() == null, "her player back on the road: she is in the town, not with them")
	_check(told.any(func(line: String) -> bool: return line.begins_with("Nix is ") and TOWN in line), "and they are told where she is: %s" % [told])
	_main.travel(Net.local_id, TOWN)
	pet = _companion()
	_check(pet != null and World.distance(pet.tile, _player().tile) <= 2 and not record.companion.has("resident"),
		"in the town she joins them again, beside them")
	record.companion["name"] = was


func _test_taken_by_raiders() -> void:
	print("\n== beaten down by raiders, she is taken, not killed: held till freed, then she waits in the town that freed her (decision 314) ==")
	var record: PlayerRecord = _main._records[Net.player_id]
	var pet := _companion()
	_settle(pet)
	var was_spared: Callable = World.spared
	World.spared = func(target: GridEntity, _source: GridEntity, _cause: StringName) -> String:
		return "raid-7" if target is Companion else ""
	var told: Array[String] = []
	var note := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			told.append(str(data.get("text", "")))
	Net.message_received.connect(note)
	World.damage(pet, pet.hp + 5)
	World.spared = was_spared
	_check(not pet.spawned and _companion() == null and record.companion.get("alive", false)
		and record.companion.get("taken", {}).get("by", "") == "raid-7", "off the map, alive, held by the group (%s)" % [record.companion.get("taken", {})])
	_check(record.companion.get("facts", []).any(func(fact: Dictionary) -> bool: return "carried off by raiders" in str(fact["text"])),
		"carried off is a fact about her")
	_check(told.any(func(line: String) -> bool: return "carried them off" in line), "her player is told (%s)" % [told])
	var saved := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(saved.companion.get("taken", {}) == record.companion["taken"], "kept through a save and a load")
	told.clear()
	_main.travel(Net.local_id, ROAD)
	_main.travel(Net.local_id, TOWN)
	Net.message_received.disconnect(note)
	_check(_companion() == null and told.any(func(line: String) -> bool: return "held by them still" in line),
		"held, she is not spawned beside them, and they are told why (%s)" % [told])
	_check(_main.companion_freed(Net.player_id, STORE) and not record.companion.has("taken")
		and record.companion.get("resident", {}).get("place", "") == STORE, "freed by the town: she waits there (%s)" % [record.companion.get("resident", {})])
	_check(record.companion["facts"].any(func(fact: Dictionary) -> bool: return "freed from the raiders" in str(fact["text"])), "and that is a fact about her")
	_check(not _main.companion_freed(Net.player_id, STORE), "not freed twice")
	_main.travel(Net.local_id, ROAD)
	_main.travel(Net.local_id, TOWN)
	_check(_companion() != null and not record.companion.has("resident"), "her player in the town: she joins them again")


# --- helpers ------------------------------------------------------------------

func _told_to_stay(pet: Companion) -> void:
	pet._serial += 1
	pet._set_stance(Companion.Stance.HOLD, pet._serial, "test")
	pet._instruction = "Player just said to you: \"Stay here.\""
	pet._instruction_tick = World.tick


func _settle(pet: Companion) -> void:
	pet.stance = Companion.Stance.GUARD
	pet._instruction = ""


func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity != null and entity.tile != tile:
		World._relocate(entity, tile)


## A free, walkable cell of the store's ground, not [param besides].
func _town_cell(besides: Vector2i) -> Vector2i:
	for y in 10:
		for x in 16:
			var at := Vector2i(x, y)
			if at != besides and World.is_free(at) and Stockpile.place_at(World.holdings, TOWN, at) == STORE:
				return at
	return Vector2i(-1, -1)


func _trade() -> String:
	return str(_main._records[Net.player_id].companion.get("traits", {}).get("trade", ""))


func _pet_name() -> String:
	return String(_main._records[Net.player_id].companion.get("name", ""))


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
