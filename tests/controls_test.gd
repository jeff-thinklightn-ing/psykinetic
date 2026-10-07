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
	_test_scheme_default()
	_test_screen_lean()
	_test_drag_and_freeze()
	_test_diamonds()
	_test_tilt_keys()
	_test_pitch_peek()
	_test_middle_drag_axis()
	_test_schemes_are_inert_outside()
	_test_click_uses_the_frame_pick()

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


func _test_scheme_default() -> void:
	print("\n== click is the default scheme ==")
	_check(Net.controls_from("") == "click" and Net.controls_from("mouse") == "click", "nothing, or anything else: click")
	_check(Net.controls_from("wasd") == "wasd" and Net.controls_from(" WASD ") == "wasd", "wasd: WASD")


func _test_screen_lean() -> void:
	print("\n== the WASD lean comes from the cursor's place on the screen ==")
	var size := Vector2(1920, 1080)
	_check(Main.screen_lean(size * 0.5, size) == Vector2.ZERO, "the middle: no lean")
	_check(Main.screen_lean(size * 0.5 + Vector2(0.14 * 960, 0), size) == Vector2.ZERO,
			"inside the dead zone (14% of half the width out): no lean")
	var edge := Main.screen_lean(Vector2(1920, 540), size)
	_check(edge.is_equal_approx(Vector2(1, 0)), "the right edge: a full lean right (%s)" % edge)
	var corner := Main.screen_lean(Vector2(0, 0), size)
	_check(is_equal_approx(corner.length(), 1.0), "a corner: no more than a full lean (%s)" % corner)
	var right := Main.lean_to_ground(Vector2(1, 0), 0.0)
	_check(Iso.project(right).x > 0.0 and is_zero_approx(Iso.project(right).y),
			"yaw 0: a lean right is right on the 2D screen (%s)" % right)
	var down := Main.lean_to_ground(Vector2(0, 1), 90.0)
	_check(down.is_equal_approx(Main.lean_to_ground(Vector2(0, 1), 0.0).rotated(-PI * 0.5)),
			"and it turns with the yaw (%s)" % down)


func _test_drag_and_freeze() -> void:
	print("\n== WASD: a middle drag turns the camera, settles on a diamond, never under a held key ==")
	var saved: String = Net.controls
	Net.controls = "wasd"
	var rig := _rig()
	var start := rig.yaw
	rig.begin_drag()
	rig.drag(20.0)
	_check(is_equal_approx(rig.yaw, start + 20.0), "the drag turns it at once (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start), "let go at 20: back to the nearest diamond (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(50.0)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 90.0), "let go at 50: on to the next diamond (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(170.0)
	_check(is_equal_approx(rig.yaw, start + 260.0), "a drag goes as far round as it likes (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 270.0), "and settles on the nearest diamond (%s)" % rig.yaw)
	start = rig.yaw
	rig.set_frozen(true)
	rig.begin_drag()
	rig.drag(100.0)
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start), "a key held: the drag does not turn it (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start), "nor does letting the button go (%s)" % rig.yaw)
	rig.set_frozen(false)
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 90.0), "the keys let go: it settles on the diamond nearest where the drag was let go (%s)" % rig.yaw)
	start = rig.yaw
	rig.begin_drag()
	rig.set_frozen(true)
	rig.drag(40.0)
	rig.set_frozen(false)
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 40.0), "a drag held through a run applies when the keys are let go (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	rig.set_frozen(true)
	rig._settle_on(rig._yaw_step + 90.0)
	var held := rig.yaw
	_ease(rig)
	_check(is_equal_approx(rig.yaw, held), "frozen, nothing turns it, not even an ease under way (%s)" % rig.yaw)
	rig.set_frozen(false)
	_ease(rig)
	Net.controls = saved
	_free_rig(rig)


func _test_diamonds() -> void:
	print("\n== click: the camera's home follows the way the player walks, damped; A/D look and spring back ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var rig := _rig()
	var player := _place_player(Vector2i(11, 3))
	rig._process(0.0)
	var puppet: Node3D = rig._puppets[player.get_instance_id()]
	var step := 1.0 / 60.0
	_check(is_equal_approx(rig.yaw, 0.0), "it starts on the 2D diamond (%s)" % rig.yaw)
	# Walking +x, down-right on screen at yaw 0: -90 puts that up the screen.
	_check(is_equal_approx(Client3D.home_for(Vector2(1, 0), 0.0), -90.0), "walking +x, the home that puts it up is -90")
	_walk(rig, puppet, Vector2(1, 0), 0.6, step)
	_check(is_equal_approx(rig.yaw, 0.0), "walking that way 0.6 s: not yet (%s)" % rig.yaw)
	var walked := 0.6
	while rig._home_t >= 1.0 and walked < 2.0:
		_walk(rig, puppet, Vector2(1, 0), step, step)
		walked += step
	_check(absf(walked - Client3D.HOME_HOLD_SECONDS) < step * 1.5 and is_equal_approx(rig._home_step, -90.0),
			"it turns toward -90 after %.2f s of that heading" % walked)
	# Straight away a new heading, held well past 0.7 s: the turn just begun
	# blocks another until 1.5 s after it.
	_walk(rig, puppet, Vector2(0, 1), 0.5, step)
	_check(absf(rig.yaw + 45.0) < 3.0, "half a second into the turn: half way (%.1f)" % rig.yaw)
	_walk(rig, puppet, Vector2(0, 1), 0.5, step)
	_check(is_equal_approx(rig.yaw, -90.0) and is_equal_approx(rig._home_step, -90.0),
			"a second in: there, and no new turn yet though the new heading is 1 s old (%s)" % rig.yaw)
	_check(rig._camera_target.is_equal_approx(puppet.position), "the player is the middle of the screen")
	_walk(rig, puppet, Vector2(0, 1), 0.45, step)
	_check(is_equal_approx(rig._home_step, -90.0), "1.45 s after the last turn began: still none")
	_walk(rig, puppet, Vector2(0, 1), 0.1, step)
	_check(rig._home_t < 1.0 and is_equal_approx(rig._home_step, -180.0),
			"1.5 s after it: the next turn (to %s)" % rig._home_step)
	_walk(rig, puppet, Vector2(0, 1), 1.1, step)
	_check(is_equal_approx(rig.yaw, -180.0), "on to -180 (%s)" % rig.yaw)
	_walk(rig, puppet, Vector2(-1, 0), 0.65, step)
	_walk(rig, puppet, Vector2.ZERO, 3.0, step)
	_check(is_equal_approx(rig.yaw, -180.0) and is_nan(rig._wanted_home),
			"a new heading walked 0.65 s, then standing 3 s: it never turns standing (%s)" % rig.yaw)
	_walk(rig, puppet, Vector2(-1, 0), 0.65, step)
	_check(is_equal_approx(rig._home_step, -180.0), "walking again: the count starts over (0.65 s, no turn)")
	_check(is_equal_approx(Client3D.home_for(Vector2(1, 0), -90.0), -90.0) and is_equal_approx(Client3D.home_for(Vector2(1, 0), 180.0), 180.0),
			"a heading half way between two diamonds keeps the home it has")
	_walk(rig, puppet, Vector2.ZERO, 2.0, step)
	var home := rig.home_yaw
	for i in 15:
		rig.look_by(1.0, 0.05)
		rig._update_home(0.05)
	_check(is_equal_approx(rig.look, 90.0) and is_equal_approx(rig.yaw, home + 90.0), "D held: a look up to 90 off the home (%s)" % rig.look)
	rig.end_look()
	rig._update_home(Client3D.LOOK_RETURN_SECONDS * 0.5)
	_check(rig.look > 0.0 and rig.look < 90.0, "let go: springing back (%.1f)" % rig.look)
	rig._update_home(Client3D.LOOK_RETURN_SECONDS * 0.5)
	_check(is_equal_approx(rig.yaw, home) and is_equal_approx(rig.look, 0.0), "back on the home at %d ms (%s)" % [
			roundi(Client3D.LOOK_RETURN_SECONDS * 1000.0), rig.yaw])
	for i in 15:
		rig.look_by(-1.0, 0.05)
	_check(is_equal_approx(rig.look, -90.0), "A: the other way, up to -90 (%s)" % rig.look)
	rig.end_look()
	rig._update_home(1.0)
	var path := OS.get_user_data_dir().path_join("home_test.cfg")
	var kept := [Net._settings_override, Net.player_id]
	Net._settings_override = path
	Net.save_settings("127.0.0.1", 17788, "", "Tester")
	_check(not "camera_yaw" in FileAccess.get_file_as_string(path), "no yaw is saved")
	DirAccess.remove_absolute(path)
	Net._settings_override = kept[0]
	Net.player_id = kept[1]
	Net.controls = saved
	_free_rig(rig)


## Moves [param puppet] along [param way] (grid units, at 4 cells a second;
## ZERO: standing) for [param seconds], a frame of [param step] at a time,
## letting the home follow.
func _walk(rig: Client3D, puppet: Node3D, way: Vector2, seconds: float, step: float) -> void:
	for i in roundi(seconds / step):
		puppet.position += Vector3(way.x, 0.0, way.y) * 4.0 * step
		rig._update_home(step)
		rig._camera_target = puppet.position
		rig._follow(step)


func _test_tilt_keys() -> void:
	print("\n== click: W/S tilt while held and spring back to 50 when let go ==")
	var rig := _rig()
	var yaw := rig.yaw
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "it starts at 50 (%s)" % rig.pitch)
	rig.tilt(1.0, 0.1)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH + 6.0), "W for 100 ms: 6 degrees up, 60 a second (%s)" % rig.pitch)
	var last := rig.pitch
	var slowest := INF
	var fastest := 0.0
	for i in 40:
		rig.tilt(1.0, 0.05)
		var moved := rig.pitch - last
		if moved > 0.0:
			slowest = minf(slowest, moved)
			fastest = maxf(fastest, moved)
		last = rig.pitch
	_check(is_equal_approx(rig.pitch, Client3D.PITCH_MAX), "held on: it stops at the top, %s" % rig.pitch)
	_check(slowest < fastest * 0.5, "slowing into the end (fastest %.2f, slowest %.2f a frame)" % [fastest, slowest])
	_check(is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE), "the size never changes (%s)" % rig._camera.size)
	rig.end_tilt()
	rig._ease_tilt(Client3D.TILT_RETURN_SECONDS * 0.5)
	_check(rig.pitch < Client3D.PITCH_MAX and rig.pitch > Client3D.CAMERA_PITCH, "let go: springing back (%s)" % rig.pitch)
	rig._ease_tilt(Client3D.TILT_RETURN_SECONDS * 0.5)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "back at 50 at %d ms (%s)" % [
			roundi(Client3D.TILT_RETURN_SECONDS * 1000.0), rig.pitch])
	for i in 60:
		rig.tilt(-1.0, 0.05)
	_check(is_equal_approx(rig.pitch, Client3D.PITCH_MIN), "S: down to %s" % rig.pitch)
	rig.end_tilt()
	_ease(rig)
	for i in 10:
		rig._ease_tilt(0.05)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "and back up to 50 when let go (%s)" % rig.pitch)
	_check(is_equal_approx(rig.yaw, yaw), "the yaw never moved (%s)" % rig.yaw)
	_free_rig(rig)


func _test_pitch_peek() -> void:
	print("\n== a vertical middle drag tilts toward top-down and springs back ==")
	var rig := _rig()
	_ease(rig)
	var yaw := rig.yaw
	var saved := Net.camera_yaw
	var near_before := _near_walls(rig)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE),
			"at rest: pitch %s, size %s" % [rig.pitch, rig._camera.size])
	rig.begin_pitch_peek()
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * 0.5)
	_check(is_equal_approx(rig.pitch, (Client3D.CAMERA_PITCH + Client3D.PEEK_PITCH) * 0.5),
			"half the drag: half way up, eased in and out (%s)" % rig.pitch)
	var quarter := rig.pitch
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * 0.25)
	_check(rig.pitch < quarter and rig.pitch - Client3D.CAMERA_PITCH < (quarter - Client3D.CAMERA_PITCH) * 0.5,
			"a quarter of it: less than half that, the ease starts gently (%s)" % rig.pitch)
	rig.pitch_peek(Client3D.PEEK_DRAG_PX * 2.0)
	_check(is_equal_approx(rig.pitch, Client3D.PEEK_PITCH)
			and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE * Client3D.PEEK_PULL_BACK),
			"past the full drag, either way: top-down at %s and pulled back to %s" % [rig.pitch, rig._camera.size])
	_check(is_equal_approx(rig.yaw, yaw), "the yaw never moves (%s)" % rig.yaw)
	_check(_near_walls(rig) == near_before, "the same walls are near, and see-through, at the full tilt")
	rig.end_pitch_peek()
	rig._ease_peek(Client3D.PEEK_RETURN_SECONDS * 0.5)
	_check(rig.pitch > Client3D.CAMERA_PITCH and rig.pitch < Client3D.PEEK_PITCH, "let go: springing back (%s)" % rig.pitch)
	rig._ease_peek(Client3D.PEEK_RETURN_SECONDS * 0.5)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE),
			"back at rest after %d ms (pitch %s, size %s)" % [roundi(Client3D.PEEK_RETURN_SECONDS * 1000.0), rig.pitch, rig._camera.size])
	_check(is_equal_approx(rig.yaw, yaw) and is_equal_approx(Net.camera_yaw, saved), "yaw and saved yaw as they were")
	_free_rig(rig)


func _test_middle_drag_axis() -> void:
	print("\n== a middle drag is a turn or a tilt by the axis it moves on first ==")
	var rig := _rig()
	_ease(rig)
	var saved: String = Net.controls
	Net.controls = "wasd"
	var yaw := rig.yaw
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(3, 2))
	_check(not rig._dragging and not rig._peeking, "wasd: under %d px it is not yet either" % Main.DRAG_AXIS_PX)
	_main._middle_drag(Vector2(40, 10))
	_check(rig._dragging and is_equal_approx(rig.yaw, yaw + 40.0 * Main.DRAG_DEGREES_PER_PX), "sideways first: a turn (%s)" % rig.yaw)
	_main._middle_drag(Vector2(40, 300))
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "and it stays a turn: moving up and down then does not tilt")
	_main._end_middle_drag()
	_ease(rig)
	yaw = rig.yaw
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(2, -20))
	_check(rig._peeking and not rig._dragging and rig.pitch > Client3D.CAMERA_PITCH, "up and down first: a tilt (%s)" % rig.pitch)
	_main._middle_drag(Vector2(300, -20))
	_check(is_equal_approx(rig.yaw, yaw), "and it stays a tilt: moving sideways then does not turn (%s)" % rig.yaw)
	_main._end_middle_drag()
	for i in 10:
		rig._ease_peek(0.05)
	Net.controls = "click"
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(300, 0))
	_check(is_equal_approx(rig.yaw, yaw) and not rig._dragging, "click: a sideways middle drag does nothing (%s)" % rig.yaw)
	_main._end_middle_drag()
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(0, -150))
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and not rig._peeking, "nor does an up and down one (%s)" % rig.pitch)
	_main._end_middle_drag()
	var before := rig.pitch
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(2, 1))
	_main._end_middle_drag()
	_check(is_equal_approx(rig.pitch, before) and rig._tilt_t >= 1.0, "a middle click does nothing either")
	Net.controls = saved
	_free_rig(rig)


## Wall edge keys the 3D view has see-through now.
func _near_walls(rig: Client3D) -> Array[Vector3i]:
	var near: Array[Vector3i] = []
	for key: Vector3i in rig._walls:
		if rig._is_near(key):
			near.append(key)
	return near


func _test_schemes_are_inert_outside() -> void:
	print("\n== keys and buttons outside the active scheme do nothing ==")
	var rig := _rig()
	var saved: String = Net.controls
	var step := rig._yaw_step
	Net.controls = "wasd"
	_main._unhandled_input(_key(KEY_Q))
	_check(is_equal_approx(rig._yaw_step, step), "wasd: Q does nothing")
	Net.controls = "click"
	_main._unhandled_input(_key(KEY_Q))
	_main._unhandled_input(_key(KEY_E))
	_check(is_equal_approx(rig._yaw_step, step), "click: a Q or E press steps nothing round")
	_main._unhandled_input(_middle(true))
	_check(not rig._peeking and not rig._dragging, "click: the middle button neither peeks nor turns")
	_main._unhandled_input(_middle(false))
	Net.test_walk = [{"keys": "wqed", "seconds": 5.0}] as Array[Dictionary]
	_main._walk_index = -1
	var pitch := rig.pitch
	var yaw := rig.yaw
	var size := rig._camera.size
	_main._drive_camera_keys(0.1)
	rig._update_home(0.0)
	_check(rig.pitch > pitch and rig.yaw > yaw and is_equal_approx(rig._camera.size, size),
			"click: W tilts up and D looks round; Q and E do nothing")
	Net.controls = "wasd"
	pitch = rig.pitch
	yaw = rig.yaw
	_main._drive_camera_keys(0.1)
	_check(is_equal_approx(rig.pitch, pitch) and is_equal_approx(rig.yaw, yaw), "wasd: they leave the camera alone")
	Net.test_walk = [] as Array[Dictionary]
	Net.controls = "click"
	_main._drive_camera_keys(0.1)
	Net.controls = "wasd"
	_main._unhandled_input(_middle(true))
	_main._middle_drag(Vector2(20, 0))
	_check(rig._dragging, "wasd: a sideways middle drag turns")
	_main._unhandled_input(_middle(false))
	Net.controls = "click"
	var player := _place_player(Vector2i(11, 3))
	Net.test_walk = [{"keys": "s", "seconds": 5.0}] as Array[Dictionary]
	_main._walk_index = -1
	_main._drive_wasd()
	_check(player.queued_steps.is_empty(), "click: a movement key held sends no step")
	Net.controls = "wasd"
	_main._drive_wasd()
	_check(player.queued_steps.size() == 1, "wasd: it does")
	Net.test_walk = [] as Array[Dictionary]
	player.queued_steps.clear()
	Net.controls = saved
	_free_rig(rig)


func _test_click_uses_the_frame_pick() -> void:
	print("\n== a click goes to the cell the hover shows ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(11, 3))
	_main._pick_grid = Vector2(9.2, 6.1)
	_check(_main._mouse_tile() == Vector2i(9, 6), "the frame's pick is the hover cell")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_main._unhandled_input(click)
	click.pressed = false
	_main._unhandled_input(click)
	_check(player.has_move_order and player.move_order == Vector2i(9, 6),
			"and the click sends the player there (%s)" % player.move_order)
	player.has_move_order = false
	Net.controls = saved


# --- helpers ------------------------------------------------------------------

## A 3D view on the room, hung on Main as its own would be, for the camera
## and the scheme tests.
func _rig() -> Client3D:
	var rig: Client3D = preload("res://client3d/client3d.tscn").instantiate()
	Net.camera_yaw = 0.0
	_main.add_child(rig)
	rig.setup(_main._terrain)
	rig.set_process(false)
	_main._client3d = rig
	return rig


func _free_rig(rig: Client3D) -> void:
	_main._client3d = null
	rig.queue_free()


## Long enough for any ease to finish.
func _ease(rig: Client3D) -> void:
	for i in 20:
		rig._ease_yaw(0.05)


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


func _middle(pressed: bool) -> InputEventMouseButton:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_MIDDLE
	button.pressed = pressed
	return button



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
