extends Node
## Level respawn and the server console, against the real room in main.tscn.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.
##
## Everything happens inside one frame, so nodes that died are still waiting
## to be freed; entities are therefore found by spawn slot, never by name.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	# The grid's steps: free walk is the default (decision 693).
	Net.free_walk = false
	World.free_walk = false
	Net.port = preload("res://tests/test_ports.gd").of(17782)  # Not 7777: the editor may be hosting there.
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)

	_check(_main.minimap.texture != null, "a host's minimap is drawn at boot (ui's report: it was left blank)")
	_test_respawn_waits_for_time_and_distance()
	_test_crate_respawns_at_its_spawn_tile()
	_test_respawns_staggered()
	_test_wake_spaced()
	_test_console()
	_test_player_reset()
	_test_old_snapshot_gets_current_looks()
	_test_click_snaps_to_floor()
	_test_renderer_setting()
	_test_player_body()
	_test_closed_link()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_respawn_waits_for_time_and_distance() -> void:
	print("\n== a dead monster respawns after the delay, once players are clear ==")
	var player := _player()
	var imp := _slot_entity(4)  # Imp2 in LEVEL_ENTITIES
	var spawn_tile: Vector2i = imp.start_tile
	_check(spawn_tile == Vector2i(2, 6), "slot 4 is the imp at (2, 6)")
	_kill_monsters()  # So nothing interferes with the walk; they all become dead slots.
	var died_at := World.tick
	_check(_slot_entity(4) == null and _monsters() == 0, "killed")

	_walk_to(player, spawn_tile)
	_check(player.tile == spawn_tile, "player stands on the spawn tile (at %s)" % player.tile)
	while World.tick < died_at + _main.RESPAWN_DELAY_TICKS + 5:
		World.step()
	_check(_slot_entity(4) == null, "no respawn with a player on the tile, even %d ticks after death" % (World.tick - died_at))
	_check(_monsters() == 0, "nor of any other monster within %d tiles (%d)" % [_main.RESPAWN_MIN_DISTANCE, _monsters()])

	_walk_to(player, Vector2i(8, 6))
	_check(World.distance(player.tile, spawn_tile) == _main.RESPAWN_MIN_DISTANCE and _slot_entity(4) == null,
			"still nothing with the player exactly %d tiles away" % _main.RESPAWN_MIN_DISTANCE)
	# Other slots are 7 or more tiles from here and come back; the imp next
	# door would walk through the tile under test, so kill them again.
	for i in 3:
		World.step()
	_kill_monsters(4)
	_check(_slot_entity(4) == null, "the slot under test is still dead")
	# One of them came back just now: the stagger (decision 382) would hold
	# the imp RESPAWN_STAGGER_TICKS more. This checks the distance alone.
	_main._respawned_at.clear()
	World.order_move(player, Vector2i(9, 6))
	World.step()
	World.step()  # move_ticks: the step lands on the second tick.
	_check(player.tile == Vector2i(9, 6), "player is 7 tiles from the spawn tile (at %s)" % player.tile)
	var back := _slot_entity(4)
	_check(back is Monster and back.start_tile == spawn_tile, "the imp respawned on its spawn tile that same tick")
	_check(back != null and back.hp == back.max_hp and back.stamina == back.max_stamina, "at full stats")
	_kill_monsters()  # They would chase the player through the next test.


func _test_crate_respawns_at_its_spawn_tile() -> void:
	print("\n== a broken crate respawns at its spawn tile; a pushed one stays put ==")
	var player := _player()
	var crate := _slot_entity(5)  # Crate1 at (8, 2)
	var spawn_tile: Vector2i = crate.start_tile
	_walk_to(player, spawn_tile + Vector2i(1, 0))
	_shove(player, crate)
	var pushed_to: Vector2i = crate.tile
	_check(pushed_to != spawn_tile and crate.spawned, "crate was pushed off its spawn tile (to %s)" % pushed_to)
	World.damage(crate, 999)
	_check(not crate.spawned, "and broken there")
	_walk_to(player, Vector2i(12, 12))
	_kill_monsters()
	var died_at := World.tick
	# The monsters fall due with it, one a RESPAWN_STAGGER_TICKS (382).
	while World.tick < died_at + _main.RESPAWN_DELAY_TICKS + 7 * _main.RESPAWN_STAGGER_TICKS and _slot_entity(5) == null:
		World.step()
	var back := _slot_entity(5)
	_check(back is Pushable and back.tile == spawn_tile, "a new crate is on the original spawn tile %s" % spawn_tile)
	_check(World.get_entity_at(pushed_to) == null, "not where the old one broke")
	_kill_monsters()

	var other := _slot_entity(6)  # Crate2 at (8, 3)
	var other_spawn: Vector2i = other.start_tile
	_walk_to(player, other_spawn + Vector2i(1, 0))
	_shove(player, other)
	_check(other.tile != other_spawn and other.spawned, "another crate is pushed but not broken (to %s)" % other.tile)
	for i in _main.RESPAWN_DELAY_TICKS + 1:
		World.step()
	_check(other.spawned and _slot_entity(6) == other and World.get_entity_at(other_spawn) == null,
			"it stays where it was pushed; nothing appears at its spawn tile")


func _test_respawns_staggered() -> void:
	print("
== due respawns come back one at a time, the farthest first; not near a player just come (382) ==")
	Monster.noticing = false  # The ones back stand still: nothing hunts the player meanwhile.
	var player := _player()
	_walk_to(player, Vector2i(12, 12))
	_kill_monsters()
	var slots: Array = _main._dead_since.keys()
	var away := func(slot: int) -> int: return World.distance(player.tile, _main._slot_spec(slot)["tile"])
	var farthest: int = slots.map(away).max()
	for slot: int in slots:
		_main._dead_since[slot] = World.tick - _main.RESPAWN_DELAY_TICKS
	_main._respawned_at.clear()
	World.step()
	var first: Array = slots.filter(func(slot: int) -> bool: return _slot_entity(slot) != null)
	_check(_monsters() == 1 and first.size() == 1 and away.call(first[0]) == farthest,
			"%d due at once: one comes back, %d tiles off, the farthest (%d)" % [slots.size(), away.call(first[0]) if first.size() == 1 else -1, farthest])
	for i in _main.RESPAWN_STAGGER_TICKS - 1:
		World.step()
	_check(_monsters() == 1, "no second within %d ticks" % _main.RESPAWN_STAGGER_TICKS)
	World.step()
	_check(_monsters() == 2, "a second at %d" % _main.RESPAWN_STAGGER_TICKS)

	_kill_monsters()
	for slot: int in slots:
		_main._dead_since[slot] = World.tick - _main.RESPAWN_DELAY_TICKS
	_main._respawned_at.clear()
	_main._arrived_at[_main._players.find_key(player)] = World.tick
	_check(slots.all(func(slot: int) -> bool: return away.call(slot) <= _main.RESPAWN_JOIN_DISTANCE), "every spawn within %d tiles of the player" % _main.RESPAWN_JOIN_DISTANCE)
	for i in _main.RESPAWN_ARRIVAL_TICKS - 1:
		World.step()
	_check(_monsters() == 0, "a player just come: nothing back within %d tiles for %d ticks" % [_main.RESPAWN_JOIN_DISTANCE, _main.RESPAWN_ARRIVAL_TICKS])
	World.step()
	World.step()
	_check(_monsters() == 1, "then the first, as before")
	_kill_monsters()
	Monster.noticing = true


func _test_wake_spaced() -> void:
	print("\n== a zone woken: one of its due dead now, the rest each a full wait apart; none in a just-come player's sight (382 amended (2)) ==")
	Monster.noticing = false
	var player := _player()
	var peer: int = _main._players.find_key(player)
	_walk_to(player, Vector2i(12, 12))
	_kill_monsters()
	var slots: Array = _main._dead_since.keys()
	for slot: int in slots:
		_main._dead_since[slot] = World.tick - 10 * _main.RESPAWN_DELAY_TICKS  # Long overdue, as after a long sleep.
	_main._respawned_at.clear()
	_main._arrived_at[peer] = World.tick - _main.RESPAWN_ARRIVAL_TICKS
	var zone_name: String = World.zone.name if World.zone != null else ""
	_main._woken[zone_name] = true
	World.step()
	_check(_monsters() <= 1, "%d long due on waking: one at most comes back (%d)" % [slots.size(), _monsters()])
	var back := _monsters()
	var due: Array = []
	for slot: int in _main._dead_since:
		due.append(_main._dead_since[slot] + _main._respawn_delay(slot))
	due.sort()
	var spaced := true
	for i in range(1, due.size()):
		spaced = spaced and due[i] - due[i - 1] >= _main.RESPAWN_DELAY_TICKS
	_check(due.size() == slots.size() - back and spaced and (back == 0 or due[0] >= World.tick + _main.RESPAWN_DELAY_TICKS - 1),
			"the rest (%d) each a full %d ticks after the one before (next at +%d)" % [due.size(), _main.RESPAWN_DELAY_TICKS, due[0] - World.tick if not due.is_empty() else -1])
	for i in _main.RESPAWN_DELAY_TICKS - 2:
		World.step()
	_check(_monsters() <= back + 1, "no more than one more within %d ticks (it was one every %d before)" % [_main.RESPAWN_DELAY_TICKS, _main.RESPAWN_STAGGER_TICKS])
	_kill_monsters()

	# The farthest floor tile in the player's sight (the room is small: the
	# player stands in a corner for it; the far one, (1, 1), is a link).
	_walk_to(player, Vector2i(14, 12))
	var far := player.tile
	for cell: Vector2i in World.floor_cells():
		if World.distance(player.tile, cell) > World.distance(player.tile, far) and World.has_line_of_sight(player.tile, cell):
			far = cell
	_check(World.distance(player.tile, far) > _main.RESPAWN_JOIN_DISTANCE, "a floor tile %d off in the player's sight (at %s)" % [World.distance(player.tile, far), far])
	_main._arrived_at[peer] = World.tick
	_check(_main._nearest_player(far, World.tick) == -1, "a player just come holds it back")
	_check(_main._nearest_player(far, World.tick + _main.RESPAWN_ARRIVAL_TICKS) > 0, "not after %d ticks" % _main.RESPAWN_ARRIVAL_TICKS)
	_main._arrived_at[peer] = World.tick - _main.RESPAWN_ARRIVAL_TICKS
	Monster.noticing = true


func _test_console() -> void:
	print("\n== server console ==")
	_kill_monsters()
	_check(_monsters() == 0, "all monsters dead")
	var reply: String = _main.admin_command("respawn")
	_check(reply == "respawned 5", "'respawn' brings them all back at once (%s)" % reply)
	_check(_monsters() == 5, "five monsters again")
	reply = _main.admin_command("players")
	_check(reply.begins_with("1 connected") and "Player1" in reply and "dev-host" in reply,
			"'players' lists the host (%s)" % reply.replace("\n", " / "))
	reply = _main.admin_command("save")
	_check(reply == "no --state file to save to", "'save' without --state says so (%s)" % reply)
	reply = _main.admin_command("nonsense")
	_check(reply.begins_with("unknown command"), "an unknown command is reported (%s)" % reply)
	World.damage(_slot_entity(5), 999)
	var player := _player()
	var was_at: Vector2i = player.tile
	reply = _main.admin_command("reset")
	_check(reply.begins_with("test_room rebuilt"), "'reset' rebuilds the room (%s)" % reply)
	var fresh := _slot_entity(5)
	_check(fresh != null and fresh.spawned and fresh.tile == Vector2i(8, 2), "the broken crate is back at its spawn tile")
	_check(_player() != null and _player().tile == was_at, "the host player is back where it was, from its record")


func _test_player_reset() -> void:
	print("\n== a player's reset command rebuilds the room, while players may ==")
	World.damage(_slot_entity(5), 999)
	_check(_slot_entity(5) == null, "a crate is broken")
	# Sent as a client's R would arrive: for a player some other peer owns.
	_player().owner_peer = 77
	World.command(_player(), "reset", {})
	var crate := _slot_entity(5)
	_check(crate != null and crate.tile == Vector2i(8, 2), "a player's 'reset' command brings the room back")
	_check(_player() != null and _monsters() == 5, "with its player and all five monsters")

	Net.player_reset = false
	World.damage(_slot_entity(5), 999)
	_player().owner_peer = 77
	World.command(_player(), "reset", {})
	_check(_slot_entity(5) == null, "with --no-player-reset another peer's command does nothing")
	_player().owner_peer = Net.local_id
	World.command(_player(), "reset", {})
	_check(_slot_entity(5) != null, "but the authority's own player still can")
	Net.player_reset = true


func _test_old_snapshot_gets_current_looks() -> void:
	print("\n== level entities from an old snapshot look as the map says now ==")
	# As builds before the generic entity scene wrote it: a type, no shape, no
	# tint, no slot. The crate was pushed to (5, 5); the boulder to (9, 9).
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("respawn_test_old_world.json")
	var no_props := {"type": "Dictionary", "args": []}
	var file := FileAccess.open(Net.state_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "tick": 0, "players": [], "respawns": [], "entities": [
		{"type": "pushable", "name": "Crate1", "tile": [5, 5], "hp": 7, "stamina": 0, "facing": [0, 1], "props": no_props},
		{"type": "pushable", "name": "Boulder", "tile": [9, 9], "hp": 0, "stamina": 0, "facing": [0, 1], "props": no_props},
		{"type": "monster", "name": "Stray", "tile": [10, 4], "hp": 12, "stamina": 60, "facing": [0, 1], "props": no_props},
	]}))
	file.close()
	_main._start_level(true)

	var crate := _slot_entity(5)
	_check(crate != null and crate.tile == Vector2i(5, 5) and crate.hp == 7, "the crate is where the snapshot left it, with its hp")
	_check(crate != null and crate.spawn_spec.get("shape") == "cube" and crate.spawn_spec.get("tint") == Color(0.8, 0.6, 0.35),
			"and is the map's tan cube, not a bare white one")
	var boulder := _slot_entity(8)
	_check(boulder != null and boulder.tile == Vector2i(9, 9), "the boulder is where the snapshot left it")
	_check(boulder != null and boulder.spawn_spec.get("shape") == "sphere"
			and boulder.mass == 200.0 and boulder.body_material == GridEntity.BodyMaterial.STONE,
			"and is the map's round stone boulder, not a crate")
	var stray: GridEntity = World.get_entity_at(Vector2i(10, 4))
	_check(stray is Monster and not stray.spawn_spec.has("spawn"), "an entity that is not in the map is kept as saved")
	for i in _main.RESPAWN_DELAY_TICKS + 5:
		World.step()
	var crates := 0
	for entity in World.get_entities():
		if entity is Pushable and entity.spawn_spec.get("spawn") == 5:
			crates += 1
	# Something else may stand there (Pip, in a fight that drew the imps).
	_check(crates == 1 and not World.get_entity_at(Vector2i(8, 2)) is Pushable,
			"the crate holds its slot, so no second one respawns at its spawn tile")
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""


# --- helpers ------------------------------------------------------------------

func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player:
			return entity
	return null


## The live entity holding LEVEL_ENTITIES slot [param slot], or null.
func _slot_entity(slot: int) -> GridEntity:
	for entity in World.get_entities():
		if entity.spawned and entity.spawn_spec.get("spawn", -1) == slot:
			return entity
	return null


func _monsters() -> int:
	var count := 0
	for entity in World.get_entities():
		if entity is Monster and entity.spawned:
			count += 1
	return count


func _test_closed_link() -> void:
	print("\n== a closed link (decision 463) ==")
	var player := _player()
	var at := Vector2i(9, 4)
	_main.level["links"].append({"tile": at, "to_map": "nowhere_yet", "to_spawn": "", "one_way": false, "closed": true})
	var zone: String = World.zone.name
	_kill_monsters()  # Nobody to crowd the steps on and off.
	var before: int = _main.party_log.size()
	_walk_to(player, at)
	World.step()
	_walk_to(player, at + Vector2i(1, 0))
	_walk_to(player, at)
	World.step()
	var lines: Array[String] = _main.party_log.last(_main.party_log.size() - before)
	_check(player.tile == at and World.zone.name == zone and is_instance_valid(player) and player.spawned,
		"stepping on it goes nowhere (at %s in %s)" % [player.tile, World.zone.name])
	_check(lines.count("The way on is closed.") == 2, "and says the way on is closed, once each time stepped on (%s)" % [lines])
	_main.level["links"].pop_back()


## Kills every monster, and starts every dead slot's delay again from now
## (but [param keep]'s), so the ones still due under the stagger (382) do
## not come back into the next check one by one.
func _kill_monsters(keep := -1) -> void:
	for entity in World.get_entities():
		if entity is Monster:
			World.damage(entity, 999)
	for slot: int in _main._dead_since:
		if slot != keep:
			_main._dead_since[slot] = World.tick


func _walk_to(entity: GridEntity, tile: Vector2i) -> void:
	World.order_move(entity, tile)
	for i in 120:
		if entity.tile == tile:
			return
		World.step()


## Shoves, waiting out the cooldown and the mid-step rule first.
func _shove(attacker: GridEntity, target: GridEntity) -> void:
	while World.tick < maxf(attacker.next_attack_tick, attacker.next_move_tick):
		World.step()
	World.order_shove(attacker, target)
	World.step()


func _test_click_snaps_to_floor() -> void:
	print("\n== a move click off the floor goes to the nearest walkable cell ==")
	_check(_main._snap_to_floor(Vector2(3.0, 2.0)) == Vector2i(3, 2), "a click on floor is that cell")
	var across_the_wall := Vector2(0.3, 2.1)
	_check(not World.is_walkable(Iso.local_to_tile(_grid_point(across_the_wall))), "the point past the west wall is void")
	_check(_main._snap_to_floor(across_the_wall) == Vector2i(1, 2), "and snaps to the floor cell across the wall")
	_check(_main._snap_to_floor(Vector2(-0.4, -0.6)) == Vector2i(1, 1), "past the corner, the corner cell")
	_check(_main._snap_to_floor(Vector2(-2.6, 2.0)) == _main.NONE, "further than %.0f tiles from any floor: no target" % _main.SNAP_RANGE)
	_check(_main._snap_to_floor(Vector2(-1.9, 2.0)) == Vector2i(1, 2), "just inside that range: the nearest cell")
	_check(_main._snap_to_floor(Vector2(NAN, NAN)) == _main.NONE, "a point off the ground plane: no target")


## A point on the ground plane at continuous grid coordinates.
func _grid_point(grid: Vector2) -> Vector2:
	return Vector2((grid.x - grid.y) * Iso.HALF.x + Iso.HALF.x, (grid.x + grid.y) * Iso.HALF.y + Iso.HALF.y)


func _test_renderer_setting() -> void:
	print("\n== renderer: 3D unless 2d is asked for; the command line wins over the file ==")
	_check(Net.renderer_from("2d") == "2d" and Net.renderer_from(" 2D ") == "2d", "2d is the 2D view")
	_check(Net.renderer_from("3d") == "3d" and Net.renderer_from("") == "3d" and Net.renderer_from("iso") == "3d",
			"3d, nothing or anything else is the 3D view")
	var path: String = preload("res://tests/test_ports.gd").scratch_path("renderer_test.cfg")
	var saved := [Net._settings_override, Net.renderer, Net._renderer_given, Net._settings_renderer, Net.player_id]
	Net._settings_override = path
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("address=127.0.0.1
renderer=2d
")
	file.close()
	Net.renderer = "3d"
	Net._renderer_given = false
	Net._apply_renderer_setting()
	_check(Net.renderer == "2d", "renderer=2d in the file picks the 2D view")
	Net.renderer = "3d"
	Net._renderer_given = true
	Net._apply_renderer_setting()
	_check(Net.renderer == "3d", "--renderer on the command line wins over the file")
	Net.save_settings("127.0.0.1", 17782, "", "Tester")
	_check("renderer=2d" in FileAccess.get_file_as_string(path), "a rewrite keeps the file's renderer=, not the command line's")
	DirAccess.remove_absolute(path)
	Net._settings_override = saved[0]
	Net.renderer = saved[1]
	Net._renderer_given = saved[2]
	Net._settings_renderer = saved[3]
	Net.player_id = saved[4]


func _test_player_body() -> void:
	print("
== a player's body (decision 388): asked for at the join, kept on the record ==")
	_check(_player().body == Net.player_body, "the host's own player wears its setting (%s)" % _player().body)
	const SAM := 5
	const SAM_ID := "5a5a5a5a-0000-4000-8000-0000000000c2"
	Net._bodies[SAM_ID] = Net.tidy_body("female")
	_main._admit(SAM, SAM_ID, "Sam")
	var sam: Player = _main._players.get(SAM)
	var record: PlayerRecord = _main._records.get(SAM_ID)
	_check(sam != null and sam.body == &"female" and record.body == &"female",
			"a player who asks for the female body wears it, and the record keeps it")
	_main._leave(SAM, sam, SAM_ID)
	Net._bodies.erase(SAM_ID)  # As after a restart: not asked for this run.
	_main._admit(SAM, SAM_ID, "Sam")
	sam = _main._players.get(SAM)
	_check(sam != null and sam.body == &"female", "back without asking: the record's body")
	_main._leave(SAM, sam, SAM_ID)
	var back := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(back.body == &"female", "saved and loaded, the record keeps it")
	var old := record.to_dict()
	old.erase("body")
	_check(PlayerRecord.from_dict(old).body == &"male", "an older snapshot's record (no body) wears male")
	_check(Net.tidy_body("") == &"male" and Net.tidy_body("Female ") == &"female" and Net.tidy_body("x") == &"male",
			"tidy_body: female, else male")
	print("
== a player's look (decision 439): asked for at the join, cleaned, kept, in the spawn spec ==")
	Net._bodies[SAM_ID] = &"male"
	Net._looks[SAM_ID] = Net.tidy_look("seed=77 build=heavy hair=long skin=6")
	_main._admit(SAM, SAM_ID, "Sam")
	sam = _main._players.get(SAM)
	record = _main._records.get(SAM_ID)
	_check(sam != null and record.look == "seed=77 build=heavy hair=long skin=6"
			and str(sam.spawn_spec.get("look", "")) == record.look,
			"a player's chosen look is kept on the record and spawned in their spec (%s)" % record.look)
	_check(sam != null and Client3D.look_for(sam).keys.has("heavy") and "Hair_Long" in Client3D.look_for(sam).parts,
			"and drawn as it says: heavy, long hair")
	_main._leave(SAM, sam, SAM_ID)
	Net._bodies.erase(SAM_ID)
	Net._looks.erase(SAM_ID)
	_main._admit(SAM, SAM_ID, "Sam")
	sam = _main._players.get(SAM)
	_check(sam != null and str(sam.spawn_spec.get("look", "")) == "seed=77 build=heavy hair=long skin=6",
			"back without asking: the record's look")
	_main._leave(SAM, sam, SAM_ID)
	back = PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(back.look == record.look, "saved and loaded, the record keeps it")
	old = record.to_dict()
	old.erase("look")
	_check(PlayerRecord.from_dict(old).look == "", "an older snapshot's record has none (seeded by name)")
	# A look comes from any client and goes to every other: cleaned before it is kept.
	var junk := "seed=12 build=enormous hair=long hair=bald headwear=hood apron=yes age=old skin=9 skin=3 beard=full x=1 <b>=y seed=99"
	_check(Net.tidy_look(junk) == "seed=12 hair=long skin=3 beard=full",
			"tidy_look: only what a player may choose, known values, each once (%s)" % Net.tidy_look(junk))
	_check(Net.tidy_look("seed=-4 build=lean") == "build=lean" and Net.tidy_look("seed=123456789012 build=lean") == "build=lean"
			and Net.tidy_look("seed=4x hair=long") == "hair=long", "a seed a whole number in range, else dropped")
	var long := ""
	for i in 5000:
		long += "hair=long "
	_check(Net.tidy_look(long) == "hair=long" and Net.tidy_look("build=lean ".repeat(100) + "stature=tall").length() <= Net.MAX_LOOK_LENGTH,
			"a huge look is cut, never kept whole")
	Net._bodies[SAM_ID] = &"male"  # A join this run sends both.
	Net._looks[SAM_ID] = Net.tidy_look("build=" + "x".repeat(10000))
	_main._admit(SAM, SAM_ID, "Sam")
	sam = _main._players.get(SAM)
	_check(sam != null and str(sam.spawn_spec.get("look", "")) == "", "a junk look asked for is none")
	_main._leave(SAM, sam, SAM_ID)
	Net._bodies.erase(SAM_ID)
	Net._looks.erase(SAM_ID)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
