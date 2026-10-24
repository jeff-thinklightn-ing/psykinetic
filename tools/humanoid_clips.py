# Authors humanoid clips the Universal Animation Library lacks (a block, a knockdown and
# getting up, a hit from behind, strikes by weapon), on the UAL's own skeleton, so they play
# on every body rigged to it (the human bodies, the goblin) as the UAL's clips do; exported
# beside the pack's own clips as one .glb that tools/extract_clips.gd takes clips from.
#
#   blender -b -P tools/humanoid_clips.py -- <UAL1.glb> <out.glb> [<clip> ...] [--contacts]
#
# A clip is a few keyed poses, eased between (Blender's Bezier keys), or a stretch of a UAL
# clip played again (SEGMENT). A pose is a UAL clip at a moment, its joints then turned
# about their own heads (each turn carries the bones below it along) and the pelvis moved,
# all in the character's own axes, as it stands: it faces -Y, its left is +X, Z is up.
#   LIFT (about -X): the front of a thing rises: arms forward and up, head up, leaning back;
#     negative: leaning forward, arms back.
#   TURN (about +Z): turns toward its left (seen from above, anticlockwise).
#   TILT (about +Y): the top toward its left.
#   (bone, Vector, AIM): the bone pointed along that direction (character axes: up is
#     (0, 0, 1), ahead (0, -1, 0), its left (1, 0, 0)), from wherever it points.
#   ("upperarm_x", (target, pole), REACH): the arm's two bones turned so its wrist (the hand's
#     head) comes to [target], the elbow bent toward [pole] (a direction); [target] is
#     [(bone, offset, weight), ...], the weighted sum of those bones' heads (as the pose stands
#     without its reaches; reaches are met in order, each seeing the ones before) plus offsets.
#   ("hand_x", (length, side), GRASP): the hand turned so a held piece's length (the hand's own +Z;
#     Client3D's socket) lies along [length], its side (the hand's -X) toward [side].
# A strike's contact (the moment it lands, seconds) is measured, not guessed: the moment its
# striking bone (STRIKES) moves fastest forward (and down) relative to the pelvis. The UAL's own strikes are
# measured the same way (--contacts prints them all); the game's tables (Client3D) carry them.
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 24
LIFT = Vector((-1.0, 0.0, 0.0))
TURN = Vector((0.0, 0.0, 1.0))
TILT = Vector((0.0, 1.0, 0.0))
AIM = None
REACH = "reach"
GRASP = "grasp"


def P(base: str, at: float = 0.0, turns: list = (), move: tuple = (0.0, 0.0, 0.0)) -> dict:
	"""A pose: UAL clip [base] at [at] seconds, [turns] [(bone, axis, degrees), ...] after,
	the pelvis moved by [move] metres (character axes)."""
	return {"base": base, "at": at, "turns": list(turns), "move": Vector(move)}


def both(bone: str, axis: Vector, degrees: float, mirror: bool = True) -> list:
	"""The turn on both sides' [bone] (e.g. "thigh"); mirrored (TURN and TILT flip) for the right."""
	right = axis if not mirror or axis == LIFT else -axis
	return [(bone + "_l", axis, degrees), (bone + "_r", right, degrees)]


# The block: the shield arm (left) raised across the chest, forearm up; the weapon arm
# (right) up and ready; a little crouched forward. Upper body (perf's layer); the legs idle.
GUARD = [("upperarm_l", LIFT, 75.0), ("upperarm_l", TURN, -35.0), ("lowerarm_l", LIFT, 55.0),
	("upperarm_r", LIFT, 35.0), ("lowerarm_r", LIFT, 70.0), ("spine_02", LIFT, -8.0), ("Head", LIFT, 8.0)]

# A two-handed hold, weapon up before the body: the stance the axe and spear start from.
HOLD = [("upperarm_l", LIFT, 40.0), ("lowerarm_l", LIFT, 45.0), ("upperarm_l", TURN, -20.0),
	("upperarm_r", LIFT, 30.0), ("lowerarm_r", LIFT, 50.0)]

# Lying on the left side from Death01's lying on the back (head +Y, feet -Y): the pelvis
# rolled about the body's length so the front faces +X, then each part in those same axes.
SIDE_SLEEP = [("pelvis", TILT, 90.0), ("spine_02", TURN, 8.0), ("Head", TURN, 12.0),
	("thigh_l", Vector((0.75, -0.65, -0.12)), AIM), ("calf_l", Vector((-0.45, -0.9, -0.05)), AIM),
	("thigh_r", Vector((0.85, -0.5, -0.2)), AIM), ("calf_r", Vector((-0.35, -0.9, -0.15)), AIM),
	("upperarm_l", Vector((1.0, 0.2, 0.0)), AIM), ("lowerarm_l", Vector((-0.83, 0.55, 0.0)), AIM),
	("upperarm_r", Vector((0.6, -0.2, -0.8)), AIM), ("lowerarm_r", Vector((1.0, 0.1, -0.3)), AIM)]
SIDE_LIFT = (0.0, 0.0, 0.15)

CLIPS = {
	"Block_Idle_Loop": {"loop": True, "keys": [
		(0.0, P("Idle_Loop", 0.0, GUARD)),
		(1.25, P("Idle_Loop", 1.25, GUARD + [("spine_02", LIFT, -2.0)])),
		(2.5, P("Idle_Loop", 0.0, GUARD)),
	]},
	# Knocked down: Death01's fall, played as it is; then lying, breathing; then up.
	"Knockdown": {"segment": ("Death01", 0.0, 2.4)},
	"Lie_Loop": {"loop": True, "keys": [
		(0.0, P("Death01", 2.4)),
		(1.0, P("Death01", 2.4, [("spine_02", LIFT, 3.0), ("spine_03", LIFT, 2.0)])),
		(2.0, P("Death01", 2.4)),
	]},
	# Asleep on her side (621 amended: a companion asleep by the fire): Death01's lying, rolled
	# onto the left side, front to its left (+X), knees drawn up, the left forearm under the
	# head, the right arm over in front; a slow breath (4 s), the chest swelling forward.
	"Sleep_Side_Loop": {"loop": True, "keys": [
		(0.0, P("Death01", 2.4, SIDE_SLEEP, move=SIDE_LIFT)),
		(2.0, P("Death01", 2.4, SIDE_SLEEP + [("spine_02", TURN, 3.0), ("spine_03", TURN, 2.0)], move=SIDE_LIFT)),
		(4.0, P("Death01", 2.4, SIDE_SLEEP, move=SIDE_LIFT)),
	]},
	"Get_Up": {"keys": [
		(0.0, P("Death01", 2.4)),
		(0.45, P("GroundSit_Idle_Loop", 0.0)),
		(0.9, P("Crouch_Idle_Loop", 0.0)),
		(1.4, P("Idle_Loop", 0.0)),
	]},
	# Struck from behind: thrown forward from the hips, the head snapping back, arms flung
	# back; then back to standing.
	"Hit_Back": {"keys": [
		(0.0, P("Idle_Loop", 0.0)),
		(0.12, P("Idle_Loop", 0.12, [("spine_01", LIFT, -18.0), ("spine_02", LIFT, -12.0), ("Head", LIFT, 22.0),
			("upperarm_l", LIFT, -35.0), ("upperarm_r", LIFT, -35.0)], move=(0.0, -0.06, -0.02))),
		(0.5, P("Idle_Loop", 0.5)),
	]},
	# The axe overhead, both hands: raised up and back over the head, the body leaning
	# back, then brought down in front, the body bowing into it.
	"Axe_Overhead": {"keys": [
		(0.0, P("Sword_Idle", 0.0, HOLD)),
		(0.38, P("Sword_Idle", 0.0, [("upperarm_l", Vector((0.15, 0.25, 1.0)), AIM), ("lowerarm_l", Vector((-0.3, 0.6, 0.7)), AIM),
			("upperarm_r", Vector((-0.15, 0.25, 1.0)), AIM), ("lowerarm_r", Vector((0.3, 0.6, 0.7)), AIM),
			("spine_02", LIFT, 12.0), ("spine_03", LIFT, 6.0)])),
		(0.52, P("Sword_Idle", 0.0, [("upperarm_l", LIFT, 55.0), ("upperarm_l", TURN, -25.0), ("lowerarm_l", LIFT, 5.0),
			("upperarm_r", LIFT, 55.0), ("upperarm_r", TURN, 20.0), ("lowerarm_r", LIFT, 5.0),
			("spine_01", LIFT, -18.0), ("spine_02", LIFT, -14.0), ("Head", LIFT, 15.0)], move=(0.0, -0.06, -0.06))),
		(1.0, P("Sword_Idle", 0.0, HOLD)),
	]},
	# The dagger: the hand drawn back to the hip, then stabbed forward, the right shoulder
	# turned in behind it.
	"Dagger_Stab": {"keys": [
		(0.0, P("Sword_Idle", 0.0)),
		(0.12, P("Sword_Idle", 0.0, [("upperarm_r", LIFT, -25.0), ("lowerarm_r", LIFT, 70.0), ("spine_02", TURN, -12.0)])),
		(0.24, P("Sword_Idle", 0.0, [("upperarm_r", LIFT, 95.0), ("upperarm_r", TURN, 20.0), ("lowerarm_r", LIFT, -10.0), ("spine_02", TURN, 18.0),
			("spine_01", LIFT, -6.0)], move=(0.0, -0.06, 0.0))),
		(0.55, P("Sword_Idle", 0.0)),
	]},
	# The spear, both hands: drawn back, the body turned away; then thrust, the body
	# turning in, a step forward.
	"Spear_Thrust": {"keys": [
		(0.0, P("Sword_Idle", 0.0, HOLD)),
		(0.22, P("Sword_Idle", 0.0, HOLD + [("upperarm_r", LIFT, -35.0), ("lowerarm_r", LIFT, 25.0), ("spine_02", TURN, -22.0)],
			move=(0.0, 0.05, 0.0))),
		(0.36, P("Sword_Idle", 0.0, [("upperarm_r", LIFT, 75.0), ("lowerarm_r", LIFT, 5.0), ("upperarm_l", LIFT, 75.0),
			("upperarm_l", TURN, -30.0), ("lowerarm_l", LIFT, 15.0), ("spine_02", TURN, 16.0), ("spine_01", LIFT, -8.0)],
			move=(0.0, -0.12, -0.02))),
		(0.8, P("Sword_Idle", 0.0, HOLD)),
	]},
	# The shield bash: from the guard, the left shoulder drawn back, then driven forward
	# behind the shield, a lunge.
	"Shield_Bash": {"keys": [
		(0.0, P("Idle_Loop", 0.0, GUARD)),
		(0.14, P("Idle_Loop", 0.0, GUARD + [("spine_02", TURN, 22.0)], move=(0.0, 0.04, 0.0))),
		(0.27, P("Idle_Loop", 0.0, GUARD + [("spine_02", TURN, -38.0), ("upperarm_l", LIFT, 20.0), ("upperarm_l", TURN, 15.0),
			("spine_01", LIFT, -14.0), ("thigh_l", LIFT, 25.0), ("calf_l", LIFT, -20.0)], move=(0.0, -0.2, -0.05))),
		(0.65, P("Idle_Loop", 0.0, GUARD)),
	]},
}
## Each strike's striking bone, whose reach forward gives its contact.
STRIKES = {"Axe_Overhead": "hand_r", "Dagger_Stab": "hand_r", "Spear_Thrust": "hand_r", "Shield_Bash": "hand_l",
	"Sword_Attack": "hand_r", "Sword_Attack_Standing": "hand_r", "Punch_Jab": "hand_l", "Punch_Cross": "hand_r",
	"Kick": "foot_r"}
CONTACT = {}
# The run's stride, shortened for the human bodies (Jeff on v0.1.149: "the strides seem
# just a little too long for the legs"): the pack's Jog_Fwd and Sprint, their legs' and
# arms' swing narrowed, so the same ground speed plays them faster, in shorter steps.
# Postures (perf's additive layer, decision 390): the rest pose with the bend, so the
# layer adds the bend alone to whatever plays. Stooped: the back bent forward, the head
# held up to look ahead; slouching: the shoulders rounded forward, the head forward.
CLIPS["Posture_Stooped"] = {"keys": [(0.0, P("rest", 0.0, [("spine_01", LIFT, -8.0), ("spine_02", LIFT, -10.0),
	("spine_03", LIFT, -8.0), ("neck_01", LIFT, 12.0), ("Head", LIFT, 10.0)] + both("clavicle", TURN, -6.0)))]}
CLIPS["Posture_Slouch"] = {"keys": [(0.0, P("rest", 0.0, [("spine_02", LIFT, -4.0), ("spine_03", LIFT, -7.0),
	("neck_01", LIFT, -4.0), ("Head", LIFT, 8.0)] + both("clavicle", TURN, -14.0)))]}
CLIPS["Jog_Short_Loop"] = {"loop": True, "segment": ("Jog_Fwd_Loop", 0.0, 0.9333), "stride": {"legs": 0.62, "arms": 0.8, "bounce": 0.7}}
CLIPS["Sprint_Short_Loop"] = {"loop": True, "segment": ("Sprint_Loop", 0.0, 0.6667), "stride": {"legs": 0.72, "arms": 0.85, "bounce": 0.75}}


# The bow (Jeff: archery wants playtesting): a right-handed archer, the bow in the left hand
# (Client3D draws a held bow there, the arrows in the right), side on to the shot: the trunk
# turned to its right so the left shoulder leads, the head turned back to look ahead.
# BOW_LOW: the bow carried at the left thigh, an arrow's bundle at the right hip. NOCK: the bow
# low before the belly, the trunk half turned, the string hand at the string. DRAWN: the bow arm
# out at the target, its elbow soft; the string hand's wrist at the right jaw, below the ear, the
# elbow out to the right and level behind it. The draw's contact is full draw.
# The arms are reached (REACH), not aimed bone by bone (462 amended; Jeff on v0.1.160: "the bow
# draw back arm is all wrong, it clips through the body then is held as if the arm is behind
# wrapping behind the head", "bow arm is too long, bow is held out too far away from body"): the
# wrists placed against the shoulder, the head and the bow hand, so the pull runs before the face
# and back along the jaw, never behind the head nor through the chest.
AHEAD = Vector((0.0, -1.0, 0.0))
SIDE_ON = [("spine_01", TURN, -18.0), ("spine_02", TURN, -22.0), ("spine_03", TURN, -20.0),
	("neck_01", TURN, 30.0), ("Head", TURN, 28.0)]


def side_on(share: float) -> list:
	"""SIDE_ON [share] of the way."""
	return [(bone, axis, degrees * share) for bone, axis, degrees in SIDE_ON]


def bow_arm(ahead: float, out: float, up: float, length: tuple, side: tuple = (1.0, 0.0, 0.1), pole: tuple = (1.0, 0.1, -0.5)) -> list:
	"""The bow arm: its wrist [ahead], [out] (to its left) and [up] of the shoulder, the elbow
	toward [pole]; the bow's length along [length], its flat to [side]."""
	return [("upperarm_l", ([("upperarm_l", (out, -ahead, up), 1.0)], pole), REACH), ("hand_l", (length, side), GRASP)]


def string_arm(nock: float, pole: tuple, back: float = 0.0, out: float = 0.0) -> list:
	"""The string arm: its wrist [nock] of the way from the string at the bow (0) to the anchor
	at the jaw (1); [back] moves the anchor back past the ear (the release), [out] the wrist out to
	its right (clear of the chin on the way); the elbow toward [pole]."""
	string = (-0.04 - out, 0.13, 0.0)
	anchor = (-0.14 - out, 0.03 + back, -0.04)
	return [("upperarm_r", ([("hand_l", string, 1.0 - nock), ("Head", anchor, nock)], pole), REACH),
		("hand_r", Vector((0.1, -1.0, 0.0)), AIM)]


BOW_UP = (-0.12, 0.15, 1.0)
DRAWN_ARM = (0.49, -0.16, 0.05)
# BOW_LOW (462 amended; Jeff: "arm and bow clipping body", then "held out too far away from
# body"): the arm hanging at the side, the wrist by the thigh, the bow upright beside the leg, its
# top a little forward.
BOW_LOW = bow_arm(0.0, 0.16, -0.46, (0.2, -0.45, 1.0), (1.0, 0.0, 0.0), (0.3, 1.0, 0.0)) + [
	# The bundle's arm hanging at its side, the hand by the hip (it was lifted, the bundle at the
	# chest; the coordinator on the bow check).
	("upperarm_r", Vector((-0.4, 0.02, -1.0)), AIM), ("lowerarm_r", Vector((-0.3, -0.3, -1.0)), AIM)]
NOCK = side_on(0.2) + [("clavicle_r", TURN, 20.0)] + bow_arm(0.36, -0.14, -0.2, (0.15, 0.0, 1.0), pole=(1.0, 0.3, -0.6)) + string_arm(0.0, (-1.0, -0.2, 0.1))
# Between the thigh and the nock, the bow swung out before the leg.
LIFTING = side_on(0.1) + bow_arm(0.32, 0.12, -0.32, (-0.1, -0.6, 1.0), (1.0, 0.0, 0.0), (0.6, 0.6, -0.3)) + [
	("upperarm_r", Vector((-0.4, -0.05, -1.0)), AIM), ("lowerarm_r", Vector((-0.3, -0.6, -0.8)), AIM)]
DRAWN = SIDE_ON + bow_arm(*DRAWN_ARM, BOW_UP) + string_arm(1.0, (-1.0, 0.6, 0.1))
# Fidgets (Jeff: "the idle need variability and same scratch is very predictable"): short
# things a person does standing about, each from Idle and back to it, so any may follow any.
# Shift: the weight onto one leg, the hip out and the shoulders tilting against it.
SHIFT = [("spine_01", TILT, -4.0), ("spine_02", TILT, 3.0), ("spine_03", TILT, 2.0), ("Head", TILT, 2.0),
	("thigh_r", TILT, -3.0), ("calf_r", LIFT, -10.0), ("thigh_r", LIFT, 6.0)]
# Look back: over the right shoulder, the trunk turning with the head.
LOOK_BACK = [("spine_01", TURN, -8.0), ("spine_02", TURN, -12.0), ("spine_03", TURN, -14.0), ("neck_01", TURN, -25.0),
	("Head", TURN, -30.0)]
# Shoulders: both clavicles up (a shrug, a roll), the chest a little back.
SHRUG = [("clavicle_l", TILT, 14.0), ("clavicle_r", TILT, -14.0), ("spine_03", LIFT, 4.0), ("Head", LIFT, -4.0)]
# Brush the sleeve: the left forearm before the waist, the right hand across it, eyes down.
SLEEVE = [("upperarm_l", Vector((0.15, -0.35, -1.0)), AIM), ("lowerarm_l", Vector((-0.75, -0.6, 0.1)), AIM),
	("upperarm_r", Vector((-0.1, -0.45, -1.0)), AIM), ("lowerarm_r", Vector((0.85, -0.5, 0.2)), AIM),
	("Head", LIFT, -18.0), ("neck_01", LIFT, -8.0)]
# Arms crossed: both forearms folded across the chest.
CROSSED = [("upperarm_l", Vector((0.12, -0.3, -1.0)), AIM), ("lowerarm_l", Vector((-1.0, -0.3, 0.25)), AIM),
	("upperarm_r", Vector((-0.12, -0.32, -1.0)), AIM), ("lowerarm_r", Vector((1.0, -0.35, 0.3)), AIM),
	("spine_03", LIFT, 3.0)]
CLIPS["Fidget_Shift"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0)), (0.7, P("Idle_Loop", 0.7, SHIFT, move=(-0.035, 0.0, -0.01))),
	(2.2, P("Idle_Loop", 2.2, SHIFT, move=(-0.035, 0.0, -0.01))), (3.0, P("Idle_Loop", 0.0)),
]}
CLIPS["Fidget_LookBack"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0)), (0.8, P("Idle_Loop", 0.8, LOOK_BACK)), (1.8, P("Idle_Loop", 1.8, LOOK_BACK)),
	(2.6, P("Idle_Loop", 0.0)),
]}
CLIPS["Fidget_Shoulders"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0)), (0.45, P("Idle_Loop", 0.45, SHRUG)), (0.9, P("Idle_Loop", 0.9)),
	(1.35, P("Idle_Loop", 1.35, SHRUG)), (2.0, P("Idle_Loop", 0.0)),
]}
CLIPS["Fidget_Sleeve"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0)), (0.6, P("Idle_Loop", 0.6, SLEEVE)),
	(1.0, P("Idle_Loop", 1.0, SLEEVE + [("lowerarm_r", LIFT, 12.0)])), (1.4, P("Idle_Loop", 1.4, SLEEVE)),
	(1.8, P("Idle_Loop", 1.8, SLEEVE + [("lowerarm_r", LIFT, 12.0)])), (2.5, P("Idle_Loop", 0.0)),
]}
CLIPS["Fidget_ArmsCrossed"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0)), (0.7, P("Idle_Loop", 0.7, CROSSED)),
	(2.6, P("Idle_Loop", 2.6, CROSSED + [("Head", TURN, 8.0)])), (3.4, P("Idle_Loop", 0.0)),
]}
CLIPS["Bow_Idle_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, BOW_LOW)),
	(1.25, P("Idle_Loop", 1.25, BOW_LOW + [("spine_02", LIFT, -2.0)])),
	(2.5, P("Idle_Loop", 0.0, BOW_LOW)),
]}
# The draw: nocked low, the bow raised to the target as the string hand comes up before the
# chest, then drawn back along the arrow's line to the jaw.
CLIPS["Bow_Draw"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0, BOW_LOW)),
	(0.15, P("Idle_Loop", 0.15, LIFTING)),
	(0.3, P("Idle_Loop", 0.3, NOCK)),
	(0.42, P("Idle_Loop", 0.4, side_on(0.35) + [("clavicle_r", TURN, 20.0)] + bow_arm(0.4, -0.14, -0.12, (-0.05, 0.0, 1.0))
		+ string_arm(0.12, (-1.0, -0.2, 0.1), out=0.1))),
	(0.55, P("Idle_Loop", 0.5, side_on(0.6) + [("clavicle_r", TURN, 15.0)] + bow_arm(0.45, -0.13, 0.0, BOW_UP) + string_arm(0.25, (-1.0, -0.1, 0.0), out=0.1))),
	(0.68, P("Idle_Loop", 0.6, side_on(0.95) + bow_arm(0.48, -0.15, 0.04, BOW_UP) + string_arm(0.5, (-1.0, 0.3, -0.3), out=0.08))),
	(0.8, P("Idle_Loop", 0.7, SIDE_ON + bow_arm(*DRAWN_ARM, BOW_UP) + string_arm(0.7, (-1.0, 0.4, -0.25)))),
	(1.0, P("Idle_Loop", 0.9, DRAWN)),
]}
CLIPS["Bow_Hold_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, DRAWN)),
	(0.75, P("Idle_Loop", 0.75, [("spine_02", LIFT, 1.0)] + DRAWN)),
	(1.5, P("Idle_Loop", 0.0, DRAWN)),
]}
CLIPS["Bow_Loose"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0, DRAWN)),
	# The release (Jeff: "firing animation is awkward"): the string hand slides back along the
	# jaw past the ear, the bow arm dropping a touch with the string's kick; held a moment; then
	# the hand back to the nock and the bow down.
	(0.08, P("Idle_Loop", 0.08, SIDE_ON + bow_arm(0.49, -0.16, 0.02, BOW_UP) + string_arm(1.0, (-1.0, 0.7, 0.05), 0.09))),
	(0.3, P("Idle_Loop", 0.3, SIDE_ON + bow_arm(0.48, -0.16, -0.01, BOW_UP) + string_arm(1.0, (-1.0, 0.7, 0.0), 0.1))),
	(0.6, P("Idle_Loop", 0.6, NOCK)),
	(0.8, P("Idle_Loop", 0.8, LIFTING)),
	(1.0, P("Idle_Loop", 1.0, BOW_LOW)),
]}

# Visible work (566, pc-character's side; Jeff: "town people need to be doing activities to better
# the town, chopping wood ... building a half constructed building"): the work a resident shows,
# looped, a tool in the right hand (art-kit's tool.*: the grip at the origin, the length +y, the
# edge or face +x, so GRASP's length and side are the tool's).


def right_arm(ahead: float, out: float, up: float, pole: tuple) -> list:
	"""The right wrist [ahead], [out] (to its right) and [up] of its shoulder, the elbow toward [pole]."""
	return [("upperarm_r", ([("upperarm_r", (-out, -ahead, up), 1.0)], pole), REACH)]


def left_arm(ahead: float, out: float, up: float, pole: tuple) -> list:
	"""The left wrist [ahead], [out] (to its left) and [up] of its shoulder, the elbow toward [pole]."""
	return [("upperarm_l", ([("upperarm_l", (out, -ahead, up), 1.0)], pole), REACH)]


# Chopping: both hands on the haft, each placed (REACH) so neither forearm crosses the chest
# (Axe_Overhead's hold did, for the brute): ready, the head resting toward the block ahead and
# low; raised over the right shoulder, the head up behind; brought down ahead into the block,
# the trunk bowing into it; a breath, again. The right wrist within reach of its shoulder (0.46 m:
# farther, the arm stops short and the left hand missed the haft by 0.33 m); the haft along
# [haft] from the left hand, at its butt, through the right, CHOP_GRIP between them (Client3D
# slides tool.axe, its origin at the butt, that far and a little over down the right hand); its
# edge toward [edge] made square to it.
CHOP_GRIP = 0.18
# The trunk turned, the right shoulder brought forward (the base holds it 0.12 m back): the axe
# out in front, the left forearm clear of the chest.
SQUARED = [("spine_02", TURN, 18.0), ("spine_03", TURN, 14.0)]
# Where a hand holds a thing, from its wrist in its own bone's axes here: Client3D's hand socket,
# (0, HAND_GRIP, HAND_PALM) in Godot's, whose bone axes are these turned (x there is z here, z there
# is -x here); a thing held lies along the socket's +y, the right bone's +z here, the left's -z.
# Chop_Loop was authored with the socket at (0, 0.10, 0.03), as here. The socket moved into the
# mitten's middle, (0, 0.07, 0.005) (451 amended (2)), and the shipped clip still keeps the left hand
# on the haft by anim_rig_test's measure. Authored again with the new hold, the left forearm went 6 cm
# into the chest at 0.55 s, so a new hold here needs CHOP_* re-posed too.
HOLD_AT = (-0.03, 0.10, 0.0)


def grasped(length: Vector, side: Vector) -> tuple:
	"""The hand's axes (x, y, z) here as GRASP turns it to [length] and [side]."""
	z = length.normalized()
	x = -(side - z * side.dot(z)).normalized()
	return x, z.cross(x), z


def holding(length: Vector, side: Vector) -> Vector:
	"""From the wrist to where the hand holds, the hand GRASPed to [length] and [side]."""
	x, y, _z = grasped(length, side)
	return x * HOLD_AT[0] + y * HOLD_AT[1]


def chop(right: tuple, haft: tuple, edge: tuple, poles: tuple = ((-1.0, 0.3, -0.5), (0.8, -0.6, -0.4))) -> list:
	"""The right wrist at [right] = (ahead, out to its right, up) of the right shoulder; the haft
	along [haft] = (ahead, to the right, up) from the left hand's hold, CHOP_GRIP back down it from
	the right's, each hand turned along it (GRASP), the left wrist placed for its hold from the
	right wrist as posed (the base turns the shoulders: the right one sat 0.12 m back of the left)."""
	length = Vector((-haft[1], -haft[0], haft[2])).normalized()
	e = Vector(edge)
	e = (e - length * e.dot(length)).normalized()
	# Both hands wrapping the haft from the same side (the left's turned end for end, its side too).
	left = holding(length, e) - length * CHOP_GRIP - holding(-length, -e)
	return SQUARED + right_arm(right[0], right[1], right[2], poles[0]) + [
		("upperarm_l", ([("hand_r", tuple(left), 1.0)], poles[1]), REACH),
		("hand_r", (tuple(length), tuple(e)), GRASP), ("hand_l", (tuple(-length), tuple(-e)), GRASP)]


CHOP_READY = chop((0.45, 0.04, 0.0), (0.85, 0.0, -0.5), (0.0, 0.0, -1.0), ((-1.0, 0.3, -0.5), (1.0, -0.6, -0.1))) + [
	("spine_02", LIFT, -2.0)]
CHOP_UP = chop((0.16, 0.06, 0.38), (-0.4, 0.1, 0.9), (0.0, -1.0, 0.45)) + [("spine_02", LIFT, 8.0), ("spine_03", LIFT, 4.0)]
# Halfway down, the head high ahead (between the raise and the strike, each hand solved, not
# their blend: blended, the left left the haft and the head dipped into the body).
CHOP_SWING = chop((0.34, 0.02, 0.22), (0.45, 0.05, 0.9), (0.0, -1.0, 0.0)) + [("spine_02", LIFT, 2.0)]
CHOP_DOWN = chop((0.44, -0.16, -0.2), (0.8, -0.1, -0.55), (0.0, 0.0, -1.0)) + [
	("spine_01", LIFT, -14.0), ("spine_02", LIFT, -10.0), ("Head", LIFT, 10.0)]
CLIPS["Chop_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, CHOP_READY)),
	(0.45, P("Idle_Loop", 0.45, CHOP_UP)),
	(0.54, P("Idle_Loop", 0.54, CHOP_SWING)),
	(0.62, P("Idle_Loop", 0.62, CHOP_DOWN, move=(0.0, -0.04, -0.05))),
	(0.8, P("Idle_Loop", 0.8, CHOP_DOWN)),
	(1.3, P("Idle_Loop", 1.3, CHOP_READY + [("spine_02", LIFT, 2.0)])),
	(1.6, P("Idle_Loop", 0.0, CHOP_READY)),
]}
# Sawing at the woodpile: bent over the log, the left hand pressing it down ahead to the left,
# the saw in the right hand pushed and drawn ahead and down, the blade sloping into the cut, the
# teeth below; the trunk rocking a little with each stroke.
BENT = [("spine_01", LIFT, -14.0), ("spine_02", LIFT, -12.0), ("Head", LIFT, -10.0), ("thigh_l", LIFT, 8.0),
	("calf_l", LIFT, -12.0), ("thigh_r", LIFT, 4.0), ("calf_r", LIFT, -8.0)]
SAW_HOLD = left_arm(0.42, 0.18, -0.52, (1.0, 0.4, 0.2)) + [("hand_l", Vector((0.1, -0.4, -1.0)), AIM)]
CLIPS["Saw_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, BENT + SAW_HOLD + right_arm(0.24, 0.14, -0.36, (-1.0, 0.6, -0.2))
		+ [("hand_r", ((0.0, -1.0, -0.55), (0.0, 0.55, -1.0)), GRASP)])),
	(0.4, P("Idle_Loop", 0.4, BENT + [("spine_02", LIFT, -4.0)] + SAW_HOLD + right_arm(0.58, 0.12, -0.5, (-1.0, 0.4, -0.3))
		+ [("hand_r", ((0.0, -1.0, -0.6), (0.0, 0.6, -1.0)), GRASP)], move=(0.0, -0.02, -0.01))),
	(0.8, P("Idle_Loop", 0.0, BENT + SAW_HOLD + right_arm(0.24, 0.14, -0.36, (-1.0, 0.6, -0.2))
		+ [("hand_r", ((0.0, -1.0, -0.55), (0.0, 0.55, -1.0)), GRASP)])),
]}
# Hammering at the frame: standing to it, the left hand braced on the timber ahead, the hammer
# raised by the head, its face toward the work, then struck at chest height, the face square on.
BRACE = left_arm(0.42, 0.12, 0.02, (1.0, 0.3, -0.4)) + [("hand_l", Vector((0.0, -1.0, 0.1)), AIM)]
HAMMER_UP = right_arm(0.12, 0.14, 0.26, (-1.0, 0.3, -0.3)) + [("hand_r", ((0.0, 0.4, 1.0), (0.0, -1.0, 0.4)), GRASP)]
HAMMER_DOWN = right_arm(0.44, 0.1, -0.04, (-1.0, 0.2, -0.6)) + [("hand_r", ((0.0, -1.0, 0.25), (0.0, -0.25, -1.0)), GRASP)]
CLIPS["Hammer_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, BRACE + HAMMER_UP + [("spine_02", LIFT, 3.0)])),
	(0.22, P("Idle_Loop", 0.22, BRACE + HAMMER_DOWN + [("spine_02", LIFT, -5.0)], move=(0.0, -0.01, 0.0))),
	(0.32, P("Idle_Loop", 0.32, BRACE + HAMMER_DOWN + [("spine_02", LIFT, -4.0)])),
	(0.7, P("Idle_Loop", 0.7, BRACE + HAMMER_UP + [("spine_02", LIFT, 3.0)])),
]}
# Carrying on the shoulder (the upper layer, over the walk or standing): the right hand up on the
# load's outer side ahead of the shoulder (Client3D's socket puts it out past the joint, its
# thickness clear of the head), the elbow forward and down, the head tilted away from it.
SHOULDERED = right_arm(0.14, 0.12, 0.06, (0.0, -1.0, -0.6)) + [("hand_r", Vector((0.0, -0.3, 1.0)), AIM),
	("neck_01", TILT, 5.0), ("Head", TILT, 7.0), ("clavicle_r", TILT, -6.0)]
CLIPS["Carry_Shoulder_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, SHOULDERED)),
	(1.0, P("Idle_Loop", 1.0, SHOULDERED + [("spine_02", LIFT, -2.0)])),
	(2.0, P("Idle_Loop", 0.0, SHOULDERED)),
]}


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def action_named(name: str):
	for action in bpy.data.actions:
		if action.name.split("|")[-1] == name:
			return action
	raise SystemExit("no clip %s in the pack" % name)


def depth(bone) -> int:
	return 0 if bone.parent is None else 1 + depth(bone.parent)


class Rig:
	def __init__(self, arm):
		self.arm = arm
		self.bones = sorted(arm.data.bones, key=depth)  # Parents first.
		if arm.animation_data is None:
			arm.animation_data_create()

	def posed(self, base: str, at: float) -> dict:
		"""Each bone's armature-space matrix in [base] at [at] seconds ("rest": the rest pose)."""
		if base == "rest":
			return {b.name: b.matrix_local.copy() for b in self.bones}
		self.arm.animation_data.action = action_named(base)
		frame = at * FPS
		bpy.context.scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
		bpy.context.view_layer.update()
		return {b.name: self.arm.pose.bones[b.name].matrix.copy() for b in self.bones}

	def pose(self, spec: dict) -> dict:
		"""[spec]'s matrices: its base's, each bone turned about its own head after its parents'
		turns carried it, the pelvis moved; its reaches met in order."""
		turns = [t for t in spec["turns"] if t[2] != REACH]
		for bone, (target, pole), _reach in [t for t in spec["turns"] if t[2] == REACH]:
			now = self.turned(spec, turns)
			fore, hand = bone.replace("upperarm", "lowerarm"), bone.replace("upperarm", "hand")
			at = sum(((now[b].translation + Vector(off)) * w for b, off, w in target), Vector())
			upper, lower = solve(now[bone].translation, now[fore].translation, now[hand].translation, at, Vector(pole))
			turns = turns + [(bone, upper, AIM), (fore, lower, AIM)]
		return self.turned(spec, turns)

	def turned(self, spec: dict, listed: list) -> dict:
		base = self.posed(spec["base"], spec["at"])
		turns = {}
		for bone, axis, degrees in listed:
			turns.setdefault(bone, []).append((axis, degrees))
		out = {}
		for b in self.bones:
			carried = base[b.name]
			if b.parent is not None:
				carried = out[b.parent.name] @ base[b.parent.name].inverted() @ base[b.name]
			if b.name == "pelvis" and spec["move"].length > 0.0:
				carried = Matrix.Translation(spec["move"]) @ carried
			for axis, degrees in turns.get(b.name, []):
				if degrees is None:
					# AIM: pointed along [axis], from wherever it points now.
					turn = carried.col[1].xyz.normalized().rotation_difference(axis.normalized())
				elif degrees == GRASP:
					length, side = (Vector(v).normalized() for v in axis)
					z = length
					x = -(side - z * side.dot(z)).normalized()
					want = Matrix((x, z.cross(x), z)).transposed()
					turn = (want @ carried.to_3x3().normalized().inverted()).to_quaternion()
				else:
					turn = Quaternion(axis, math.radians(degrees))
				head = carried.translation.copy()
				carried = Matrix.Translation(head) @ turn.to_matrix().to_4x4() @ Matrix.Translation(-head) @ carried
			out[b.name] = carried
		return out

	def basis(self, matrices: dict) -> dict:
		"""The pose-space (local) transform of each bone that gives [matrices]."""
		out = {}
		for b in self.bones:
			rest = b.matrix_local
			if b.parent is None:
				out[b.name] = rest.inverted() @ matrices[b.name]
			else:
				rest_in_parent = b.parent.matrix_local.inverted() @ rest
				out[b.name] = (matrices[b.parent.name] @ rest_in_parent).inverted() @ matrices[b.name]
		return out

	def key(self, action, frame: float, matrices: dict, last: dict) -> None:
		self.arm.animation_data.action = action
		for b in self.bones:
			pb = self.arm.pose.bones[b.name]
			pb.rotation_mode = "QUATERNION"
			local = self.basis_cache[b.name]
			loc, rot, _scale = local.decompose()
			if b.name in last and last[b.name].dot(rot) < 0.0:
				rot = -rot  # The short way from the last key.
			last[b.name] = rot
			pb.location = loc
			pb.rotation_quaternion = rot
			pb.keyframe_insert("location", frame=frame)
			pb.keyframe_insert("rotation_quaternion", frame=frame)

	def author(self, name: str, clip: dict):
		action = bpy.data.actions.new(name)
		action.use_fake_user = True
		last = {}
		if "segment" in clip:
			base, start, end = clip["segment"]
			frames = [self.basis(self.posed(base, start + f / FPS)) for f in range(round((end - start) * FPS) + 1)]
			if "stride" in clip:
				frames = narrowed(frames, clip["stride"])
			for f, basis in enumerate(frames):
				self.basis_cache = basis
				self.key(action, f, None, last)
		else:
			for at, spec in clip["keys"]:
				self.basis_cache = self.basis(self.pose(spec))
				self.key(action, round(at * FPS), None, last)
		if name in STRIKES:
			CONTACT[name] = self.contact(action, STRIKES[name])
		self.arm.animation_data.action = None
		frames = action.frame_range
		print("clip %-12s %.2f s%s%s" % (name, (frames[1] - frames[0]) / FPS, ", loops" if clip.get("loop") else "",
			", contact %.2f s" % CONTACT[name] if name in CONTACT else ""))
		return action


def solve(shoulder: Vector, elbow: Vector, wrist: Vector, target: Vector, pole: Vector) -> tuple:
	"""The upper arm's and forearm's directions that bring the wrist to [target], the elbow
	toward [pole]; a target past the arm's reach is met as far as the straight arm goes."""
	upper, fore = (elbow - shoulder).length, (wrist - elbow).length
	to = target - shoulder
	d = min(max(to.length, abs(upper - fore) + 1e-4), (upper + fore) * 0.9999)
	u = to.normalized()
	v = (pole - u * pole.dot(u)).normalized()
	cos = (upper * upper + d * d - fore * fore) / (2.0 * upper * d)
	bend = shoulder + (u * cos + v * math.sqrt(max(0.0, 1.0 - cos * cos))) * upper
	return (bend - shoulder).normalized(), (shoulder + u * d - bend).normalized()


## Which bones each part of "stride" scales.
GROUPS = {"legs": ("thigh", "calf", "foot", "ball"), "arms": ("clavicle", "upperarm", "lowerarm", "hand"),
	"body": ("pelvis", "spine")}


def narrowed(frames: list, stride: dict) -> list:
	"""A cycle's frames with its swing narrowed: each bone in a group of [stride]
	({"legs": 0.55, ...}) turned only that share of the way from its mean over the cycle;
	"bounce" the same for the pelvis's height."""
	names = list(frames[0])
	means = {}
	for name in names:
		total = Quaternion((0.0, 0.0, 0.0, 0.0))
		first = frames[0][name].to_quaternion()
		for basis in frames:
			q = basis[name].to_quaternion()
			total = total + (q if q.dot(first) >= 0.0 else -q)
		means[name] = total.normalized()
	heights = [basis["pelvis"].translation.z for basis in frames]
	mean_height = sum(heights) / len(heights)
	out = []
	for basis in frames:
		new = {}
		for name in names:
			share = 1.0
			for group, prefixes in GROUPS.items():
				if group in stride and name.startswith(prefixes):
					share = stride[group]
			loc, rot, scale = basis[name].decompose()
			if name == "pelvis" and "bounce" in stride:
				loc.z = mean_height + (loc.z - mean_height) * stride["bounce"]
			if rot.dot(means[name]) < 0.0:
				rot = -rot
			rot = means[name].slerp(rot, share)
			new[name] = Matrix.Translation(loc) @ rot.to_matrix().to_4x4() @ Matrix.Diagonal(scale.to_4d())
		out.append(new)
	return out


def reach(rig: Rig, action, bone: str) -> float:
	"""The moment (seconds) [bone] moves fastest forward (and down) relative to the pelvis in [action]: a blow
	lands as the hand is at its fastest (the goblin's Sword_Attack: 0.45 s, as
	Client3D.CLIP_HEAVY_CONTACT was measured)."""
	rig.arm.animation_data.action = action
	start, end = (int(f) for f in action.frame_range)
	places = []
	for f in range(start, end + 1):
		bpy.context.scene.frame_set(f)
		bpy.context.view_layer.update()
		pose = rig.arm.pose.bones
		places.append(pose[bone].head - pose["pelvis"].head)
	# Forward (-Y) and down count, as a blow moves; a draw-back does not.
	speeds = [max(0.0, -(places[i + 1] - places[i - 1]).y) + max(0.0, -(places[i + 1] - places[i - 1]).z) * 0.5
		for i in range(1, len(places) - 1)]
	return (speeds.index(max(speeds)) + 1) / FPS if speeds else 0.0


Rig.contact = reach


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <UAL1.glb> <out.glb> [<clip> ...]")
	source, out = (os.path.abspath(p) for p in a[:2])
	contacts = "--contacts" in a
	wanted = [n for n in a[2:] if n != "--contacts"] or list(CLIPS)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.context.scene.render.fps = FPS
	bpy.ops.import_scene.gltf(filepath=source)
	arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
	rig = Rig(arm)
	if contacts:
		# The pack's own strikes, measured as ours are.
		for name, bone in STRIKES.items():
			if name not in CLIPS:
				action = action_named(name)
				print("contact %-22s %.2f s of %.2f s" % (name, reach(rig, action, bone), (action.frame_range[1] - action.frame_range[0]) / FPS))
	made = [rig.author(name, CLIPS[name]) for name in wanted]
	# Only the new clips go out (the pack's are taken from the pack).
	for action in list(bpy.data.actions):
		if action not in made:
			bpy.data.actions.remove(action)
	for obj in list(bpy.data.objects):
		if obj.type == "MESH" and obj.name.startswith("Icosphere"):
			bpy.data.objects.remove(obj)
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_animations=True, export_animation_mode="ACTIONS", export_extras=True)
	print("wrote %s: %s" % (out, ", ".join(a.name for a in made)))


if __name__ == "__main__":
	main()
