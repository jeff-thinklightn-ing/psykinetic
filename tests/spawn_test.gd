extends Node
## Where and how players are put down: spawn safety (not next to a hostile)
## and spawn grace (monsters leave a fresh spawn alone for a moment).
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = 17787  # Not 7777: the editor may be hosting there.
	Net.companions = false  # A companion would pick fights with the test's imps.
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_kill_monsters()

	_test_reconnect_avoids_hostiles()
	_test_respawn_avoids_hostiles()
	_test_spawn_grace()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_reconnect_avoids_hostiles() -> void:
	print("\n== coming back: the saved tile, unless a hostile is within 5 of it ==")
	var saved := Vector2i(6, 6)
	_walk_to(_player(), saved)
	_rejoin()
	_check(_player().tile == saved, "no hostile about: back on the saved tile (at %s)" % _player().tile)

	_leave()
	var imp := _spawn_imp(saved + Vector2i(2, 0))
	_join()
	var player := _player()
	# Of the start tiles, (12, 1) is the first that is 5 from an imp at (8, 6).
	_check(player.tile == Vector2i(12, 1), "hostile 2 tiles from the saved tile: put on the farthest start tile (at %s)" % player.tile)
	_check(World.distance(player.tile, imp.tile) == 5, "which is 5 from the hostile (%d)" % World.distance(player.tile, imp.tile))
	World.damage(imp, 999)

	_walk_to(player, saved)
	_leave()
	imp = _spawn_imp(saved + Vector2i(6, 0))
	_join()
	_check(_player().tile == saved, "hostile 6 tiles away is far enough: back on the saved tile (at %s)" % _player().tile)
	World.damage(imp, 999)


func _test_respawn_avoids_hostiles() -> void:
	print("\n== respawning after death: not at a start tile with a hostile near it ==")
	var imp := _spawn_imp(Vector2i(12, 2))
	World.damage(_player(), 999)
	_check(_player() == null, "player died")
	for i in _main.RESPAWN_TICKS + 1:
		World.step()
	var player := _player()
	# (11, 2), the usual first start tile, is 1 from the imp; (10, 1) is 2.
	_check(player != null and player.tile == Vector2i(10, 1), "respawned on the start tile farthest from the hostile (at %s)" % (player.tile if player else Vector2i(-1, -1)))
	_check(player != null and player.hp == player.max_hp, "at full hp")
	World.damage(imp, 999)


func _test_spawn_grace() -> void:
	print("\n== spawn grace: monsters ignore a fresh spawn for 30 ticks, or until it acts ==")
	_rejoin()
	var player := _player()
	_check(player.protected, "a newly spawned player is protected")
	var imp := _spawn_imp(player.tile + Vector2i(-3, 0))
	imp.sight_range = 7
	var imp_start := imp.tile
	for i in _main.SPAWN_GRACE_TICKS - 2:
		World.step()
	_check(player.protected and imp.tile == imp_start and player.hp == player.max_hp,
			"for 28 ticks a sighted imp 3 tiles away does nothing (imp at %s, hp %d)" % [imp.tile, player.hp])
	for i in 3:
		World.step()
	_check(not player.protected, "the grace runs out after %d ticks" % _main.SPAWN_GRACE_TICKS)
	for i in 30:
		World.step()
	_check(imp.tile != imp_start or player.hp < player.max_hp, "and then the imp comes for it (imp at %s, hp %d)" % [imp.tile, player.hp])
	World.damage(imp, 999)

	World.protect(player, _main.SPAWN_GRACE_TICKS)
	_check(player.protected, "protected again")
	World.order_move(player, player.tile + Vector2i(0, 1))
	World.step()
	_check(not player.protected, "moving ends the grace at once")

	World.protect(player, _main.SPAWN_GRACE_TICKS)
	imp = _spawn_imp(player.tile + Vector2i(1, 0))
	while World.tick < maxf(player.next_attack_tick, player.next_move_tick):
		World.step()
	_check(player.protected, "protected, with an imp beside it")
	World.order_attack(player, imp)
	World.step()
	_check(not player.protected, "attacking ends it too")


# --- helpers ------------------------------------------------------------------

func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _leave() -> void:
	_main._on_peer_disconnected(Net.local_id)


func _join() -> void:
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)


func _rejoin() -> void:
	_leave()
	_join()


func _spawn_imp(tile: Vector2i) -> Monster:
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "TestImp%d" % World.tick, "tile": tile}) as Monster
	imp.sight_range = 0  # Stands still unless a test turns it on.
	return imp


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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
