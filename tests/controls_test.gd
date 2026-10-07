extends Node
## WASD and the orders behind the hand, against the real room in main.tscn:
## the key-to-direction mapping at every camera yaw (checked against a real
## Camera3D), the server's step queue and its timer, refusals, a move
## order's via tiles, and the swing. Run it with tests/run.ps1 or
## tests/run.sh. Prints PASS/FAIL per assertion and quits with exit code 1
## if any assertion failed, 0 otherwise.

const KEYS := {
	"w": Vector2(0, 1), "s": Vector2(0, -1), "a": Vector2(-1, 0), "d": Vector2(1, 0),
	"wd": Vector2(1, 1), "wa": Vector2(-1, 1), "sd": Vector2(1, -1), "sa": Vector2(-1, -1),
}

var _failures := 0
var _main: Node
var _swings: Array[Vector2i] = []


func _ready() -> void:
	World.set_process(false)
	Net.port = 17788  # Not 7777: the editor may be hosting there.
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	World.entity_swung.connect(func(_entity: GridEntity, direction: Vector2i) -> void: _swings.append(direction))

	_test_wasd_mapping()
	_test_steps_take_the_timer()
	_test_release_stops()
	_test_refused_step_and_stale_steps()
	_test_order_walks_via_first()
	_test_swing()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_wasd_mapping() -> void:
	print("\n== WASD is screen-relative at every 45 degree yaw ==")
	_check(Main.wasd_direction(KEYS["w"], 0.0) == Vector2i(-1, -1), "yaw 0: W is (-1, -1), up the 2D diamond")
	_check(Iso.project(Vector2(-1, -1)).x == 0.0 and Iso.project(Vector2(-1, -1)).y < 0.0,
			"and (-1, -1) is straight up in the 2D view")
	# A camera rigged as Client3D rigs its own, in a viewport of its own.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Client3D.CAMERA_SIZE
	viewport.add_child(camera)
	var rig := Client3D.new()
	var all_ok := true
	for step in 8:
		var yaw := step * 45.0
		rig.yaw = yaw
		camera.position = rig._camera_offset()
		camera.look_at(Vector3.ZERO, Vector3.UP)
		var seen: Dictionary[Vector2i, bool] = {}
		for name: String in KEYS:
			var keys: Vector2 = KEYS[name]
			var got := Main.wasd_direction(keys, yaw)
			seen[got] = true
			# The grid direction that looks most like those keys on screen
			# (screen y grows downward, W is up).
			var wanted := Vector2(keys.x, -keys.y).normalized()
			var best := Vector2i.ZERO
			var best_dot := -INF
			for direction in World.DIRECTIONS:
				var on_screen := camera.unproject_position(Vector3(direction.x, 0, direction.y)) \
						- camera.unproject_position(Vector3.ZERO)
				var dot := on_screen.normalized().dot(wanted)
				if dot > best_dot:
					best = direction
					best_dot = dot
			if got != best:
				all_ok = false
				_check(false, "yaw %d, %s: %s, but %s points that way on screen" % [yaw, name, got, best])
		if seen.size() != 8:
			all_ok = false
			_check(false, "yaw %d: the eight key sets give %d directions" % [yaw, seen.size()])
	_check(all_ok, "eight key sets x eight yaws: each key set walks the way it points on screen, all eight distinct")
	_check(Main.wasd_direction(Vector2.ZERO, 45.0) == Vector2i.ZERO, "no keys: no direction")
	rig.free()
	viewport.queue_free()


func _test_steps_take_the_timer() -> void:
	print("\n== WASD steps go at 4 cells a second, one per free tick ==")
	_kill_monsters()
	var player := _place_player(Vector2i(11, 3))
	var start := player.tile
	# A client sends the next step as the last one ends; here, whenever the
	# queue is empty.
	var moved_at: Array[int] = []
	var at := player.tile
	for i in 20:
		if player.queued_steps.is_empty():
			World.order_step(player, Vector2i(0, 1) if player.tile.y < 6 else Vector2i(-1, 0), player.refusals, true)
		World.step()
		if player.tile != at:
			moved_at.append(World.tick)
			at = player.tile
	_check(moved_at.size() == 8, "8 steps in 20 ticks (%d: on ticks %s)" % [moved_at.size(), moved_at])
	var gaps: Array[int] = []
	for i in range(1, moved_at.size()):
		gaps.append(moved_at[i] - moved_at[i - 1])
	_check(gaps.all(func(gap: int) -> bool: return gap == 2 or gap == 3) and gaps.count(2) >= 3 and gaps.count(3) >= 3,
			"steps 2 and 3 ticks apart, alternating (%s): 2.5 on average" % [gaps])
	_check(is_equal_approx(player._move_duration, 2.5), "each drawn over 2.5 ticks (%s)" % player._move_duration)
	_check(World.distance(start, player.tile) >= 4, "and they went where they were sent (%s -> %s)" % [start, player.tile])


func _test_release_stops() -> void:
	print("\n== letting go stops on the cell being entered ==")
	var player := _place_player(Vector2i(11, 3))
	World.order_step(player, Vector2i(0, 1), player.refusals, true)
	World.step()
	_check(player.tile == Vector2i(11, 4), "one step taken (%s)" % player.tile)
	for i in 10:
		World.step()
	_check(player.tile == Vector2i(11, 4), "nothing more sent: it stays (%s)" % player.tile)


func _test_refused_step_and_stale_steps() -> void:
	print("\n== a refused step ends the walk; steps sent before the client knew are dropped ==")
	var player := _place_player(Vector2i(11, 3))
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "BlockImp", "tile": Vector2i(11, 4), "props": {"mass": 200.0}}) as Monster
	imp.sight_range = 0
	_wait_free(player)
	var before := player.refusals
	World.order_step(player, Vector2i(0, 1), player.refusals, true)
	World.order_step(player, Vector2i(0, 1), player.refusals, true)
	World.step()
	_check(player.tile == Vector2i(11, 3), "the step into the imp is refused")
	_check(player.refusals == before + 1 and player.queued_steps.is_empty(), "the count goes up and the rest of the queue goes")
	World.order_step(player, Vector2i(1, 0), before, true)
	_check(player.queued_steps.is_empty(), "a step sent with the old count is dropped")
	World.order_step(player, Vector2i(1, 0), player.refusals, true)
	_check(player.queued_steps.size() == 1, "one sent with the new count is queued")
	World.step()
	_check(player.tile == Vector2i(12, 3), "and taken (%s)" % player.tile)
	World.despawn(imp)


func _test_order_walks_via_first() -> void:
	print("\n== a move order walks the steps its client already shows first ==")
	var player := _place_player(Vector2i(11, 3))
	# Straight down is the path to (11, 6); the client was showing a step
	# to (10, 4) when the order went.
	var via: Array[Vector2i] = [Vector2i(10, 4)]
	World.order_move(player, Vector2i(11, 6), via)
	World.step()
	_check(player.tile == Vector2i(10, 4), "the via tile first (%s)" % player.tile)
	for i in 12:
		World.step()
	_check(player.tile == Vector2i(11, 6), "then on to the target (%s)" % player.tile)
	_place_player(Vector2i(11, 3))
	World.order_move(player, Vector2i(11, 6), [Vector2i(11, 3), Vector2i(11, 4)] as Array[Vector2i])
	World.step()
	_check(player.tile == Vector2i(11, 4), "a via tile it already stands on is skipped (%s)" % player.tile)


func _test_swing() -> void:
	print("\n== a swing at air: facing, cooldown, and the lunge, with nothing hit ==")
	var player := _place_player(Vector2i(11, 3))
	_wait_free(player)
	_swings.clear()
	World.order_swing(player, Vector2i(-1, 0))
	World.step()
	_check(_swings.size() == 1 and _swings[0] == Vector2i(-1, 0), "swung west (%s)" % [_swings])
	_check(player.facing == Vector2i(-1, 0) and player.next_attack_tick > World.tick, "faces west, attack cooling down")
	World.order_swing(player, Vector2i(1, 0))
	World.step()
	_check(_swings.size() == 1, "a second swing waits for the cooldown")


# --- helpers ------------------------------------------------------------------

func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


## The host's player, moved to [param tile] with nothing queued.
func _place_player(tile: Vector2i) -> Player:
	var player := _player()
	player.queued_steps.clear()
	player.has_move_order = false
	player.action_order = GridEntity.Order.NONE
	if player.tile != tile:
		var occupant := World.get_entity_at(tile)
		if occupant != null and occupant != player:
			World.despawn(occupant)
		World._relocate(player, tile)
	_wait_free(player)
	return player


func _wait_free(entity: GridEntity) -> void:
	while World.tick < maxf(entity.next_move_tick, entity.next_attack_tick):
		World.step()


func _kill_monsters() -> void:
	for entity in World.get_entities():
		if entity is Monster or entity is Companion:
			World.damage(entity, 999)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
