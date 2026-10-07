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
	_test_q_e_follow_the_character()
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
	print("\n== WASD: a middle drag turns the camera, never under a held key ==")
	var rig := _rig()
	var start := rig.yaw
	rig.begin_drag()
	rig.drag(20.0)
	_check(is_equal_approx(rig.yaw, start + 20.0), "the drag turns it at once (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start), "let go at 20: back to the nearest step (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(40.0)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start), "let go at 40, short of the axis view: back to the diamond (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(50.0)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 90.0) and is_equal_approx(Net.camera_yaw, fposmod(start + 90.0, 360.0)),
			"let go at 50: on to the next diamond, and kept (%s)" % rig.yaw)
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
	rig.drag(50.0)
	rig.set_frozen(false)
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 50.0), "a drag held through a run applies when the keys are let go (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	rig.set_frozen(true)
	rig._settle_on(rig._yaw_step + 90.0)
	var held := rig.yaw
	_ease(rig)
	_check(is_equal_approx(rig.yaw, held), "frozen, nothing turns it, not even an ease under way (%s)" % rig.yaw)
	rig.set_frozen(false)
	_ease(rig)
	_free_rig(rig)


func _test_diamonds() -> void:
	print("\n== the camera rests only on the four diamond views ==")
	var rig := _rig()
	_ease(rig)
	var start := rig.yaw
	_check(is_equal_approx(fmod(start, 90.0), 0.0), "it starts on a diamond (%s)" % start)
	for i in 6:
		rig.turn(1.0, 0.01)
	_check(is_equal_approx(rig.yaw, start + 10.8), "click, D held 60 ms: 10.8 degrees at 180 a second (%s)" % rig.yaw)
	var held := rig.yaw
	rig.end_turn()
	_check(is_equal_approx(rig._ease_to, start + 90.0), "let go more than 10 past: on to the next diamond (%s)" % rig._ease_to)
	rig._ease_yaw(0.01)
	_check(absf(rig.yaw - held - 1.8) < 0.1,
			"the first frame after letting go still moves at the turning speed (%.2f degrees in 10 ms)" % (rig.yaw - held))
	var last := rig.yaw
	var steady := true
	for i in 200:
		rig._ease_yaw(0.01)
		if rig.yaw < last - 0.0001:
			steady = false
		last = rig.yaw
	_check(steady and is_equal_approx(rig.yaw, start + 90.0), "and slows onto it without stopping first (%s)" % rig.yaw)
	_check(is_equal_approx(Net.camera_yaw, fposmod(start + 90.0, 360.0)), "saved as that diamond, within 0..360 (%s)" % Net.camera_yaw)
	start = rig.yaw
	for i in 5:
		rig.turn(-1.0, 0.01)
	rig.end_turn()
	_check(is_equal_approx(rig._ease_to, start), "A held 50 ms (9 degrees, short of 10): back to the diamond it came from")
	var furthest := rig.yaw
	for i in 100:
		rig._ease_yaw(0.01)
		furthest = minf(furthest, rig.yaw)
	_check(furthest < start - 9.0 and is_equal_approx(rig.yaw, start),
			"running on a little the way it went, then back (%.1f at most, ends %s)" % [furthest - start, rig.yaw])
	_check(is_equal_approx(Client3D.settle_target(95.0, 1.0), 90.0) and is_equal_approx(Client3D.settle_target(101.0, 1.0), 180.0)
			and is_equal_approx(Client3D.settle_target(-11.0, -1.0), -90.0) and is_equal_approx(Client3D.settle_target(90.0, 1.0), 90.0),
			"past a diamond, the 10 degrees count from the last one passed")
	rig.orbit(1)
	var seen: Array[float] = [rig.yaw]
	for i in 8:
		rig._ease_yaw(Client3D.ORBIT_SECONDS / 8.0)
		seen.append(rig.yaw)
	_check(is_equal_approx(seen[4], start + 45.0) and is_equal_approx(seen.back(), start + 90.0),
			"Q/E: a step to the next diamond, half way at 200 ms, there at 400 ms (%s)" % [seen])
	for yaw in [0.0, 90.0, 180.0, 270.0, -90.0]:
		_check(is_equal_approx(Net.saved_yaw(str(yaw), -1.0), yaw), "a saved diamond loads as it is (%s)" % yaw)
	_check(is_equal_approx(Net.saved_yaw("45", -1.0), 90.0) and is_equal_approx(Net.saved_yaw("135", -1.0), 180.0)
			and is_equal_approx(Net.saved_yaw("-45", -1.0), 0.0), "an old axis yaw rounds to a diamond on load (half way: up)")
	_check(is_equal_approx(Net.saved_yaw("30", -1.0), 0.0), "anything else to the nearest diamond")
	_check(is_equal_approx(Net.saved_yaw("", 90.0), 90.0) and is_equal_approx(Net.saved_yaw("north", 90.0), 90.0),
			"no value, or a bad one: kept as it was")
	_free_rig(rig)


func _test_q_e_follow_the_character() -> void:
	print("\n== click: Q/E look to the character's left and right, at the L corridor's corner ==")
	var rig := _rig()
	var saved: String = Net.controls
	Net.controls = "click"
	# The L: a leg north of (4, 18), x 3..4, and one east of it, rows 18..19.
	var corner := Vector2i(4, 18)
	var cases := [
		{"from": Vector2i(4, 15), "step": Vector2i(0, 1), "key": KEY_Q, "leg": Vector2(1, 0),
			"name": "walking south down the north leg, Q: the east leg, on the left"},
		{"from": Vector2i(8, 18), "step": Vector2i(-1, 0), "key": KEY_E, "leg": Vector2(0, -1),
			"name": "walking west along the east leg, E: the north leg, on the right"},
	]
	for entry: Dictionary in cases:
		var all_ok := true
		var seen: Array[String] = []
		for diamond in [0.0, 90.0, 180.0, 270.0]:
			var player := _place_player(entry["from"])
			while player.tile != corner:
				World.order_step(player, entry["step"], player.refusals, true)
				World.step()
				_wait_free(player)
			rig._ease_t = 1.0
			rig._yaw_step = diamond
			rig._set_yaw(diamond)
			_main._unhandled_input(_key(entry["key"]))
			_ease(rig)
			var up := Client3D.screen_up(rig.yaw)
			var leg: Vector2 = entry["leg"]
			var revealed := leg.dot(up) > 0.5
			var turned := is_equal_approx(absf(rig.yaw - diamond), 90.0)
			seen.append("%d->%d (up %s)" % [diamond, rig.yaw, up.snappedf(0.01)])
			if not (revealed and turned):
				all_ok = false
		_check(all_ok, "%s, toward the top of the screen from every diamond: %s" % [entry["name"], ", ".join(seen)])
	var player := _place_player(Vector2i(11, 3))
	World.order_step(player, Vector2i(0, 1), player.refusals, true)
	World.step()
	_check(GridEntity.side_of(player.heading(), -1) == Vector2(1, 0) and GridEntity.side_of(player.heading(), 1) == Vector2(-1, 0),
			"facing south (+y): left is east (+x), right is west")
	_check(Client3D.turn_raising(0.0, Client3D.screen_up(0.0), -1) == -1 and Client3D.turn_raising(0.0, Client3D.screen_up(0.0), 1) == 1,
			"a side already straight up the screen: Q turns one way, E the other")
	Net.controls = saved
	_free_rig(rig)


func _test_tilt_keys() -> void:
	print("\n== click: W/S tilt, sticky and saved; a middle click levels ==")
	var rig := _rig()
	var yaw := rig.yaw
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "it starts level (%s)" % rig.pitch)
	rig.tilt(1.0, 0.1)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH + 6.0), "W for 100 ms: 6 degrees up, 60 a second (%s)" % rig.pitch)
	_check(rig._camera.size > Client3D.CAMERA_SIZE, "and pulled back a little (%s)" % rig._camera.size)
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
	_check(is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE * Client3D.PEEK_PULL_BACK),
			"pulled back in step with the tilt, %s at the top" % rig._camera.size)
	rig.end_tilt()
	for i in 10:
		rig._process(0.05)
	_check(is_equal_approx(rig.pitch, Client3D.PITCH_MAX), "let go: it stays (%s)" % rig.pitch)
	_check(is_equal_approx(Net.camera_pitch, Client3D.PITCH_MAX), "and is saved (%s)" % Net.camera_pitch)
	for i in 60:
		rig.tilt(-1.0, 0.05)
	_check(is_equal_approx(rig.pitch, Client3D.PITCH_MIN) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE),
			"S: down to %s, at the usual size" % rig.pitch)
	rig.end_tilt()
	rig.level_pitch()
	_check(is_equal_approx(Net.camera_pitch, Client3D.CAMERA_PITCH), "a middle click saves the level pitch")
	rig._ease_level(Client3D.LEVEL_SECONDS * 0.5)
	_check(rig.pitch > Client3D.PITCH_MIN and rig.pitch < Client3D.CAMERA_PITCH, "and eases there (%s)" % rig.pitch)
	rig._ease_level(Client3D.LEVEL_SECONDS * 0.5)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "level at %d ms (%s)" % [roundi(Client3D.LEVEL_SECONDS * 1000.0), rig.pitch])
	_check(is_equal_approx(rig.yaw, yaw), "the yaw never moved (%s)" % rig.yaw)
	_check(is_equal_approx(Net.saved_pitch("70", -1.0), 70.0) and is_equal_approx(Net.saved_pitch("120", -1.0), Client3D.PITCH_MAX)
			and is_equal_approx(Net.saved_pitch("10", -1.0), Client3D.PITCH_MIN) and is_equal_approx(Net.saved_pitch("", 50.0), 50.0),
			"a saved pitch loads held to 40..85; none keeps the default")
	_free_rig(rig)
	_free_rig(_rig_with_pitch(72.0))


## A rig set up with a saved pitch: it must start there.
func _rig_with_pitch(degrees: float) -> Client3D:
	var rig := _rig(degrees)
	_check(is_equal_approx(rig.pitch, degrees) and is_equal_approx(rig._camera.size, Client3D.size_for(degrees)),
			"a saved pitch of %s is where a new view starts (%s)" % [degrees, rig.pitch])
	Net.camera_pitch = Client3D.CAMERA_PITCH
	return rig


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
	rig.tilt(1.0, 0.2)
	_main._end_middle_drag()
	_check(rig._level_t >= 1.0, "and a drag let go is no middle click: the tilt stays (%s)" % rig.pitch)
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(2, 1))
	_main._end_middle_drag()
	_check(rig._level_t < 1.0, "a middle click (a few px at most) levels the pitch")
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
	_check(is_equal_approx(rig._yaw_step, step - 90.0), "click: Q steps to the next diamond")
	_main._unhandled_input(_key(KEY_E))
	_check(is_equal_approx(rig._yaw_step, step), "and E back")
	_main._unhandled_input(_middle(true))
	_check(not rig._peeking and not rig._dragging, "click: the middle button neither peeks nor turns")
	_main._unhandled_input(_middle(false))
	Net.test_walk = [{"keys": "wd", "seconds": 5.0}] as Array[Dictionary]
	_main._walk_index = -1
	var pitch := rig.pitch
	var yaw := rig.yaw
	_main._drive_camera_keys(0.1)
	_check(rig.pitch > pitch and rig.yaw > yaw, "click: W tilts and D turns the camera")
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
func _rig(saved_pitch := Client3D.CAMERA_PITCH) -> Client3D:
	var rig: Client3D = preload("res://client3d/client3d.tscn").instantiate()
	Net.camera_pitch = saved_pitch
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
