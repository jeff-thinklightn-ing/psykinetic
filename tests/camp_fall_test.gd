extends Node
## A cleared camp falls (decision 429), against the real room in main.tscn
## with a goblin camp laid round its imp's spawn tile: with its monsters
## alive and a player in it, it holds; killed, with the player in it for
## 10 s, it falls to nobody (place_taken fires; the party log says so); a
## player stepping out before then starts the clock again; a dead monster
## whose spawn tile is in the fallen camp does not come back, others do;
## retaken, it does. Run it with tests/run.ps1 or tests/run.sh.

const IMP_SLOT := 4  # Imp2 at (2, 6) in the test room.
const CAMP_CELL := Vector2i(2, 6)

var _failures := 0
var _main: Node
var _camp := ""


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17858)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_lay_camp()
	_test_holds()
	_test_clock_restarts()
	_test_falls()
	_test_stays_cleared()
	_test_retaken()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Holdings over this zone with a goblin camp of radius 1 round the imp
## (slots 3 and 4 in it; 0 to 2, two rows down, outside).
func _lay_camp() -> void:
	var zone: String = World.zone.name
	var rows: Array[String] = []
	for y in 2 * 20 - 1:
		rows.append(".".repeat(2 * 30 - 1))
	Level.register(zone, Level.image_from_rows(rows), null, {"outdoor": true, "places": {
		"camp": {"at": [CAMP_CELL.x, CAMP_CELL.y], "kind": "camp", "holder": "goblins", "radius": 1, "worth": 4}}})
	var names: Array[String] = [zone]
	World.holdings = Holdings.new(WorldMap.build(names), Factions.read(), {})
	_camp = "%s/camp" % zone
	_check(World.holdings.holder(_camp) == "goblins", "a goblin camp round the imp's spawn tile (%s)" % _camp)


func _test_holds() -> void:
	print("\n== defended, it holds ==")
	var player := _player()
	_walk_to(player, CAMP_CELL + Vector2i(1, 0))
	_step(_main.CAMP_FALL_TICKS + 20)
	_check(World.holdings.holder(_camp) == "goblins" or _monsters() == 0,
		"with its monsters about and a player in it, the camp holds (%s, %d monsters)" % [World.holdings.holder(_camp), _monsters()])


func _test_clock_restarts() -> void:
	print("\n== stepping out starts the clock again ==")
	var player := _player()
	_kill_monsters()
	_walk_to(player, CAMP_CELL + Vector2i(1, 0))
	_step(_main.CAMP_FALL_TICKS - 30)
	_walk_to(player, CAMP_CELL + Vector2i(8, 0))
	_step(20)
	_walk_to(player, CAMP_CELL + Vector2i(1, 0))
	_step(_main.CAMP_FALL_TICKS - 30)
	_check(World.holdings.holder(_camp) == "goblins", "out and back in under 10 s each time: still the goblins'")


func _test_falls() -> void:
	print("\n== cleared and held 10 s, it falls ==")
	var taken: Array = []
	World.holdings.place_taken.connect(func(id: String, from: String, to: String) -> void: taken.append([id, from, to]))
	_kill_monsters()
	_step(_main.CAMP_FALL_TICKS + _main.CAMP_CHECK_TICKS)
	_check(World.holdings.holder(_camp) == Factions.NOBODY, "it falls to nobody")
	_check(taken == [[_camp, "goblins", Factions.NOBODY]], "place_taken fires once (%s)" % [taken])
	var log: Array[String] = _main.party_log.last(5)
	_check(log.any(func(line: String) -> bool: return line == "The Blood Rot's camp falls."), "the party log says so (%s)" % [log])


func _test_stays_cleared() -> void:
	print("\n== no refilling while fallen ==")
	var player := _player()
	_walk_to(player, Vector2i(9, 6))
	_check(player.tile == Vector2i(9, 6), "the player walks out of it (at %s)" % player.tile)
	for slot: int in _main._dead_since:
		_main._dead_since[slot] = World.tick - _main.RESPAWN_DELAY_TICKS
	_main._respawned_at.clear()
	_step(_main.RESPAWN_STAGGER_TICKS * 8)
	_check(_slot_entity(IMP_SLOT) == null, "the imp, its spawn tile in the fallen camp, stays dead")
	_check(_monsters() > 0, "the others, outside it, come back (%d; slots %s)" % [_monsters(), _main._dead_since.keys().map(
		func(slot: int) -> String: return "%d %s" % [slot, _main._slot_spec(slot)["tile"]])])


func _test_retaken() -> void:
	print("\n== retaken, it refills ==")
	World.holdings.take(_camp, "goblins")
	_main._respawned_at.clear()
	_step(_main.RESPAWN_STAGGER_TICKS * 4)
	_check(_slot_entity(IMP_SLOT) is Monster, "the goblins hold it again: the imp comes back")


func _step(ticks: int) -> void:
	for i in ticks:
		World.step()


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player:
			return entity
	return null


func _slot_entity(slot: int) -> GridEntity:
	for entity in World.get_entities():
		if entity.spawned and entity.spawn_spec.get("spawn", -1) == slot:
			return entity
	return null


func _monsters() -> int:
	var count := 0
	for entity in World.get_entities():
		if entity is Monster and not entity is Animal and entity.spawned:
			count += 1
	return count


func _kill_monsters() -> void:
	for entity in World.get_entities():
		if entity is Monster and not entity is Animal:
			World.damage(entity, 999)
	for slot: int in _main._dead_since:
		_main._dead_since[slot] = World.tick


func _walk_to(entity: GridEntity, tile: Vector2i) -> void:
	World.order_move(entity, tile)
	for i in 120:
		if entity.tile == tile:
			return
		World.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
