extends Node
## The carry's weight (451 amended (14), TASK 16 step 2; client3d/carry_sway.gd): the game's own puppet (main.tscn and
## client3d.tscn, as view_test builds them) carrying the man's battle axe and the woman's giant axe at each placing
## (shipped, j2), driven frame by frame as view_test's _carry_run drives it (Client3D._animate, _sync_bow, the rig's
## _process, on the rigs' movie clock): a stand, a walk from standing (the start), a jog with a 90-degree turn to the
## left, a sprint, a jog and a stop. Each run three times: the sway off (today's rigid carry), on, and off again.
## Checks: the off run repeats exactly (or nothing below is a measure); with the sway on, the hips, legs and feet stay
## within LOWER_SAME of the rigid run's every frame and the head's yaw and pitch within HEAD_YAW_ALLOW and
## HEAD_PITCH_ALLOW; every bound the carry keeps (the chin, the shoulders, the wrists, the left arm off the head, the
## lantern, the thighs, the grips) read every BOUND_EVERY'th carried frame, and the sway on breaks none the rigid
## carry does not break on the same leg; the four rows, failing on the rigid carry and passing on the sway: (a) at the
## jog, the weapon's head moving A_RANGE or more in the upper chest's frame, its low A_LAG or more after the hips'
## low; (b) at the start, behind the rigid carry's place B_BEHIND or more for B_TIME; (c) at the stop, ahead of it
## during the hold (J2's room only; the shipped carry has none ahead there, printed); (d) at the turn, its bearing
## D_LAG behind the rigid carry's. Off means off: a one-hander, a blow from a run, every frame the carry is out (the
## ready, a rest), another body, anyone but a player. No kick at a first frame, a jump (a zone change, an admin move),
## a gap, or a return from posing one frame in eight. Steady at 30 fps and at 100 ms frames. Pixels are the low
## camera's at zoom 1.0 on a 1080-row window. Port 17804 (tests/port_offsets.txt's animation offset); no scratch.

const CarryView := preload("res://tests/carry_view.gd")
const DRAWN := {"man": &"male", "woman": &"female"}
const RUNS := [["man", "battle_axe"], ["woman", "giant_axe"]]
const LEGS := [["stand", 0.0, 0.6], ["walk", 1.0, 2.0], ["jog", 4.0, 2.6], ["sprint", 6.5, 1.6], ["jog2", 4.0, 1.2], ["stop", 0.0, 2.0]]
const SHORT := [["stand", 0.0, 0.4], ["walk", 1.0, 1.0], ["jog", 4.0, 2.0], ["stop", 0.0, 1.4]]
const TURN_AT := 1.3
const TURN_TIME := 0.2
const DT := 0.02
const LOWER := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
## The off run against itself (m): the drive repeats.
const REPEAT := 0.0001
## The head's facing against the rigid run's when it repeats (deg): its look about is timed on the wall clock
## (Client3D's roused look, twice a second), 0.52 at the stop on the man's j2 run.
const HEAD_REPEAT := 1.0
## With the sway on: the lower body against the rigid run's (m), and the head's yaw and pitch (deg; the neck keeps
## its pose as the spine leans, so the head turns little: measured 0.3 and 4.5 on the probe, tune17).
const LOWER_SAME := 0.001
const HEAD_YAW_ALLOW := 0.5
const HEAD_PITCH_ALLOW := 5.0
## The rows (d8's step-2 call): (a) range (m) and lag (s); (b) behind (m) for (s); (c) ahead (m); (d) lag (deg).
const A_RANGE := 0.02
const A_LAG := 0.05
const B_BEHIND := 0.005
const B_TIME := 0.15
const C_AHEAD := 0.005
const D_LAG := 2.0
## The bounds (the carry's own, 451 amended (13)): the piece's top below the chin and the shoulders' top (m), the
## wrists' bend and twist (deg), the left forearm and hand off the head's centre (m), the piece off the lantern (m),
## a hand off its target (m).
const CHIN := -0.08
const SHOULDER := 0.0
const WRIST_BEND := 60.0
const WRIST_TWIST := 45.0
const HEAD_CLEAR := 0.30
const HEAD_UP := 0.09
const LAMP := 0.15
const GRIP := 0.01
const HASH := 0.25
const BOUND_EVERY := 3
## No kick: an event's frame steps the sway's outputs no more than the run's own largest step times KICK, plus
## KICK_LEAST (deg, or cm for the hand).
const KICK := 1.25
const KICK_LEAST := 0.3
## Steady: at 30 fps and at 100 ms frames the outputs' extremes stay within STEADY times the 50 fps run's, plus
## STEADY_LEAST, and finite.
const STEADY := 1.3
const STEADY_LEAST := 0.5

var _failures := 0
var _main: Node
var _rig3d: Client3D
var _px_per_cm := 0.0


func _ready() -> void:
	AnimRig.vary_on = false
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17804)
	Client3D.feel_path = ""
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	_rig3d = preload("res://client3d/client3d.tscn").instantiate()
	_main.add_child(_rig3d)
	_rig3d.indoor_view = false
	_rig3d.setup(_main._terrain)
	_main._client3d = _rig3d
	_rig3d.bubbles = _main.bubbles
	_rig3d._process(0.0)
	var dist := Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE
	_px_per_cm = 1080.0 / (2.0 * dist * tan(deg_to_rad(Client3D.LOW_FOV * 0.5))) / 100.0
	print("carry_sway_test: %.3f px a cm at the low camera's zoom 1.0 (%.0f m, fov %.0f, 1080 rows)" % [_px_per_cm, dist, Client3D.LOW_FOV])
	var placing_was := Client3D.carry_placing
	var sway_was := Client3D.carry_sway
	var steps := {}
	for r: Array in RUNS:
		for placing: String in ["shipped", "j2"]:
			Client3D.carry_placing = placing
			var off: Array = await _drive(str(r[0]), str(r[1]), false, LEGS, DT, {}, true)
			var on: Array = await _drive(str(r[0]), str(r[1]), true, LEGS, DT, {}, true)
			var again: Array = await _drive(str(r[0]), str(r[1]), false, LEGS, DT, {}, false)
			var name := "%s %s %s" % [r[0], r[1], placing]
			_check_runs(name, placing, off, on, again)
			if r[0] == "man" and placing == "shipped":
				steps = _steps(on)
				await _test_events(on, steps)
				await _test_steady(on)
	Client3D.carry_placing = "shipped"
	await _test_off_means_off()
	Client3D.carry_placing = placing_was
	Client3D.carry_sway = sway_was
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _player() -> Player:
	for e in World.get_entities():
		if e is Player and e.spawned:
			return e
	return null


## One run: [param body] carrying [param weapon] over [param legs] at [param dt] frames, the sway on or off. [param ev]
## an event at one leg's time ({leg, at, do: blow, jump, gap, unseen}); [param bounds] reads the bounds. Every run
## starts alike: the puppet's metas the drive reads cleared, the stop's settle given back, a second's stand not kept,
## then the stand's clip from its first frame and the rig's rng seeded (a looped clip's start phase is its).
func _drive(body: String, weapon: String, on: bool, legs: Array, dt: float, ev: Dictionary, bounds: bool) -> Array:
	Client3D.carry_sway = on
	var player := _player()
	_rig3d.set_process(true)
	player.body = DRAWN.get(body, StringName(body))
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	slots[Items.RIGHT_HAND] = weapon
	slots[Items.LEFT_HAND] = ""
	player.slots = slots
	player.raised = ""
	_rig3d._process(0.0)
	await _frames(2)
	_rig3d._process(0.0)
	_rig3d.set_process(false)
	var puppet: Node3D = _rig3d._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	rig.set_process(false)
	var first := RandomNumberGenerator.new()
	first.seed = 4600
	rig._rng = first
	rig.carry("", 0.0)
	if puppet.has_meta("sway"):
		(puppet.get_meta("sway") as Node).call("set_on", 0.0)
	var pace: float = puppet.get_meta("pace", 1.0)
	var sk := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bodyn := puppet.get_node("Body") as Node3D
	var held := ((puppet.get_meta("sockets") as Dictionary)["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
	var top := _top_of(held)
	for key: String in ["speed", "gait_speed", "still_since", "gait_want", "burst_since", "burst_gait", "bow_state", "roused_at",
			"stood_at", "moved_at", "turned_ms", "turning", "gait_want_at", "roused_look_at", "sky_msec", "sway_ms", "sway_struck"]:
		puppet.remove_meta(key)
	rig.upper_off()
	# A blow from the run before (the rigs' clock starts each run at the same time, so its end would lie ahead).
	rig.cancel_strike()
	puppet.remove_meta("contact_msec")
	puppet.set_meta("strike_token", int(puppet.get_meta("strike_token", 0)) + 1)
	rig._settle = 0.0
	rig._settle_rising = false
	rig._settle_stood = 0.0
	rig.every = 1
	AnimRig._clock_movie = 1
	AnimRig._clock_frame = Engine.get_process_frames()
	AnimRig._clock_msec = 1000000
	puppet.position = Vector3(40, puppet.position.y, 40)
	puppet.set_meta("busy_until", 0)
	puppet.set_meta("fidget_at", 1 << 40)  # No fidget: its time is the rig clock's, set again each run.
	puppet.set_meta("last_at", puppet.position)
	puppet.set_meta("last_ms", AnimRig._clock_msec)
	rig.loop(Client3D.CLIP_IDLE, 1.0)
	var yaw := 0.0  # Ahead along +x (the Body faces its +X).
	bodyn.rotation.y = yaw
	var model := rig.get_parent() as Node3D
	var bctx := _bounds_context(puppet, model, sk, held) if bounds and held != null else {}
	if not bctx.is_empty():
		await _frames(2)
	var head := sk.find_bone("Head")
	var uc := sk.find_bone("UpperChest")
	var hips := sk.find_bone("Hips")
	player.step_pace = 0.0
	for i in int(roundf(1.0 / dt)):
		await _step(puppet, player, rig, dt)
	rig._to_base(rig.base_clip(), float(rig._base_speed[rig._slot]), 0.0, 0.0, true)
	rig._carry_wait = 0.0
	rig._process(0.0)
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 4600
	rig._rng = seeded
	var frames := []
	var t := 0.0
	for leg: Array in legs:
		player.step_pace = float(leg[1]) * pace
		var t0 := t
		for i in int(roundf(float(leg[2]) / dt)):
			var lt := t - t0
			if str(leg[0]) == "jog" and lt >= TURN_AT and lt < TURN_AT + TURN_TIME + dt * 0.5:
				yaw = PI / 2.0 * clampf((lt + dt - TURN_AT) / TURN_TIME, 0.0, 1.0)
				bodyn.rotation.y = yaw
			var ahead := Vector3(cos(yaw), 0.0, -sin(yaw))
			puppet.position += ahead * float(leg[1]) * pace * dt
			var event := ""
			if not ev.is_empty() and str(ev["leg"]) == str(leg[0]) and lt >= float(ev["at"]) and lt < float(ev["at"]) + dt * 0.5:
				event = str(ev["do"])
				match event:
					"blow":
						_rig3d._strike(puppet, player, weapon)
					"jump":
						puppet.position += ahead * 6.0
					"gap":
						AnimRig._clock_msec += 300
					"unseen":
						rig.every = Client3D.POSE_UNSEEN_EVERY
			if not ev.is_empty() and str(ev["do"]) == "unseen" and str(ev["leg"]) == str(leg[0]) and lt >= float(ev["at"]) + 0.3 and rig.every != 1:
				rig.every = 1
				event = "seen"
			await _step(puppet, player, rig, dt)
			t += dt
			var w := held.global_transform * top if held != null else Vector3.ZERO
			var mb := model.global_basis.orthonormalized()
			var hb := (mb.inverse() * (sk.global_basis * sk.get_bone_global_pose(head).basis)).orthonormalized()
			var fwd := hb * Vector3(0, 0, 1)
			var lower := []
			for b: String in LOWER:
				var k := sk.find_bone(b)
				lower.append((sk.global_transform * sk.get_bone_global_pose(k).origin) if k >= 0 else Vector3.ZERO)
			var hips_w := sk.global_transform * sk.get_bone_global_pose(hips).origin
			var ug := sk.global_transform * sk.get_bone_global_pose(uc)
			var sway: Node = puppet.get_meta("sway") if puppet.has_meta("sway") else null
			frames.append({"leg": leg[0], "lt": lt + dt, "amount": rig.carry_amount(), "hips": hips_w.y,
				"uc": ug.basis.orthonormalized().inverse() * (w - ug.origin), "rel": mb.inverse() * (w - hips_w),
				"yaw": rad_to_deg(atan2(fwd.x, fwd.z)), "pitch": rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))), "lower": lower,
				"event": event, "striking": rig.striking(),
				"bounds": _bounds(bctx, sway) if not bctx.is_empty() and rig.carry_amount() > 0.01 and frames.size() % BOUND_EVERY == 0 else {},
				"sway": {} if sway == null else {"active": sway.active, "amount": sway.amount, "lean": sway.lean, "turn": sway.turn,
					"clav": sway.clav, "hand": (sway.hand_off as Vector3) * 100.0, "yaw": sway.yaw, "resets": sway.resets}})
	if not bctx.is_empty():
		for on_bone: Node in (bctx["at"] as Dictionary).values():
			on_bone.queue_free()
	AnimRig._clock_movie = -1
	AnimRig._clock_frame = -1
	player.step_pace = 0.0
	rig.every = 1
	rig.carry("", 0.0)
	rig.set_process(true)
	return frames


func _step(puppet: Node3D, player: Player, rig: AnimRig, dt: float) -> void:
	AnimRig._clock_frame = Engine.get_process_frames()
	AnimRig._clock_msec += int(roundf(dt * 1000.0))
	puppet.remove_meta("stood_at")  # No rest: its REST_STAND_SECONDS run on the wall clock, at the machine's pace.
	_rig3d._animate(puppet)
	_rig3d._sync_bow(player, puppet)
	rig._process(dt)
	await get_tree().process_frame
	# The rigs' clock held through the frame the readings are taken in: a read in a new frame (rig.striking()) adds
	# the wall's frame time to it otherwise (AnimRig.now_msec).
	AnimRig._clock_frame = Engine.get_process_frames()


## The weapon's head: the mean of its vertices within 5 cm of its highest, in the held node's frame.
func _top_of(held: Node3D) -> Vector3:
	if held == null:
		return Vector3.ZERO
	var pts: Array[Vector3] = []
	var high := -INF
	for mesh: MeshInstance3D in held.find_children("*", "MeshInstance3D", true, false):
		var into := held.global_transform.affine_inverse() * mesh.global_transform
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(into * v)
				high = maxf(high, (into * v).y)
	var top := Vector3.ZERO
	var n := 0
	for q in pts:
		if q.y >= high - 0.05:
			top += q
			n += 1
	return top / maxf(n, 1)


func _check_runs(name: String, placing: String, off: Array, on: Array, again: Array) -> void:
	print("== %s" % name)
	# The drive repeats.
	var rep := _against(off, again)
	_check(rep[0] <= REPEAT and rep[2] <= HEAD_REPEAT and rep[3] <= HEAD_REPEAT,
		"%s: the rigid run repeats (lower body %.5f m at %s, head yaw %.2f, pitch %.2f deg at %s; first over %.4f m: %s)" % [
		name, rep[0], rep[1], rep[2], rep[3], rep[4], REPEAT, _first_over(off, again)])
	var same := _against(off, on)
	_check(same[0] <= LOWER_SAME, "%s: sway on, the hips, legs and feet within %.3f m of the rigid run's every frame (most %.5f m, %s)" % [
		name, LOWER_SAME, same[0], same[1]])
	_check(same[2] <= HEAD_YAW_ALLOW and same[3] <= HEAD_PITCH_ALLOW, "%s: sway on, the head's facing within %.1f deg yaw, %.1f pitch of the rigid run's (%.2f, %.2f at %s)" % [
		name, HEAD_YAW_ALLOW, HEAD_PITCH_ALLOW, same[2], same[3], same[4]])
	var off_active := off.filter(func(f: Dictionary) -> bool: return not (f["sway"] as Dictionary).is_empty() and bool(f["sway"]["active"]))
	_check(off_active.is_empty(), "%s: sway off, no frame of it runs (%d)" % [name, off_active.size()])
	# The sway takes the share Client3D read before the rig's frame: the frame the carry goes out it still gives at the
	# last share (its outputs scaled by it); from the next it is off.
	var out_active := 0
	for i in range(1, on.size()):
		if float(on[i]["amount"]) <= 0.0 and float(on[i - 1]["amount"]) <= 0.0 and not (on[i]["sway"] as Dictionary).is_empty() and bool(on[i]["sway"]["active"]):
			out_active += 1
	_check(out_active == 0, "%s: sway on, off on every frame the carry is out (the stand, the ready after the stop): %d" % [name, out_active])
	var first := on.filter(func(f: Dictionary) -> bool: return not (f["sway"] as Dictionary).is_empty() and bool(f["sway"]["active"]))
	if not first.is_empty():
		var s: Dictionary = first[0]["sway"]
		_check(absf(s["lean"]) + absf(s["turn"]) + absf(s["clav"]) + (s["hand"] as Vector3).length() + absf(s["yaw"]) < 0.001,
			"%s: no kick at the first frame (lean %.3f, turn %.3f, clav %.3f, hand %.3f cm)" % [name, s["lean"], s["turn"], s["clav"], (s["hand"] as Vector3).length()])
	# The bounds: on breaks nothing off doesn't, leg by leg.
	var b_off := _breaks(off)
	var b_on := _breaks(on)
	var extra: Array[String] = []
	for k: String in b_on["breaks"]:
		if not (b_off["breaks"] as Dictionary).has(k):
			extra.append("%s x%d" % [k, b_on["breaks"][k]])
	print("    bounds off: %s" % b_off["line"])
	print("    bounds on:  %s" % b_on["line"])
	_check(extra.is_empty(), "%s: sway on breaks no bound the rigid carry keeps on that leg (%s)" % [name, ", ".join(extra) if not extra.is_empty() else "none"])
	_extremes(on)
	# The rows.
	var a_off := _row_a(off)
	var a_on := _row_a(on)
	_check(a_off[0] < A_RANGE and a_on[0] >= A_RANGE and a_on[1] >= A_LAG,
		"%s: (a) jog: the head's range in the upper chest's frame %.1f cm rigid, %.1f cm (%.1f px) on; its height follows the hips' %.2f s behind (best correlation; each step's low after the hips' %s s, mean %.2f)" % [
		name, a_off[0] * 100, a_on[0] * 100, a_on[0] * 100 * _px_per_cm, a_on[1], a_on[2], a_on[3]])
	var b_rig := _row_b(off, again)
	var b := _row_b(on, off)
	_check(b_rig[0] < B_TIME and b[0] >= B_TIME, "%s: (b) start: behind the rigid carry's place by %.1f cm or more till %.2f s from the first step (rigid %.2f s); most %.1f cm (%.1f px)" % [
		name, B_BEHIND * 100, b[0], b_rig[0], b[1] * 100, absf(b[1]) * 100 * _px_per_cm])
	var c := _row_c(on, off)
	var c_rig := _row_c(off, again)
	if placing == "j2":
		_check(c_rig[0] < C_AHEAD and c[0] >= C_AHEAD, "%s: (c) stop: ahead of the rigid carry during the hold most %.1f cm (%.1f px), %.2f s of it over %.1f cm (rigid %.1f cm)" % [
			name, c[0] * 100, c[0] * 100 * _px_per_cm, c[1], C_AHEAD * 100, c_rig[0] * 100])
	else:
		print("    (c) stop: ahead of the rigid carry during the hold most %.1f cm, %.2f s over %.1f cm: the shipped carry has no room ahead there (not checked)" % [
			c[0] * 100, c[1], C_AHEAD * 100])
	var d := _row_d(on, off)
	var d_rig := _row_d(off, again)
	_check(d_rig[0] < D_LAG and d[0] >= D_LAG, "%s: (d) turn: the head's bearing behind the rigid carry's most %.1f deg (%.1f px at its reach), %.2f s after the turn began, %.2f s over %.0f deg (rigid %.1f)" % [
		name, d[0], deg_to_rad(d[0]) * absf(d[3]) * 100 * _px_per_cm, d[1], d[2], D_LAG, d_rig[0]])


## [lower body most (m), where, head yaw most, head pitch most, where] of [param b] against [param a], frame by frame.
func _against(a: Array, b: Array) -> Array:
	var low := 0.0
	var where := "-"
	var hy := 0.0
	var hp := 0.0
	var hwhere := "-"
	for i in mini(a.size(), b.size()):
		for k in (a[i]["lower"] as Array).size():
			var d: float = (a[i]["lower"][k] as Vector3).distance_to(b[i]["lower"][k])
			if d > low:
				low = d
				where = "%s %s %.2f" % [LOWER[k], a[i]["leg"], a[i]["lt"]]
		var y := absf(wrapf(float(b[i]["yaw"]) - float(a[i]["yaw"]), -180.0, 180.0))
		var p := absf(float(b[i]["pitch"]) - float(a[i]["pitch"]))
		if y > hy or p > hp:
			hwhere = "%s %.2f" % [a[i]["leg"], a[i]["lt"]]
		hy = maxf(hy, y)
		hp = maxf(hp, p)
	return [low, where, hy, hp, hwhere]


func _first_over(a: Array, b: Array) -> String:
	for i in mini(a.size(), b.size()):
		for k in (a[i]["lower"] as Array).size():
			if (a[i]["lower"][k] as Vector3).distance_to(b[i]["lower"][k]) > REPEAT:
				return "frame %d, %s %.2f, %s %s against %s, carry %.2f against %.2f" % [i, a[i]["leg"], a[i]["lt"], LOWER[k],
					str(a[i]["lower"][k]), str(b[i]["lower"][k]), a[i]["amount"], b[i]["amount"]]
	return "none"


## (a) the jog before the turn: the head's range in the upper chest's frame, and each hips' low to the head's next
## low there (within a step: the load answers the step's dip, so a low before the hips' is the last step's): [range,
## mean lag, the lags].
func _row_a(fr: Array) -> Array:
	var seg := fr.filter(func(f: Dictionary) -> bool: return str(f["leg"]) == "jog" and float(f["lt"]) > 0.4 and float(f["lt"]) <= TURN_AT)
	if seg.size() < 10:
		return [0.0, 0.0, "", 0.0]
	var lo := INF
	var hi := -INF
	for f: Dictionary in seg:
		lo = minf(lo, (f["uc"] as Vector3).y)
		hi = maxf(hi, (f["uc"] as Vector3).y)
	var lows: Array[int] = []
	for i in range(1, seg.size() - 1):
		if float(seg[i]["hips"]) < float(seg[i - 1]["hips"]) and float(seg[i]["hips"]) <= float(seg[i + 1]["hips"]):
			lows.append(i)
	if lows.size() < 2 or hi - lo < 0.001:
		return [hi - lo, 0.0, "-", 0.0]
	var step := float(lows[-1] - lows[0]) / (lows.size() - 1)
	var lags: Array[String] = []
	var sum := 0.0
	var n := 0
	for i: int in lows:
		var best := -1
		for j in range(i, mini(i + int(ceilf(step)), seg.size() - 1)):
			if j > 0 and float(seg[j]["uc"].y) <= float(seg[j - 1]["uc"].y) and float(seg[j]["uc"].y) <= float(seg[j + 1]["uc"].y):
				best = j
				break
		if best >= 0:
			lags.append("%.2f" % ((best - i) * DT))
			sum += (best - i) * DT
			n += 1
	# The lag at which the head's height in the chest's frame best follows the hips' height (their correlation, over
	# lags 0 up to a step), the steps' lows aside.
	var best_lag := 0
	var best := -INF
	for lag in range(0, int(ceilf(step))):
		var c := 0.0
		var m := 0
		var mh := 0.0
		var mu := 0.0
		for i in range(0, seg.size() - lag):
			mh += float(seg[i]["hips"])
			mu += float(seg[i + lag]["uc"].y)
			m += 1
		mh /= m
		mu /= m
		for i in range(0, seg.size() - lag):
			c += (float(seg[i]["hips"]) - mh) * (float(seg[i + lag]["uc"].y) - mu)
		c /= m
		if c > best:
			best = c
			best_lag = lag
	return [hi - lo, best_lag * DT, ", ".join(lags), sum / maxf(n, 1)]


## (b) the start (the walk's first second): the head behind [param ref]'s place that frame in the body's frame, less
## the walk's settled difference: [the last time it is behind by B_BEHIND, the most].
func _row_b(fr: Array, ref: Array) -> Array:
	var rest := 0.0
	var n := 0
	for i in mini(fr.size(), ref.size()):
		if str(fr[i]["leg"]) == "walk" and float(fr[i]["lt"]) > 1.2:
			rest += (fr[i]["rel"] as Vector3).z - (ref[i]["rel"] as Vector3).z
			n += 1
	rest /= maxf(n, 1)
	var behind := 0.0
	var most := 0.0
	for i in mini(fr.size(), ref.size()):
		if str(fr[i]["leg"]) != "walk" or float(fr[i]["lt"]) > 1.0:
			continue
		var d: float = (fr[i]["rel"] as Vector3).z - (ref[i]["rel"] as Vector3).z - rest
		most = minf(most, d)
		if d < -B_BEHIND:
			behind = float(fr[i]["lt"])
	return [behind, most]


## (c) the stop's hold (the stop while the carry is full): [ahead of [param ref] most, seconds over C_AHEAD].
func _row_c(fr: Array, ref: Array) -> Array:
	var most := 0.0
	var over := 0
	for i in mini(fr.size(), ref.size()):
		if str(fr[i]["leg"]) != "stop" or float(fr[i]["amount"]) < 1.0:
			continue
		var d: float = (fr[i]["rel"] as Vector3).z - (ref[i]["rel"] as Vector3).z
		most = maxf(most, d)
		if d > C_AHEAD:
			over += 1
	return [most, over * DT]


## (d) the turn (left): the head's bearing about the hips in the body's frame behind [param ref]'s: [most (deg), when
## after the turn began, seconds over D_LAG, its reach (m)].
func _row_d(fr: Array, ref: Array) -> Array:
	var lag := 0.0
	var at := 0.0
	var over := 0
	var reach := 0.0
	for i in mini(fr.size(), ref.size()):
		if str(fr[i]["leg"]) != "jog" or float(fr[i]["lt"]) < TURN_AT:
			continue
		var a: Vector3 = fr[i]["rel"]
		var b: Vector3 = ref[i]["rel"]
		var d := wrapf(rad_to_deg(atan2(a.x, a.z) - atan2(b.x, b.z)), -180.0, 180.0)
		if d < lag:
			lag = d
			at = float(fr[i]["lt"]) - TURN_AT
			reach = Vector2(a.x, a.z).length()
		if d <= -D_LAG:
			over += 1
	return [-lag, at, over * DT, reach]


func _extremes(fr: Array) -> void:
	var m := {"lean+": 0.0, "lean-": 0.0, "turn+": 0.0, "turn-": 0.0, "clav": 0.0, "up+": 0.0, "up-": 0.0, "ahead+": 0.0, "ahead-": 0.0, "yaw": 0.0}
	for f: Dictionary in fr:
		var s: Dictionary = f["sway"]
		if s.is_empty() or not bool(s["active"]):
			continue
		m["lean+"] = maxf(m["lean+"], s["lean"]); m["lean-"] = minf(m["lean-"], s["lean"])
		m["turn+"] = maxf(m["turn+"], s["turn"]); m["turn-"] = minf(m["turn-"], s["turn"])
		m["clav"] = maxf(m["clav"], s["clav"])
		m["up+"] = maxf(m["up+"], (s["hand"] as Vector3).y); m["up-"] = minf(m["up-"], (s["hand"] as Vector3).y)
		m["ahead+"] = maxf(m["ahead+"], (s["hand"] as Vector3).z); m["ahead-"] = minf(m["ahead-"], (s["hand"] as Vector3).z)
		m["yaw"] = maxf(m["yaw"], absf(s["yaw"]))
	print("    sway: lean %+.1f..%+.1f deg, turn %+.1f..%+.1f, clav %.1f, hand up %+.1f..%+.1f cm, ahead %+.1f..%+.1f cm, hand yaw |%.1f|" % [
		m["lean-"], m["lean+"], m["turn-"], m["turn+"], m["clav"], m["up-"], m["up+"], m["ahead-"], m["ahead+"], m["yaw"]])


## The largest frame-to-frame step of each output over a run: {lean, turn, clav, hand (cm), yaw}.
func _steps(fr: Array) -> Dictionary:
	var out := {"lean": 0.0, "turn": 0.0, "clav": 0.0, "hand": 0.0, "yaw": 0.0}
	for i in range(1, fr.size()):
		var a: Dictionary = fr[i - 1]["sway"]
		var b: Dictionary = fr[i]["sway"]
		if a.is_empty() or b.is_empty():
			continue
		for k: String in ["lean", "turn", "clav", "yaw"]:
			out[k] = maxf(out[k], absf(float(b[k]) - float(a[k])))
		out["hand"] = maxf(out["hand"], (b["hand"] as Vector3).distance_to(a["hand"]))
	return out


## No kick: a jump of 6 m in a frame, a 300 ms gap, a return from posing one frame in eight, each in the jog; and a
## blow from a run (0.72 s into the jog) takes the sway off, eased, and keeps it off while it strikes.
func _test_events(plain: Array, steps: Dictionary) -> void:
	for ev: Dictionary in [{"leg": "jog", "at": 0.72, "do": "jump"}, {"leg": "jog", "at": 0.72, "do": "gap"},
			{"leg": "jog", "at": 0.6, "do": "unseen"}, {"leg": "jog", "at": 0.72, "do": "blow"}]:
		var fr: Array = await _drive("man", "battle_axe", true, SHORT, DT, ev, false)
		var near := _steps(fr.filter(func(f: Dictionary) -> bool: return str(f["leg"]) == "jog"))
		var worst := ""
		for k: String in near:
			if float(near[k]) > float(steps[k]) * KICK + KICK_LEAST:
				worst += " %s %.2f (run's %.2f)" % [k, near[k], steps[k]]
		var resets := 0
		for f: Dictionary in fr:
			if not (f["sway"] as Dictionary).is_empty():
				resets = maxi(resets, int(f["sway"]["resets"]))
		if str(ev["do"]) == "blow":
			var struck := fr.filter(func(f: Dictionary) -> bool: return bool(f["striking"]))
			var late := struck.slice(int(ceilf((Client3D.CARRY_SWAY_STRIKE_FADE + DT) / DT)))
			var on_late := late.filter(func(f: Dictionary) -> bool: return not (f["sway"] as Dictionary).is_empty() and bool(f["sway"]["active"]))
			_check(not struck.is_empty() and on_late.is_empty() and worst == "",
				"a blow from a run: the sway eased off over %.1f s and off while it strikes (%d frames striking, %d with the sway on after the ease; steps%s)" % [
				Client3D.CARRY_SWAY_STRIKE_FADE, struck.size(), on_late.size(), worst if worst != "" else " within the run's"])
		else:
			_check(worst == "" and (resets >= 1 or str(ev["do"]) == "unseen"), "no kick at a %s in the jog (%d reset%s; steps%s)" % [
				ev["do"], resets, "" if resets == 1 else "s", worst if worst != "" else " within the run's"])


## Steady at 30 fps and at 100 ms frames: the outputs finite, their extremes near the 50 fps run's, the rows' (a) range too.
func _test_steady(plain: Array) -> void:
	var base := _ext(plain)
	var a0: float = _row_a(plain)[0]
	for dt: float in [1.0 / 30.0, 0.1]:
		var fr: Array = await _drive("man", "battle_axe", true, LEGS, dt, {}, false)
		var e := _ext(fr)
		var bad := ""
		for k: String in e:
			if is_nan(float(e[k])) or is_inf(float(e[k])) or float(e[k]) > float(base[k]) * STEADY + STEADY_LEAST:
				bad += " %s %.2f (50 fps %.2f)" % [k, e[k], base[k]]
		_check(bad == "", "steady at %.0f ms frames: the sway's extremes within %.1f times the 50 fps run's (lean %.1f, turn %.1f, hand %.1f cm, at 50 fps %.1f, %.1f, %.1f)%s" % [
			dt * 1000, STEADY, e["lean"], e["turn"], e["hand"], base["lean"], base["turn"], base["hand"], bad])
	print("    (a) at 50 fps for the above: %.1f cm" % (a0 * 100))


func _ext(fr: Array) -> Dictionary:
	var out := {"lean": 0.0, "turn": 0.0, "clav": 0.0, "hand": 0.0, "yaw": 0.0}
	for f: Dictionary in fr:
		var s: Dictionary = f["sway"]
		if s.is_empty():
			continue
		for k: String in ["lean", "turn", "clav", "yaw"]:
			out[k] = maxf(out[k], absf(float(s[k])))
		out["hand"] = maxf(out["hand"], (s["hand"] as Vector3).length())
	return out


## Off means off: a one-hander's walk and jog make or run none; a body outside CARRY_SWAY_BODIES and anyone but a
## player get none made (Client3D._carry_sway's own gate, asked directly on the player's puppet).
func _test_off_means_off() -> void:
	var fr: Array = await _drive("man", "sword", true, SHORT, DT, {}, false)
	var ran := fr.filter(func(f: Dictionary) -> bool: return not (f["sway"] as Dictionary).is_empty() and bool(f["sway"]["active"]))
	_check(ran.is_empty(), "a one-hander (the sword): no frame of the sway runs (%d)" % ran.size())
	var player := _player()
	var puppet: Node3D = _rig3d._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	var sway: Variant = puppet.get_meta("sway") if puppet.has_meta("sway") else null
	puppet.remove_meta("sway")
	var gaits: Array = puppet.get_meta("gaits", Client3D.GAITS)
	var clip := str(Client3D.CARRY_PLACINGS["shipped"])
	Client3D.carry_sway = true
	rig.carry(clip, 0.0)
	rig._carry_wait = 0.0
	rig._process(0.0)
	var share := rig.carry_amount() if rig.carry_clip() != "" else 0.0
	var kind_was := rig.kind
	rig.kind = "imp"
	_rig3d._carry_sway(player, puppet, rig, clip, gaits, ["battle_axe", ""])
	var other_body := puppet.has_meta("sway")
	rig.kind = kind_was
	puppet.remove_meta("sway")
	var someone := GridEntity.new()
	_rig3d._carry_sway(someone, puppet, rig, clip, gaits, ["battle_axe", ""])
	var not_player := puppet.has_meta("sway")
	someone.free()
	if puppet.has_meta("sway") and puppet.get_meta("sway") != sway:
		(puppet.get_meta("sway") as Node).queue_free()
	puppet.remove_meta("sway")
	if sway != null:
		puppet.set_meta("sway", sway)
	rig.carry("", 0.0)
	_check(share > 0.0 and not other_body and not not_player, "the carry on (%.2f), none made for another body (an imp's rig: %s) or anyone but a player (%s)" % [
		share, "made" if other_body else "none", "made" if not_player else "none"])


## The bounds' context for _bounds (as carry_view.gd's read wants it), once a run.
func _bounds_context(puppet: Node3D, model: Node3D, sk: Skeleton3D, held: Node3D) -> Dictionary:
	var at := CarryView.attach(sk)
	var by_name := {}
	for bi: int in at:
		by_name[sk.get_bone_name(bi)] = at[bi]
	var lamp := Client3D._hanging_lantern(true)
	add_child(lamp)
	var lamp_box := _lamp_box(lamp)
	lamp.queue_free()
	var zones := {"L thigh": [sk.find_bone("LeftUpperLeg")], "R thigh": [sk.find_bone("RightUpperLeg")],
		"torso": [sk.find_bone("Hips"), sk.find_bone("Spine"), sk.find_bone("Chest"), sk.find_bone("UpperChest")]}
	return {"model": model, "sk": sk, "at": at, "by_name": by_name, "piece": held, "head": CarryView.head_skin(model, sk),
		"pm": CarryView.piece_mesh(held), "views": CarryView.views(), "skin": _zone_skin(model, sk, zones), "lamp_box": lamp_box,
		"sockets": puppet.get_meta("sockets"), "reach": puppet.get_meta("reach")}


## One frame's bounds: overlap (cm2, the most in any view), chin and shoulder (carry_view's top_chin and
## head_top_shoulders), wrist ([L bend, |L twist|, R bend, |R twist|]), clear (the left forearm and hand off the head's
## centre), lamp (the piece off the lantern at the belt and at the bag), lgrip, rgrip (the right hand off the sway's
## target while it runs), thigh, inside (a zone a piece vertex is inside of).
func _bounds(ctx: Dictionary, sway: Node) -> Dictionary:
	var model: Node3D = ctx["model"]
	var sk: Skeleton3D = ctx["sk"]
	var by_name: Dictionary = ctx["by_name"]
	var piece: Node3D = ctx["piece"]
	var pm: Dictionary = ctx["pm"]
	var r := {}
	var cv := CarryView.read(model, sk, ctx["at"], piece, ctx["head"], pm, ctx["views"])
	var overlap := 0.0
	for v: String in ctx["views"]:
		overlap = maxf(overlap, (cv[v] as Vector3).x)
	r["overlap"] = overlap
	r["chin"] = cv["top_chin"]
	r["shoulder"] = cv["head_top_shoulders"]
	var wl := _wrist_turn(sk, by_name, "Left")
	var wr := _wrist_turn(sk, by_name, "Right")
	r["wrist"] = [wl.x, absf(wl.y), wr.x, absf(wr.y)]
	var hd := by_name["Head"] as Node3D
	var centre := hd.global_position + hd.global_basis.y.normalized() * HEAD_UP
	var clear := INF
	for pair: Array in [["LeftLowerArm", "LeftHand"], ["LeftHand", "LeftMiddleProximal"]]:
		var a := (by_name[pair[0]] as Node3D).global_position
		var b := (by_name[pair[1]] as Node3D).global_position
		clear = minf(clear, Geometry3D.get_closest_point_to_segment(centre, a, b).distance_to(centre))
	r["clear"] = clear
	var belt := ((ctx["sockets"] as Dictionary)["belt_r"] as Node3D).global_transform
	r["lamp"] = minf(_box_gap(ctx["lamp_box"], belt.affine_inverse(), piece, pm),
		_box_gap(ctx["lamp_box"], (belt * Transform3D(Basis.IDENTITY, Client3D.LANTERN_BY_BAG)).affine_inverse(), piece, pm))
	var reach: HandReach = ctx["reach"]
	r["lgrip"] = (by_name["LeftHand"] as Node3D).global_position.distance_to(reach.target.global_position)
	var tgt: Variant = sway.get("target") if sway != null else null
	r["rgrip"] = (by_name["RightHand"] as Node3D).global_position.distance_to((tgt as Node3D).global_position) if tgt is Node3D and sway.active else 0.0
	var thigh := INF
	var inside := ""
	for zone: String in ctx["skin"]:
		var verts := []
		for e: Array in ctx["skin"][zone]:
			verts.append(_skinned_n(e, ctx["at"]))
		var grid := _grid(verts)
		for q: Vector3 in pm["verts"]:
			var near := _near(piece.global_transform * q, verts, grid)
			if zone != "torso":
				thigh = minf(thigh, near.x)
			if near.y > 0.5 and near.x < 0.05 and inside == "":
				inside = zone
	r["thigh"] = thigh
	r["inside"] = inside
	return r


## The run's most against each bound, and its breaks: {"breaks": {"<bound> (<leg>)": frames}, "line"}.
func _breaks(fr: Array) -> Dictionary:
	var m := {"chin": -INF, "shoulder": -INF, "Lb": 0.0, "Lt": 0.0, "Rb": 0.0, "Rt": 0.0, "clear": INF, "lamp": INF, "thigh": INF, "rgrip": 0.0, "overlap": 0.0}
	var breaks := {}
	var n := 0
	for f: Dictionary in fr:
		var r: Dictionary = f["bounds"]
		if r.is_empty():
			continue
		n += 1
		var w: Array = r["wrist"]
		m["overlap"] = maxf(m["overlap"], r["overlap"])
		m["chin"] = maxf(m["chin"], r["chin"])
		m["shoulder"] = maxf(m["shoulder"], r["shoulder"])
		m["Lb"] = maxf(m["Lb"], w[0]); m["Lt"] = maxf(m["Lt"], w[1]); m["Rb"] = maxf(m["Rb"], w[2]); m["Rt"] = maxf(m["Rt"], w[3])
		m["clear"] = minf(m["clear"], r["clear"])
		m["lamp"] = minf(m["lamp"], r["lamp"])
		m["thigh"] = minf(m["thigh"], r["thigh"])
		m["rgrip"] = maxf(m["rgrip"], r["rgrip"])
		var why: Array[String] = []
		if float(r["overlap"]) > 0.0:
			why.append("overlap")
		if float(r["chin"]) > CHIN:
			why.append("chin")
		if float(r["shoulder"]) > SHOULDER:
			why.append("shoulder")
		if float(w[0]) > WRIST_BEND or float(w[1]) > WRIST_TWIST:
			why.append("L wrist")
		if float(w[2]) > WRIST_BEND or float(w[3]) > WRIST_TWIST:
			why.append("R wrist")
		if float(r["clear"]) < HEAD_CLEAR:
			why.append("head clear")
		if float(r["lamp"]) < LAMP:
			why.append("lamp")
		if str(r["inside"]) != "":
			why.append("inside " + str(r["inside"]))
		if float(r["rgrip"]) > GRIP:
			why.append("R target")
		for wy in why:
			var key := "%s (%s)" % [wy, f["leg"]]
			breaks[key] = int(breaks.get(key, 0)) + 1
	var parts: Array[String] = []
	for k: String in breaks:
		parts.append("%s x%d" % [k, breaks[k]])
	return {"breaks": breaks, "line": "%d frames: overlap %.0f, chin %.3f, shoulder %.3f, wrists L %.0f/%.0f R %.0f/%.0f, arm off head %.3f, lamp %.3f, thigh %.3f, R target %.4f; breaks %s" % [
		n, m["overlap"], m["chin"], m["shoulder"], m["Lb"], m["Lt"], m["Rb"], m["Rt"], m["clear"], m["lamp"], m["thigh"], m["rgrip"],
		", ".join(parts) if not parts.is_empty() else "none"]}


static func _wrist_turn(sk: Skeleton3D, at: Dictionary, side: String) -> Vector2:
	var hand := sk.find_bone(side + "Hand")
	var rel := (at[side + "LowerArm"] as Node3D).global_basis.orthonormalized().inverse() * (at[side + "Hand"] as Node3D).global_basis.orthonormalized()
	var d := Quaternion(sk.get_bone_rest(hand).basis.orthonormalized().inverse() * rel)
	var twist := Quaternion(0.0, d.y, 0.0, d.w).normalized()
	var y := (d * twist.inverse()) * Vector3.UP
	return Vector2(rad_to_deg(acos(clampf(y.y, -1.0, 1.0))), wrapf(rad_to_deg(2.0 * atan2(twist.y, twist.w)), -180.0, 180.0))


## The Body mesh's vertices by zone (the bone each goes with most in [param zones]' lists): [vertex, normal, influences].
func _zone_skin(model: Node3D, sk: Skeleton3D, zones: Dictionary) -> Dictionary:
	var sets := {}
	for z: String in zones:
		sets[z] = []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or mi.name != "Body":
			continue
		var skin := mi.skin
		var binds := []
		for i in skin.get_bind_count():
			var bb := skin.get_bind_bone(i)
			if bb < 0:
				bb = sk.find_bone(skin.get_bind_name(i))
			binds.append([bb, skin.get_bind_pose(i)])
		var fix := mi.global_transform * sk.global_transform.affine_inverse()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():
				continue
			var per := bones.size() / verts.size()
			for v in verts.size():
				var infl := []
				var best := -1
				var bw := 0.0
				for k in per:
					var w := weights[v * per + k]
					if w <= 0.0:
						continue
					var bind: Array = binds[bones[v * per + k]]
					infl.append([bind[0], bind[1], w, fix])
					if w > bw:
						bw = w
						best = bind[0]
				for z: String in zones:
					if best in (zones[z] as Array):
						(sets[z] as Array).append([verts[v], normals[v] if v < normals.size() else Vector3.UP, infl])
	return sets


static func _skinned_n(e: Array, at: Dictionary) -> Array:
	var sum := Vector3.ZERO
	var nsum := Vector3.ZERO
	var tw := 0.0
	for inf: Array in e[2]:
		var t: Transform3D = (inf[3] as Transform3D) * (at[inf[0]] as Node3D).global_transform * (inf[1] as Transform3D)
		sum += (t * (e[0] as Vector3)) * float(inf[2])
		nsum += (t.basis * (e[1] as Vector3)) * float(inf[2])
		tw += float(inf[2])
	return [sum / maxf(tw, 0.0001), nsum.normalized()]


static func _grid(verts: Array) -> Dictionary:
	var grid := {}
	for k in verts.size():
		var key := Vector3i((verts[k][0] as Vector3 / HASH).floor())
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(k)
	return grid


## The nearest skinned vertex to [param p] within HASH: (its distance, 1 when p is behind its normal).
static func _near(p: Vector3, verts: Array, grid: Dictionary) -> Vector2:
	var c := Vector3i((p / HASH).floor())
	var best := INF
	var behind := 0.0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for k: int in grid.get(c + Vector3i(dx, dy, dz), []):
					var v: Vector3 = verts[k][0]
					var d := p.distance_to(v)
					if d < best and d <= HASH:
						best = d
						behind = 1.0 if (p - v).dot(verts[k][1] as Vector3) < 0.0 else 0.0
	return Vector2(best, behind)


static func _lamp_box(lamp: Node3D) -> AABB:
	var verts: PackedVector3Array = CarryView.piece_mesh(lamp)["verts"]
	var box := AABB(verts[0], Vector3.ZERO)
	for q in verts:
		box = box.expand(q)
	return box


static func _box_gap(box: AABB, into: Transform3D, piece: Node3D, pm: Dictionary) -> float:
	var least := INF
	var to := into * piece.global_transform
	for v: Vector3 in pm["verts"]:
		var q := to * v
		var d := (q - q.clamp(box.position, box.end)).length()
		if d == 0.0:
			d = -minf(minf(minf(q.x - box.position.x, box.end.x - q.x), minf(q.y - box.position.y, box.end.y - q.y)),
				minf(q.z - box.position.z, box.end.z - q.z))
		least = minf(least, d)
	return least


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
