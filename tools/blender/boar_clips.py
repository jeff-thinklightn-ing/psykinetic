# The boar king's own clips (780 amended (16), animation's side; package "the boar king"; enemy-ai's BoarKing; the
# coordinator's approval of C:/dev/review/animation/boar_king.md) keyed on the Quaternius Pig's rig
# (All -> legs, Body -> Neck -> Head; 319 amended (3) gave the neck its weights), beside its stock
# clips, as NLA-held actions the slot's export carries:
#   blender -b art/kit/creatures/creature.boar_king/creature.boar_king.blend -P tools/blender/boar_clips.py
#       [-- --save]
# then tools/blender/export_slot.py to the slot's .glb. --save writes the .blend back; without it
# the run only reports. Rerunnable: an earlier run's actions and tracks are replaced.
#
# Poses are given in the armature's axes (+X the boar's left, -Y ahead, +Z up), as degrees about
# them, applied over the stock Idle's first frame (Charge over each frame of the stock Run): about
# +X a bone pointing ahead tips down and a leg's foot swings back; about +Z one pointing ahead turns
# to the boar's left; about +Y the body rolls onto its right side. The bend goes on Neck more than
# Head (pc-character: a big Head-only turn creases the brow), and the trunk turns only with All, the
# legs going with it (turned against them, the leg seams open).
#
# The sim's timings (enemy-ai's BoarKing, 10 ticks a second): the charge's tell 12 ticks (1.2 s,
# ending as the run starts), the skid 15 (1.5 s), the crash's stun 25 (Dazed loops through it), the
# hook a HEAVY wind-up of 6 (0.6 s; Hook's contact 0.6 s of 0.9).
import math
import sys

import bpy
from mathutils import Euler, Quaternion, Vector

FPS = 24
ARM = "AnimalArmature"
LEG_LENGTH = 0.457  # Each leg bone's hip to foot (the rig's, at the king's scale).


def drop_for(degrees: float) -> float:
	"""How far a leg swung this far lifts its foot, so All sinks by it to keep the feet down."""
	return LEG_LENGTH * (1.0 - math.cos(math.radians(degrees)))


def delta_local(bone, rot_deg=(0.0, 0.0, 0.0)) -> Quaternion:
	r = bone.bone.matrix_local.to_quaternion()
	d = Euler([math.radians(v) for v in rot_deg], "XYZ").to_quaternion()
	return r.inverted() @ d @ r


def loc_local(bone, move=(0.0, 0.0, 0.0)) -> Vector:
	return bone.bone.matrix_local.to_quaternion().inverted() @ Vector(move)


def fcurves_of(action):
	try:
		return list(action.layers[0].strips[0].channelbags[0].fcurves)
	except (AttributeError, IndexError):
		return list(action.fcurves)


def sample(action, frame: float) -> dict:
	"""Each bone's (rotation quaternion, location) in [param action] at [param frame]."""
	out = {}
	for fc in fcurves_of(action):
		name = fc.data_path.split('"')[1]
		kind = fc.data_path.rsplit(".", 1)[1]
		rot, loc = out.setdefault(name, [Quaternion(), Vector()])
		value = fc.evaluate(frame)
		if kind == "rotation_quaternion":
			rot[fc.array_index] = value
		elif kind == "location":
			loc[fc.array_index] = value
	return out


def key_clip(arm, name: str, keys: list, base=None, base_frames=0, reverse=False, legs=1.0) -> None:
	"""Keys [param name]: keys are (seconds, {bone: (rot_deg, move)}) over the stock pose
	(Idle's first frame, or [param base] sampled at the same frame, wrapped at base_frames; with
	[param reverse], at base_frames less it: the base run backwards; the legs' swing from it scaled by
	[param legs] toward Idle's, a shorter stride)."""
	old = bpy.data.actions.get(name)
	if old is not None:
		bpy.data.actions.remove(old)
	for track in list(arm.animation_data.nla_tracks):
		if track.name == name:
			arm.animation_data.nla_tracks.remove(track)
	action = bpy.data.actions.new(name)
	action.use_fake_user = True
	arm.animation_data.action = action
	idle = sample(bpy.data.actions["Idle"], 0.0)
	for seconds, pose in keys:
		frame = round(seconds * FPS)
		if base is None:
			stock = idle
		else:
			stock = sample(base, (base_frames - frame) % base_frames if reverse else frame % base_frames)
			if legs != 1.0:
				for leg, value in stock.items():
					if "Leg" in leg:
						rest = idle.get(leg, [Quaternion(), Vector()])  # Idle keys only some legs.
						value[0] = rest[0].slerp(value[0], legs)
						value[1] = rest[1].lerp(value[1], legs)
		for bone in arm.pose.bones:
			if bone.name.endswith("_end"):
				continue
			rot0, loc0 = stock.get(bone.name, [Quaternion(), Vector()])
			rot_deg, move = pose.get(bone.name, ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
			bone.rotation_quaternion = delta_local(bone, rot_deg) @ rot0
			bone.location = loc0 + loc_local(bone, move)
			bone.keyframe_insert("rotation_quaternion", frame=frame)
			bone.keyframe_insert("location", frame=frame)
	arm.animation_data.action = None
	track = arm.animation_data.nla_tracks.new()
	track.name = name
	track.strips.new(name, 0, action)
	track.mute = True
	print("clip %-12s %.2f s, %d keys" % (name, keys[-1][0], len(keys)))


def gather(sink_deg: float) -> dict:
	"""All four feet drawn in under him (fore back, hind forward) and All sunk to keep them down."""
	return {
		"FrontLeg.L": ((sink_deg, 0, 0), (0, 0, 0)), "FrontLeg.R": ((sink_deg, 0, 0), (0, 0, 0)),
		"BackLeg.L": ((-sink_deg, 0, 0), (0, 0, 0)), "BackLeg.R": ((-sink_deg, 0, 0), (0, 0, 0)),
		"All": ((0, 0, 0), (0, 0, -drop_for(sink_deg))),
	}


def pose(*parts: dict, **bones) -> dict:
	out = {}
	for part in parts:
		out.update(part)
	for name, value in bones.items():
		out[name.replace("__", ".")] = value
	return out


def head(neck_down, head_down=0.0, turn=0.0, roll=0.0):
	"""Neck and Head: the bend mostly on Neck; turn (to his left) and roll on Neck too."""
	return {"Neck": ((neck_down, roll, turn), (0, 0, 0)), "Head": ((head_down, 0, 0), (0, 0, 0))}


def charge_tell() -> list:
	# 1.2 s, its end on the run's start. Head right down (the coordinator: unmistakable at play
	# distance), the haunches gathered, the right fore pawing back twice in big strokes, a snort's
	# toss, then leaning into the run.
	low = head(42, 10)
	crouch = gather(18)
	paw_up = lambda: {"FrontLeg.R": ((-50, 0, 0), (0, 0, 0))}  # Lifted forward.
	paw_back = lambda: {"FrontLeg.R": ((42, 0, 0), (0, 0, 0))}  # Scraped back.
	return [
		(0.0, {}),
		(0.18, pose(crouch, head(32, 6))),
		(0.3, pose(crouch, low, paw_up())),
		(0.46, pose(crouch, low, paw_back())),
		(0.6, pose(crouch, low, paw_up())),
		(0.76, pose(crouch, low, paw_back())),
		(0.9, pose(crouch, head(26, 0))),  # The snort: a toss up.
		(1.04, pose(crouch, low)),
		(1.2, pose(gather(10), head(36, 4), All=((0, 0, 0), (0, -0.06, -drop_for(10))))),
	]


def charge_keys(run) -> list:
	# Over the stock Run (16 frames): head low with the tusks near level, the stride longer.
	keys = []
	for frame in range(0, 17, 2):
		keys.append((frame / FPS, pose(head(40, -18))))
	return keys


def skid() -> list:
	# 1.5 s: the fore legs braced ahead, the whole body slewed round from the root (no counter-turn),
	# the head swinging to find his target, then a shake and the stand.
	brace = {"FrontLeg.L": ((-24, 0, 0), (0, 0, 0)), "FrontLeg.R": ((-24, 0, 0), (0, 0, 0)),
		"BackLeg.L": ((10, 0, 0), (0, 0, 0)), "BackLeg.R": ((10, 0, 0), (0, 0, 0))}
	sunk = drop_for(24)
	return [
		(0.0, pose(head(35, -10))),
		(0.17, pose(brace, head(30, -5, turn=-15), All=((0, 0, 40), (0, 0, -sunk)))),
		(0.42, pose(brace, head(20, 0, turn=-40), All=((0, 0, 70), (0, 0, -sunk)))),
		(0.7, pose(head(15, 0, turn=-25), All=((0, 0, 45), (0, 0, 0)))),
		(0.95, pose(head(10, 0, turn=10), All=((0, 0, 15), (0, 0, 0)))),
		(1.1, pose(head(12, 0, roll=16))),  # The shake.
		(1.22, pose(head(12, 0, roll=-16))),
		(1.34, pose(head(8, 0, roll=8))),
		(1.5, {}),
	]


def dazed() -> list:
	# A 1.2 s loop through the crash's stun: head low and swaying, the fore legs splayed wide, a
	# slow stagger side to side and a head shake once a loop (the coordinator: clearly more open than
	# the skid).
	splay = lambda lean: {
		"FrontLeg.L": ((4, -32 + lean, 0), (0, 0, 0)), "FrontLeg.R": ((4, 32 + lean, 0), (0, 0, 0)),
		"BackLeg.L": ((-4, -16 + lean, 0), (0, 0, 0)), "BackLeg.R": ((-4, 16 + lean, 0), (0, 0, 0)),
	}
	down = -drop_for(32) * 0.8
	return [
		(0.0, pose(splay(0), head(24, 16, turn=16, roll=-14), All=((0, -9, 0), (0.02, 0, down)))),
		(0.3, pose(splay(-4), head(28, 18, turn=0, roll=0), All=((0, 0, 0), (0, 0, down - 0.01)))),
		(0.6, pose(splay(0), head(24, 16, turn=-16, roll=14), All=((0, 9, 0), (-0.02, 0, down)))),
		(0.76, pose(splay(0), head(22, 14, turn=24, roll=8), All=((0, 4, 0), (-0.01, 0, down)))),  # The shake.
		(0.88, pose(splay(4), head(22, 14, turn=-24, roll=-8), All=((0, 0, 0), (0, 0, down)))),
		(1.2, pose(splay(0), head(24, 16, turn=16, roll=-14), All=((0, -9, 0), (0.02, 0, down)))),
	]


def hook() -> list:
	# 0.9 s, the tusks' blow at 0.6 s: the head dipped and turned to his right, then a rising hook up
	# and across to his left, and back.
	return [
		(0.0, {}),
		(0.33, pose(gather(8), head(32, 8, turn=-28, roll=-8), All=((0, 0, -8), (0, 0.03, -drop_for(8))))),
		(0.5, pose(gather(8), head(36, 10, turn=-32, roll=-10), All=((0, 0, -10), (0, 0.03, -drop_for(8))))),
		(0.6, pose(head(0, -10, turn=24, roll=12), All=((0, 0, 10), (0, -0.06, 0)))),
		(0.7, pose(head(4, -6, turn=26, roll=10), All=((0, 0, 12), (0, -0.05, 0)))),
		(0.9, {}),
	]


# The back-off's stance (the coordinator: snout near knee height, the tusks forward at his foe,
# held the whole loop), the paw ending on it.
BACK_STANCE = pose(head(50, 16), All=((0, 0, 0), (0, 0, -drop_for(8))))


def back_off() -> list:
	# Over the stock Walk (24 frames, 1 s) run backwards: backing away from his foe, still facing
	# them (enemy-ai's back-off before a charge, ~2 cells a second for up to 2 s), head low and the
	# haunches a little gathered, so it reads as squaring up, not fleeing; the stride shortened to
	# wary steps (legs 0.55: the walk's far hind fling read as a run). Loops at any frame; cut short
	# after one step, the view blends it out.
	keys = []
	for frame in range(0, 25, 3):
		keys.append((frame / FPS, BACK_STANCE))
	return keys


def paw() -> list:
	# 0.6 s on the cry "snort" (he stands its 6 ticks, enemy-ai's "paw": 6): head down, the right
	# fore scraped back once in a big stroke, and a snort's toss, ending near his stance so the
	# back-off picks up from it.
	# The hoof lifted to about the elbow and scraped well back, the toss big (the coordinator: read
	# from the iso camera at distance).
	low = head(46, 12)
	return [
		(0.0, {}),
		(0.14, pose(gather(10), low, FrontLeg__R=((-78, 0, 0), (0, 0, 0)))),
		(0.3, pose(gather(10), low, FrontLeg__R=((60, 0, 0), (0, 0, 0)))),
		(0.44, pose(gather(10), head(8, -20))),  # The snort: a big toss up.
		(0.6, BACK_STANCE),
	]


def main() -> None:
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	arm = bpy.data.objects[ARM]
	if arm.animation_data is None:
		arm.animation_data_create()
	was = arm.animation_data.action
	arm.animation_data.action = None
	key_clip(arm, "Charge_Tell", charge_tell())
	key_clip(arm, "Charge", charge_keys(None), base=bpy.data.actions["Run"], base_frames=16)
	key_clip(arm, "Skid", skid())
	key_clip(arm, "Dazed", dazed())
	key_clip(arm, "Hook", hook())
	key_clip(arm, "Back_Off", back_off(), base=bpy.data.actions["Walk"], base_frames=24, reverse=True, legs=0.55)
	key_clip(arm, "Paw", paw())
	arm.animation_data.action = was
	if "--save" in args:
		bpy.ops.wm.save_mainfile()
		print("saved %s" % bpy.data.filepath)


main()
