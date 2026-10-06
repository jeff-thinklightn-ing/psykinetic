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
	Net.port = 17782  # Not 7777: the editor may be hosting there.
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)

	_test_respawn_waits_for_time_and_distance()
	_test_crate_respawns_at_its_spawn_tile()
	_test_console()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_respawn_waits_for_time_and_distance() -> void:
	print("\n== a dead monster respawns after the delay, once players are clear ==")
	var player := _player()
	var imp := _slot_entity(4)  # Imp2 in LEVEL_ENTITIES
	var spawn_tile: Vector2i = imp.start_tile
	_check(spawn_tile == Vector2i(3, 6), "slot 4 is the imp at (3, 6)")
	_kill_monsters()  # So nothing interferes with the walk; they all become dead slots.
	var died_at := World.tick
	_check(_slot_entity(4) == null and _monsters() == 0, "killed")

	_walk_to(player, spawn_tile)
	_check(player.tile == spawn_tile, "player stands on the spawn tile (at %s)" % player.tile)
	while World.tick < died_at + _main.RESPAWN_DELAY_TICKS + 5:
		World.step()
	_check(_slot_entity(4) == null, "no respawn with a player on the tile, even %d ticks after death" % (World.tick - died_at))
	_check(_monsters() == 0, "nor of any other monster within %d tiles (%d)" % [_main.RESPAWN_MIN_DISTANCE, _monsters()])

	_walk_to(player, Vector2i(9, 6))
	_check(World.distance(player.tile, spawn_tile) == _main.RESPAWN_MIN_DISTANCE and _slot_entity(4) == null,
			"still nothing with the player exactly %d tiles away" % _main.RESPAWN_MIN_DISTANCE)
	# Other slots are 7 or more tiles from here and come back; the imp next
	# door would walk through the tile under test, so kill them again.
	for i in 3:
		World.step()
	_kill_monsters()
	_check(_slot_entity(4) == null, "the slot under test is still dead")
	World.order_move(player, Vector2i(10, 6))
	World.step()
	World.step()  # move_ticks: the step lands on the second tick.
	_check(player.tile == Vector2i(10, 6), "player is 7 tiles from the spawn tile (at %s)" % player.tile)
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
	while World.tick < died_at + _main.RESPAWN_DELAY_TICKS + 1:
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
	_check(reply.begins_with("room rebuilt"), "'reset' rebuilds the room (%s)" % reply)
	var fresh := _slot_entity(5)
	_check(fresh != null and fresh.spawned and fresh.tile == Vector2i(8, 2), "the broken crate is back at its spawn tile")
	_check(_player() != null and _player().tile == was_at, "the host player is back where it was, from its record")


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


func _kill_monsters() -> void:
	for entity in World.get_entities():
		if entity is Monster:
			World.damage(entity, 999)


func _walk_to(entity: GridEntity, tile: Vector2i) -> void:
	World.order_move(entity, tile)
	for i in 120:
		if entity.tile == tile:
			return
		World.step()


## Shoves, waiting out the cooldown and the mid-step rule first.
func _shove(attacker: GridEntity, target: GridEntity) -> void:
	while World.tick < maxi(attacker.next_attack_tick, attacker.next_move_tick):
		World.step()
	World.order_shove(attacker, target)
	World.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
