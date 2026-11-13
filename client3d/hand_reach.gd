class_name HandReach
extends SkeletonModifier3D
## The left hand on a two-handed piece's second grip (451 amended (2), step 4;
## Jeff: "great axe model attachment needs fixing, it held sideways by player
## and draugr"): the piece is in the right hand (Client3D's hand_r socket) and
## its art has a "grip_2" (art-kit's sockets, up its length); the left hand is
## brought there, turned as the right one is about the haft, its fist's axis
## along the piece's length, so both thumbs point up it.
##
## Three modifiers on the skeleton, in this order, after the clips are played:
## this one (PLACE) puts [member target] where the left hand bone must be, from
## the right hand as this frame's pose has it (not the last frame's, as the
## hand's BoneAttachment3D would give), and the elbow's pole below and out to
## the left; a TwoBoneIK3D reaches the left arm's wrist to it; this one again
## (TURN) turns the left hand to the target's turn. Client3D.reach_with makes
## them, Client3D._sync_held turns them on and off.

enum {PLACE, TURN}
## Where the elbow is pushed, from the left shoulder, in the skeleton's axes
## (+X its left, +Y up, +Z its front), per metre of the body's height.
const POLE := Vector3(0.45, -0.5, -0.1)

var stage := PLACE
## The node the TwoBoneIK3D reaches to, and its pole.
var target: Node3D
var pole: Node3D
## The sockets' transforms in their hand bones' frames (hand_r, hand_l).
var right_socket: Transform3D
var left_socket: Transform3D
## The piece in the right hand (its transform in the socket) and its grip_2.
var held := Transform3D.IDENTITY
var grip := Vector3.ZERO
## The left hand bone's pose as PLACE found it, for TURN.
var _hand := Transform3D.IDENTITY
var _twin: HandReach


static func make(skeleton: Skeleton3D, right: Transform3D, left: Transform3D) -> HandReach:
	var place := HandReach.new()
	place.name = "ReachPlace"
	place.right_socket = right
	place.left_socket = left
	place.target = Node3D.new()
	place.target.name = "ReachTarget"
	place.pole = Node3D.new()
	place.pole.name = "ReachPole"
	skeleton.add_child(place)
	place.add_child(place.target)
	place.add_child(place.pole)
	var ik := TwoBoneIK3D.new()
	ik.name = "ReachArm"
	ik.setting_count = 1
	ik.set_root_bone_name(0, "LeftUpperArm")
	ik.set_middle_bone_name(0, "LeftLowerArm")
	ik.set_end_bone_name(0, "LeftHand")
	skeleton.add_child(ik)
	ik.set_target_node(0, ik.get_path_to(place.target))
	ik.set_pole_node(0, ik.get_path_to(place.pole))
	var turn := HandReach.new()
	turn.name = "ReachTurn"
	turn.stage = TURN
	turn._twin = place
	skeleton.add_child(turn)
	place._twin = turn
	place.set_meta("arm", ik)
	place.reach(false)
	return place


## On, for a piece held [param at] in the right hand's socket with its second
## grip at [param second] (the piece's own axes), or off.
func reach(on: bool, at := Transform3D.IDENTITY, second := Vector3.ZERO) -> void:
	held = at
	grip = second
	active = on
	(get_meta("arm") as SkeletonModifier3D).active = on
	_twin.active = on


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var hand := skeleton.find_bone("LeftHand")
	if stage == TURN:
		if hand >= 0:
			var now := skeleton.get_bone_global_pose(hand)
			_roll_forearm(skeleton, hand, now.origin, _twin._hand.basis)
			skeleton.set_bone_global_pose(hand, Transform3D(_within_wrist(skeleton, hand, _twin._hand.basis), now.origin))
		return
	var right := skeleton.find_bone("RightHand")
	var shoulder := skeleton.find_bone("LeftUpperArm")
	if right < 0 or hand < 0 or shoulder < 0:
		return
	# The right hand's socket as this frame poses it, moved up the piece to its
	# second grip: the left hand's socket there, so its hand bone is that less
	# the left socket's own place in the hand.
	var socket := skeleton.get_bone_global_pose(right) * right_socket
	var there := Transform3D(socket.basis, (socket * held) * grip)
	_hand = there * left_socket.affine_inverse()
	target.global_transform = skeleton.global_transform * _hand
	var height := skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin.y if skeleton.find_bone("Head") >= 0 else 1.6
	pole.global_position = skeleton.global_transform * (skeleton.get_bone_global_pose(shoulder).origin + POLE * height)


## The share of the left hand's twist about the forearm (its turn on the haft against the forearm the IK left)
## that the forearm takes, rolled about its own line from the elbow to the wrist, as the forearm's two bones turn
## the hand in life; the wrist keeps the rest (451 amended (6); Jeff, v0.1.213: "wrist bends at non anatomic
## angle"; anim_rig_test _test_held_wrists holds every holding wrist within 45 degrees of twist: the ready's left
## twisted up to 57 without it, 17 to 25 with it).
const FOREARM_ROLL := 0.6


## Rolls the left forearm about the line from its elbow to [param wrist] by FOREARM_ROLL of the twist the hand
## turned to [param want] (skeleton space) would have about it: the wrist stays where it is.
static func _roll_forearm(skeleton: Skeleton3D, hand: int, wrist: Vector3, want: Basis) -> void:
	var lower := skeleton.get_bone_parent(hand)
	if lower < 0:
		return
	var fore := skeleton.get_bone_global_pose(lower)
	var d := Quaternion((fore.basis.orthonormalized() * skeleton.get_bone_rest(hand).basis.orthonormalized()).inverse() * want.orthonormalized())
	var twist := 2.0 * atan2(d.y, d.w)
	var axis := wrist - fore.origin
	if axis.length() < 0.001 or absf(twist) < 0.001:
		return
	twist = wrapf(twist, -PI, PI)
	skeleton.set_bone_global_pose(lower, Transform3D(Basis(axis.normalized(), twist * FOREARM_ROLL) * fore.basis, fore.origin))


## The most the left wrist bends off the forearm's line (its swing from its rest), degrees: past it the fist turns
## off the haft's line by what is over, up to FIST_OFF_MOST, as a wrist at its stop does, rather than bending on
## (451 amended (6); anim_rig_test _test_held_wrists holds every holding wrist within 60). The ready's left bends
## 35 to 48, inside it; a pose bent farther than both (the heavy axes' rests, about 110, open rows in
## anim_rig_test) has its fist FIST_OFF_MOST off the haft and bends on past them.
const WRIST_MOST := 55.0
const FIST_OFF_MOST := 10.0


## [param want] (the hand's turn on the haft, skeleton space) with its swing off the forearm past WRIST_MOST taken
## back, by FIST_OFF_MOST at most, its twist kept.
static func _within_wrist(skeleton: Skeleton3D, hand: int, want: Basis) -> Basis:
	var lower := skeleton.get_bone_parent(hand)
	if lower < 0:
		return want
	var rest := skeleton.get_bone_global_pose(lower).basis.orthonormalized() * skeleton.get_bone_rest(hand).basis.orthonormalized()
	var d := Quaternion(rest.inverse() * want.orthonormalized())
	var twist := Quaternion(0.0, d.y, 0.0, d.w).normalized()
	var swing := d * twist.inverse()
	var angle := swing.get_angle()
	if angle <= deg_to_rad(WRIST_MOST):
		return want
	swing = Quaternion.IDENTITY.slerp(swing, (angle - minf(angle - deg_to_rad(WRIST_MOST), deg_to_rad(FIST_OFF_MOST))) / angle)
	return (rest * Basis(swing * twist)).scaled(want.get_scale())
