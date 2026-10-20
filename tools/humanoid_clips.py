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
# BOW_LOW: the bow held low and forward, an arrow's bundle at the right hip. NOCK: both
# hands before the chest, an arrow to the string. DRAWN: the bow arm straight at the target,
# the drawing hand back at the jaw, the elbow up behind it. The draw's contact is full draw.
AHEAD = Vector((0.0, -1.0, 0.0))
SIDE_ON = [("spine_01", TURN, -18.0), ("spine_02", TURN, -22.0), ("spine_03", TURN, -20.0),
	("neck_01", TURN, 30.0), ("Head", TURN, 28.0)]
# The bow hand rolled thumb up about the arm (ROLL), so the bow held in it stands upright.
ROLL = [("hand_l", AHEAD, -90.0)]
# BOW_LOW (462 amended; Jeff: "arm and bow clipping body"): the arm hanging a little out and
# forward, the grip at the left side (0.25 m ahead, 0.84 up on the man), the hand turned so the bow
# (its length out of the thumb's side) stands upright, its top a little forward and out, clear of the
# shoulder and the leg. It hung behind the body, the bow up through the back.
BOW_LOW_HAND = [("hand_l", Vector((-0.573, 0.740, 0.352)), 48.0)]
BOW_LOW = [("upperarm_l", Vector((0.3, -0.12, -1.0)), AIM), ("lowerarm_l", Vector((0.15, -0.5, -0.85)), AIM)] + BOW_LOW_HAND + [
	# The bundle's arm hanging at its side, the hand by the hip (it was lifted, the bundle at the
	# chest; the coordinator on the bow check).
	("upperarm_r", Vector((-0.18, 0.02, -1.0)), AIM), ("lowerarm_r", Vector((-0.08, -0.3, -1.0)), AIM)]
NOCK = SIDE_ON + [("upperarm_l", Vector((0.15, -1.0, -0.25)), AIM), ("lowerarm_l", Vector((-0.1, -1.0, -0.1)), AIM),
	("upperarm_r", Vector((-0.2, -0.7, -0.6)), AIM), ("lowerarm_r", Vector((0.55, -0.8, 0.15)), AIM)] + ROLL
DRAWN = SIDE_ON + [("upperarm_l", Vector((0.0, -1.0, 0.04)), AIM), ("lowerarm_l", Vector((0.0, -1.0, 0.04)), AIM),
	("upperarm_r", Vector((-0.35, 0.9, 0.05)), AIM), ("lowerarm_r", Vector((0.5, -0.85, 0.05)), AIM)] + ROLL
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
CLIPS["Bow_Draw"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0, BOW_LOW)),
	(0.3, P("Idle_Loop", 0.3, NOCK)),
	(0.65, P("Idle_Loop", 0.6, DRAWN[:5] + [("upperarm_l", Vector((0.0, -1.0, 0.04)), AIM), ("lowerarm_l", Vector((0.0, -1.0, 0.04)), AIM),
		("upperarm_r", Vector((-0.3, -0.2, 0.0)), AIM), ("lowerarm_r", Vector((0.4, -0.9, 0.05)), AIM)] + ROLL)),
	(1.0, P("Idle_Loop", 0.9, DRAWN)),
]}
CLIPS["Bow_Hold_Loop"] = {"loop": True, "keys": [
	(0.0, P("Idle_Loop", 0.0, DRAWN)),
	(0.75, P("Idle_Loop", 0.75, DRAWN + [("spine_02", LIFT, 1.0), ("upperarm_r", LIFT, 1.5)])),
	(1.5, P("Idle_Loop", 0.0, DRAWN)),
]}
CLIPS["Bow_Loose"] = {"keys": [
	(0.0, P("Idle_Loop", 0.0, DRAWN)),
	# The release (Jeff: "firing animation is awkward"): the string hand slides back past the jaw,
	# its forearm turning out a little (a turn of the forearm, not a swing through the front), the
	# bow arm dropping a touch with the string's kick; held a moment; then the hand back to the
	# nock and the bow down.
	(0.08, P("Idle_Loop", 0.08, SIDE_ON + [("upperarm_l", Vector((0.0, -1.0, -0.04)), AIM), ("lowerarm_l", Vector((0.0, -1.0, -0.06)), AIM),
		("upperarm_r", Vector((-0.45, 0.85, 0.1)), AIM), ("lowerarm_r", Vector((-0.4, -0.85, 0.15)), AIM)] + ROLL)),
	(0.3, P("Idle_Loop", 0.3, SIDE_ON + [("upperarm_l", Vector((0.0, -1.0, -0.06)), AIM), ("lowerarm_l", Vector((0.0, -1.0, -0.08)), AIM),
		("upperarm_r", Vector((-0.45, 0.85, 0.05)), AIM), ("lowerarm_r", Vector((-0.4, -0.85, 0.1)), AIM)] + ROLL)),
	(0.6, P("Idle_Loop", 0.6, NOCK)),
	(1.0, P("Idle_Loop", 1.0, BOW_LOW)),
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
		turns carried it, the pelvis moved."""
		base = self.posed(spec["base"], spec["at"])
		turns = {}
		for bone, axis, degrees in spec["turns"]:
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
