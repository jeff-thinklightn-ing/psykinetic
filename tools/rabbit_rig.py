# Rigs a rabbit mesh (a TRELLIS.2 model of a rabbit in its resting crouch) on a small
# four-legged skeleton of its own, built from landmarks measured on the mesh, and authors its
# clips by script: Idle, Hop, Hop_Run, Nibble, Sit_Up, Hit, Death (the names
# creature.rabbit's slot reads). Weights by bone heat; faceted and coloured on art-kit's
# palette; the .blend saved beside the .glb, as the slot's source.
#
#   blender -b -P tools/rabbit_rig.py -- <mesh .glb> <out.glb> [--height M] [--tris N]
#       [--turn DEGREES] [--colours REGION=ROW,COL ...]
#
# The mesh should crouch as the brief asks: front legs straight down and apart, the long
# hind feet flat on the ground beside the body, ears up and apart, head toward -Y
# (Blender's front; --turn 180 if it faces +Y). It is centred, stood on z = 0 and scaled
# uniformly to --height (the ear tips) if given.
#
# Landmarks: the ground points part into front paws and hind feet at the widest gap along
# the length; each side's paw is its points' middle, a hind foot runs from its heel (the
# back of its points) to its toe. The ears are what stands above the lowest height at which
# a slice across them still has a gap in it; the snout the front-most points. The back and
# belly by rays down and up the centre line, as tools/creature_rig.py finds them.
#
# Bones (local X is the world's +X for all of them, the rabbit's left, so a rotation about
# X tips a bone in the side view: positive sends the front down and the bottom back):
#   root (ground, under the middle, along +Y), hips (the hip joint to the middle of the
#   back), spine (to the chest), neck, head (to the snout), ear_l, ear_r, tail; per side
#   thigh, shin, foot (hip, knee, hock on the ground, toe), upper_arm, forearm, paw.
#
# Colours (--colours): regions body, belly (faces looking down, under the body's middle,
# and the chin), tail (the tail bone's length off the rump, near the middle), ear_tips (the top quarter of the ears);
# default body=5,2 belly=7,7 tail=7,7 ear_tips=5,6.
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True  # No __pycache__ left in tools/.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from creature_rig import args, bounds, decimate, load_mesh, points, stand, tris  # noqa: E402

FPS = 24
## How much of the height counts as touching the ground.
GROUND_BAND = 0.05
DEFAULT_COLOURS = {"body": (5, 2), "belly": (7, 7), "tail": (7, 7), "ear_tips": (5, 6)}


def side_of(pts: list, left: bool) -> list:
	return [p for p in pts if (p.x > 0.0) == left]


def middle(pts: list) -> Vector:
	return sum(pts, Vector()) / len(pts)


## The rabbit's landmarks (world space, the body stood and centred).
def marks(body) -> dict:
	pts = points(body)
	lo, hi = bounds(pts)
	h = hi.z - lo.z
	ground = sorted((p for p in pts if p.z < lo.z + GROUND_BAND * h), key=lambda p: p.y)
	gap, at = max((ground[i + 1].y - ground[i].y, i) for i in range(len(ground) - 1))
	front, hind = ground[:at + 1], ground[at + 1:]
	print("ground: %d front, %d hind points, a gap of %.3f m" % (len(front), len(hind), gap))
	m = {"lo": lo, "hi": hi, "h": h}
	for name, left in (("l", True), ("r", False)):
		paw = side_of(front, left)
		foot = sorted(side_of(hind, left), key=lambda p: p.y)
		if not paw or len(foot) < 4:
			raise SystemExit("no %s front paw or hind foot on the ground" % name)
		m["paw_" + name] = middle(paw)
		k = max(1, len(foot) // 10)
		m["toe_" + name] = middle(foot[:k])
		m["heel_" + name] = middle(foot[-k:])
	tree = BVHTree.FromPolygons(pts, [list(p.vertices) for p in body.data.polygons])

	def ray(y: float, up: bool) -> float:
		start = Vector((0.0, y, lo.z - 1.0 if up else hi.z + 1.0))
		hit = tree.ray_cast(start, Vector((0, 0, 1 if up else -1)))[0]
		return hit.z if hit is not None else None

	m["ray"] = ray
	# The ears: down from the top, the lowest slice that still has a gap across x.
	# A slice is 3 cm-ish thick (0.08 of the height) so each ear has points in it; the gap
	# must cross the middle (the ears stand either side of it).
	z = hi.z
	step, thick = 0.01 * h, 0.08 * h
	ear_base, split = None, None
	while z > lo.z + 0.4 * h:
		xs = sorted(p.x for p in pts if z - thick <= p.z < z)
		gaps = [(xs[j + 1] - xs[j], j) for j in range(len(xs) - 1) if xs[j] < 0.05 * h and xs[j + 1] > -0.05 * h]
		wide, i = max(gaps) if gaps else (0.0, 0)
		if wide >= 0.04 * h:
			split = (xs[i] + xs[i + 1]) / 2
		elif split is not None and len(xs) > 2:  # Both ears seen apart, and now joined: their base.
			ear_base = z - thick / 2
			break
		z -= step
	if ear_base is None:
		raise SystemExit("no ears found")
	ears = [p for p in pts if p.z >= ear_base]
	m["ear_base"] = ear_base
	for name, left in (("l", True), ("r", False)):
		ear = [p for p in ears if (p.x > split) == left]
		ear.sort(key=lambda p: p.z)
		m["ear_root_" + name] = middle(ear[:max(1, len(ear) // 8)])
		m["ear_tip_" + name] = middle(ear[-max(1, len(ear) // 20):])
	nose = sorted(pts, key=lambda p: p.y)[:6]
	m["snout"] = Vector((0.0, middle(nose).y, middle(nose).z))
	# The tail: the rear-most points.
	tail = sorted(pts, key=lambda p: -p.y)[:max(3, len(pts) // 100)]
	m["tail_tip"] = Vector((0.0, hi.y, middle(tail).z))
	for key in sorted(k for k in m if isinstance(m[k], Vector)):
		print("  %-11s (%.3f %.3f %.3f)" % (key, *m[key]))
	print("  ear_base    %.3f" % ear_base)
	return m


## Rays (as marks' own) on [param body] as it is now, after decimating.
def marks_ray(body, m: dict):
	pts = points(body)
	tree = BVHTree.FromPolygons(pts, [list(p.vertices) for p in body.data.polygons])
	lo, hi = m["lo"], m["hi"]

	def ray(y: float, up: bool) -> float:
		start = Vector((0.0, y, lo.z - 1.0 if up else hi.z + 1.0))
		hit = tree.ray_cast(start, Vector((0, 0, 1 if up else -1)))[0]
		return hit.z if hit is not None else None

	return ray


## The skeleton's joints from the landmarks: {bone: (head, tail, parent)}.
def joints(m: dict) -> dict:
	h = m["h"]
	ray = m["ray"]
	paw_y = (m["paw_l"].y + m["paw_r"].y) / 2
	toe_y = (m["toe_l"].y + m["toe_r"].y) / 2
	heel_y = (m["heel_l"].y + m["heel_r"].y) / 2
	foot_len = heel_y - toe_y
	# The hip joint over the back of the foot, halfway up the haunch.
	hip_y = heel_y - 0.25 * foot_len
	back_hip = ray(hip_y, False) or 0.6 * h
	hip = Vector((0.0, hip_y, 0.5 * back_hip))
	mid_y = (hip_y + paw_y) / 2
	belly, back = ray(mid_y, True) or 0.2 * h, ray(mid_y, False) or 0.6 * h
	mid = Vector((0.0, mid_y, (belly + back) / 2))
	chest_y = paw_y + 0.3 * (mid_y - paw_y)
	chest_low = ray(chest_y, True) or 0.25 * h
	chest = Vector((0.0, chest_y, chest_low + 0.12 * h))
	ear_root = (m["ear_root_l"] + m["ear_root_r"]) / 2
	poll = Vector((0.0, ear_root.y + 0.06 * h, ear_root.z - 0.12 * h))  # The head's pivot.
	out = {
		"root": (Vector((0.0, mid_y, 0.0)), Vector((0.0, mid_y + 0.15 * h, 0.0)), None),
		"hips": (hip, mid, "root"),
		"spine": (mid, chest, "hips"),
		"neck": (chest, poll, "spine"),
		"head": (poll, m["snout"], "neck"),
		"tail": (Vector((0.0, m["tail_tip"].y - 0.12 * h, m["tail_tip"].z)), m["tail_tip"], "hips"),
	}
	for s in ("l", "r"):
		sign = 1.0 if s == "l" else -1.0
		toe, heel, paw = m["toe_" + s], m["heel_" + s], m["paw_" + s]
		x = abs(heel.x + toe.x) / 2 * sign
		hip_s = Vector((0.8 * x, hip.y, hip.z))
		knee = Vector((x, toe_y + 0.45 * foot_len, 0.5 * hip.z))
		hock = Vector((x, heel.y, 0.06 * h))
		out["thigh_" + s] = (hip_s, knee, "hips")
		out["shin_" + s] = (knee, hock, "thigh_" + s)
		out["foot_" + s] = (hock, Vector((x, toe.y, 0.015 * h)), "shin_" + s)
		shoulder = Vector((paw.x, paw.y + 0.03 * h, chest.z))
		elbow = Vector((paw.x, paw.y + 0.02 * h, 0.5 * chest.z))
		wrist = Vector((paw.x, paw.y, 0.05 * h))
		out["ear_" + s] = (m["ear_root_" + s], m["ear_tip_" + s], "head")
		out["upper_arm_" + s] = (shoulder, elbow, "spine")
		out["forearm_" + s] = (elbow, wrist, "upper_arm_" + s)
		out["paw_" + s] = (wrist, Vector((paw.x, paw.y - 0.08 * h, 0.015 * h)), "forearm_" + s)
	return out


def build_armature(spec: dict):
	data = bpy.data.armatures.new("RabbitArmature")
	arm = bpy.data.objects.new("RabbitArmature", data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for name, (head, tail, parent) in spec.items():  # Parents come first in the spec.
		bone = data.edit_bones.new(name)
		bone.head, bone.tail = head, tail
		if parent:
			bone.parent = data.edit_bones[parent]
		# Local X along the world's +X, so every bone tips the same way about it.
		bone.align_roll(Vector((0.0, 0.0, 1.0)) if abs(bone.vector.normalized().z) < 0.9 else Vector((0.0, -1.0, 0.0)))
		if bone.x_axis.x < 0.0:
			bone.roll += math.pi
		print("  %-12s (%.3f %.3f %.3f) -> (%.3f %.3f %.3f)  x axis (%.2f %.2f %.2f)" % (name, *head, *tail, *bone.x_axis))
	bpy.ops.object.mode_set(mode="OBJECT")
	return arm


## Bone heat, then any vertex it left without a bone (a loose piece) takes its nearest
## weighted neighbour's weights; at most four, summing to one.
def skin(body, arm) -> None:
	from mathutils.kdtree import KDTree
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.parent_set(type="ARMATURE_AUTO")
	verts = body.data.vertices
	weighted = [v for v in verts if any(g.weight > 1e-4 for g in v.groups)]
	bare = [v for v in verts if not any(g.weight > 1e-4 for g in v.groups)]
	if bare:
		tree = KDTree(len(weighted))
		for i, v in enumerate(weighted):
			tree.insert(v.co, i)
		tree.balance()
		groups = body.vertex_groups
		for v in bare:
			src = weighted[tree.find(v.co)[1]]
			for g in src.groups:
				groups[g.group].add([v.index], g.weight, "REPLACE")
		print("skin: %d vertices took their nearest neighbour's weights" % len(bare))
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
	bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)


def colour(body, m: dict, swatches: dict, rows: int) -> None:
	mesh = body.data
	if not mesh.uv_layers:
		mesh.uv_layers.new(name="UVMap")
	uv = mesh.uv_layers.active.data
	h = m["h"]
	ray = m["ray"]
	paw_y = (m["paw_l"].y + m["paw_r"].y) / 2
	heel_y = (m["heel_l"].y + m["heel_r"].y) / 2
	tips = min(m["ear_tip_l"].z, m["ear_tip_r"].z)
	ear_cut = tips - 0.25 * (tips - m["ear_base"])
	counts = {}
	for poly in mesh.polygons:
		c = poly.center
		middle_z = None
		if c.z >= ear_cut:
			region = "ear_tips"
		elif c.y > m["tail_tip"].y - 0.12 * h and abs(c.x) < 0.12 * h and c.z > 0.12 * h:
			region = "tail"
		elif poly.normal.z < -0.4 and c.z > 0.08 * h:
			# Under the body (the belly between the legs) or under the chin.
			middle_z = ray(c.y, True)
			region = "belly" if c.y < paw_y or (middle_z is not None and c.z < middle_z + 0.1 * h) else "body"
		else:
			region = "body"
		region = region if region in swatches else "body"
		counts[region] = counts.get(region, 0) + 1
		row, col = swatches[region]
		at = ((col + 0.5) / 8.0, 1.0 - (row + 0.5) / rows)
		for li in poly.loop_indices:
			uv[li].uv = at
	mesh.materials.clear()
	mesh.materials.append(bpy.data.materials.get("palette") or bpy.data.materials.new("palette"))
	print("colours: %s" % counts)


# The clips. Each is a function of t (0..1 through the clip) giving a pose: bone rotations
# {bone: (rx, ry, rz)} in degrees (about the bone's own axes; X is the world's +X for every
# bone, so rx tips it in the side view, adding to its angle there), the root's "lift"
# (metres up), "back" (metres toward the tail) and "roll" (degrees about the body's length),
# and where the feet go: "hock", "toe" (a hind foot's heel and toe) and "wrist", "tip" (a
# front paw's), each (dy, dz) metres from where it stands at rest, both sides alike. Legs
# the pose gives no rotations for are solved to reach their feet (Legs.solve), so a foot
# not told to move stays planted while the body moves over it.

def bump(t: float, start: float, end: float) -> float:
	"""0 outside start..end, rising to 1 in the middle and back, smoothly."""
	if t <= start or t >= end:
		return 0.0
	return math.sin(math.pi * (t - start) / (end - start)) ** 2


def ease(t: float, start: float, end: float) -> float:
	"""0 before start, 1 after end, smooth between."""
	if t <= start:
		return 0.0
	if t >= end:
		return 1.0
	u = (t - start) / (end - start)
	return u * u * (3.0 - 2.0 * u)


def angle(a: tuple, b: tuple) -> float:
	"""The side view's angle (degrees) from a to b, (y, z) points: rx adds to it."""
	return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def turn(p: tuple, about: tuple, degrees: float) -> tuple:
	c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
	y, z = p[0] - about[0], p[1] - about[1]
	return (about[0] + y * c - z * s, about[1] + y * s + z * c)


def toward(p: tuple, degrees: float, length: float) -> tuple:
	return (p[0] + length * math.cos(math.radians(degrees)), p[1] + length * math.sin(math.radians(degrees)))


## Two bones from [param root] reaching for [param goal] (side view): their angles and the
## joint between, bent forward (toward -Y, a knee) or back (an elbow). Out of reach, they
## point at it.
def reach(root: tuple, goal: tuple, a: float, b: float, forward: bool) -> tuple:
	d = math.dist(root, goal)
	d = min(max(d, abs(a - b) + 1e-5), a + b - 1e-5)
	base = angle(root, goal)
	bend = math.degrees(math.acos(max(-1.0, min(1.0, (a * a + d * d - b * b) / (2.0 * a * d)))))
	first = min((base + bend, base - bend), key=lambda deg: toward(root, deg, a)[0] * (1 if forward else -1))
	joint = toward(root, first, a)
	return first, angle(joint, goal), joint


class Legs:
	"""The legs' rest in the side view, and the rotations that put the feet where a pose
	says, the body posed above them (root, hips, spine)."""

	def __init__(self, arm):
		self.rest = {}
		for bone in arm.data.bones:
			head = arm.matrix_world @ bone.head_local
			tail = arm.matrix_world @ bone.tail_local
			self.rest[bone.name] = ((head.y, head.z), (tail.y, tail.z))

	def solve(self, pose: dict) -> dict:
		out = dict(pose)
		r = self.rest
		hips, spine = pose.get("hips", (0.0,) * 3)[0], pose.get("spine", (0.0,) * 3)[0]
		shift = (pose.get("back", 0.0), pose.get("lift", 0.0))
		hip = r["hips"][0]

		def placed(p: tuple) -> tuple:  # Turned with the hips, then moved by the root.
			q = turn(p, hip, hips)
			return (q[0] + shift[0], q[1] + shift[1])

		for s in ("l", "r"):
			if "thigh_" + s not in pose:
				j0, k0 = r["thigh_" + s]
				h0, t0 = r["foot_" + s]
				a, b = math.dist(j0, k0), math.dist(k0, h0)
				dh = pose.get("hock", (0.0, 0.0))
				dt = pose.get("toe", dh)
				goal = (h0[0] + dh[0], h0[1] + dh[1])
				toe = (t0[0] + dt[0], t0[1] + dt[1])
				j = placed(j0)
				thigh, shin, knee = reach(j, goal, a, b, True)
				hock = toward(knee, shin, b)
				rx_thigh = thigh - angle(j0, k0) - hips
				rx_shin = shin - angle(k0, h0) - hips - rx_thigh
				rx_foot = angle(hock, toe) - angle(h0, t0) - hips - rx_thigh - rx_shin
				out["thigh_" + s] = (rx_thigh, 0.0, 0.0)
				out["shin_" + s] = (rx_shin, 0.0, 0.0)
				out["foot_" + s] = (rx_foot, 0.0, 0.0)
			if "upper_arm_" + s not in pose:
				s0, e0 = r["upper_arm_" + s]
				w0, p0 = r["paw_" + s]
				a, b = math.dist(s0, e0), math.dist(e0, w0)
				dw = pose.get("wrist", (0.0, 0.0))
				dp = pose.get("tip", dw)
				goal = (w0[0] + dw[0], w0[1] + dw[1])
				tip = (p0[0] + dp[0], p0[1] + dp[1])
				# The shoulder rides the spine, which rides the hips.
				shoulder = placed(turn(s0, r["spine"][0], spine))
				up, fore, elbow = reach(shoulder, goal, a, b, False)
				wrist = toward(elbow, fore, b)
				body = hips + spine
				rx_up = up - angle(s0, e0) - body
				rx_fore = fore - angle(e0, w0) - body - rx_up
				rx_paw = angle(wrist, tip) - angle(w0, p0) - body - rx_up - rx_fore
				out["upper_arm_" + s] = (rx_up, 0.0, 0.0)
				out["forearm_" + s] = (rx_fore, 0.0, 0.0)
				out["paw_" + s] = (rx_paw, 0.0, 0.0)
		# Angles wrapped to -180..180, so keys between frames turn the short way.
		for name, value in out.items():
			if name.split("_")[0] in ("thigh", "shin", "foot", "upper", "forearm", "paw"):
				out[name] = ((value[0] + 180.0) % 360.0 - 180.0, value[1], value[2])
		return out


def both(pose: dict, **bones) -> dict:
	"""Rotations (rx only) for both sides' bones, by their names without the side."""
	for name, rx in bones.items():
		for s in ("l", "r"):
			pose["%s_%s" % (name, s)] = (rx, 0.0, 0.0)
	return pose


def ears(pose: dict, back: float, spread: float = 0.0, twitch_l: float = 0.0) -> dict:
	# back: the tips toward the tail (negative rx); spread: apart (about the bone's Z).
	pose["ear_l"] = (-back, twitch_l, spread)
	pose["ear_r"] = (-back, 0.0, -spread)
	return pose


def level_head(pose: dict, share: float = 0.8) -> dict:
	"""The neck and head turned against the body's pitch, so the head stays near level."""
	body = pose.get("hips", (0.0,) * 3)[0] + pose.get("spine", (0.0,) * 3)[0]
	nx = pose.get("neck", (0.0,) * 3)[0]
	hx = pose.get("head", (0.0, 0.0, 0.0))
	pose["neck"] = (nx - 0.5 * share * body, 0.0, 0.0)
	pose["head"] = (hx[0] - 0.5 * share * body, hx[1], hx[2])
	return pose


def idle(t: float, h: float, foot: float) -> dict:
	breath = math.sin(2.0 * math.pi * t)
	pose = {"hips": (0.8 * breath, 0.0, 0.0), "spine": (-0.6 * breath, 0.0, 0.0),
		"head": (2.0 * math.sin(2.0 * math.pi * (t - 0.2)), 0.0, 0.0), "lift": 0.004 * h * breath}
	return ears(level_head(pose), 0.0, 0.0, 25.0 * bump(t, 0.55, 0.65))


def hop(t: float, h: float, foot: float, big: float) -> dict:
	"""One hop: the hind legs push, heels first (0..0.3); airborne (0.15..0.65), the front
	paws reaching and the hind feet trailing; down on the front paws, then the hind feet
	brought up under the body (0.6..0.95). big: 1 for the walking hop, more for the run."""
	air = bump(t, 0.15, 0.65)
	lift = 0.12 * h * big * air
	pitch = big * (8.0 * bump(t, 0.0, 0.3) - 6.0 * bump(t, 0.25, 0.55) + 10.0 * bump(t, 0.5, 0.85))
	pose = {"hips": (pitch, 0.0, 0.0), "spine": (-4.0 * big * air, 0.0, 0.0),
		"tail": (-15.0 * big * air, 0.0, 0.0), "lift": lift}
	trail = 0.35 * foot * big * bump(t, 0.12, 0.85)
	pose["hock"] = (trail, 0.7 * lift + 0.35 * foot * big * bump(t, 0.0, 0.4))
	pose["toe"] = (trail, 0.7 * lift + 0.05 * foot * big * bump(t, 0.15, 0.6))
	reach_y = -0.35 * foot * big * bump(t, 0.12, 0.6) + 0.15 * foot * big * bump(t, 0.5, 0.95)
	pose["wrist"] = (reach_y, 0.8 * lift + 0.1 * foot * big * bump(t, 0.12, 0.5))
	pose["tip"] = (reach_y, 0.8 * lift)
	return ears(level_head(pose, 0.6), 12.0 * big * air + (25.0 if big > 1.0 else 0.0), 4.0 * big)


def nibble(t: float, h: float, foot: float) -> dict:
	down = ease(t, 0.0, 0.15) * (1.0 - ease(t, 0.85, 1.0))
	chew = math.sin(2.0 * math.pi * 6.0 * t) * down
	pose = {"hips": (6.0 * down, 0.0, 0.0), "spine": (6.0 * down, 0.0, 0.0),
		"neck": (22.0 * down, 0.0, 0.0), "head": (20.0 * down + 3.0 * chew, 0.0, 0.0)}
	return ears(pose, 15.0 * down, -3.0 * down)


def sit_up(t: float, h: float, foot: float) -> dict:
	up = ease(t, 0.0, 0.25) * (1.0 - ease(t, 0.8, 1.0))
	look = math.sin(2.0 * math.pi * t)
	pose = {"hips": (-38.0 * up, 0.0, 0.0), "spine": (-14.0 * up, 0.0, 0.0),
		"head": (0.0, 12.0 * look * up, 0.0), "tail": (10.0 * up, 0.0, 0.0)}
	level_head(pose, 1.0)
	# The hind feet stay as they stood (solved); the front legs hang, tucked.
	both(pose, upper_arm=40.0 * up, forearm=-35.0 * up, paw=30.0 * up)
	return ears(pose, -6.0 * up, 6.0 * up, 20.0 * bump(t, 0.45, 0.55))


def hit(t: float, h: float, foot: float) -> dict:
	jolt = bump(t, 0.0, 0.6) if t < 0.6 else 0.0
	pose = {"hips": (-10.0 * jolt, 0.0, 0.0), "spine": (-6.0 * jolt, 0.0, 0.0),
		"neck": (-10.0 * jolt, 0.0, 0.0), "head": (-12.0 * jolt, 0.0, 0.0),
		"tail": (-20.0 * jolt, 0.0, 0.0), "lift": 0.03 * h * jolt, "back": 0.06 * h * jolt}
	return ears(pose, 45.0 * bump(t, 0.0, 1.0), 6.0 * jolt)


def death(t: float, h: float, foot: float, width: float) -> dict:
	fall = ease(t, 0.15, 0.6)
	jump = bump(t, 0.0, 0.3)
	limp = ease(t, 0.45, 0.9)
	pose = {"hips": (-8.0 * jump, 0.0, 0.0), "spine": (-6.0 * jump + 4.0 * limp, 0.0, 0.0),
		"neck": (-10.0 * jump + 25.0 * limp, 0.0, 0.0), "head": (15.0 * limp, 0.0, 0.0),
		"tail": (0.0, 0.0, 0.0), "lift": 0.06 * h * jump + 0.45 * width * fall,
		"roll": 88.0 * fall}
	both(pose, thigh=30.0 * limp, shin=-20.0 * limp, foot=20.0 * limp, upper_arm=-30.0 * limp,
		forearm=10.0 * limp, paw=0.0)
	return ears(pose, 50.0 * limp, 0.0)


def author(arm, legs: Legs, name: str, seconds: float, loop: bool, pose_at) -> None:
	frames = max(2, round(seconds * FPS))
	action = bpy.data.actions.new(name)
	action.use_fake_user = True
	if arm.animation_data is None:
		arm.animation_data_create()
	arm.animation_data.action = action
	bones = arm.pose.bones
	for b in bones:
		b.rotation_mode = "XYZ"
	for f in range(frames + 1):
		t = f / frames
		pose = legs.solve(pose_at(0.0 if loop and f == frames else t))
		for b in bones:
			rx, ry, rz = pose.get(b.name, (0.0, 0.0, 0.0)) if b.name != "root" else (0.0, pose.get("roll", 0.0), 0.0)
			b.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))
			b.keyframe_insert("rotation_euler", frame=f + 1)
			if b.name == "root":
				# The root's own axes: Y along the body toward the tail, Z up.
				b.location = (0.0, pose.get("back", 0.0), pose.get("lift", 0.0))
				b.keyframe_insert("location", frame=f + 1)
	print("clip %-8s %d frames%s" % (name, frames + 1, ", looped" if loop else ""))


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <mesh .glb> <out.glb> [--height M] [--tris N] [--turn DEG] [--colours region=row,col ...]")
	mesh_path, out = (os.path.abspath(p) for p in a[:2])
	height, target, turn, swatches = None, 0, 0.0, dict(DEFAULT_COLOURS)
	rest = a[2:]
	i = 0
	while i < len(rest):
		if rest[i] in ("--height", "--tris", "--turn"):
			value = rest[i + 1]
			if rest[i] == "--height":
				height = float(value)
			elif rest[i] == "--tris":
				target = int(value)
			else:
				turn = float(value)
			i += 2
		elif rest[i] == "--colours":
			i += 1
			while i < len(rest) and not rest[i].startswith("--"):
				region, at = rest[i].split("=")
				row, col = at.split(",")
				swatches[region] = (int(row), int(col))
				i += 1
		else:
			raise SystemExit("unknown argument %s" % rest[i])
	bpy.ops.wm.read_factory_settings(use_empty=True)
	body = load_mesh(mesh_path)
	if turn:
		# On the mesh's own data (a glTF import's object turns by quaternion: see creature_rig).
		from mathutils import Matrix
		body.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
		body.data.update()
	stand(body, height)
	m = marks(body)  # On the full mesh: more points to find the ears and feet by.
	if target:
		decimate(body, target)
		m["ray"] = marks_ray(body, m)
	arm = build_armature(joints(m))
	skin(body, arm)
	print("rigged: %d vertices, %d tris" % (len(body.data.vertices), tris(body)))
	palette = bpy.data.images.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "kit", "palette.png"))
	rows = round(palette.size[1] / (palette.size[0] / 8))
	bpy.data.images.remove(palette)
	colour(body, m, swatches, rows)
	h = m["h"]
	width = m["hi"].x - m["lo"].x
	foot = sum(math.dist((m["heel_" + s].y, m["heel_" + s].z), (m["toe_" + s].y, m["toe_" + s].z)) for s in "lr") / 2
	legs = Legs(arm)
	author(arm, legs, "Idle", 2.0, True, lambda t: idle(t, h, foot))
	author(arm, legs, "Hop", 0.5, True, lambda t: hop(t, h, foot, 1.0))
	author(arm, legs, "Hop_Run", 0.34, True, lambda t: hop(t, h, foot, 1.6))
	author(arm, legs, "Nibble", 1.6, True, lambda t: nibble(t, h, foot))
	author(arm, legs, "Sit_Up", 2.0, True, lambda t: sit_up(t, h, foot))
	author(arm, legs, "Hit", 0.4, False, lambda t: hit(t, h, foot))
	author(arm, legs, "Death", 1.0, False, lambda t: death(t, h, foot, width))
	arm.animation_data.action = None
	for b in arm.pose.bones:
		b.location = (0.0, 0.0, 0.0)
		b.rotation_euler = (0.0, 0.0, 0.0)
	bpy.context.scene["source"] = "%s rigged by tools/rabbit_rig.py" % os.path.basename(mesh_path)
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(out)[0] + ".blend")
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_animations=True, export_animation_mode="ACTIONS", export_extras=True)
	print("wrote %s" % out)


if __name__ == "__main__":
	main()
