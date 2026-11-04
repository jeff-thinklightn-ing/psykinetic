# Rigs a four-legged body (art-kit's own mesh, one object, no armature) on a skeleton of its own,
# built from landmarks measured on the mesh, and authors a species' clips by script (780: the great
# bear first; the hill cat next, on the same bones with a long tail, ears and a jaw). Weights by
# bone heat; the mesh's own UVs (art-kit's palette swatches) kept; the rigged .blend saved beside
# the .glb.
#
#   blender -b -P tools/quadruped_rig.py -- <body .blend|.glb> <out.glb> --clips bear|hill_cat
#       [--tail N] [--hock SHARE] [--head SHARE] [--height M] [--turn DEGREES]
#       [--find-tail 1] [--ears 1] [--jaw 1]
#
# The body stands four-square at rest: legs straight down and apart, head toward -Y (Blender's
# front; --turn 180 if it faces +Y), feet on z = 0. It is centred and stood on z = 0 (scaled to
# --height if given).
#
# Landmarks: the four feet (tools/creature_rig.py's foot_centres; front the two nearer -Y), each
# foot's toe and heel (its ground points' front and back); the back and belly by rays down and up
# the centre line; the snout (the front-most points) and the rump (the rear-most). --head is the
# head's length as a share of the body's (default 0.16); --hock the hind heel's height as a share of
# the height (0.06, a bear's flat foot; a cat stands on its toes, about 0.2); --tail the tail's bones
# (1 for a stub). --find-tail 1: a long tail starts where the body's depth behind the hips falls
# under TAIL_SECTION of its depth at them (else a stub off the rump). --ears 1: an ear bone a side
# from the points standing above the skull near its highest (loose ear and tuft pieces wholly on
# it). --jaw 1: a jaw bone for a loose jaw piece under the snout (wholly on it).
#
# Bones (local X is the world's +X for all of them, the body's left, so a rotation about X tips a
# bone in the side view: positive sends its far end down, toward -Z, for a bone pointing ahead):
#   root (the ground under the middle, along +Y), hips (the hip joint to the middle of the back),
#   spine (to the chest), chest (to the withers, over the shoulders), neck (to the poll), head (to
#   the snout), tail_1..N; per side (l, r) thigh, shin, foot (hip, knee, hock, toe) and upper_arm,
#   forearm, paw (shoulder, elbow, wrist, toe); ear_l, ear_r and jaw on the head where asked for.
#
# Clips (--clips bear): Idle, Walk, Run, Swipe, Slam, Charge_Tell, Roar, Winded, Sleep, Hit, Death; each
# described at its function. The tells' timings are the sim's (levels/monsters.json great_bear's
# moves, 10 ticks a second): Swipe's blow lands at 0.6 s (windup 6), Slam's at 1.2 s (windup 12),
# Charge_Tell is the 0.8 s roar before the rush (roar 8), Winded loops (597's ~15 ticks).
# Clips (--clips hill_cat, with --tail 5 --hock 0.2 --find-tail 1 --ears 1 --jaw 1): Idle, Walk, Run,
# Lie, Crouch_Tell, Pounce, Recover, Swipe, Bite, Snarl, Hit, Death, on enemy-ai's provisional moves
# (no monsters.json row yet; retimed when it lands): the pounce's crouch 8 (Crouch_Tell 0.8 s, then
# Pounce's contact on landing at 0.4 s), swipe windup 5 (0.5 s), bite windup 4 (0.4 s).
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True  # No __pycache__ left in tools/.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from creature_rig import args, bounds, foot_centres, points, stand, tris  # noqa: E402

FPS = 30
## How much of the height counts as touching the ground, for a foot's toe and heel.
GROUND_BAND = 0.05


def middle(pts: list) -> Vector:
	return sum(pts, Vector()) / len(pts)


## The body: the one mesh object of a .blend, or a .glb's meshes joined.
def load_body(path: str):
	if path.lower().endswith(".blend"):
		bpy.ops.wm.open_mainfile(filepath=path)
		meshes = [o for o in bpy.data.objects if o.type == "MESH"]
		for o in list(bpy.data.objects):
			if o not in meshes:
				bpy.data.objects.remove(o)
		if len(meshes) != 1:
			raise SystemExit("the .blend should hold one mesh, not %d" % len(meshes))
		body = meshes[0]
		bpy.ops.object.select_all(action="DESELECT")
		body.select_set(True)
		bpy.context.view_layer.objects.active = body
		body.parent = None
		bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
		body.vertex_groups.clear()
		body.modifiers.clear()
		body.name = "Body"
		return body
	from creature_rig import load_mesh
	bpy.ops.wm.read_factory_settings(use_empty=True)
	return load_mesh(path)


## The landmarks (world space, the body stood and centred).
def marks(body, head_share: float, hock_share: float) -> dict:
	pts = points(body)
	lo, hi = bounds(pts)
	h = hi.z - lo.z
	length = hi.y - lo.y
	feet = sorted(foot_centres(pts), key=lambda c: c.y)
	front, hind = feet[:2], feet[2:]
	m = {"lo": lo, "hi": hi, "h": h, "length": length}
	ground = [p for p in pts if p.z < lo.z + GROUND_BAND * h]
	for key, pair in (("f", front), ("h", hind)):
		for c in pair:
			s = "l" if c.x > 0.0 else "r"
			near = [p for p in ground if (p.x > 0.0) == (s == "l") and abs(p.y - c.y) < 0.2 * length]
			near.sort(key=lambda p: p.y)
			k = max(1, len(near) // 10)
			m["toe_%s%s" % (key, s)] = middle(near[:k])
			m["heel_%s%s" % (key, s)] = middle(near[-k:])
			m["foot_%s%s" % (key, s)] = c
	tree = BVHTree.FromPolygons(pts, [list(p.vertices) for p in body.data.polygons])

	def ray(y: float, up: bool, x: float = 0.0):
		start = Vector((x, y, lo.z - 1.0 if up else hi.z + 1.0))
		hit = tree.ray_cast(start, Vector((0, 0, 1 if up else -1)))[0]
		return hit.z if hit is not None else None

	m["ray"] = ray
	nose = sorted(pts, key=lambda p: p.y)[:6]
	m["snout"] = Vector((0.0, middle(nose).y, middle(nose).z))
	rump = sorted(pts, key=lambda p: -p.y)[:max(3, len(pts) // 100)]
	m["rump"] = Vector((0.0, hi.y, middle(rump).z))
	m["head_len"] = head_share * length
	m["hock_z"] = hock_share * h
	for key in sorted(k for k in m if isinstance(m[k], Vector)):
		print("  %-9s (%.3f %.3f %.3f)" % (key, *m[key]))
	return m


## The body's depth (back less belly) down the middle at y, or None past its end.
def depth(m: dict, y: float):
	top, low = m["ray"](y, False), m["ray"](y, True)
	return top - low if top is not None and low is not None and low < top else None


## Where a long tail leaves the body: going back from the hips, the first y whose depth is under
## TAIL_SECTION of the depth at the hips (between the two samples that cross it); None if none does.
TAIL_SECTION = 0.6


def tail_root(m: dict, hip_y: float):
	at_hips = depth(m, hip_y)
	if at_hips is None:
		return None
	step = 0.01 * m["length"]
	y, last = hip_y, at_hips
	while y < m["hi"].y - step:
		y += step
		d = depth(m, y)
		if d is None:
			return None
		if d < TAIL_SECTION * at_hips:
			u = (last - TAIL_SECTION * at_hips) / max(last - d, 1e-6)
			found = y - step + u * step
			print("  tail root y %.3f (depth %.3f at the hips)" % (found, at_hips))
			return found
		last = d
	return None


## The mesh's connected pieces, vertices at one position joined (a faceted mesh may split faces):
## [vertex indices] each, the largest first.
def pieces(body) -> list:
	verts = body.data.vertices
	up = list(range(len(verts)))

	def find(i: int) -> int:
		while up[i] != i:
			up[i] = up[up[i]]
			i = up[i]
		return i

	seen = {}
	for v in verts:
		key = tuple(round(c, 5) for c in v.co)
		if key in seen:
			up[find(v.index)] = find(seen[key])
		else:
			seen[key] = v.index
	for e in body.data.edges:
		a, b = find(e.vertices[0]), find(e.vertices[1])
		if a != b:
			up[a] = b
	groups = {}
	for v in verts:
		groups.setdefault(find(v.index), []).append(v.index)
	return sorted(groups.values(), key=len, reverse=True)


## The ears: per side, the points over the head standing above the skull's top there (a ray down
## the middle) near the highest of them (within 0.75 of its height over the skull, across), so an
## eye or brow that rises a little isn't one, joined by the loose pieces holding any of them (the
## ear, a tuft), which go wholly to its bone; (base, tip) from the middle of the lowest fifth of
## their height to the highest tenth's.
def find_ears(body, m: dict) -> None:
	pts = [body.matrix_world @ v.co for v in body.data.vertices]
	h, ray = m["h"], m["ray"]
	front = m["snout"].y
	back = front + 1.6 * m["head_len"]
	ears, members = {}, {}
	for s in ("l", "r"):
		above = []
		for i, p in enumerate(pts):
			if (p.x > 0.0) != (s == "l") or not (front < p.y < back):
				continue
			skull = ray(p.y, False)
			if skull is not None and p.z > skull + 0.01 * h:
				above.append(i)
		if len(above) < 3:
			continue
		top = max((pts[i] for i in above), key=lambda p: p.z)
		reach = max(0.75 * (top.z - (ray(top.y, False) or top.z)), 0.03 * h)
		above = [i for i in above if math.hypot(pts[i].x - top.x, pts[i].y - top.y) < reach]
		loose = [p for p in m["pieces"][1:] if set(above) & set(p)]
		above = sorted(set(above).union(*loose), key=lambda i: pts[i].z)
		z0, z1 = pts[above[0]].z, pts[above[-1]].z
		low = [pts[i] for i in above if pts[i].z <= z0 + 0.2 * (z1 - z0)]
		high = [pts[i] for i in above if pts[i].z >= z1 - 0.1 * (z1 - z0)]
		ears[s] = (middle(low), middle(high))
		members[s] = loose
		print("  ear_%s     (%.3f %.3f %.3f) -> (%.3f %.3f %.3f), %d points" % (s, *ears[s][0], *ears[s][1], len(above)))
	m["ears"] = ears
	m["ear_pieces"] = members


## The jaw: the largest loose piece under the snout and ahead of the poll, near the middle; hinge
## behind and above its back end, to its front. Its piece goes wholly to the jaw.
def find_jaw(body, m: dict) -> None:
	pts = [body.matrix_world @ v.co for v in body.data.vertices]
	poll_y = m["snout"].y + m["head_len"]
	best = None
	for p in m["pieces"][1:]:
		c = middle([pts[i] for i in p])
		if c.y < poll_y and c.z < m["snout"].z and abs(c.x) < 0.05 * m["h"] and (best is None or len(p) > len(best)):
			best = p
	if best is None:
		m["jaw"] = None
		print("  no jaw piece")
		return
	ps = [pts[i] for i in best]
	ys, zs = [p.y for p in ps], [p.z for p in ps]
	span = max(ys) - min(ys)
	hinge = Vector((0.0, max(ys) + 0.4 * span, max(zs) + 0.2 * span))
	chin = Vector((0.0, min(ys), sum(zs) / len(zs)))
	m["jaw"] = (hinge, chin)
	m["jaw_piece"] = best
	print("  jaw       (%.3f %.3f %.3f) -> (%.3f %.3f %.3f), %d points" % (*hinge, *chin, len(best)))


## The skeleton's joints from the landmarks: {bone: (head, tail, parent)}, parents first.
def joints(m: dict, tail_bones: int) -> dict:
	h, ray = m["h"], m["ray"]
	fy = sum(m["foot_f" + s].y for s in "lr") / 2
	hy = sum(m["foot_h" + s].y for s in "lr") / 2
	mid_y = (fy + hy) / 2

	def centre(y: float, share: float = 0.5) -> float:  # Between belly and back, at share up.
		top = ray(y, False) or 0.75 * h
		low = ray(y, True)
		low = low if low is not None and low < top else 0.4 * h
		return low + share * (top - low)

	hip = Vector((0.0, hy, centre(hy, 0.55)))
	mid = Vector((0.0, mid_y, centre(mid_y)))
	chest_y = fy + 0.35 * (mid_y - fy)
	chest = Vector((0.0, chest_y, centre(chest_y)))
	withers = Vector((0.0, fy, centre(fy, 0.6)))
	poll_y = m["snout"].y + m["head_len"]
	poll = Vector((0.0, poll_y, centre(poll_y)))
	out = {
		"root": (Vector((0.0, mid_y, 0.0)), Vector((0.0, mid_y + 0.15 * h, 0.0)), None),
		"hips": (hip, mid, "root"),
		"spine": (mid, chest, "hips"),
		"chest": (chest, withers, "spine"),
		"neck": (withers, poll, "chest"),
		"head": (poll, m["snout"], "neck"),
	}
	# The tail: from the rump's top back to its rear-most point, in equal bones. A long tail
	# (find_tail) starts where the body's depth behind the hips first falls under TAIL_SECTION of
	# its depth at them, and its bones follow the middle of its depth.
	rump = m["rump"]
	root_y = rump.y - max(0.08 * h, 0.04 * m["length"] * tail_bones)
	found = tail_root(m, hy) if m.get("find_tail") else None
	if found is not None:
		root_y = found
	start = Vector((0.0, root_y, centre(root_y, 0.5 if found is not None else 0.65)))
	parent = "hips"
	for i in range(tail_bones):
		a = start.lerp(rump, i / tail_bones)
		b = start.lerp(rump, (i + 1) / tail_bones)
		if found is not None:
			a.z = centre(a.y) if i > 0 else start.z
			b.z = centre(b.y) if i + 1 < tail_bones else rump.z
		out["tail_%d" % (i + 1)] = (a, b, parent)
		parent = "tail_%d" % (i + 1)
	# The ears (find_ears): per side, from the lowest of the points standing above the skull to the
	# highest (a tuft on its tip included), on the head.
	for s, ear in m.get("ears", {}).items():
		out["ear_" + s] = (ear[0], ear[1], "head")
	# The jaw (a separate piece under the lip): from its hinge, behind and above its back end,
	# to the chin.
	if m.get("jaw") is not None:
		out["jaw"] = (m["jaw"][0], m["jaw"][1], "head")
	for s in ("l", "r"):
		toe, heel, foot = m["toe_h" + s], m["heel_h" + s], m["foot_h" + s]
		x = foot.x
		hip_s = Vector((0.75 * x, hip.y, hip.z))
		hock = Vector((x, heel.y, max(m["hock_z"], 0.03 * h)))
		knee = Vector((x, hock.y - 0.12 * h, (hip.z + hock.z) / 2))
		out["thigh_" + s] = (hip_s, knee, "hips")
		out["shin_" + s] = (knee, hock, "thigh_" + s)
		out["foot_" + s] = (hock, Vector((x, toe.y, 0.02 * h)), "shin_" + s)
		toe, heel, foot = m["toe_f" + s], m["heel_f" + s], m["foot_f" + s]
		x = foot.x
		shoulder = Vector((0.85 * x, heel.y - 0.02 * h, 0.82 * withers.z))
		wrist = Vector((x, heel.y - 0.02 * h, 0.06 * h))
		elbow = Vector((x, heel.y + 0.04 * h, (shoulder.z + wrist.z) / 2))
		out["upper_arm_" + s] = (shoulder, elbow, "chest")
		out["forearm_" + s] = (elbow, wrist, "upper_arm_" + s)
		out["paw_" + s] = (wrist, Vector((x, toe.y, 0.02 * h)), "forearm_" + s)
	return out


def build_armature(spec: dict, name: str):
	data = bpy.data.armatures.new(name)
	arm = bpy.data.objects.new(name, data)
	bpy.context.scene.collection.objects.link(arm)
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for bone_name, (head, tail, parent) in spec.items():
		bone = data.edit_bones.new(bone_name)
		bone.head, bone.tail = head, tail
		if parent:
			bone.parent = data.edit_bones[parent]
		# Local X along the world's +X, so every bone tips the same way about it.
		bone.align_roll(Vector((0.0, 0.0, 1.0)) if abs(bone.vector.normalized().z) < 0.9 else Vector((0.0, -1.0, 0.0)))
		if bone.x_axis.x < 0.0:
			bone.roll += math.pi
		print("  %-12s (%.3f %.3f %.3f) -> (%.3f %.3f %.3f)" % (bone_name, *head, *tail))
	bpy.ops.object.mode_set(mode="OBJECT")
	return arm


## Bone heat, then any vertex it left without a bone (a loose piece: a claw, an eye) takes its
## nearest weighted neighbour's weights; at most four, summing to one.
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


## A loose piece wholly on one bone (the jaw, an ear and its tuft): every other weight taken off.
def own(body, bone: str, members: list) -> None:
	groups = body.vertex_groups
	for g in groups:
		if g.name != bone:
			g.remove(members)
	groups[bone].add(members, 1.0, "REPLACE")
	print("skin: %d vertices wholly on %s" % (len(members), bone))


# --- Posing: side-view helpers, (y, z) points ------------------------------------------------

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


def hold(t: float, rise: tuple, fall: tuple) -> float:
	"""Up over rise (start, end), held, down over fall."""
	return ease(t, *rise) * (1.0 - ease(t, *fall))


def angle(a: tuple, b: tuple) -> float:
	return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def turn(p: tuple, about: tuple, degrees: float) -> tuple:
	c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
	y, z = p[0] - about[0], p[1] - about[1]
	return (about[0] + y * c - z * s, about[1] + y * s + z * c)


def toward(p: tuple, degrees: float, length: float) -> tuple:
	return (p[0] + length * math.cos(math.radians(degrees)), p[1] + length * math.sin(math.radians(degrees)))


## Two bones from [param root] reaching for [param goal]: their angles and the joint between,
## the joint ahead (toward -Y: forward=True) or behind. Out of reach, they point at it.
def reach(root: tuple, goal: tuple, a: float, b: float, forward: bool) -> tuple:
	d = math.dist(root, goal)
	d = min(max(d, abs(a - b) + 1e-5), a + b - 1e-5)
	base = angle(root, goal)
	bend = math.degrees(math.acos(max(-1.0, min(1.0, (a * a + d * d - b * b) / (2.0 * a * d)))))
	first = min((base + bend, base - bend), key=lambda deg: toward(root, deg, a)[0] * (1 if forward else -1))
	joint = toward(root, first, a)
	return first, angle(joint, goal), joint


def wrap(degrees: float) -> float:
	return (degrees + 180.0) % 360.0 - 180.0


class Legs:
	"""The legs' rest in the side view, and the rotations that put each foot where a pose says,
	the body posed above them. A pose: {bone: (rx, ry, rz)} for what it turns itself, "back" and
	"lift" (the root moved, metres), and per foot ("fl", "fr", "hl", "hr") a (dy, dz, pitch): the
	foot's ground segment (wrist or hock to toe) moved by dy, dz from its rest and turned pitch
	degrees about its back end (positive: toe down). A leg whose top bone the pose turns itself
	isn't solved."""

	def __init__(self, arm):
		self.rest = {}
		for bone in arm.data.bones:
			head = arm.matrix_world @ bone.head_local
			tail = arm.matrix_world @ bone.tail_local
			self.rest[bone.name] = ((head.y, head.z), (tail.y, tail.z))

	def place_hind(self, p: tuple, pose: dict) -> tuple:
		r = self.rest
		q = turn(p, r["hips"][0], rx(pose, "hips"))
		return (q[0] + pose.get("back", 0.0), q[1] + pose.get("lift", 0.0))

	def place_front(self, p: tuple, pose: dict) -> tuple:
		r = self.rest
		q = turn(p, r["chest"][0], rx(pose, "chest"))
		q = turn(q, r["spine"][0], rx(pose, "spine"))
		return self.place_hind(q, pose)

	def solve(self, pose: dict) -> dict:
		out = dict(pose)
		r = self.rest
		hips = rx(pose, "hips")
		front_body = hips + rx(pose, "spine") + rx(pose, "chest")
		for s in ("l", "r"):
			for top, mid, low, key, body, place, forward in (
					("thigh", "shin", "foot", "h", hips, self.place_hind, True),
					("upper_arm", "forearm", "paw", "f", front_body, self.place_front, False)):
				if "%s_%s" % (top, s) in pose:
					continue
				j0, k0 = r["%s_%s" % (top, s)]
				h0, t0 = r["%s_%s" % (low, s)]
				a, b = math.dist(j0, k0), math.dist(k0, h0)
				dy, dz, pitch = pose.get(key + s, (0.0, 0.0, 0.0))
				goal = (h0[0] + dy, h0[1] + dz)
				toe = turn((t0[0] + dy, t0[1] + dz), goal, -pitch)
				j = place(j0, pose)
				up, down, joint = reach(j, goal, a, b, forward)
				end = toward(joint, down, b)
				r_top = up - angle(j0, k0) - body
				r_mid = down - angle(k0, h0) - body - r_top
				r_low = angle(end, toe) - angle(h0, t0) - body - r_top - r_mid
				extra = pose.get("%s_%s+" % (top, s), (0.0, 0.0, 0.0))
				out["%s_%s" % (top, s)] = (wrap(r_top) + extra[0], extra[1], extra[2])
				out["%s_%s" % (mid, s)] = (wrap(r_mid), 0.0, 0.0)
				out["%s_%s" % (low, s)] = (wrap(r_low), 0.0, 0.0)
		return out


def rx(pose: dict, bone: str) -> float:
	return pose.get(bone, (0.0, 0.0, 0.0))[0]


def add(pose: dict, bone: str, x: float = 0.0, y: float = 0.0, z: float = 0.0) -> dict:
	old = pose.get(bone, (0.0, 0.0, 0.0))
	pose[bone] = (old[0] + x, old[1] + y, old[2] + z)
	return pose


def level_head(pose: dict, share: float = 0.8) -> dict:
	"""The neck and head turned against the body's pitch, so the head stays near level."""
	body = rx(pose, "hips") + rx(pose, "spine") + rx(pose, "chest")
	add(pose, "neck", -0.5 * share * body)
	add(pose, "head", -0.5 * share * body)
	return pose


def tail(pose: dict, bones: int, lift: float, sway: float = 0.0, curl: float = 0.0) -> dict:
	"""The tail: lift (degrees up at its root), sway (to the side, each bone alike), curl (down
	more toward the tip)."""
	for i in range(bones):
		share = (i + 1) / bones
		add(pose, "tail_%d" % (i + 1), -lift if i == 0 else curl * share, 0.0, sway)
	return pose


# --- Gaits ------------------------------------------------------------------------------------

def step(phase: float, stance: float, stride: float, height: float) -> tuple:
	"""A foot's (dy, dz, pitch) at [param phase] (0..1) of its own cycle: on the ground for the
	first [param stance] of it, moving back from stride/2 ahead to stride/2 behind; then lifted
	and brought forward."""
	phase %= 1.0
	if phase < stance:
		u = phase / stance
		return (-stride / 2 + stride * u, 0.0, 0.0)
	u = (phase - stance) / (1.0 - stance)
	smooth = u * u * (3.0 - 2.0 * u)
	return (stride / 2 - stride * smooth, height * math.sin(math.pi * u), 25.0 * math.sin(math.pi * u) - 10.0 * bump(u, 0.6, 1.0))


def gait(t: float, h: float, stride: float, lift: float, stance: float, offsets: dict) -> dict:
	pose = {}
	for foot, off in offsets.items():
		pose[foot] = step(t + off, stance, stride, lift)
	return pose


# --- The bear's clips -------------------------------------------------------------------------

## The swipe's sweep (degrees about the raised arm's upright axis): out in the wind-up, in through the blow.
SWEEP_OUT = 35.0
SWEEP_IN = 80.0


class Bear:
	"""The great bear's clips. h the height, tail_bones the tail's."""

	def __init__(self, m: dict, tail_bones: int):
		self.h = m["h"]
		self.tail_bones = tail_bones

	def idle(self, t: float) -> dict:
		"""Standing, breathing; the head swings low and sniffs once."""
		breath = math.sin(2.0 * math.pi * t)
		look = math.sin(2.0 * math.pi * t)
		pose = {"lift": 0.006 * self.h * breath}
		add(pose, "spine", 1.0 * breath)
		add(pose, "chest", -0.8 * breath)
		add(pose, "neck", 4.0 + 3.0 * bump(t, 0.4, 0.8))
		add(pose, "head", -2.0 + 6.0 * bump(t, 0.5, 0.65) * math.sin(2.0 * math.pi * 6.0 * t) ** 2, 0.0, 6.0 * look)
		return tail(pose, self.tail_bones, 0.0, 4.0 * breath)

	def walk(self, t: float) -> dict:
		"""The bear's four-beat walk: hind left, fore left, hind right, fore right; the shoulders
		roll and the head nods with each front step."""
		stride = 0.42 * self.h
		pose = gait(t, self.h, stride, 0.1 * self.h, 0.66, {"hl": 0.0, "fl": 0.25, "hr": 0.5, "fr": 0.75})
		nod = math.cos(4.0 * math.pi * t)
		pose["lift"] = 0.008 * self.h * nod
		add(pose, "spine", 0.0, 0.0, 3.0 * math.sin(2.0 * math.pi * t))
		add(pose, "chest", 1.5 * nod, 4.0 * math.sin(2.0 * math.pi * (t - 0.25)))
		add(pose, "hips", 0.0, -3.0 * math.sin(2.0 * math.pi * t))
		add(pose, "neck", 6.0 - 2.0 * nod)
		add(pose, "head", 3.0 * nod, 0.0, -4.0 * math.sin(2.0 * math.pi * t))
		return tail(pose, self.tail_bones, 0.0, 5.0 * math.sin(2.0 * math.pi * t))

	def run(self, t: float) -> dict:
		"""The bound of a running bear: the hind feet land together ahead, the fore feet reach out
		together, the back folding and stretching between, the head low."""
		stride = 0.6 * self.h
		pose = gait(t, self.h, stride, 0.14 * self.h, 0.4, {"hl": 0.0, "hr": 0.08, "fl": 0.45, "fr": 0.53})
		flex = math.sin(2.0 * math.pi * (t - 0.15))
		pose["lift"] = 0.04 * self.h * bump((t + 0.1) % 1.0, 0.25, 0.75) - 0.02 * self.h
		add(pose, "hips", 7.0 * flex)
		add(pose, "spine", -5.0 * flex)
		add(pose, "chest", -4.0 * flex)
		add(pose, "neck", 10.0 + 4.0 * flex)
		add(pose, "head", -6.0 - 4.0 * flex)
		return tail(pose, self.tail_bones, 10.0 * flex)

	def swipe(self, t: float, seconds: float) -> dict:
		"""The swipe (windup 6 ticks): the bear rocks back onto its haunches and lifts its right
		fore paw high and out to the side, shoulders turned away (0..0.6 s), then rakes it across
		its front, the shoulders turning into it (the blow at 0.6 s), carried through and down."""
		s = t * seconds
		wind = ease(s, 0.0, 0.5)
		cut = ease(s, 0.52, 0.7)
		back = 1.0 - ease(s, 0.75, seconds)
		up = wind * back
		pose = {"back": 0.06 * self.h * up, "lift": 0.03 * self.h * up}
		add(pose, "hips", -6.0 * up)
		add(pose, "spine", -4.0 * up)
		# The shoulders turn away (yaw about the spine's own Z, the bone along the body) and back into it.
		turn_to = (12.0 * wind - 28.0 * cut) * back
		add(pose, "chest", -6.0 * up, 0.0, turn_to)
		add(pose, "neck", -6.0 * up, 0.0, 0.5 * turn_to)
		add(pose, "head", 4.0 * up, 0.0, 0.5 * turn_to)
		# The paw: up and forward with the elbow out (the arm swung out about its own Z), then
		# across: the swing out undone and carried in past the middle.
		# The sweep is a turn about the arm's rest Y (straight down at rest, so upright: a yaw of the
		# raised arm); its rest Z would only roll an arm pointing ahead.
		raised = wind * (1.0 - 0.6 * cut) * back
		pose["upper_arm_r"] = (-115.0 * raised, (SWEEP_OUT * wind - SWEEP_IN * cut) * back, -12.0 * raised)
		pose["forearm_r"] = (70.0 * raised, 0.0, 0.0)
		pose["paw_r"] = (45.0 * raised, 0.0, 0.0)
		pose["fl"] = (-0.04 * self.h * up, 0.0, 0.0)
		return tail(pose, self.tail_bones, 6.0 * up)

	def slam(self, t: float, seconds: float) -> dict:
		"""The slam (windup 12 ticks): the bear rears up on its hind legs, fore paws raised
		(0..0.9 s), holds over its height, then drops its weight down onto both fore paws (the blow
		at 1.2 s), the head low, and settles."""
		s = t * seconds
		rise = ease(s, 0.05, 0.85)
		drop = ease(s, 0.95, 1.2)
		settle = ease(s, 1.25, seconds)
		up = rise * (1.0 - drop)
		pose = {"back": 0.12 * self.h * up, "lift": 0.04 * self.h * up}
		add(pose, "hips", -52.0 * up + 6.0 * drop * (1.0 - settle))
		add(pose, "spine", -10.0 * up + 3.0 * drop * (1.0 - settle))
		add(pose, "chest", -6.0 * up)
		add(pose, "neck", 34.0 * up - 6.0 * drop * (1.0 - settle))
		add(pose, "head", 20.0 * up + 10.0 * drop * (1.0 - settle))
		if up > 0.001:
			# Reared: the fore legs held up and bent, paws hanging, arms out a little.
			for s_ in ("l", "r"):
				sign = 1.0 if s_ == "l" else -1.0
				pose["upper_arm_" + s_] = (-35.0 * up, 0.0, sign * 14.0 * up)
				pose["forearm_" + s_] = (60.0 * up, 0.0, 0.0)
				pose["paw_" + s_] = (35.0 * up, 0.0, 0.0)
		# The landing: fore paws a little ahead of where they stood, the chest low.
		land = drop * (1.0 - settle)
		pose["fl"] = (-0.12 * self.h * land, 0.0, 0.0)
		pose["fr"] = (-0.12 * self.h * land, 0.0, 0.0)
		pose["lift"] -= 0.04 * self.h * land * (1.0 - up)
		return tail(pose, self.tail_bones, 8.0 * up)

	def charge(self, t: float, seconds: float) -> dict:
		"""The charge's tell (roar 8 ticks): head down and thrust out, the fore paws spread and
		planted, the haunches gathered under, a scrape of the right fore paw; ready to rush."""
		s = t * seconds
		low = ease(s, 0.0, 0.3)
		scrape = bump(s, 0.3, 0.6)
		pose = {"lift": -0.05 * self.h * low, "back": 0.05 * self.h * low}
		add(pose, "hips", 6.0 * low)
		add(pose, "spine", 3.0 * low)
		add(pose, "chest", 4.0 * low)
		add(pose, "neck", 14.0 * low + 2.0 * math.sin(2.0 * math.pi * 3.0 * t) * low)
		add(pose, "head", -18.0 * low)
		pose["hl"] = (-0.08 * self.h * low, 0.0, 0.0)
		pose["hr"] = (-0.08 * self.h * low, 0.0, 0.0)
		pose["fr"] = (0.1 * self.h * scrape - 0.05 * self.h * low, 0.06 * self.h * scrape, 20.0 * scrape)
		pose["fl"] = (-0.05 * self.h * low, 0.0, 0.0)
		return tail(pose, self.tail_bones, -4.0 * low)

	def roar(self, t: float, seconds: float) -> dict:
		"""The roar: the bear rises a little on its fore legs, head thrown up and out, swinging side
		to side as it roars (0.3..1.3 s), and settles."""
		s = t * seconds
		up = hold(s, (0.0, 0.3), (1.3, seconds))
		shake = math.sin(2.0 * math.pi * 2.5 * s) * bump(s, 0.3, 1.4)
		pose = {"lift": 0.02 * self.h * up}
		add(pose, "hips", -4.0 * up)
		add(pose, "spine", -3.0 * up)
		add(pose, "chest", -5.0 * up)
		add(pose, "neck", -22.0 * up, 0.0, 6.0 * shake)
		add(pose, "head", -14.0 * up, 4.0 * shake, 8.0 * shake)
		pose["fl"] = (-0.03 * self.h * up, 0.0, 0.0)
		pose["fr"] = (-0.03 * self.h * up, 0.0, 0.0)
		return tail(pose, self.tail_bones, 6.0 * up)

	def winded(self, t: float) -> dict:
		"""Winded after a missed charge: head hung low, sides heaving fast, the fore legs splayed."""
		pant = math.sin(2.0 * math.pi * 3.0 * t)
		pose = {"lift": -0.04 * self.h + 0.006 * self.h * pant}
		add(pose, "hips", 3.0)
		add(pose, "spine", 4.0 + 1.5 * pant)
		add(pose, "chest", 3.0 - 1.5 * pant)
		add(pose, "neck", 26.0 + 2.0 * pant)
		add(pose, "head", 8.0 - 2.0 * pant, 0.0, 4.0 * math.sin(2.0 * math.pi * t))
		pose["upper_arm_l+"] = (0.0, 0.0, 6.0)
		pose["upper_arm_r+"] = (0.0, 0.0, -6.0)
		return tail(pose, self.tail_bones, -4.0)

	def sleep(self, t: float) -> dict:
		"""Asleep: lying on its belly, legs folded under, head down on its fore paws, breathing
		slowly."""
		breath = math.sin(2.0 * math.pi * t)
		h = self.h
		pose = {"lift": -0.24 * h + 0.008 * h * breath}
		add(pose, "hips", 4.0)
		add(pose, "spine", -1.0 + 1.2 * breath)
		add(pose, "chest", -2.0 - 0.6 * breath)
		add(pose, "neck", 22.0, 0.0, 10.0)
		add(pose, "head", 6.0 + 1.0 * breath, 0.0, 6.0)
		for s_ in ("l", "r"):
			pose["thigh_" + s_] = (-60.0, 0.0, 0.0)
			pose["shin_" + s_] = (110.0, 0.0, 0.0)
			pose["foot_" + s_] = (-50.0, 0.0, 0.0)
			pose["upper_arm_" + s_] = (-55.0, 0.0, 0.0)
			pose["forearm_" + s_] = (-30.0, 0.0, 0.0)
			pose["paw_" + s_] = (85.0, 0.0, 0.0)
		return tail(pose, self.tail_bones, -10.0)

	def hit(self, t: float) -> dict:
		"""Struck: a jolt back, the head jerked up and away."""
		jolt = bump(t, 0.0, 0.7)
		pose = {"back": 0.05 * self.h * jolt}
		add(pose, "hips", -3.0 * jolt)
		add(pose, "spine", -3.0 * jolt)
		add(pose, "chest", -4.0 * jolt, 0.0, 6.0 * jolt)
		add(pose, "neck", -10.0 * jolt, 0.0, 6.0 * jolt)
		add(pose, "head", -8.0 * jolt, 6.0 * jolt, 0.0)
		return tail(pose, self.tail_bones, 0.0)

	def death(self, t: float) -> dict:
		"""Death: the legs give, the bear sinks and rolls onto its left side, the head last."""
		h = self.h
		sink = ease(t, 0.0, 0.45)
		fall = ease(t, 0.3, 0.75)
		limp = ease(t, 0.55, 1.0)
		# The root rolls about the ground under it: as it goes over, it comes up by about the body's
		# half-width, so the side it lies on rests on the ground, not half through it.
		pose = {"lift": -0.1 * h * sink * (1.0 - fall) + 0.24 * h * fall, "roll": 82.0 * fall}
		add(pose, "spine", 4.0 * sink)
		add(pose, "neck", 18.0 * sink - 10.0 * limp)
		add(pose, "head", 10.0 * limp, 0.0, 10.0 * limp)
		for s_ in ("l", "r"):
			pose["thigh_" + s_] = (-30.0 * sink + 20.0 * limp, 0.0, 0.0)
			pose["shin_" + s_] = (50.0 * sink - 30.0 * limp, 0.0, 0.0)
			pose["foot_" + s_] = (-20.0 * sink + 10.0 * limp, 0.0, 0.0)
			pose["upper_arm_" + s_] = (-30.0 * sink + 20.0 * limp, 0.0, 0.0)
			pose["forearm_" + s_] = (-20.0 * sink, 0.0, 0.0)
			pose["paw_" + s_] = (40.0 * sink - 20.0 * limp, 0.0, 0.0)
		return tail(pose, self.tail_bones, -6.0 * limp)

	def clips(self) -> list:
		"""[name, seconds, loop, pose_at(t in 0..1)] each."""
		return [
			["Idle", 4.0, True, self.idle],
			["Walk", 1.4, True, self.walk],
			["Run", 0.7, True, self.run],
			["Swipe", 1.1, False, lambda t: self.swipe(t, 1.1)],
			["Slam", 1.7, False, lambda t: self.slam(t, 1.7)],
			["Charge_Tell", 0.8, False, lambda t: self.charge(t, 0.8)],
			["Roar", 1.7, False, lambda t: self.roar(t, 1.7)],
			["Winded", 1.0, True, self.winded],
			["Sleep", 4.0, True, self.sleep],
			["Hit", 0.45, False, self.hit],
			["Death", 1.6, False, self.death],
		]


# --- The hill cat's clips ---------------------------------------------------------------------

def cat_tail(pose: dict, bones: int, up: float = 0.0, bend: float = 0.0, side: float = 0.0,
		wave: float = 0.0, phase: float = 0.0) -> dict:
	"""A long tail: up (degrees its root rises; a bone pointing back rises for a positive turn
	about X), bend (curling up toward the tip, more each bone; negative hangs it), side (swept to
	one side, curling more toward the tip) and a wave (degrees, a ripple running down it at phase
	0..1)."""
	for i in range(bones):
		share = (i + 1) / bones
		ripple = wave * share * math.sin(2.0 * math.pi * (phase - 0.5 * share))
		add(pose, "tail_%d" % (i + 1), (up if i == 0 else 0.0) + bend * share, 0.0, side * share + ripple)
	return pose


def ears(pose: dict, back: float = 0.0, out: float = 0.0, flick_l: float = 0.0, flick_r: float = 0.0) -> dict:
	"""The ears: back (degrees laid back; an upright bone tips forward for a positive turn about
	X), out (turned out to the sides), and a flick of either."""
	add(pose, "ear_l", -back - 25.0 * flick_l, 0.0, -out - 20.0 * flick_l)
	add(pose, "ear_r", -back - 25.0 * flick_r, 0.0, out + 20.0 * flick_r)
	return pose


class HillCat:
	"""The hill cat's clips (enemy-ai's provisional moves, 780): Idle, Walk, Run, Lie (lying up on
	a rock, its idle in its spot), Crouch_Tell (the pounce's crouch, 8 ticks, rising from Lie or a
	stand), Pounce (the leap, contact on landing at 0.4 s), Recover (after a pounce, about 10
	ticks), Swipe (windup 5: the blow at 0.5 s), Bite (windup 4: the jaws shut at 0.4 s), Snarl
	(the threat cry), Hit, Death. Low and long; the head kept level; the long tail always moving.
	m the landmarks, tail_bones the tail's."""

	def __init__(self, m: dict, tail_bones: int):
		self.h = m["h"]
		self.n = tail_bones
		mid_y = sum(m["foot_" + k].y for k in ("fl", "fr", "hl", "hr")) / 4.0
		self.belly = m["ray"](mid_y, True) or 0.4 * self.h

	def tail(self, pose: dict, **kw) -> dict:
		return cat_tail(pose, self.n, **kw)

	def idle(self, t: float) -> dict:
		"""Standing, breathing, looking about; the tail low with its tip curling up and flicking,
		an ear turning now and then."""
		breath = math.sin(2.0 * math.pi * 2.0 * t)
		look = math.sin(2.0 * math.pi * t)
		pose = {"lift": 0.004 * self.h * breath}
		add(pose, "spine", 1.0 * breath)
		add(pose, "neck", 2.0, 0.0, 10.0 * look)
		add(pose, "head", -2.0, 0.0, 8.0 * look)
		ears(pose, flick_l=bump(t, 0.3, 0.38), flick_r=bump(t, 0.72, 0.8))
		return self.tail(pose, up=-6.0, bend=6.0 + 10.0 * bump(t, 0.5, 0.9), side=6.0 * look, wave=8.0, phase=t)

	def walk(self, t: float) -> dict:
		"""The cat's walk: hind left, fore left, hind right, fore right, soft and low, the head
		carried level and low, the shoulder blades rolling, the tail low and swaying."""
		pose = gait(t, self.h, 0.42 * self.h, 0.09 * self.h, 0.62, {"hl": 0.0, "fl": 0.25, "hr": 0.5, "fr": 0.75})
		nod = math.cos(4.0 * math.pi * t)
		pose["lift"] = -0.02 * self.h + 0.006 * self.h * nod
		add(pose, "spine", 0.0, 0.0, 3.0 * math.sin(2.0 * math.pi * t))
		add(pose, "chest", 1.0 * nod, 3.0 * math.sin(2.0 * math.pi * (t - 0.25)))
		add(pose, "hips", 0.0, -3.0 * math.sin(2.0 * math.pi * t))
		add(pose, "neck", 8.0)
		add(pose, "head", -6.0 + 2.0 * nod, 0.0, -3.0 * math.sin(2.0 * math.pi * t))
		return self.tail(pose, up=-8.0, bend=4.0, wave=10.0, phase=t)

	def run(self, t: float) -> dict:
		"""The bound: hind feet together, fore feet reaching out together, the long back folding
		and stretching between, the head level and the tail out behind for balance."""
		pose = gait(t, self.h, 0.75 * self.h, 0.12 * self.h, 0.36, {"hl": 0.0, "hr": 0.07, "fl": 0.5, "fr": 0.57})
		flex = math.sin(2.0 * math.pi * (t - 0.15))
		pose["lift"] = 0.05 * self.h * bump((t + 0.1) % 1.0, 0.25, 0.75) - 0.03 * self.h
		add(pose, "hips", 12.0 * flex)
		add(pose, "spine", -8.0 * flex)
		add(pose, "chest", -6.0 * flex)
		add(pose, "neck", 6.0 + 4.0 * flex)
		add(pose, "head", -4.0 - 4.0 * flex)
		ears(pose, back=15.0)
		return self.tail(pose, up=4.0 - 8.0 * flex, bend=-4.0, wave=6.0, phase=t)

	def lie(self, t: float) -> dict:
		"""Lying up: on its belly, hind legs folded under, fore legs out ahead along the rock, head
		up and watching; slow breath, the tail curled round its side, its tip flicking, the head
		turning to look."""
		breath = math.sin(2.0 * math.pi * t)
		look = ease(t, 0.35, 0.45) * (1.0 - ease(t, 0.7, 0.8))
		h = self.h
		pose = {"lift": -(self.belly - 0.08 * h) + 0.004 * h * breath}
		add(pose, "spine", 1.0 * breath)
		add(pose, "neck", -14.0, 0.0, 22.0 * look)
		add(pose, "head", 12.0, 0.0, 10.0 * look)
		for s_ in ("l", "r"):
			pose["f" + s_] = (-0.22 * h, 0.0, 0.0)
			# The hock down on the rock, the hind foot flat along it (a positive pitch levels it).
			pose["h" + s_] = (0.06 * h, -0.09 * h, 45.0)
		ears(pose, flick_l=bump(t, 0.15, 0.22), flick_r=bump(t, 0.55, 0.62))
		return self.tail(pose, up=-14.0, side=70.0, wave=6.0 * bump(t, 0.6, 1.0), phase=2.0 * t)

	def crouch(self, t: float, seconds: float) -> dict:
		"""The pounce's tell (crouch 8 ticks): it drops flat, belly near the ground, haunches
		gathered under it, head low and level, ears forward and fixed; the hind end treads and
		wiggles, the tail tip twitching; at the end it is coiled to spring."""
		s = t * seconds
		low = ease(s, 0.0, 0.3)
		wiggle = math.sin(2.0 * math.pi * 5.0 * s) * bump(s, 0.35, seconds + 0.05)
		h = self.h
		pose = {"lift": -0.55 * self.belly * low, "back": 0.03 * h * low}
		add(pose, "hips", -4.0 * low, 0.0, 5.0 * wiggle)
		add(pose, "spine", 3.0 * low)
		add(pose, "neck", 10.0 * low)
		add(pose, "head", -10.0 * low)
		pose["hl"] = (-0.06 * h * low, 0.01 * h * max(0.0, wiggle), 0.0)
		pose["hr"] = (-0.06 * h * low, 0.01 * h * max(0.0, -wiggle), 0.0)
		ears(pose, back=-10.0 * low)
		return self.tail(pose, up=-6.0 * low, bend=-4.0, wave=14.0 * low, phase=3.0 * s)

	def pounce(self, t: float, seconds: float) -> dict:
		"""The pounce: from the crouch it springs (0..0.1 s), flies stretched out, fore legs reaching
		ahead and claws out, hind legs trailing (0.1..0.4 s), lands on its fore paws on the target
		(contact at 0.4 s), and gathers itself."""
		s = t * seconds
		h = self.h
		spring = ease(s, 0.0, 0.1)
		land = ease(s, 0.34, 0.42)
		fly = spring * (1.0 - land)
		# The legs leave the ground once the body is up off its crouch, and are planted again on landing.
		air = ease(s, 0.08, 0.18) * (1.0 - land)
		after = 1.0 - ease(s, 0.45, seconds)
		coil = 1.0 - spring
		settle = ease(s, 0.42, 0.5) * after
		pose = {"lift": -0.55 * self.belly * coil + 0.22 * h * bump(s, 0.05, 0.42) - 0.05 * h * settle}
		add(pose, "hips", -4.0 * coil - 10.0 * fly + 6.0 * settle)
		add(pose, "spine", 3.0 * coil - 6.0 * fly + 4.0 * settle)
		add(pose, "neck", 10.0 * coil - 4.0 * fly + 6.0 * settle)
		add(pose, "head", -10.0 * coil + 2.0 * fly)
		if air > 0.001:
			for s_ in ("l", "r"):
				pose["upper_arm_" + s_] = (-75.0 * air, 0.0, 0.0)
				pose["forearm_" + s_] = (20.0 * air, 0.0, 0.0)
				pose["paw_" + s_] = (-20.0 * air, 0.0, 0.0)
				pose["thigh_" + s_] = (55.0 * air, 0.0, 0.0)
				pose["shin_" + s_] = (-10.0 * air, 0.0, 0.0)
				pose["foot_" + s_] = (30.0 * air, 0.0, 0.0)
		else:
			for s_ in ("l", "r"):
				pose["f" + s_] = (-0.12 * h * land * after, 0.0, 0.0)
				pose["h" + s_] = (-0.06 * h * coil, 0.0, 0.0)
		ears(pose, back=-10.0 * coil + 20.0 * fly + 10.0 * land * after)
		add(pose, "jaw", 18.0 * bump(s, 0.2, 0.6))
		return self.tail(pose, up=-6.0 * coil + 10.0 * fly, bend=-6.0 * fly, wave=8.0 * after, phase=2.0 * s)

	def recover(self, t: float) -> dict:
		"""After a pounce: crouched low, sides heaving, mouth a little open, head low (the opening
		for whoever it missed)."""
		pant = math.sin(2.0 * math.pi * 3.0 * t)
		h = self.h
		pose = {"lift": -0.25 * self.belly + 0.005 * h * pant}
		add(pose, "hips", 4.0)
		add(pose, "spine", 3.0 + 1.5 * pant)
		add(pose, "chest", 2.0 - 1.5 * pant)
		add(pose, "neck", 18.0 + 2.0 * pant)
		add(pose, "head", -4.0 - 2.0 * pant)
		add(pose, "jaw", 10.0 + 4.0 * pant)
		pose["fl"] = (-0.04 * h, 0.0, 0.0)
		pose["fr"] = (-0.02 * h, 0.0, 0.0)
		ears(pose, back=10.0)
		return self.tail(pose, up=-10.0, bend=-4.0, wave=6.0, phase=t)

	def swipe(self, t: float, seconds: float) -> dict:
		"""The swipe (windup 5): weight back on the haunches, the right fore paw up and out, claws
		out (0..0.45 s), raked across its front (the blow at 0.5 s), back down."""
		s = t * seconds
		wind = ease(s, 0.0, 0.42)
		cut = ease(s, 0.44, 0.56)
		back = 1.0 - ease(s, 0.62, seconds)
		up = wind * back
		h = self.h
		pose = {"back": 0.04 * h * up, "lift": 0.01 * h * up}
		add(pose, "hips", -6.0 * up)
		add(pose, "spine", -3.0 * up)
		turn_to = (10.0 * wind - 24.0 * cut) * back
		add(pose, "chest", -4.0 * up, 0.0, turn_to)
		add(pose, "neck", -4.0 * up, 0.0, 0.5 * turn_to)
		add(pose, "head", 4.0 * up, 0.0, 0.5 * turn_to)
		raised = wind * (1.0 - 0.6 * cut) * back
		pose["upper_arm_r"] = (-100.0 * raised, (30.0 * wind - 70.0 * cut) * back, -10.0 * raised)
		pose["forearm_r"] = (55.0 * raised, 0.0, 0.0)
		pose["paw_r"] = (30.0 * raised, 0.0, 0.0)
		pose["fl"] = (-0.03 * h * up, 0.0, 0.0)
		ears(pose, back=40.0 * up, out=10.0 * up)
		add(pose, "jaw", 12.0 * up)
		return self.tail(pose, up=4.0 * up, wave=12.0, phase=2.0 * s)

	def bite(self, t: float, seconds: float) -> dict:
		"""The bite (windup 4): head drawn back and up, the jaws opening wide (0..0.3 s), a lunge
		forward and down, the jaws snapping shut at 0.4 s, a shake, back."""
		s = t * seconds
		h = self.h
		draw = ease(s, 0.0, 0.25) * (1.0 - ease(s, 0.25, 0.38))
		lunge = ease(s, 0.25, 0.38) * (1.0 - ease(s, 0.5, seconds))
		gape = ease(s, 0.05, 0.3) * (1.0 - ease(s, 0.36, 0.41))
		shake = math.sin(2.0 * math.pi * 8.0 * s) * bump(s, 0.4, 0.6)
		pose = {"back": 0.03 * h * draw - 0.07 * h * lunge, "lift": -0.03 * h * lunge}
		add(pose, "hips", 3.0 * lunge)
		add(pose, "spine", -2.0 * draw + 3.0 * lunge)
		add(pose, "neck", -10.0 * draw + 16.0 * lunge, 0.0, 6.0 * shake)
		add(pose, "head", 8.0 * draw - 6.0 * lunge, 0.0, 8.0 * shake)
		add(pose, "jaw", 38.0 * gape)
		pose["fl"] = (-0.05 * h * lunge, 0.0, 0.0)
		pose["fr"] = (-0.05 * h * lunge, 0.0, 0.0)
		ears(pose, back=45.0 * max(draw, lunge), out=10.0 * max(draw, lunge))
		return self.tail(pose, up=4.0 * lunge, wave=10.0, phase=2.0 * s)

	def snarl(self, t: float, seconds: float) -> dict:
		"""The snarl (its threat cry): it sinks on its fore legs, head low and thrust out, ears flat
		and turned out, jaws wide and trembling, the tail lashing; then rises."""
		s = t * seconds
		on = hold(s, (0.0, 0.2), (1.0, seconds))
		tremble = math.sin(2.0 * math.pi * 9.0 * s)
		h = self.h
		pose = {"lift": -0.06 * h * on}
		add(pose, "hips", -3.0 * on)
		add(pose, "chest", 4.0 * on)
		add(pose, "neck", 10.0 * on)
		add(pose, "head", -16.0 * on + 1.5 * tremble * on)
		add(pose, "jaw", (34.0 + 3.0 * tremble) * on)
		pose["fl"] = (-0.03 * h * on, 0.0, 0.0)
		pose["fr"] = (-0.03 * h * on, 0.0, 0.0)
		ears(pose, back=55.0 * on, out=25.0 * on)
		return self.tail(pose, up=-4.0 * on, side=10.0 * on, wave=26.0 * on, phase=2.5 * s)

	def hit(self, t: float) -> dict:
		"""Struck: a jolt back and aside, the head jerked away, ears flat."""
		jolt = bump(t, 0.0, 0.7)
		pose = {"back": 0.04 * self.h * jolt}
		add(pose, "hips", -3.0 * jolt)
		add(pose, "chest", -4.0 * jolt, 0.0, 8.0 * jolt)
		add(pose, "neck", -10.0 * jolt, 0.0, 8.0 * jolt)
		add(pose, "head", -6.0 * jolt, 6.0 * jolt, 0.0)
		add(pose, "jaw", 14.0 * jolt)
		ears(pose, back=40.0 * jolt)
		return self.tail(pose, up=8.0 * jolt, wave=10.0, phase=t)

	def death(self, t: float) -> dict:
		"""Death: the legs give, it sinks and rolls onto its left side, the head and tail last,
		the jaw slack."""
		h = self.h
		sink = ease(t, 0.0, 0.45)
		fall = ease(t, 0.3, 0.75)
		limp = ease(t, 0.55, 1.0)
		pose = {"lift": -0.3 * self.belly * sink * (1.0 - fall) + 0.2 * h * fall, "roll": 84.0 * fall}
		add(pose, "spine", 3.0 * sink)
		add(pose, "neck", 14.0 * sink - 10.0 * limp)
		add(pose, "head", 8.0 * limp, 0.0, 8.0 * limp)
		add(pose, "jaw", 12.0 * limp)
		for s_ in ("l", "r"):
			pose["thigh_" + s_] = (-30.0 * sink + 20.0 * limp, 0.0, 0.0)
			pose["shin_" + s_] = (40.0 * sink - 20.0 * limp, 0.0, 0.0)
			pose["foot_" + s_] = (-20.0 * sink + 10.0 * limp, 0.0, 0.0)
			pose["upper_arm_" + s_] = (-30.0 * sink + 20.0 * limp, 0.0, 0.0)
			pose["forearm_" + s_] = (-20.0 * sink, 0.0, 0.0)
			pose["paw_" + s_] = (40.0 * sink - 20.0 * limp, 0.0, 0.0)
		ears(pose, back=20.0 * limp)
		return self.tail(pose, bend=4.0 * limp)

	def clips(self) -> list:
		"""[name, seconds, loop, pose_at(t in 0..1)] each."""
		return [
			["Idle", 4.0, True, self.idle],
			["Walk", 1.2, True, self.walk],
			["Run", 0.55, True, self.run],
			["Lie", 4.0, True, self.lie],
			["Crouch_Tell", 0.8, False, lambda t: self.crouch(t, 0.8)],
			["Pounce", 0.8, False, lambda t: self.pounce(t, 0.8)],
			["Recover", 1.0, True, self.recover],
			["Swipe", 0.9, False, lambda t: self.swipe(t, 0.9)],
			["Bite", 0.8, False, lambda t: self.bite(t, 0.8)],
			["Snarl", 1.2, False, lambda t: self.snarl(t, 1.2)],
			["Hit", 0.4, False, self.hit],
			["Death", 1.5, False, self.death],
		]


SPECIES = {"bear": Bear, "hill_cat": HillCat}


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
			if b.name == "root":
				# The root's own axes: Y along the body toward the tail, Z up; a roll about Y.
				b.rotation_euler = (0.0, math.radians(pose.get("roll", 0.0)), 0.0)
				b.location = (0.0, pose.get("back", 0.0), pose.get("lift", 0.0))
				b.keyframe_insert("location", frame=f + 1)
			else:
				x, y, z = pose.get(b.name, (0.0, 0.0, 0.0))
				b.rotation_euler = (math.radians(x), math.radians(y), math.radians(z))
			b.keyframe_insert("rotation_euler", frame=f + 1)
	print("clip %-8s %d frames%s" % (name, frames + 1, ", looped" if loop else ""))


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <body .blend|.glb> <out.glb> --clips SPECIES [--tail N] [--hock SHARE] [--head SHARE] [--height M] [--turn DEG] [--find-tail 1] [--ears 1] [--jaw 1]")
	body_path, out = (os.path.abspath(p) for p in a[:2])
	opts = {"--clips": "bear", "--tail": "1", "--hock": "0.06", "--head": "0.16", "--height": "", "--turn": "0", "--find-tail": "0", "--ears": "0", "--jaw": "0"}
	rest = a[2:]
	for i in range(0, len(rest), 2):
		if rest[i] not in opts or i + 1 >= len(rest):
			raise SystemExit("unknown or valueless argument %s" % rest[i])
		opts[rest[i]] = rest[i + 1]
	if opts["--clips"] not in SPECIES:
		raise SystemExit("no clips for %s (known: %s)" % (opts["--clips"], ", ".join(SPECIES)))
	body = load_body(body_path)
	if float(opts["--turn"]):
		body.data.transform(Matrix.Rotation(math.radians(float(opts["--turn"])), 4, "Z"))
		body.data.update()
	stand(body, float(opts["--height"]) if opts["--height"] else None)
	tail_bones = int(opts["--tail"])
	m = marks(body, float(opts["--head"]), float(opts["--hock"]))
	m["pieces"] = pieces(body)
	m["find_tail"] = opts["--find-tail"] == "1"
	if opts["--ears"] == "1":
		find_ears(body, m)
	if opts["--jaw"] == "1":
		find_jaw(body, m)
	species = opts["--clips"]
	arm = build_armature(joints(m, tail_bones), species.capitalize() + "Armature")
	skin(body, arm)
	if m.get("jaw") is not None:
		own(body, "jaw", m["jaw_piece"])
	for s_, loose in m.get("ear_pieces", {}).items():
		for piece in loose:
			own(body, "ear_" + s_, piece)
	print("rigged: %d vertices, %d tris" % (len(body.data.vertices), tris(body)))
	legs = Legs(arm)
	maker = SPECIES[species](m, tail_bones)
	for name, seconds, loop, pose_at in maker.clips():
		author(arm, legs, name, seconds, loop, pose_at)
	arm.animation_data.action = None
	for b in arm.pose.bones:
		b.location = (0.0, 0.0, 0.0)
		b.rotation_euler = (0.0, 0.0, 0.0)
	bpy.context.scene["source"] = "%s rigged by tools/quadruped_rig.py --clips %s" % (os.path.basename(body_path), species)
	bpy.context.scene.render.fps = FPS
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
