extends Node
## WASD and the orders behind the hand, against the real room in main.tscn:
## the key-to-direction mapping at every camera yaw (checked against a real
## Camera3D), a click's free route, the swing and the strikes. Run it with tests/run.ps1 or
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
	# The grid's steps: free walk is the default (decision 693).
	Net.port = preload("res://tests/test_ports.gd").of(17788)  # Not 7777: the editor may be hosting there.
	Client3D.feel_path = ""  # 673 step 2: the defaults, whatever the tuned file holds.
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	World.entity_swung.connect(func(_entity: GridEntity, direction: Vector2i) -> void: _swings.append(direction))

	_test_wasd_mapping()
	_test_swing()
	_test_scheme_default()
	_test_screen_lean()
	_test_drag_and_freeze()
	_test_diamonds()
	_test_overhead_keys()
	_test_wheel_zoom()
	_test_pitch_peek()
	_test_middle_drag_axis()
	_test_schemes_are_inert_outside()
	_test_click_uses_the_frame_pick()
	_test_bow_click_walks()
	_test_friend_click()
	_test_peaceable_click()
	_test_bubble_click_goes_through()
	_test_stand_and_signature()
	_test_cursor_bandage()
	_test_telegraph_message()
	_test_item_keys()
	_test_free_click()
	_test_guide_route()
	_test_free_pull()
	_test_free_chase()

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
	print("\n== WASD: a middle drag turns freely and stays where it is let go (671 amended), never under a held key ==")
	var saved: String = Net.controls
	Net.controls = "wasd"
	var rig := _rig()
	_check(is_equal_approx(rig.yaw, 0.0), "it starts on the saved diamond (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(20.0)
	_check(is_equal_approx(rig.yaw, 20.0), "the drag turns it at once (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, 20.0) and is_equal_approx(Net.camera_yaw, 20.0),
			"let go 20 round: it stays at 20, no snap, and is saved (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(5.0)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, 25.0), "a small drag of 5 stays too (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(-100.0)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, -75.0), "100 the other way, past 0: at -75 (%s)" % rig.yaw)
	rig.begin_drag()
	rig.drag(300.0)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, 225.0) and is_equal_approx(Net.camera_yaw, 225.0),
			"300 round: at 225, saved (%s)" % rig.yaw)
	var start := rig.yaw
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
	_check(is_equal_approx(rig.yaw, start + 100.0), "the keys let go: it goes to where the drag was let go (%s)" % rig.yaw)
	start = rig.yaw
	rig.begin_drag()
	rig.set_frozen(true)
	rig.drag(40.0)
	rig.set_frozen(false)
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 40.0), "a drag held through a run applies when the keys are let go (%s)" % rig.yaw)
	rig.end_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, start + 40.0), "and stays there (%s)" % rig.yaw)
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
	print("\n== click: A/D turn freely, all the way round, and lock on the next of the eight views (671) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var rig := _rig()
	_check(is_equal_approx(rig.yaw, 0.0), "it starts on the saved diamond (%s)" % rig.yaw)
	for i in 6:
		rig.turn(1.0, 0.01)
	_check(is_equal_approx(rig.yaw, 10.8), "D held 60 ms: 10.8 degrees at 180 a second (%s)" % rig.yaw)
	var held := rig.yaw
	rig.end_turn()
	_check(is_equal_approx(rig._ease_to, 45.0), "let go 10.8 round: on to the next view, square-on at 45 (%s)" % rig._ease_to)
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
	_check(steady and is_equal_approx(rig.yaw, 45.0), "and slows onto it without stopping first (%s)" % rig.yaw)
	_check(is_equal_approx(Net.camera_yaw, 45.0), "saved as that view (%s)" % Net.camera_yaw)
	for i in 250:
		rig.turn(1.0, 0.01)
	_check(is_equal_approx(rig.yaw, 495.0), "D held 2.5 s: 450 degrees round, no limit (%s)" % rig.yaw)
	rig.end_turn()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, 495.0) and is_equal_approx(Net.camera_yaw, 135.0),
			"let go on a view: it stays, saved as %s" % Net.camera_yaw)
	for i in 5:
		rig.turn(-1.0, 0.01)
	rig.end_turn()
	_check(is_equal_approx(rig._ease_to, 495.0), "A held 50 ms (9 degrees, under 10): back where it set off")
	var furthest := rig.yaw
	for i in 100:
		rig._ease_yaw(0.01)
		furthest = minf(furthest, rig.yaw)
	_check(furthest < 486.0 and is_equal_approx(rig.yaw, 495.0),
			"running on a little the way it went, then back (%.1f at most, ends %s)" % [furthest - 495.0, rig.yaw])
	for i in 30:
		rig.turn(-1.0, 0.01)
	rig.end_turn()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, 405.0), "A held 300 ms (54 degrees, to 441): on to the next view that way (%s)" % rig.yaw)
	_check(is_equal_approx(Client3D.settle_target(0.0, 5.0, 1.0), 0.0) and is_equal_approx(Client3D.settle_target(0.0, 12.0, 1.0), 45.0)
			and is_equal_approx(Client3D.settle_target(0.0, 95.0, 1.0), 135.0) and is_equal_approx(Client3D.settle_target(90.0, 95.0, 1.0), 90.0) and is_equal_approx(Client3D.settle_target(0.0, -12.0, -1.0), -45.0)
			and is_equal_approx(Client3D.settle_target(0.0, 180.0, 1.0), 180.0),
			"settle: under 10 back, else the next view ahead (0 to 95 goes on to 135; 90 to 95 is back), or the one it is on")
	_check(is_equal_approx(Net.saved_yaw("180", -1.0), 180.0) and is_equal_approx(Net.saved_yaw("-90", -1.0), 270.0)
			and is_equal_approx(Net.saved_yaw("45", -1.0), 45.0) and is_equal_approx(Net.saved_yaw("100", -1.0), 100.0) and is_equal_approx(Net.saved_yaw("", 90.0), 90.0),
			"a saved yaw loads as it is (0..360), one between the views too (671 amended); none keeps what it had")
	Net.controls = saved
	_free_rig(rig)


func _test_wheel_zoom() -> void:
	print("\n== the mouse wheel zooms on the player in small eased steps, 0.5x (the low camera 0.8x) to 1.1x, saved; a middle click does nothing ==")
	var saved: String = Net.controls
	var rig := _rig()
	_check(is_equal_approx(rig.zoom, 1.0) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE), "it starts at 1x")
	for scheme: String in ["click", "wasd"]:
		Net.controls = scheme
		rig.zoom = 1.0
		rig._zoom_to = 1.0
		_main._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
		_check(is_equal_approx(rig._zoom_to, 1.0 / Client3D.ZOOM_STEP), "%s: a notch up, in by %.1fx (%.3f)" % [scheme, Client3D.ZOOM_STEP, rig._zoom_to])
	rig._ease_zoom(1.0 / 60.0)
	_check(rig.zoom < 1.0 and rig.zoom > rig._zoom_to, "eased, not at once (%.3f a frame in)" % rig.zoom)
	for i in 30:
		rig._ease_zoom(1.0 / 60.0)
	_check(is_equal_approx(rig.zoom, rig._zoom_to) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE * rig.zoom),
			"there within half a second (size %.2f)" % rig._camera.size)
	for i in 10:
		rig.zoom_by(1)
	_check(is_equal_approx(rig._zoom_to, Client3D.ZOOM_MIN) and is_equal_approx(Client3D.ZOOM_MIN, 0.5), "in no nearer than %sx" % rig._zoom_to)
	for i in 20:
		rig.zoom_by(-1)
	_check(is_equal_approx(rig._zoom_to, Client3D.ZOOM_MAX) and is_equal_approx(Net.camera_zoom, Client3D.ZOOM_MAX),
			"out no further than %sx, and saved" % rig._zoom_to)
	for i in 60:
		rig._ease_zoom(1.0 / 60.0)
	var target := rig._camera_target
	_check(rig._camera_target == target and rig._camera.position.is_equal_approx(rig._camera_target + rig._camera_offset()),
			"zooming leaves the camera on the player")
	var yaw := rig.yaw
	var pitch := rig.pitch
	_main._begin_middle_drag(Vector2(500, 500))
	_main._end_middle_drag()
	for i in 60:
		rig._ease_zoom(1.0 / 60.0)
	_check(is_equal_approx(rig.zoom, Client3D.ZOOM_MAX) and is_equal_approx(Net.camera_zoom, Client3D.ZOOM_MAX) and is_equal_approx(rig.yaw, yaw)
			and is_equal_approx(rig.pitch, pitch), "%s: a middle click leaves the zoom (and all else) as it was" % Net.controls)
	_check(is_equal_approx(Net.saved_zoom("1.05", -1.0), 1.05) and is_equal_approx(Net.saved_zoom("2", -1.0), Client3D.ZOOM_MAX)
			and is_equal_approx(Net.saved_zoom("0.6", -1.0), 0.6) and is_equal_approx(Net.saved_zoom("0.3", -1.0), Client3D.ZOOM_MIN) and is_equal_approx(Net.saved_zoom("", 1.0), 1.0),
			"a saved zoom loads held to 0.5..1.1; none keeps 1x")
	Net.camera_zoom = 1.25
	var again := _rig()
	_free_rig(again)
	Net.camera_zoom = 1.05
	var reload: Client3D = preload("res://client3d/client3d.tscn").instantiate()
	_main.add_child(reload)
	reload.setup(_main._terrain)
	_check(is_equal_approx(reload.zoom, 1.05) and is_equal_approx(reload._camera.size, Client3D.CAMERA_SIZE * 1.05),
			"a saved zoom is where a new view starts (%s)" % reload.zoom)
	reload.queue_free()
	Net.camera_zoom = 1.0
	Net.controls = saved
	_free_rig(rig)


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = button
	wheel.pressed = true
	return wheel


func _test_overhead_keys() -> void:
	print("\n== click: W eases overhead and stays, S back to normal (671) ==")
	var rig := _rig()
	var yaw := rig.yaw
	var was: bool = Net.camera_overhead
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and not rig.overhead, "it starts at 50, not overhead (%s)" % rig.pitch)
	rig.set_overhead(true)
	rig._ease_tilt(Client3D.PITCH_EASE_SECONDS * 0.1)
	var early := rig.pitch - Client3D.CAMERA_PITCH
	rig._ease_tilt(Client3D.PITCH_EASE_SECONDS * 0.4)
	var half := rig.pitch
	_check(early > 0.0 and early < (Client3D.OVERHEAD_PITCH - Client3D.CAMERA_PITCH) * 0.1 and is_equal_approx(half, (Client3D.CAMERA_PITCH + Client3D.OVERHEAD_PITCH) * 0.5),
			"W: easing up, gently at first (%.2f in a tenth), half way at half the time (%.1f)" % [early, half])
	rig._ease_tilt(Client3D.PITCH_EASE_SECONDS * 0.5)
	_check(is_equal_approx(rig.pitch, Client3D.OVERHEAD_PITCH) and rig.overhead and Net.camera_overhead,
			"overhead at %s after %d ms, saved" % [rig.pitch, roundi(Client3D.PITCH_EASE_SECONDS * 1000.0)])
	for i in 20:
		rig._ease_tilt(0.05)
	_check(is_equal_approx(rig.pitch, Client3D.OVERHEAD_PITCH), "and it stays there with no key held (%s)" % rig.pitch)
	_check(is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE), "the size never changes (%s)" % rig._camera.size)
	rig.set_overhead(false)
	rig._ease_tilt(Client3D.PITCH_EASE_SECONDS * 0.5)
	var going := rig.pitch
	rig.set_overhead(true)
	_check(is_equal_approx(rig.pitch, going), "S, then W half way back: it turns round from where it is, no snap (%.1f)" % rig.pitch)
	rig._ease_tilt(Client3D.PITCH_EASE_SECONDS)
	_check(is_equal_approx(rig.pitch, Client3D.OVERHEAD_PITCH), "and goes on up (%s)" % rig.pitch)
	rig.set_overhead(false)
	rig._ease_tilt(Client3D.PITCH_EASE_SECONDS)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and not rig.overhead and not Net.camera_overhead, "S: back at 50 to stay, saved (%s)" % rig.pitch)
	rig.set_overhead(false)
	_check(rig._tilt_t >= 1.0, "S at rest: nothing to ease")
	_check(is_equal_approx(rig.yaw, yaw), "the yaw never moved (%s)" % rig.yaw)
	Net.camera_overhead = was
	_free_rig(rig)


func _test_pitch_peek() -> void:
	print("\n== a vertical middle drag tilts toward the other pitch: springs back, or past a third commits (671) ==")
	var rig := _rig()
	_ease(rig)
	var yaw := rig.yaw
	var saved := Net.camera_yaw
	rig._update_fade(true)
	var fade_before := rig._fade_key
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE),
			"at rest: pitch %s, size %s" % [rig.pitch, rig._camera.size])
	rig.begin_pitch_peek()
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * 0.5)
	_check(is_equal_approx(rig.pitch, (Client3D.CAMERA_PITCH + Client3D.OVERHEAD_PITCH) * 0.5),
			"half the drag: half way up, eased in and out (%s)" % rig.pitch)
	var quarter := rig.pitch
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * 0.25)
	_check(rig.pitch < quarter and rig.pitch - Client3D.CAMERA_PITCH < (quarter - Client3D.CAMERA_PITCH) * 0.5,
			"a quarter of it: less than half that, the ease starts gently (%s)" % rig.pitch)
	rig.pitch_peek(Client3D.PEEK_DRAG_PX * 0.5)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH), "down the screen from the normal pitch: no tilt (%s)" % rig.pitch)
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * 2.0)
	_check(is_equal_approx(rig.pitch, Client3D.OVERHEAD_PITCH)
			and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE * Client3D.PEEK_PULL_BACK),
			"past the full drag up: overhead at %s and pulled back to %s" % [rig.pitch, rig._camera.size])
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * Client3D.PEEK_COMMIT * 0.9)
	_check(is_equal_approx(rig.yaw, yaw), "the yaw never moves (%s)" % rig.yaw)
	rig._update_fade()
	_check(rig._fade_key != fade_before, "at the full tilt, what fades is worked out again for that view")
	rig.end_pitch_peek()
	rig._ease_peek(Client3D.PEEK_RETURN_SECONDS * 0.5)
	_check(rig.pitch > Client3D.CAMERA_PITCH and rig.pitch < Client3D.OVERHEAD_PITCH and not rig.overhead,
			"let go under a third of the drag: springing back (%s)" % rig.pitch)
	rig._ease_peek(Client3D.PEEK_RETURN_SECONDS * 0.5)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE),
			"back at rest after %d ms (pitch %s, size %s)" % [roundi(Client3D.PEEK_RETURN_SECONDS * 1000.0), rig.pitch, rig._camera.size])
	_check(is_equal_approx(rig.yaw, yaw) and is_equal_approx(Net.camera_yaw, saved), "yaw and saved yaw as they were")
	var was: bool = Net.camera_overhead
	rig.begin_pitch_peek()
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX * 0.5)
	var at_let_go := rig.pitch
	rig.end_pitch_peek()
	_check(rig.overhead and Net.camera_overhead and is_equal_approx(rig.pitch, at_let_go), "let go past a third: overhead to stay, saved, from where it was (%.1f)" % rig.pitch)
	for i in 10:
		rig._ease_peek(0.05)
		rig._ease_tilt(0.05)
	_check(is_equal_approx(rig.pitch, Client3D.OVERHEAD_PITCH) and is_equal_approx(rig._camera.size, Client3D.CAMERA_SIZE),
			"on up to %s, the pull back gone (size %s)" % [rig.pitch, rig._camera.size])
	rig.begin_pitch_peek()
	rig.pitch_peek(-Client3D.PEEK_DRAG_PX)
	_check(is_equal_approx(rig.pitch, Client3D.OVERHEAD_PITCH), "overhead, up the screen: no tilt (%s)" % rig.pitch)
	rig.pitch_peek(Client3D.PEEK_DRAG_PX * 0.5)
	_check(is_equal_approx(rig.pitch, (Client3D.CAMERA_PITCH + Client3D.OVERHEAD_PITCH) * 0.5), "down the screen: half way back toward 50 (%s)" % rig.pitch)
	rig.end_pitch_peek()
	for i in 10:
		rig._ease_peek(0.05)
		rig._ease_tilt(0.05)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and not rig.overhead and not Net.camera_overhead, "let go: back to the normal pitch to stay (%s)" % rig.pitch)
	Net.camera_overhead = was
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
	yaw = rig.yaw
	_main._begin_middle_drag(Vector2(500, 500))
	_main._middle_drag(Vector2(60, 5))
	_check(rig._dragging and is_equal_approx(rig.yaw, yaw + 60.0 * Main.DRAG_DEGREES_PER_PX) and rig.pan == Vector3.ZERO,
			"click (671 amended): a sideways middle drag turns too, no pan (%s)" % rig.yaw)
	_main._end_middle_drag()
	_ease(rig)
	_check(is_equal_approx(rig.yaw, yaw + 60.0 * Main.DRAG_DEGREES_PER_PX), "and stays where it is let go (%s)" % rig.yaw)
	rig._settle_on(yaw)
	_ease(rig)
	print("\n== Ctrl with a middle drag pans, the ground under the cursor kept under it, and springs back when let go ==")
	rig._sync_puppets()
	rig._follow(0.0)
	var ground := rig._camera_target
	var at := rig._camera.unproject_position(rig.to_global(ground))
	_main._begin_middle_drag(Vector2(500, 500), true)
	_main._middle_drag(Vector2(3, 2))
	_check(rig.pan == Vector3.ZERO, "under %d px it is not yet a pan" % Main.DRAG_AXIS_PX)
	_main._middle_drag(Vector2(120, 0))
	rig._follow(0.0)
	var moved := rig._camera.unproject_position(rig.to_global(ground)) - at
	_check(moved.distance_to(Vector2(120, 0)) < 1.0, "sideways: the ground goes with the cursor (%s)" % moved)
	_check(is_equal_approx(rig.yaw, yaw) and not rig._dragging, "and it does not turn (%s)" % rig.yaw)
	_main._middle_drag(Vector2(120, -90))
	rig._follow(0.0)
	moved = rig._camera.unproject_position(rig.to_global(ground)) - at
	_check(moved.distance_to(Vector2(120, -90)) < 1.0, "up and down too, through the tilt (%s)" % moved)
	_check(is_equal_approx(rig.pitch, Client3D.CAMERA_PITCH) and not rig._peeking, "and it does not tilt (%s)" % rig.pitch)
	var panned := rig.pan
	_main._end_middle_drag()
	rig._ease_pan(1.0 / 60.0)
	_check(rig.pan != Vector3.ZERO and rig.pan.length() < panned.length(), "let go, it springs back, eased, not at once (%s)" % rig.pan)
	for i in 60:
		rig._ease_pan(1.0 / 60.0)
	rig._follow(0.0)
	_check(rig.pan == Vector3.ZERO and rig._camera_target.is_equal_approx(_player_puppet(rig)), "on the player again within a second")
	_main._begin_middle_drag(Vector2(500, 500), true)
	_main._middle_drag(Vector2(100000, 0))
	_check(rig.pan.length() <= Client3D.PAN_MAX + 0.001, "never more than %d tiles off (%.2f)" % [Client3D.PAN_MAX, rig.pan.length()])
	_main._end_middle_drag()
	for i in 3:
		rig._ease_pan(1.0 / 60.0)
	var easing := rig.pan
	_main._begin_middle_drag(Vector2(500, 500), true)
	_main._middle_drag(Vector2(0, 30))
	rig._ease_pan(1.0 / 60.0)
	_check(easing != Vector3.ZERO and rig.pan.distance_to(easing) < 2.0 and not rig._pan_home,
			"caught on its way back, a new drag holds it from there")
	_main._end_middle_drag()
	for i in 90:
		rig._ease_pan(1.0 / 60.0)
	var before := rig.pitch
	var zoom_to := rig._zoom_to
	_main._begin_middle_drag(Vector2(500, 500), true)
	_main._middle_drag(Vector2(2, 1))
	_main._end_middle_drag()
	_check(is_equal_approx(rig.pitch, before) and rig._tilt_t >= 1.0 and is_equal_approx(rig._zoom_to, zoom_to) and rig.pan == Vector3.ZERO,
			"a middle click does nothing: no tilt, no zoom, no pan")
	Net.controls = saved
	_free_rig(rig)


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
	var overhead_was: bool = Net.camera_overhead
	_main._drive_camera_keys(0.1)
	rig._ease_tilt(0.1)
	_check(rig.overhead and rig.pitch > pitch and rig.yaw > yaw and is_equal_approx(rig._camera.size, size),
			"click: W puts the view overhead (671) and D turns the camera; Q and E do nothing")
	rig.set_overhead(false)
	rig._ease_tilt(1.0)
	Net.camera_overhead = overhead_was
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
	var own: RefCounted = _main._free_own(player)
	_check(_main._free_intent(player, own) == Vector2.ZERO, "click: a movement key held walks nowhere")
	Net.controls = "wasd"
	_check(_main._free_intent(player, own).length() > 0.99, "wasd: it walks")
	Net.test_walk = [] as Array[Dictionary]
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
	_check(_walking_to(Vector2i(9, 6)),
			"and the click sends the player there (%s)" % [_walk_end()])
	_stop_walk()
	Net.controls = saved



func _test_bow_click_walks() -> void:
	print("\n== a bow in hand: a plain left click walks at once; Shift held draws and stands firm, the left release looses, Shift up lets it down (583 amended (2)) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(11, 3))
	var bow := World.items.mint("bow", "built")
	var arrows := World.items.mint("arrows", "built")
	World.put_item(player, player, Player.RIGHT_HAND, bow)
	World.put_item(player, player, Player.LEFT_HAND, arrows)
	_check(World.off_hand(player) == "draw", "(a bow and arrows in hand)")
	_main._pick_grid = Vector2(9.2, 6.1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_main._unhandled_input(click)
	_check(_main._stance == "" and player.raised == "" and not _main.aim_drawn and _walking_to(Vector2i(9, 6)),
			"a plain press: no draw, the walk at once (%s)" % [_walk_end()])
	click.pressed = false
	_main._unhandled_input(click)
	_stop_walk()
	var shift := InputEventMouseButton.new()
	shift.button_index = MOUSE_BUTTON_LEFT
	shift.shift_pressed = true
	shift.pressed = true
	_main._unhandled_input(shift)
	_check(_main._stance == "draw" and player.raised == "draw" and not _walking(), "Shift with the press: the bow drawn, no walk, no stand swing")
	_main.drive_stand_draw(false, true)
	_check(_main._stance == "draw" and player.raised == "draw", "Shift up with the left button still down: still drawn (583 amended (2))")
	var again := InputEventMouseButton.new()
	again.button_index = MOUSE_BUTTON_LEFT
	again.pressed = true
	_main._unhandled_input(again)
	_check(_main._stance == "draw" and player.raised == "draw", "a press while drawn: nothing, still drawn (583 amended (2))")
	var let_go := InputEventMouseButton.new()
	let_go.button_index = MOUSE_BUTTON_LEFT
	let_go.pressed = false
	_main._unhandled_input(let_go)
	_check(_main._stance == "" and player.raised == "", "the left release while drawn: loosed (or let down before draw_min), the bow lowered (583 amended (2))")
	# Shift held, walking: the body stops where it stands and draws.
	_main._move_click(player, Vector2i(5, 3))
	_check(_walking_to(Vector2i(5, 3)), "(walking to 5,3)")
	_main.drive_stand_draw(true)
	_check(_main._stance == "draw" and player.raised == "draw" and World.free_held(player),
			"Shift held while walking: the bow drawn at once, the body held")
	var at := player.free_pos
	World.free_input(player, Vector2.LEFT, 0.5)
	_resolve()
	_check(player.free_pos.is_equal_approx(at), "drawn, the server takes no walk: it stands firm (%s)" % player.free_pos)
	_stop_walk()
	_main.drive_stand_draw(true)
	_check(_main._stance == "draw", "Shift still held: still drawn")
	_main.drive_stand_draw(false)
	_check(_main._stance == "" and player.raised == "" and player.slots[Player.LEFT_HAND] == "arrows",
			"Shift let go: the bow let down, the arrow kept, nothing loosed")
	# The right button with a bow (decision 677): held, the lob at the sky; let go, loosed.
	var outdoor_was := World.fields.outdoor
	World.fields.outdoor = true
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_main._unhandled_input(right)
	_check(_main._stance == "lob" and player.raised == "draw" and player.lobbing and not _walking(), "RMB held with a bow: drawn at the sky, standing firm")
	_main._unhandled_input(again)
	_main._unhandled_input(let_go)
	_main.drive_stand_draw(true)
	_check(_main._stance == "lob" and player.lobbing, "the left button and Shift leave a lob alone")
	player.raised_tick = World.tick - 40
	var lobs := World._lobs.size()
	right.pressed = false
	_main._unhandled_input(right)
	_check(_main._stance == "" and player.raised == "" and not player.lobbing and World._lobs.size() == lobs + 1, "RMB let go: lobbed at the cursor, the stance ended")
	_main.drive_stand_draw(false)
	World.fields.outdoor = outdoor_was
	_check(not World.free_held(player), "let down: it walks again")
	World.items.end(World.take_item(player, player, Player.RIGHT_HAND), "gone")
	World.items.end(World.take_item(player, player, Player.LEFT_HAND), "gone")
	Net.controls = saved


func _test_friend_click() -> void:
	print("
== a left click on a friend talks, never attacks; Shift's swing strikes one (decisions 454, 593) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(11, 3))
	var occupant := World.get_entity_at(Vector2i(9, 6))
	if occupant != null:
		World.despawn(occupant)
	var body := Resident.new()
	body.name = "Tam"
	_check(World.spawn(body, Vector2i(9, 6)), "(a resident stands at 9,6)")
	_main._pick_grid = Vector2(9.1, 6.1)
	_left(false)
	_check(player.action_order != GridEntity.Order.ATTACK and _walking_beside(body) and _main._talk_wanted == body,
			"a plain click walks beside them to talk, no attack (%s)" % [_walk_end()])
	var hints_were: bool = Net.hints
	Net.hints = true
	_check(_main.context_hint_for(body) == "LMB  interact", "the hint says interact with hints=on (560; %s)" % _main.context_hint_for(body))
	Net.hints = hints_were
	_check("Shift+LMB	swing where you stand" in _main.hint_lines()
			and "Shift held, bow	stand firm and draw: LMB release looses, let go lowers it (arrow kept), walk keys turn" in _main.hint_lines()
			and "RMB, bow	hold to aim at the sky, let go to lob onto the circle: over walls, knocks down" in _main.hint_lines(),
			"the controls list: Shift+LMB swings where you stand; with a bow, Shift held stands firm and draws, LMB release looses (583 amended (2)); RMB lobs (677)")
	_stop_walk()
	_left(true)
	_check(player.action_order == GridEntity.Order.SWING and not _walking() and _main._talk_wanted == null,
			"Shift+click from afar: a swing where you stand, no walk, no talk")
	var hp := body.hp
	_wait_free(player)
	World.step()
	_check(body.hp == hp and player.tile == Vector2i(11, 3), "out of reach: nothing struck, not a step taken")
	_place_player(Vector2i(10, 5))
	if not body.is_inside_tree():
		_main.add_child(body)  # On screen, for the bar to stand under (the 2D view's anchor).
	_main._pick_grid = Vector2(9.1, 6.1)
	_left(false)
	_check(_main._bar.visible and _main._bar_for == body, "beside them, a plain click opens the talk bar under them (560 amended)")
	_main._pick_grid = Vector2(11.1, 3.1)
	_left(false)
	_check(not _main._bar.visible, "and a click elsewhere closes it")
	_place_player(Vector2i(10, 5))
	_main._pick_grid = Vector2(9.1, 6.1)
	_left(true)
	_wait_free(player)
	World.step()
	_resolve()
	_check(body.hp < hp, "beside them, Shift+click strikes the friend that way (%d -> %d)" % [hp, body.hp])
	player.action_order = GridEntity.Order.NONE
	World.despawn(body)
	body.queue_free()
	Net.controls = saved

## A speech bubble takes no clicks (560 amended; Jeff, through the
## coordinator): a click over one goes to what is under it, the ground
## walked to, a monster at war attacked.
func _test_bubble_click_goes_through() -> void:
	print("\n== a click over a speech bubble walks or attacks what is beneath (560 amended) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(11, 3))
	var bubbles: SpeechBubbles = _main.bubbles
	var anchor_was: Callable = bubbles.anchor_of
	var speaker := Resident.new()
	speaker.name = "Wynn"
	_check(World.spawn(speaker, Vector2i(12, 4)), "(a resident speaks at 12,4)")
	var key := speaker.get_instance_id()
	bubbles.anchor_of = func(k: int) -> Variant: return bubbles.get_local_mouse_position() + Vector2(0.0, 12.0) if k == key else null
	bubbles.show_line(key, "Fine weather for it.")
	bubbles._layout()
	_check(bubbles.key_under_mouse() == key and bubbles.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"(the bubble is under the mouse, and takes no mouse)")
	_main._pick_grid = Vector2(9.2, 6.1)
	_left(false)
	_check(_walking_to(Vector2i(9, 6)) and not _main._bar.visible and _main._talk_wanted == null,
			"the ground under the bubble: walked to, no talk bar (%s)" % [_walk_end()])
	_stop_walk()
	var occupant := World.get_entity_at(Vector2i(9, 6))
	if occupant != null:
		World.despawn(occupant)
	var foe := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": "Foe", "tile": Vector2i(9, 6)}) as Monster
	foe.sight_range = 0
	_main.add_child(foe)
	_check(World.spawn(foe, Vector2i(9, 6)), "(a monster stands under the bubble at 9,6)")
	_left(false)
	_check(player.action_order == GridEntity.Order.ATTACK and not _main._bar.visible, "a monster under it: attacked")
	player.action_order = GridEntity.Order.NONE
	_stop_walk()
	World.despawn(foe)
	foe.queue_free()
	World.despawn(speaker)
	bubbles.anchor_of = anchor_was
	Net.controls = saved


## A plain left click on a talking monster at peace talks, as on a friend
## (decision 648; Jeff: "earlier i struck the draugr because left clicking
## attacked"); Shift's swing still strikes it; at war, a click attacks.
func _test_peaceable_click() -> void:
	print("
== a left click on a peaceable talker talks; Shift's swing strikes it; at war a click attacks (decision 648) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(11, 3))
	var occupant := World.get_entity_at(Vector2i(9, 6))
	if occupant != null:
		World.despawn(occupant)
	var talker := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": "Talker", "tile": Vector2i(9, 6)}) as Monster
	talker.sight_range = 0
	talker.talks = true
	talker.peaceable = true
	_main.add_child(talker)
	_check(World.spawn(talker, Vector2i(9, 6)), "(a talking monster at peace stands at 9,6)")
	_main._pick_grid = Vector2(9.1, 6.1)
	_left(false)
	_check(player.action_order != GridEntity.Order.ATTACK and _walking_beside(talker) and _main._talk_wanted == talker,
			"a plain click walks beside it to talk, no attack (%s)" % [_walk_end()])
	_stop_walk()
	_main._talk_wanted = null
	_left(true)
	_check(player.action_order == GridEntity.Order.SWING and _main._talk_wanted == null, "Shift+click: a swing where you stand, deliberate")
	player.action_order = GridEntity.Order.NONE
	talker.peaceable = false
	_left(false)
	_check(player.action_order == GridEntity.Order.ATTACK and _main._talk_wanted == null, "at war (peaceable false): a plain click attacks as ever")
	player.action_order = GridEntity.Order.NONE
	_stop_walk()
	talker.talks = false
	talker.peaceable = true
	_left(false)
	_check(player.action_order == GridEntity.Order.ATTACK, "a monster that does not talk: a click attacks, whatever its flag")
	player.action_order = GridEntity.Order.NONE
	_stop_walk()
	World.despawn(talker)
	talker.queue_free()
	Net.controls = saved



func _left(shift: bool, ctrl := false) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.shift_pressed = shift
		click.ctrl_pressed = ctrl
		_main._unhandled_input(click)


## A few ticks, for queued hits to resolve.
func _resolve() -> void:
	for i in 3:
		World.step()


func _test_stand_and_signature() -> void:
	print("
== Shift swings at air where you stand; Ctrl is the shield's bash, a plain click with it up strikes (decision 593) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	_kill_monsters()
	var player := _place_player(Vector2i(11, 3))
	_main._pick_grid = Vector2(13.0, 3.2)
	_swings.clear()
	_left(true)
	_wait_free(player)
	World.step()
	_check(_swings == [Vector2i(1, 0)] and player.tile == Vector2i(11, 3), "Shift on empty ground: a swing east at the air, no step (%s)" % [_swings])
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "BashImp", "tile": Vector2i(12, 3), "props": {"mass": 40.0}}) as Monster
	imp.sight_range = 0
	_main._pick_grid = Vector2(12.1, 3.0)
	_left(false, true)
	_check(player.action_order == GridEntity.Order.NONE, "Ctrl+click with no shield: no signature, nothing ordered")
	var shield := World.items.mint("shield", "built")
	World.put_item(player, player, Player.LEFT_HAND, shield)
	_check(World.signature_of(player) == "bash", "a shield in the left hand: the signature is the bash")
	var bashes := []
	var bashed := func(_by: GridEntity, _target: GridEntity, opened: bool) -> void: bashes.append(opened)
	World.shield_bashed.connect(bashed)
	_wait_free(player)
	_left(false, true)
	_check(player.action_order == GridEntity.Order.SIGNATURE, "Ctrl+click on the imp: a signature order")
	_resolve()
	_check(bashes.size() == 1 and World.is_stunned(imp), "bashed: the imp staggered")
	World.try_stance(player, "block")
	_wait_free(player)
	var hp := imp.hp
	_left(false)
	_check(player.action_order == GridEntity.Order.ATTACK, "a plain click with the shield up: an attack order")
	_wait_free(player)
	_resolve()
	_check(bashes.size() == 1 and imp.hp < hp, "a blow, not a bash (379's left button moved to Ctrl; %d -> %d)" % [hp, imp.hp])
	World.try_stance(player, "")
	_kill_monsters()
	var two := Vector2i(-1, -1)  # Two cells off, the one between free.
	for direction: Vector2i in World.DIRECTIONS:
		if World.is_free(player.tile + direction) and World.is_free(player.tile + direction * 2) 				and World.can_melee(player.tile, player.tile + direction):
			two = player.tile + direction * 2
			break
	var far := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "FarImp", "tile": two, "props": {"mass": 40.0}}) as Monster
	far.sight_range = 0
	_main._pick_grid = Vector2(two)
	player.next_bash_tick = 0
	_left(false, true)
	_resolve()
	_check(bashes.size() == 1 and player.tile == Vector2i(11, 3), "Ctrl+click two cells off: no walk, no bash")
	World.shield_bashed.disconnect(bashed)
	World.items.end(World.take_item(player, player, Player.LEFT_HAND), "gone")
	_kill_monsters()
	player.action_order = GridEntity.Order.NONE
	Net.controls = saved


func _test_telegraph_message() -> void:
	print("
== a telegraph reaches the zone's players: shown, then over (decision 602) ==")
	var player := _place_player(Vector2i(11, 3))
	var heard := []
	var on_start := func(id: int, data: Dictionary) -> void: heard.append(["start", id, data["cells"].size()])
	var on_end := func(id: int, landed: bool) -> void: heard.append(["end", id, landed])
	_main.telegraph_started.connect(on_start)
	_main.telegraph_ended.connect(on_end)
	var id := World.telegraph(player, "spin", Telegraph.cone(player.tile, Vector2(1, 0), 2.0, 150.0), 15)
	_check(_main.telegraphs.has(id) and heard.size() == 1 and heard[0][0] == "start" and int(heard[0][2]) > 0,
			"the host's own client is told, with its cells (%s)" % [heard])
	World.end_telegraph(id, true)
	_check(not _main.telegraphs.has(id) and heard.back() == ["end", id, true], "and told it landed (%s)" % [heard.back()])
	_main.telegraph_started.disconnect(on_start)
	_main.telegraph_ended.disconnect(on_end)


func _test_cursor_bandage() -> void:
	print("
== B puts a bandage on the cursor; a click applies it, never an attack; Esc puts it back (decision 593) ==")
	var saved: String = Net.controls
	Net.controls = "click"
	_kill_monsters()
	var player := _place_player(Vector2i(11, 3))
	_press(KEY_B)
	_check(_main._cursor_item.is_empty(), "no kit: B puts nothing on the cursor")
	var kit := World.items.mint("bandaging_kit", "built")
	World.put_item(player, player, Player.RIGHT_HAND, kit)
	_press(KEY_B)
	_check(_main._cursor_item.get("kind") == "bandage", "with a kit: a bandage on the cursor")
	_press(KEY_ESCAPE)
	_check(_main._cursor_item.is_empty(), "Esc puts it back")
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "CursorImp", "tile": Vector2i(12, 3), "props": {"mass": 40.0}}) as Monster
	imp.sight_range = 0
	_press(KEY_B)
	_main._pick_grid = Vector2(12.0, 3.0)
	_left(false)
	_check(player.action_order == GridEntity.Order.NONE and not _walking() and _main._cursor_item.is_empty(),
			"a click on a monster with the bandage on the cursor: no attack, no walk; the cursor emptied")
	_kill_monsters()
	player.hp = player.max_hp - 5
	player.hurt_tick = -1000
	_press(KEY_B)
	_main._pick_grid = Vector2(11.0, 3.0)
	_left(false)
	_check(player.mending == 1, "B, then a click on yourself: the bandage goes on")
	World.items.end(World.take_item(player, player, Player.RIGHT_HAND), "gone")
	Net.controls = saved


# --- helpers ------------------------------------------------------------------

## A 3D view on the room, hung on Main as its own would be, for the camera
## and the scheme tests.
func _rig() -> Client3D:
	var rig: Client3D = preload("res://client3d/client3d.tscn").instantiate()
	Net.camera_yaw = 0.0
	Net.camera_zoom = 1.0
	rig.indoor_view = false  # The test room is walled in (671): its pitch checks are the outdoor rules.
	_main.add_child(rig)
	rig.setup(_main._terrain)
	rig.set_process(false)
	_main._client3d = rig
	return rig


func _free_rig(rig: Client3D) -> void:
	_main._client3d = null
	rig.queue_free()


## Long enough for any ease to finish.
## Where the local player's puppet is in [param rig] (its WASD lean aside:
## the click scheme has none).
func _player_puppet(rig: Client3D) -> Vector3:
	var player := rig._local_player()
	return (rig._puppets[player.get_instance_id()] as Node3D).position


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



func _test_item_keys() -> void:
	print("\n== F picks up, G puts down, T throws, in both schemes, and the list says so ==")
	var was: String = Net.controls
	var player := _player()
	for scheme in ["click", "wasd"]:
		Net.controls = scheme
		var lines := "\n".join(_main.hint_lines())
		_check("F\tpick up" in lines and "G\tput down" in lines and "T\tthrow" in lines, "%s: F, G and T in the controls list" % scheme)
		_check("E hold\tbandage" in lines and "E\topen" in lines and "RMB, shield\tblock" in lines,
				"%s: E opens and, held, bandages; the right button blocks with a shield: in the list" % scheme)
		var uid := World.items.mint("bandaging_kit", "built")
		World.put_item(player, player, Player.RIGHT_HAND, uid)
		_press(KEY_G)
		_check(player.slots[Player.RIGHT_HAND] == "" and World.ground_uids(player.tile).has(uid), "%s: G puts the kit down at the feet" % scheme)
		_press(KEY_F)
		_check(player.slot_items[Player.RIGHT_HAND] == uid and World.ground_uids(player.tile).is_empty(), "%s: F picks it up again" % scheme)
		var free := Vector2i(-1, -1)
		for direction: Vector2i in World.DIRECTIONS:
			var cell := player.tile + direction * 2
			if World.is_free(player.tile + direction) and World.is_free(cell) and not World._terrain_blocks_step(player.tile, direction, false, false) \
					and not World._terrain_blocks_step(player.tile + direction, direction, false, false):
				free = cell
				break
		World.command(player, "throw", {"cell": [free.x, free.y]})
		_check(World.ground_uids(free).has(uid), "%s: T's command throws it two cells, to %s" % [scheme, free])
		World.items.end(World.take_from_ground(free, World.ground_uids(free).find(uid)), "gone")
	Net.controls = was


func _press(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	_main._unhandled_input(key)


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


## A free body's route (689 amended (5); Jeff: "mouse move directions is
## very unreponsive"): steered straight at the farthest cell in clear line,
## not from centre to centre, so a new click heads its way at once.
func _test_free_pull() -> void:
	print("
== a route's string pulled: straight at the farthest cell in clear line ==")
	var player := _place_player(Vector2i(4, 3))
	_free_start(player)
	var path: Array = []
	for cell: Vector2i in World.walk_path(Vector2i(4, 3), Vector2i(9, 3), player):
		path.append(cell)
	var cells := path.size()
	_main._free_pull(player, path, Vector2(4.4, 3.3))
	_check(cells >= 5 and path.size() == 1 and path[0] == Vector2i(9, 3), "from off its centre: straight at (9, 3) (%d cells to %s)" % [cells, path])


## A click on a creature with a free body (697, ui's side; Jeff: "quite
## choppy"): the order holds (combat's side), the client walks the body a
## cell from it, and the server strikes.
func _test_free_chase() -> void:
	print("
== a click on an imp with a free body: walked to it, then struck ==")
	var player := _place_player(Vector2i(4, 3))
	_free_start(player)
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "ChaseImp", "tile": Vector2i(9, 3), "props": {"mass": 40.0}}) as Monster
	imp.sight_range = 0
	var hp := imp.hp
	# Whole and standing, whatever an earlier test left (a downing or a stun holds a free body).
	player.hp = player.max_hp
	player.stunned_until_tick = 0
	player.downed_until = 0
	player.down_until = 0
	player.free_halt_until = 0
	_free_frames(player, 2)
	World.command_attack(player, imp)
	_main._free_chase_start(player, imp)
	var frames := 0
	while frames < 400 and imp.hp == hp:
		_free_frames(player, 6)
		frames += 6
	var settle := 0
	while settle < 30 and _main._free["chase"] != null:  # Its view catches up with where it was stopped for the blow.
		_free_frames(player, 2)
		settle += 2
	_check(imp.hp < hp and player.free_pos.distance_to(World.body_centre(imp)) <= World.reach_limit(player) and _main._free["chase"] == null,
			"walked into reach (699: the centres within %.1f) and struck (%d -> %d, at %s, %d frames, the chase over %d after)" % [World.reach_limit(player), hp, imp.hp, player.free_pos, frames, settle])
	_main._free_chase_start(player, imp)
	_main._move_click(player, Vector2i(4, 3))
	_check(_main._free["chase"] == null, "a click elsewhere: the chase given up")
	World.despawn(imp)
	player.free_view = null


## Guide under free walk (695, ui's side): her route ("guide_route" in the
## world message) is walked as a click's; his own click takes over and tells
## the server once (the "guide" command's stop "moved"); an empty path ends
## it; another zone's is not ours.
func _test_guide_route() -> void:
	print("
== she leads a free body: her route walked, his click takes over and says so once ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(4, 3))
	_free_start(player)
	var stops := {"n": 0}
	var on_command := func(_entity: GridEntity, command_name: String, args: Dictionary) -> void:
		if command_name == "guide" and args.get("stop") == "moved":
			stops["n"] += 1
	World.command_received.connect(on_command)
	_free_frames(player, 2)
	var zone := String(player.zone)
	_main._on_message("world", {"full": false, "guide_route": {"companion": "Pip", "zone": "elsewhere", "path": [[5, 3]]}})
	_check(not _main._free.get("guided", false), "another zone's route: not taken")
	var path: Array = []
	for at: Vector2i in World.walk_path(player.tile, Vector2i(8, 3), player):
		path.append([at.x, at.y])
	_main._on_message("world", {"full": false, "guide_route": {"companion": "Pip", "zone": zone, "path": path}})
	var arrived := _free_frames(player, 300, Vector2i(8, 3))
	_check(arrived and _main._free.get("guided", false), "her route walked to her heel, (8, 3) (at %s)" % player.free_pos)
	_main._on_message("world", {"full": false, "guide_route": {"companion": "Pip", "zone": zone, "path": [[7, 3], [6, 3]]}})
	_main._test_holding = true
	_main._move_click(player, Vector2i(8, 5))
	_main._test_holding = false
	_main._move_click(player, Vector2i(8, 6))
	_check(stops["n"] == 1 and not _main._free.get("guided", false), "his click took over: the server told once (%d)" % stops["n"])
	_free_frames(player, 300, Vector2i(8, 6))
	_main._on_message("world", {"full": false, "guide_route": {"companion": "Pip", "zone": zone, "path": [[7, 6]]}})
	_main._on_message("world", {"full": false, "guide_route": {"companion": "Pip", "zone": zone, "path": []}})
	_check(not _main._free.get("guided", false) and (_main._free["path"] as Array).is_empty(), "an empty path: her lead over, nothing left to walk")
	World.command_received.disconnect(on_command)
	player.free_view = null
	Net.controls = saved


## The host's player, moved to [param tile] with nothing queued.
## Free movement (decision 689; Jeff on the prototype: "left click has to
## be held down to move. wasn't one click enough before?"): one click and
## let go walks the whole route to its cell; a new click on the way goes
## there instead.
func _test_free_click() -> void:
	print("
== a free body: one click let go walks to its cell; a new click redirects ==")
	var saved: String = Net.controls
	Net.controls = "click"
	var player := _place_player(Vector2i(4, 3))
	_free_start(player)
	_main._test_holding = true
	_main._move_click(player, Vector2i(9, 6))
	_free_frames(player, 3)
	_main._test_holding = false  # Let go at once: a click, not a hold.
	var arrived := _free_frames(player, 300, Vector2i(9, 6))
	_check(arrived, "one click let go: walked to (9, 6) (at %s, %s)" % [player.tile, player.free_pos])
	_main._test_holding = true
	_main._move_click(player, Vector2i(4, 3))
	_free_frames(player, 3)
	_main._test_holding = false
	_free_frames(player, 30)
	var midway := player.free_pos
	_main._move_click(player, Vector2i(9, 3))
	arrived = _free_frames(player, 300, Vector2i(9, 3))
	_check(midway.distance_to(Vector2(9, 6)) > 0.5 and arrived,
			"a new click on the way (left (9, 6) for %s): went to (9, 3) instead (at %s)" % [midway, player.free_pos])
	_main._move_click(player, Vector2i(4, 3))
	_free_frames(player, 20)
	var own: Variant = player.free_view
	var was: Vector2 = own.shown(player)
	_main._move_click(player, Vector2i(was.round()))  # The cell it is drawn in, as a player clicks it.
	_free_frames(player, 2)
	var stopped_at: Vector2 = own.shown(player)
	_free_frames(player, 30)
	_check(stopped_at.distance_to(was) < 0.15 and own.shown(player).distance_to(stopped_at) < 0.01,
			"a click on its own cell mid-walk: stopped where it stood (from %s: went on %.2f, then %.3f)" % [
			was, stopped_at.distance_to(was), own.shown(player).distance_to(stopped_at)])
	player.free_view = null
	Net.controls = saved


## [param frames] sixtieths of a second of the free drive, World a tick
## every six: true once the body stands on [param cell]'s centre.
func _free_frames(player: Player, frames: int, cell := Main.NONE) -> bool:
	for i in frames:
		player.free_allowance = World.FREE_COMMANDS_PER_SECOND  # The test runs faster than the clock.
		_main._free_drive(1.0 / 60.0)
		if i % 6 == 5:
			World.step()
		if cell != Main.NONE and player.tile == cell and player.free_pos.distance_to(Vector2(cell)) < 0.06:
			return true
	return false


func _place_player(tile: Vector2i) -> Player:
	var player := _player()
	_stop_walk()
	player.action_order = GridEntity.Order.NONE
	if player.tile != tile:
		var occupant := World.get_entity_at(tile)
		if occupant != null and occupant != player:
			World.despawn(occupant)
		World._relocate(player, tile)
	_wait_free(player)
	return player


## 703: a click's walk is the own body's free route (Main._free["path"]).
func _walking() -> bool:
	return not (_main._free["path"] as Array).is_empty()


## The cell the route ends on, NONE for none.
func _walk_end() -> Vector2i:
	var path: Array = _main._free["path"]
	return path.back() if not path.is_empty() else Main.NONE


func _walking_to(cell: Vector2i) -> bool:
	return _walk_end() == cell


## Walking to a cell beside [param body].
func _walking_beside(body: GridEntity) -> bool:
	return _walking() and World.distance(_walk_end(), body.tile) == 1


func _stop_walk() -> void:
	_main._free["path"] = []


## The body set off from its cell's centre, nothing pending (as the old
## free_walk switch's turning on did, 689).
func _free_start(player: Player) -> void:
	World.free_drop(player)
	player.free_pos = Vector2(player.tile)
	player.free_way = Vector2.ZERO
	player.free_seen = -1
	player.free_acked = -1
	player.pack_free()


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
