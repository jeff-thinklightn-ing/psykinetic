extends SkeletonModifier3D
## A two-hander's weight in the carry (451 amended (14), TASK 16 step 2; Jeff on the carry: "the axe is heavy it would
## move a lot with the body and is physics question - that would make it look real"). Trunk-led: the load is a damped
## spring hung on the body, and the trunk gives to it: the Spine leans forward with the pace and with the load's lag
## fore and aft, and counter-turns with its lag in yaw (the body's turns and the hips' own swing in the gait); the
## right clavicle drops as the load falls behind the hips at a footfall. The Neck gives the spine's turn and lean back,
## so the head keeps its facing. The hands give inside the placing's own room: the right hand carried down/up and
## back/ahead by a TwoBoneIK3D on the right arm, turned about the vertical (the left follows by HandReach, after).
##
## Driven by the drawn body alone (no physics body, no randomness): the Hips' height for the footfalls, and the body's
## velocity and yaw rate, low-passed, for the starts, stops and turns, integrated in fixed sub-steps of STEP on the
## rigs' clock (AnimRig.now_msec), so 30 frames a second and 100 ms frames move it alike. Heavier is slower and further
## (Items.weight_of, WEIGHT for a piece with none). Each give is held inside ROOM (C:/dev/review/animation/axe_run/
## sway/envelope.txt: the most each move alone passes every bound on all frames of the loop, per placing, body and
## gait) times MARGIN, by a soft clamp (cells cut further where moves together broke a bound: TIGHTENED); the
## room is the tighter of the clip's gait and the pace's (a start into the sprint still on the jog's clip), eased
## over ROOM_EASE where it widens and ROOM_SHRINK where it narrows. [member amount] is the carry layer's share: at 0 every part is off and the state starts again from rest.
## From rest on a first frame (the carry coming on). No kick: on a gap over RESET_DT, a body moved over RESET_JUMP in
## one (a zone change, an admin move, a respawn) and a body posed one frame in POSE_UNSEEN_EVERY (out of the frame), the
## give is held as it was and its readings taken again from there.

## The share of each room the give may take.
const MARGIN := 0.5
## A piece's weight (items.json's) when it has none.
const WEIGHT := 5.0
## The weight the springs below are tuned at: lighter is quicker and less, heavier slower and further.
const WEIGHT_REF := 6.0
const WEIGHT_GAIN := Vector2(0.6, 1.5)
const STEP := 1.0 / 120.0
const RESET_DT := 0.25
const RESET_JUMP := 1.0
const ROOM_EASE := 0.15
const ROOM_SHRINK := 0.03
## The load's springs: up and down on the hips, fore and aft on the body's pace, in yaw on its turn (rad/s, damping).
const VERT := Vector2(12.5, 0.35)
const FORE := Vector2(7.5, 0.5)
const YAW := Vector2(9.0, 0.45)
## The pace low-passed (s), and the lean's own slower follow of it (s).
const PACE_LAG := 0.08
const LEAN_LAG := 0.3
## Gains: the hand's give per m of the load's lag (up, ahead), the clavicle and the lean per m of it (deg), the lean per
## m/s of pace (deg), the spine's and the hand's turn per degree of the load's yaw lag.
const HAND_UP := 1.0
const HAND_AHEAD := 0.15
const CLAV_DROP := 150.0
const LEAN_BOB := 50.0
const LEAN_AHEAD := 8.0
const LEAN_PACE := 1.2
const TURN := 0.3
const HAND_YAW := 0.3
## The room, from envelope.txt: per carry clip, body (AnimRig.kind) and gait (0 walk, 1 jog, 2 sprint), [the hand
## down, up, back, ahead (cm); its yaw left, right; the lean forward, back; the turn left, right; the clavicle down
## (degrees)]. 32 is the probe's top (nothing broke under it).
const ROOM := {
	"Axe_Carry": {
		"human_m": [[2.0, 4.0, 8.0, 1.0, 7.5, 1.4, 32.0, 4.0, 32.0, 32.0, 3.8], [1.6, 3.0, 9.0, 1.1, 6.5, 1.5, 30.0, 3.8, 32.0, 32.0, 2.0],
			[1.0, 3.8, 6.5, 1.8, 5.0, 2.5, 12.0, 32.0, 32.0, 18.0, 14.0]],
		"human_f": [[2.0, 2.5, 8.0, 1.0, 6.0, 1.5, 30.0, 2.8, 32.0, 32.0, 2.3], [1.5, 1.0, 9.0, 1.1, 6.0, 1.6, 26.0, 1.5, 32.0, 32.0, 0.8],
			[1.0, 3.5, 2.3, 1.8, 5.0, 2.5, 4.5, 32.0, 32.0, 6.0, 5.0]]},
	"Axe_Carry_J2": {
		"human_m": [[6.5, 5.0, 5.0, 5.0, 2.8, 6.5, 32.0, 16.0, 32.0, 32.0, 7.0], [6.0, 4.5, 5.5, 5.0, 2.0, 7.0, 28.0, 24.0, 32.0, 32.0, 4.5],
			[3.5, 3.3, 9.0, 8.0, 1.4, 15.0, 7.0, 32.0, 12.0, 32.0, 2.3]],
		"human_f": [[8.0, 5.0, 4.5, 6.5, 2.8, 8.0, 32.0, 22.0, 32.0, 32.0, 8.0], [7.0, 4.5, 5.0, 6.5, 2.0, 9.0, 24.0, 28.0, 32.0, 32.0, 5.0],
			[4.0, 0.0, 6.5, 9.0, 1.4, 18.0, 0.0, 32.0, 13.0, 18.0, 0.4]]},
}
## The cells cut below envelope.txt's (moves alone) where moves together broke a bound on the probe
## (C:/dev/review/animation/axe_run/sway/tune11_tune.txt): [clip, body, gait, cell, envelope's, why].
const TIGHTENED := [
	["Axe_Carry", "human_f", 2, 10, 8.0, "the lantern at the sprint, the clavicle beside the lean"],
	["Axe_Carry_J2", "human_f", 2, 1, 0.4, "the chin at the sprint, the rigid carry 2 mm off it"],
	["Axe_Carry_J2", "human_f", 2, 6, 0.9, "the chin at the sprint, the rigid carry 2 mm off it"],
]
const ROOM_NAMES := ["down", "up", "back", "ahead", "yaw left", "yaw right", "lean fwd", "lean back", "turn left", "turn right", "clav down"]


## The hand's turn (the second stage, after the arm's IK): the right hand's basis as the first stage wants it.
class HandTurn extends SkeletonModifier3D:
	var twin: Node

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or twin == null:
			return
		var hand := sk.find_bone("RightHand")
		var now := sk.get_bone_global_pose(hand)
		sk.set_bone_global_pose(hand, Transform3D(twin.want, now.origin))


var body: Node3D
var rig: AnimRig
var ik: TwoBoneIK3D
var turn_stage: HandTurn
var target: Node3D
var pole: Node3D
## The carry layer's share (Client3D._carry_sway sets it each frame).
var amount := 0.0
## The held piece's weight.
var weight := WEIGHT
## The give as last applied (the hand's in m, the rest in degrees), and the hand's wanted basis for HandTurn.
var hand_off := Vector3.ZERO
var yaw := 0.0
var lean := 0.0
var turn := 0.0
var clav := 0.0
var want := Basis()
## Each frame's own reading, for the rows: the load's lag up (m), ahead (m) and in yaw (rad).
var lag := Vector3.ZERO
var resets := 0

var _fresh := true
var _ms := 0
var _at := Vector3.ZERO
var _facing := 0.0
var _hips_y := 0.0
var _hips_yaw := 0.0
var _room: Array = []
var _room_want: Array = []
# The load: [height, its speed], [lag ahead, its speed along], [yaw lag, its yaw rate]; the pace and the lean's pace.
var _v := Vector2.ZERO
var _f := Vector2.ZERO
var _y := Vector2.ZERO
var _pace := 0.0
var _lean_pace := 0.0


## The sway on [param sk] of [param model] (the drawn body, x its left, z ahead), its three parts put before ReachPlace
## (HandReach's first), off till Client3D gives it an amount.
static func make(sk: Skeleton3D, model: Node3D, of_rig: AnimRig) -> Node:
	var me: SkeletonModifier3D = (load("res://client3d/carry_sway.gd") as GDScript).new()
	me.name = "Sway"
	me.set("body", model)
	me.set("rig", of_rig)
	var t := Node3D.new()
	var p := Node3D.new()
	me.add_child(t)
	me.add_child(p)
	me.set("target", t)
	me.set("pole", p)
	sk.add_child(me)
	var arm := TwoBoneIK3D.new()
	arm.name = "SwayArm"
	arm.setting_count = 1
	arm.set_root_bone_name(0, "RightUpperArm")
	arm.set_middle_bone_name(0, "RightLowerArm")
	arm.set_end_bone_name(0, "RightHand")
	sk.add_child(arm)
	arm.set_target_node(0, arm.get_path_to(t))
	arm.set_pole_node(0, arm.get_path_to(p))
	var hand := HandTurn.new()
	hand.name = "SwayHand"
	hand.twin = me
	sk.add_child(hand)
	if sk.has_node("ReachPlace"):
		var first := sk.get_node("ReachPlace").get_index()
		sk.move_child(me, first)
		sk.move_child(arm, first + 1)
		sk.move_child(hand, first + 2)
	me.set("ik", arm)
	me.set("turn_stage", hand)
	me.call("set_on", 0.0)
	return me


## The carry's share now: every part off at 0 (and the state at rest for the next).
func set_on(share: float) -> void:
	amount = clampf(share, 0.0, 1.0)
	var on := amount > 0.0
	if not on:
		_fresh = true
		hand_off = Vector3.ZERO
		yaw = 0.0
		lean = 0.0
		turn = 0.0
		clav = 0.0
		lag = Vector3.ZERO
	active = on
	ik.active = on
	ik.influence = amount
	turn_stage.active = on
	turn_stage.influence = amount


## The room for the carry clip, the body and the gait index, times MARGIN ([] if none is measured).
static func room_of(clip: String, kind: String, gait: int, by_pace := -1) -> Array:
	var by_body: Dictionary = ROOM.get(clip, {})
	var cells: Array = by_body.get(kind, [])
	if cells.is_empty():
		return []
	var row: Array = cells[clampi(gait, 0, cells.size() - 1)]
	var other: Array = cells[clampi(by_pace, 0, cells.size() - 1)] if by_pace >= 0 else row
	var out := []
	for j in row.size():
		out.append(minf(float(row[j]), float(other[j])) * MARGIN)
	return out


## Toward [param room] (room_of's) for the gait now, eased over ROOM_EASE where it widens and ROOM_SHRINK where it
## narrows (a tighter gait's cell holds within a frame or two); taken at once from rest.
func set_room(room: Array) -> void:
	if room.is_empty():
		return
	_room_want = room
	if _room.is_empty() or _fresh:
		_room = room.duplicate()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or body == null or _room.is_empty():
		return
	var ms := AnimRig.now_msec()
	# The skeleton's own frame: +z ahead (the model faces its +z; Client3D turns it to the Body's +X), +x the body's
	# left, +y up. Every turn and offset below is in it.
	var hp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	var left := sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg")).origin - sk.get_bone_global_pose(sk.find_bone("RightUpperLeg")).origin
	var hips_yaw := atan2(-left.z, left.x)
	var ahead := sk.global_basis.z.normalized()
	var facing := atan2(ahead.x, ahead.z)
	var at := body.global_position
	var dt := (ms - _ms) / 1000.0
	var heavy := clampf(weight / WEIGHT_REF, WEIGHT_GAIN.x, WEIGHT_GAIN.y)
	if _fresh:
		# From rest: the carry coming on.
		_fresh = false
		_v = Vector2(hp.y, 0.0)
		_f = Vector2.ZERO
		_y = Vector2.ZERO
		_pace = 0.0
		_lean_pace = 0.0
		if not _room_want.is_empty():
			_room = _room_want.duplicate()
	elif dt > RESET_DT or dt < 0.0 or at.distance_to(_at) > RESET_JUMP or (rig != null and rig.every >= Client3D.POSE_UNSEEN_EVERY):
		# Not a frame to read a pace or a footfall from: the give is held as it was (dropping it would be the kick), the
		# readings taken again from here; the load's height moved with the hips.
		resets += 1
		_v.x += hp.y - _hips_y
	elif dt > 0.0:
		var flat := Vector3(at.x - _at.x, 0.0, at.z - _at.z)
		var pace := flat.dot(Vector3(ahead.x, 0.0, ahead.z).normalized()) / dt
		var climb := (hp.y - _hips_y) / dt
		var spin := (wrapf(facing - _facing, -PI, PI) + wrapf(hips_yaw - _hips_yaw, -PI, PI)) / dt
		var slow := sqrt(1.0 / heavy)
		var steps := ceili(dt / STEP)
		var h := dt / steps
		for i in steps:
			var hy := lerpf(_hips_y, hp.y, float(i + 1) / steps)
			_pace += (pace - _pace) * (1.0 - exp(-h / PACE_LAG))
			_lean_pace += (_pace - _lean_pace) * (1.0 - exp(-h / LEAN_LAG))
			_v.y += h * (VERT.x * VERT.x * slow * slow * (hy - _v.x) + 2.0 * VERT.y * VERT.x * slow * (climb - _v.y))
			_v.x += h * _v.y
			# The load's speed along against the body's pace; its lag ahead (the load's speed less the pace).
			_f.y += h * (-FORE.x * FORE.x * slow * slow * _f.x - 2.0 * FORE.y * FORE.x * slow * (_f.y - _pace))
			_f.x += h * (_f.y - _pace)
			_y.y += h * (-YAW.x * YAW.x * slow * slow * _y.x - 2.0 * YAW.y * YAW.x * slow * (_y.y - spin))
			_y.x += h * (_y.y - spin)
		var grow := 1.0 - exp(-dt / ROOM_EASE)
		var shrink := 1.0 - exp(-dt / ROOM_SHRINK)
		for j in mini(_room.size(), _room_want.size()):
			_room[j] = lerpf(float(_room[j]), float(_room_want[j]), grow if float(_room_want[j]) > float(_room[j]) else shrink)
	_ms = ms
	_at = at
	_facing = facing
	_hips_y = hp.y
	_hips_yaw = hips_yaw
	var up := _v.x - hp.y
	lag = Vector3(up, _f.x, _y.x)
	var r := _room
	hand_off = Vector3(0.0, _soft(HAND_UP * heavy * up, r[0] * 0.01, r[1] * 0.01), _soft(HAND_AHEAD * heavy * _f.x, r[2] * 0.01, r[3] * 0.01)) * amount
	yaw = _soft(HAND_YAW * heavy * rad_to_deg(_y.x), r[5], r[4]) * amount
	lean = _soft(heavy * (LEAN_PACE * _lean_pace + LEAN_AHEAD * _f.x - LEAN_BOB * up), r[7], r[6]) * amount
	turn = _soft(TURN * heavy * rad_to_deg(_y.x), r[9], r[8]) * amount
	clav = _soft(-CLAV_DROP * heavy * up, 0.0, r[10]) * amount
	var neck := sk.find_bone("Neck")
	var neck_was := sk.get_bone_global_pose(neck).basis if neck >= 0 else Basis()
	_turn_bone(sk, "Spine", Vector3.RIGHT, lean)
	_turn_bone(sk, "Spine", Vector3.UP, turn)
	_turn_bone(sk, "RightShoulder", Vector3.BACK, clav)
	if neck >= 0 and (lean != 0.0 or turn != 0.0):
		sk.set_bone_global_pose(neck, Transform3D(neck_was, sk.get_bone_global_pose(neck).origin))
	var hand := sk.find_bone("RightHand")
	var hg := sk.get_bone_global_pose(hand)
	want = Basis(Vector3.UP, deg_to_rad(yaw)) * hg.basis
	target.global_transform = sk.global_transform * Transform3D(want, hg.origin + hand_off)
	var sh := sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	var el := sk.get_bone_global_pose(sk.find_bone("RightLowerArm")).origin
	pole.global_position = sk.global_transform * (el + (el - (sh + hg.origin) * 0.5).normalized() * 0.3)


## [param x] held softly inside [-[param below], [param above]] (no give where the room is 0).
static func _soft(x: float, below: float, above: float) -> float:
	if x >= 0.0:
		return above * tanh(x / above) if above > 0.0 else 0.0
	return below * tanh(x / below) if below > 0.0 else 0.0


static func _turn_bone(sk: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	if deg == 0.0:
		return
	var b := sk.find_bone(bone)
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	sk.set_bone_global_pose(b, Transform3D(Basis(axis.normalized(), deg_to_rad(deg)) * g.basis, g.origin))
