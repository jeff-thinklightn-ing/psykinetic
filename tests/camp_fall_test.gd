extends Node
## A cleared camp falls (decision 429), against the real room in main.tscn
## with a goblin camp laid round its imp's spawn tile: with its monsters
## alive and a player in it, it holds; killed, with the player in it for
## 10 s, it falls to nobody (place_taken fires; the party log says so); a
## player stepping out before then starts the clock again; a dead monster
## whose spawn tile is in the fallen camp does not come back, others do;
## who held it takes it back after rescue.restock_days, not with a player
## in it, remembered across a restart; then it does. Run it with tests/run.ps1 or tests/run.sh.

const Walk := preload("res://tests/walk.gd")
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
	_test_truce()
	_lay_camp()
	_test_holds()
	_test_clock_restarts()
	_test_falls()
	_test_stays_cleared()
	_test_retaken()
	_test_occupied()
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
	World.holdings.place_taken.connect(_main._on_place_taken)  # As Main does its own Holdings.
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
	_kill_monsters()
	var player := _standing_player()
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
	var sent: int = _main.rewards_by_track.get("deed", 0)
	var players_there: int = _main._players_in(World.zone.name).size()
	_step(_main.CAMP_FALL_TICKS + _main.CAMP_CHECK_TICKS)
	_check(World.holdings.holder(_camp) == Factions.NOBODY, "it falls to nobody")
	# Deeds alone: a companion there gains bond and needs of her own (804 amended (3)).
	var deeds: int = _main.rewards_by_track.get("deed", 0) - sent
	_check(players_there > 0 and deeds == players_there,
		"a deed for each player in its area (804, enemy-ai's side): %d sent for %d" % [deeds, players_there])
	var held: String = _main.camp_cleared_name("camp", "Camp", "the Blood Rot")
	var labelled: String = _main.camp_cleared_name("bridge_camp", "the camp by the bridge", "the Blood Rot")
	var bare: String = _main.camp_cleared_name("low_camp", "Camp below Hollowfell", "the Blood Rot")
	_check(held == "the Blood Rot's camp" and labelled == "the camp by the bridge" and bare == "the camp below Hollowfell",
		"its name for the float (%s; %s; %s)" % [held, labelled, bare])
	var banners: Array = [_main.camp_cleared_banner(held), _main.camp_cleared_banner(labelled)]
	_check(banners == ["The Blood Rot's camp, cleared", "Camp by the bridge, cleared"], "its banner in voice's words (%s)" % [banners])
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
	print("\n== taken back in time, it refills ==")
	_check(World.holdings.fallen_camps().map(func(f: Dictionary) -> String: return f["id"] + " " + f["faction"]) == [_camp + " goblins"],
		"Holdings remembers who held the fallen camp")
	var saved := World.holdings.to_dict()
	var names: Array[String] = [World.zone.name]
	var again := Holdings.new(WorldMap.build(names), Factions.read(), JSON.parse_string(JSON.stringify(saved)))
	_check(again.fallen_camps().size() == 1 and again.fallen_camps()[0]["faction"] == "goblins", "and still after a restart")
	_check(_main._retake_camps() == 0, "not before rescue.restock_days have passed")
	World.holdings._since[_camp] = World.holdings.now() - 6 * maxi(DayNight.day_steps, 1)
	var player := _player()
	if player == null or World.is_downed(player):
		# Beaten down by the imps meanwhile (Mortally Wounded): bled out, and back.
		if player != null:
			World.damage(player, player.hp, null, &"bled")
		for i in _main.RESPAWN_TICKS * 4:
			World.step()
			if _player() != null:
				break
		player = _player()
	_walk_to(player, CAMP_CELL + Vector2i(1, 0))
	_check(_main._retake_camps() == 0, "nor with a player standing in it")
	_walk_to(player, Vector2i(9, 6))
	_check(_main._retake_camps() == 1 and World.holdings.holder(_camp) == "goblins" and World.holdings.fallen_camps().is_empty(),
		"after them, with nobody in it, the goblins take it back")
	# Clear of the imp's tile (RESPAWN_MIN_DISTANCE) and past the grace of their
	# respawn earlier on (_arrived_at): this passed only while the player happened
	# to die again here.
	_walk_to(player, Vector2i(12, 1))
	_main._arrived_at.clear()
	_main._respawned_at.clear()
	for slot: int in _main._dead_since:
		_main._dead_since[slot] = World.tick - _main.RESPAWN_DELAY_TICKS  # Its wait (739: restarted while the player stood in it) run out.
	_step(_main.RESPAWN_STAGGER_TICKS * 4)
	_check(_slot_entity(IMP_SLOT) is Monster, "the goblins hold it again: the imp comes back")


## Decision 739 (Jeff: "occupancy blocks campfire respawns"): with a player
## in it (its radius and CAMP_OCCUPIED_MARGIN), a camp's dead never come
## back and their wait starts over; leaving, the full wait runs from then.
## Main.held_camp: occupied and cleared.
func _test_occupied() -> void:
	print("
== occupied, a camp's dead stay down; cleared and occupied, it is held (739) ==")
	var player := _standing_player()
	_walk_to(player, CAMP_CELL + Vector2i(1, 0))
	_check(_main.held_camp(CAMP_CELL) == "" or _monsters() == 0, "its monsters about: not held (%s)" % _main.held_camp(CAMP_CELL))
	_kill_monsters()
	player = _standing_player()
	_walk_to(player, CAMP_CELL + Vector2i(1, 0))
	_check(_main.held_camp(CAMP_CELL) == _camp and _main.held_camp(CAMP_CELL + Vector2i(9, 0)) == "",
			"cleared with a player in it: held; a cell outside it is not")
	for slot: int in _main._dead_since:
		_main._dead_since[slot] = World.tick - _main.RESPAWN_DELAY_TICKS
	_main._respawned_at.clear()
	_main._arrived_at.clear()
	_step(_main.RESPAWN_STAGGER_TICKS * 3)
	_check(_slot_entity(IMP_SLOT) == null and _main._dead_since.has(IMP_SLOT) and World.tick - int(_main._dead_since[IMP_SLOT]) <= _main.RESPAWN_STAGGER_TICKS,
			"long past its wait, the imp stays down while the camp is occupied, its wait starting over (%d ticks)" % (World.tick - int(_main._dead_since.get(IMP_SLOT, 0))))
	_walk_to(player, Vector2i(12, 1))
	var left := World.tick
	_main._respawned_at.clear()
	_step(_main.RESPAWN_STAGGER_TICKS + 1)
	_check(_slot_entity(IMP_SLOT) == null and int(_main._dead_since.get(IMP_SLOT, 0)) >= left - _main.RESPAWN_STAGGER_TICKS,
			"left, it is not back at once: its full wait runs from when they left")
	_check(_main.held_camp(CAMP_CELL) == "", "nobody in it: not held")


## Decision 799, enemy-ai's side: the camp laid with "truce" (the Toll
## Camp's): the imp, of its band, lets a player beside it be and goes after
## no din; a camp trader is nobody's foe; the player's blow turns the whole
## band (both slots in the camp); the camp changing hands brings the truce
## back. The plain camp is laid after.
func _test_truce() -> void:
	print("
== a camp's truce (799, enemy-ai's side) ==")
	var zone: String = World.zone.name
	var rows: Array[String] = []
	for y in 2 * 20 - 1:
		rows.append(".".repeat(2 * 30 - 1))
	Level.register(zone, Level.image_from_rows(rows), null, {"outdoor": true, "places": {
		"camp": {"at": [CAMP_CELL.x, CAMP_CELL.y], "kind": "camp", "holder": "goblins", "radius": 1, "worth": 4, "truce": true},
		"post": {"at": [20, 20], "kind": "other", "truce": true}}})
	var names: Array[String] = [zone]
	World.holdings = Holdings.new(WorldMap.build(names), Factions.read(), {}, func() -> int: return World.steps)
	var camp := "%s/camp" % zone
	_check(World.holdings.place(camp).get("truce", false) and not World.holdings.place("%s/post" % zone).has("truce"),
		"a camp's truce is read; on a place not a camp it is left out")
	var band: Array[Monster] = []
	for entity in World.get_entities():
		if entity is Monster and not entity is Animal and entity.spawned:
			if _main._within((entity as Monster).home, CAMP_CELL, 1):
				band.append(entity)
	var imp := _slot_entity(IMP_SLOT) as Monster
	_check(imp != null and imp in band and imp.truce_camp() == camp and imp.in_truce(),
		"the imp is of the camp's band, its truce holding (%s, band %d)" % [imp.truce_camp() if imp != null else "?", band.size()])
	# Its pick asked straight, with no steps: the room's companion goes for
	# monsters on sight (her own side of the truce is companions').
	var player := _player()
	var graced: bool = player.protected
	player.protected = false  # Out of its spawn grace, so only the truce keeps it out of the fight.
	_check(player != null and imp._nearest_visible_target() != player and not imp.threatens(player),
		"a player in the room is let be (picks %s)" % [imp._nearest_visible_target()])
	var alert_was: int = imp.alert
	imp._heard({"at": imp.tile + Vector2i(1, 0), "kind": &"fight", "radius": 8, "source": player, "tick": World.tick})
	_check(imp.alert == alert_was, "a din near it is not minded")
	var trader := Resident.new()
	trader.camp_trader = "forest/southeast_camp_trader"  # npc's 799: his place id.
	var townsfolk := Resident.new()
	_check(Monster.camp_trader(trader) and not Monster.camp_trader(townsfolk) and not Monster.camp_trader(player),
		"a camp trader is told by Resident.camp_trader, townsfolk and players not")
	imp.foes.append("town")
	_check(not imp._may_fight(trader), "a camp trader is no foe, even to a side that fights the town")
	imp.foes.erase("town")
	trader.free()
	townsfolk.free()
	World.damage(imp, 1, player)
	_check(not imp.in_truce() and band.all(func(each: Monster) -> bool: return not each.in_truce()),
		"the player's blow breaks it for the whole band (%d)" % band.size())
	_check(imp.threatens(player) and band.all(func(each: Monster) -> bool: return each.threatens(player)),
		"the band would fight the player now")
	World.steps += 1
	World.holdings.take(camp, Factions.NOBODY)
	World.steps += 1
	World.holdings.take(camp, "goblins")
	_check(imp.in_truce(), "the camp fallen and retaken, its band keeps the truce again")
	imp.struck_by = null
	player.protected = graced
	imp.hp = imp.max_hp
	Monster.truce_broken.clear()
	for each in band:
		each._truce_camp = "?"


## The player on their feet: one beaten down by the camp's monsters while
## it held (five on a free body standing still) bleeds out and is back.
func _standing_player() -> Player:
	var player := _player()
	if player != null and not World.is_downed(player):
		return player
	if player != null:
		World.damage(player, player.hp, null, &"bled")
	for i in _main.RESPAWN_TICKS * 4:
		World.step()
		if _player() != null and _player() != player:
			break
	return _player()


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
	Walk.to(entity, tile, 240)  # A free body (703): its commands, a tick at a time.


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
