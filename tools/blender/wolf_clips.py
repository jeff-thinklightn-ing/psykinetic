# The old grey's lunge as a made leap (780 amended (24), animation's side; the coordinator's ask after
# v0.1.210's known leaks: "a squash and spring, not a made leap"; package the old grey's) keyed on the
# Quaternius Wolf's rig, beside its stock clips, as NLA-held actions the slot's export carries:
#   blender -b art/kit/creatures/creature.old_wolf/creature.old_wolf.blend -P tools/blender/wolf_clips.py
#       [-- --save]
# then tools/blender/export_slot.py to the slot's .glb. --save writes the .blend back; without it
# the run only reports. Rerunnable: an earlier run's actions and tracks are replaced.
#
# Built from the rig's own jump: the stock Gallop_Jump and Jump_ToIdle (the same leap, the latter
# landing into the stand) gather low at frame CROUCH, are in the air by 16 and down by 22, all in
# place (the game's rush slides the body). Poses are each bone's local values (rotation, location),
# the IK targets among them, so a mix of two poses keeps the feet the rig's.
#
# The sim's timings (enemy-ai's OldWolf, 10 ticks a second): the lunge's tell SPRING["windup"] 8 ticks
# (0.8 s, Lunge_Tell ending on the spring as the rush starts), the rush 3 cells at a tick a cell
# (about 0.3-0.4 s: Leap's flight LEAP_PACE times the stock's), then his pant 20 ticks (the view's).
# His bite's lead (780 amended (23), 6 ticks): Bite_Lead, its contact the snap, struck so the snap
# lands with the blow (CreatureView.wind).
import sys

import bpy
from mathutils import Euler, Quaternion, Vector

FPS = 24
ARM = "AnimalArmature"
CROUCH = 7  # Gallop_Jump's frame most gathered: the tell ends on it, the leap starts from it.
TELL_HELD = 1.25  # Lunge_Tell's crouch held past the spring (0.8 s) till here: the view starts the leap
# when the rush's slide begins, which can come a tick or more after (slots.json contact 0.8 / 1.25).
LEAP_PACE = 1.5  # The stock leap played this much faster: its flight (frames 7-22) about 0.42 s.
DRAWN = 4  # The stock Attack's frame drawn furthest back, head low: the lead holds it.
SNAP = 9  # The stock Attack's bite: the head furthest forward, the lead's contact.
SNAP_AT = 0.65  # Seconds into bite_lead its snap lands (slots.json's contact: SNAP_AT / its length).
FOLLOW_PACE = 1.5  # The stock Attack after its bite, played this much faster.


def fcurves_of(action):
	try:
		return list(action.layers[0].strips[0].channelbags[0].fcurves)
	except (AttributeError, IndexError):
		return list(action.fcurves)


def sample(action, frame: float) -> dict:
	"""Each bone's [rotation quaternion, location] in [param action] at [param frame]."""
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


def mix(a: dict, b: dict, t: float) -> dict:
	"""[param a] toward [param b] by [param t], bone by bone (a bone in one only keeps its value)."""
	out = {}
	for name in set(a) | set(b):
		ra, la = a.get(name, b.get(name))
		rb, lb = b.get(name, a.get(name))
		out[name] = [ra.slerp(rb, t), la.lerp(lb, t)]
	return out


def bent(arm, pose: dict, turns: dict) -> dict:
	"""[param pose] with [param turns] ({bone: degrees about the armature's X, Y, Z}) laid over it:
	about +X a bone pointing ahead (-Y) tips down, an ear or the tail tips back or down."""
	out = {name: [value[0].copy(), value[1].copy()] for name, value in pose.items()}
	for name, deg in turns.items():
		bone = arm.pose.bones[name]
		r = bone.bone.matrix_local.to_quaternion()
		d = Euler([v * 3.14159265 / 180.0 for v in deg], "XYZ").to_quaternion()
		rot, loc = out.setdefault(name, [Quaternion(), Vector()])
		out[name] = [(r.inverted() @ d @ r) @ rot, loc]
	return out


def key_clip(arm, name: str, keys: list) -> None:
	"""Keys [param name]: keys are (seconds, pose) with every bone of the pose keyed."""
	old = bpy.data.actions.get(name)
	if old is not None:
		bpy.data.actions.remove(old)
	for track in list(arm.animation_data.nla_tracks):
		if track.name == name:
			arm.animation_data.nla_tracks.remove(track)
	action = bpy.data.actions.new(name)
	arm.animation_data.action = action
	for seconds, pose in keys:
		frame = seconds * FPS
		for bone in arm.pose.bones:
			if bone.name not in pose:
				continue
			bone.rotation_mode = "QUATERNION"
			bone.rotation_quaternion, bone.location = pose[bone.name]
			bone.keyframe_insert("rotation_quaternion", frame=frame)
			bone.keyframe_insert("location", frame=frame)
	arm.animation_data.action = None
	track = arm.animation_data.nla_tracks.new()
	track.name = name
	track.strips.new(name, 0, action)
	track.mute = True
	print("clip %-12s %.2f s, %d keys" % (name, keys[-1][0], len(keys)))


# The coil's look over the crouch: head and neck let down at his foe, ears laid back, tail low.
def coiled(arm, pose: dict, amount: float) -> dict:
	return bent(arm, pose, {
		"Neck1": (20 * amount, 0, 0), "Neck2": (14 * amount, 0, 0), "Head": (8 * amount, 0, 0),
		"Ear1.L": (-35 * amount, 0, 0), "Ear1.R": (-35 * amount, 0, 0),
		"Tail1": (18 * amount, 0, 0), "Tail2": (8 * amount, 0, 0)})


def lunge_tell(arm) -> list:
	# 0.8 s to the spring (its contact), the crouch held on after it: from the stand he sinks onto his haunches
	# into the leap's own crouch, head down and ears back, held a breath, then the head comes level as
	# the hind legs load, ending on Gallop_Jump's CROUCH so the leap goes on from it.
	stand = sample(bpy.data.actions["Idle"], 0)
	crouch = sample(bpy.data.actions["Gallop_Jump"], CROUCH)
	return [
		(0.0, stand),
		(0.22, coiled(arm, mix(stand, crouch, 0.45), 0.6)),
		(0.45, coiled(arm, mix(stand, crouch, 0.9), 1.0)),
		(0.62, coiled(arm, crouch, 1.0)),
		(0.8, crouch),
		(TELL_HELD, crouch),
	]


def leap(arm) -> list:
	# The stock leap from its crouch to the stand (Jump_ToIdle CROUCH..32): up off the hind legs, the
	# fore reaching, down on them, settled; LEAP_PACE faster than the stock, so its flight spans the
	# rush and he lands into his pant.
	jump = bpy.data.actions["Jump_ToIdle"]
	end = int(jump.frame_range[1])
	return [((f - CROUCH) / FPS / LEAP_PACE, sample(jump, f)) for f in range(CROUCH, end + 1)]


def bite_lead(arm) -> list:
	# His bite told ahead (enemy-ai's 780 amended (23): his lead 6 ticks, the coordinator's approval):
	# drawn back off his forelegs into the stock Attack's gather, head let down and back, ears flat,
	# held a breath deeper, then the snap (the stock bite, SNAP_AT) and its follow-through, quicker.
	attack = bpy.data.actions["Attack"]
	stand = sample(attack, 0)
	drawn = sample(attack, DRAWN)
	end = int(attack.frame_range[1])
	keys = [
		(0.0, stand),
		(0.16, coiled(arm, drawn, 0.9)),
		(0.5, coiled(arm, drawn, 1.15)),
	]
	keys += [(SNAP_AT + (f - SNAP) / FPS / FOLLOW_PACE, sample(attack, f)) for f in range(SNAP, end + 1)]
	print("bite_lead contact %.3f (snap %.2f s of %.2f s)" % (SNAP_AT / keys[-1][0], SNAP_AT, keys[-1][0]))
	return keys


def main() -> None:
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	arm = bpy.data.objects[ARM]
	if arm.animation_data is None:
		arm.animation_data_create()
	was = arm.animation_data.action
	arm.animation_data.action = None
	key_clip(arm, "Lunge_Tell", lunge_tell(arm))
	key_clip(arm, "Leap", leap(arm))
	key_clip(arm, "Bite_Lead", bite_lead(arm))
	arm.animation_data.action = was
	if "--save" in args:
		bpy.ops.wm.save_mainfile()
		print("saved %s" % bpy.data.filepath)


main()
