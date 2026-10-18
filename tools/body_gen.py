# The human base body, authored by script (decision pending; the character generator's
# step 1): a faceted low-poly man or woman (--sex) built on the Universal Animation
# Library's own joints, scaled to the height, so tools/body_rig.py fits it as it stands and
# every UAL clip plays on it. No mesh from elsewhere: every vertex is placed here.
#
#   blender -b -P tools/body_gen.py -- <UAL1.glb> <out.glb> [--height M] [--sex male|female]
#       [--people human|orc|kobold]
#
# --people (decision 478): a human (the default), or the Blood Rot's allies (decision 416),
# the orc (the brute: big and heavy, bare-armed in a kilt, tusked) or the kobold (the sneak:
# small and crouched, a digger: big clawed hands, a snouted head, a tail, a miner's cap). On
# the same skeleton, its joints moved to the people's proportions (PROPORTIONS: an orc's
# long arms and short neck, a kobold's short legs), so every UAL clip plays on them too; the
# body is then scaled so its head's top is at the height.
#
# The UAL armature, scaled to the height, rigs it as built (bone heat; each leg's weights its
# own below the crotch): no fitting is needed, the joints are the armature's.
#
# Box modelling by script: each part is a loft of rings (cross-sections, the same number of
# points each) along its axis, quads between them, capped: the torso (the tunic, flaring
# below the belt to its hem), the arms (sleeves to the wrists), the legs (trousers), the
# neck and the head (lofted from the jaw to the crown, its front shaped into planes: chin,
# mouth, nose, brows, cheeks), the hands (mittens with a thumb), the boots, the belt, the
# hair (a cap over the crown and the back). Parts overlap at the joints, as low-poly game
# characters do: an arm's top sits inside the shoulder, so it turns there without a seam
# showing. Each part is one region's material (Skin, Hair, Tunic, Trousers, Belt, Boots),
# as tools/body_build.py --parts colours them.
#
# Axes as the UAL stands: it faces -Y, its left is +X, Z is up; T-pose, arms along X.
import math
import os
import sys

import bpy
from mathutils import Vector

## The UAL mannequin's height: its joints are scaled from this to --height.
UAL_HEIGHT = 1.829
## The height every size below is given at: the body is built there, then it and its
## skeleton are scaled to --height together.
BUILD_HEIGHT = 1.75
## Each sex's height when --height isn't given.
HEIGHTS = {"male": 1.75, "female": 1.66}
## Each people's (decision 478), its head's top.
PEOPLE_HEIGHTS = {"orc": 1.95, "kobold": 1.0}

## The body being built: "male" or "female" (set by main from --sex).
SEX = "male"
## Its people: "human", "orc" or "kobold" (set by main from --people).
PEOPLE = "human"


def per(human, orc=None, kobold=None):
	"""[human] for a human, else the people's own (a human's where it gives none)."""
	own = {"orc": orc, "kobold": kobold}.get(PEOPLE)
	return human if own is None else own


## The skeleton's segments scaled by people (decision 478), as the UAL stands at
## BUILD_HEIGHT: each bone's offset from its parent by the parent's segment (legs: thigh and
## calf; arms: upper and lower arm; shoulders: the clavicles' across; hips: the thighs'
## across; spine; neck: to the head; hands: the fingers; feet: heel to toe). The feet are
## then put back on the ground.
PROPORTIONS = {
	"orc": {"legs": 0.94, "arms": 1.12, "shoulders": 1.3, "hips": 1.18, "spine": 1.0, "neck": 0.55,
		"hands": 1.25, "feet": 1.15},
	"kobold": {"legs": 0.66, "arms": 1.0, "shoulders": 0.95, "hips": 0.9, "spine": 0.84, "neck": 0.8,
		"hands": 1.4, "feet": 1.45},
}
## The torso's rings (torso_rings' ten) widened or narrowed by people: across, front to back.
TORSO_WIDTH = {
	"orc": [1.15, 1.15, 1.15, 1.2, 1.22, 1.3, 1.32, 1.34, 1.5, 1.5],
	"kobold": [1.08, 1.04, 1.0, 0.9, 0.92, 0.98, 0.96, 0.95, 0.85, 0.85],
}
TORSO_DEPTH = {
	"orc": [1.15, 1.15, 1.15, 1.2, 1.25, 1.3, 1.3, 1.3, 1.45, 1.45],
	"kobold": [1.08, 1.04, 1.0, 0.95, 0.98, 1.0, 0.95, 0.92, 0.85, 0.85],
}


def female() -> bool:
	return SEX == "female"


def pick(male, woman):
	"""[male] for the man, [woman] for the woman."""
	return woman if female() else male


## The body's proportions as built: factors on the stations' sizes (1 as authored) and
## amounts added (ADDED: the belly, metres forward at the waist; sag, how far age has
## flattened the chest, 0..1). The base body is built with
## none; each shape key is the body built again with KEYS' (the same parts, the same rings,
## so the same vertices in the same order), its positions the key's.
MORPH = {}
ADDED = ("belly", "sag")


def m(name: str) -> float:
	return MORPH.get(name, 0.0 if name in ADDED else 1.0)


## The shape keys the game blends by a person's words and seed (each 0..1).
KEYS = {
	# Thinner all over.
	"lean": {"torso": 0.9, "waist": 0.92, "arms": 0.86, "legs": 0.88, "neck": 0.92, "hands": 0.95},
	# Thicker all over, a belly most of all.
	"heavy": {"torso": 1.1, "waist": 1.14, "belly": 0.045, "chest": 1.04, "hips": 1.04, "arms": 1.16, "legs": 1.12,
		"neck": 1.14, "hands": 1.06},
	# Broad or narrow across the shoulders and the chest.
	"broad": {"shoulders": 1.12, "chest": 1.05, "arms": 1.06},
	"narrow": {"shoulders": 0.9, "chest": 0.96, "arms": 0.95},
	"hips": {"hips": 1.12, "thighs": 1.08},
	# Old: thinner limbs and neck, a softer belly, the chest lower and flatter, the
	# shoulders in a little.
	"old": {"arms": 0.9, "legs": 0.92, "neck": 0.9, "belly": 0.02, "chest": 0.95, "shoulders": 0.96, "sag": 1.0},
	# Young: slighter, the head a touch larger for the body.
	"young": {"torso": 0.93, "waist": 0.95, "shoulders": 0.94, "arms": 0.9, "legs": 0.92, "neck": 0.92, "hands": 0.93,
		"head": 1.06},
}


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def skeleton(ual: str, height: float) -> tuple:
	"""The UAL armature alone, scaled to [height] (applied), its clips and mannequin gone;
	and each bone's head (and tail, as "<bone>.tail") where it now stands. Objects already
	in the scene stay."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=ual)
	new = [o for o in bpy.data.objects if o not in before]
	arm = [o for o in new if o.type == "ARMATURE"][0]
	for obj in new:
		if obj is not arm:
			bpy.data.objects.remove(obj)
	if arm.animation_data:
		arm.animation_data_clear()
	for action in list(bpy.data.actions):
		bpy.data.actions.remove(action)
	world = arm.matrix_world.copy()
	arm.parent = None
	arm.matrix_world = world
	arm.scale = arm.scale * (height / UAL_HEIGHT)
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	arm.name = "Armature"
	out = {}
	for b in arm.data.bones:
		out[b.name] = arm.matrix_world @ b.head_local
		out[b.name + ".tail"] = arm.matrix_world @ b.tail_local
	return arm, out


def _segment(parent: str, child: str, P: dict) -> Vector:
	"""The scale of [child]'s offset from [parent] (PROPORTIONS' [P])."""
	f = lambda k: P.get(k, 1.0)
	if child.startswith("thigh_"):
		return Vector((f("hips"), 1.0, 1.0))
	if parent == "root":
		return Vector((1.0, 1.0, f("legs")))
	if parent.startswith(("thigh_", "calf_")):
		return Vector((1.0, 1.0, 1.0)) * f("legs")
	if child.startswith("clavicle_"):
		return Vector((f("shoulders"), 1.0, f("spine")))
	if parent.startswith("clavicle_"):
		return Vector((1.0, 1.0, 1.0)) * f("shoulders")
	if parent.startswith(("upperarm_", "lowerarm_")):
		return Vector((1.0, 1.0, 1.0)) * f("arms")
	if parent.startswith(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")):
		return Vector((1.0, 1.0, 1.0)) * f("hands")
	if parent.startswith(("foot_", "ball_")):
		return Vector((1.0, 1.0, 1.0)) * f("feet")
	if parent in ("pelvis", "spine_01", "spine_02", "spine_03"):
		return Vector((1.0, 1.0, 1.0)) * f("spine")
	if parent == "neck_01":
		return Vector((1.0, 1.0, 1.0)) * f("neck")
	return Vector((1.0, 1.0, 1.0))


def proportion(arm) -> dict:
	"""[arm]'s joints moved to the people's PROPORTIONS (none for a human), the feet back on
	the ground; each bone's head (and tail) where it now stands, as skeleton gives them."""
	P = PROPORTIONS.get(PEOPLE, {})
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	bones = arm.data.edit_bones
	old = {b.name: (b.head.copy(), b.tail.copy()) for b in bones}
	new = {}

	def place(b):
		if b.parent is None:
			new[b.name] = old[b.name][0].copy()
		else:
			p = b.parent.name
			d = old[b.name][0] - old[p][0]
			new[b.name] = new[p] + d * _segment(p, b.name, P)
		for c in b.children:
			place(c)

	for b in bones:
		b.use_connect = False
	for b in [b for b in bones if b.parent is None]:
		place(b)
	# The feet's lowest point (the toes' tails) where it was.
	toes = [n for n in old if n.startswith("ball_leaf_")]
	drop = 0.0
	if toes:
		was = min(old[n][1].z for n in toes)
		now = min((new[n] + (old[n][1] - old[n][0]) * _segment(n, n, P)).z for n in toes)
		drop = was - now
	for b in bones:
		first = b.children[0].name if b.children else b.name
		tail = new[b.name] + (old[b.name][1] - old[b.name][0]) * _segment(b.name, first, P)
		lift = Vector((0.0, 0.0, drop)) if b.parent is not None else Vector()
		b.head = new[b.name] + lift
		b.tail = tail + lift
	bpy.ops.object.mode_set(mode="OBJECT")
	out = {}
	for b in arm.data.bones:
		out[b.name] = arm.matrix_world @ b.head_local
		out[b.name + ".tail"] = arm.matrix_world @ b.tail_local
	return out


def people_skeleton(ual: str, scale: float) -> tuple:
	"""The UAL skeleton at BUILD_HEIGHT, PROPORTIONS' joints, then scaled by [scale] whole."""
	arm, J = skeleton(ual, BUILD_HEIGHT)
	J = proportion(arm)
	if abs(scale - 1.0) > 1e-6:
		arm.scale = arm.scale * scale
		bpy.ops.object.select_all(action="DESELECT")
		arm.select_set(True)
		bpy.context.view_layer.objects.active = arm
		bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
		J = {}
		for b in arm.data.bones:
			J[b.name] = arm.matrix_world @ b.head_local
			J[b.name + ".tail"] = arm.matrix_world @ b.tail_local
	return arm, J


def skin(body, arm, J: dict) -> None:
	"""The armature on the body: its parts already weighted (Part.bones, rigid); the
	following parts (belt, collar) take the weights of the nearest vertex not following; at
	most four a vertex, summing to one."""
	body.parent = arm
	body.modifiers.new("Armature", "ARMATURE").object = arm
	from mathutils.kdtree import KDTree
	marks = {g.index: g.name for g in body.vertex_groups if g.name.startswith("_")}
	follow = {v.index for v in body.data.vertices if any(g.group in marks for g in v.groups)}
	# Following pieces: the weights of the nearest vertex not itself following.
	hosts = [v for v in body.data.vertices if v.index not in follow and v.groups]
	host_tree = KDTree(len(hosts))
	for k, v in enumerate(hosts):
		host_tree.insert(v.co, k)
	host_tree.balance()
	for i in follow:
		v = body.data.vertices[i]
		for g in [g.group for g in v.groups if g.group not in marks]:
			body.vertex_groups[g].remove([i])
		for g in hosts[host_tree.find(v.co)[1]].groups:
			if g.group not in marks:
				body.vertex_groups[g.group].add([i], g.weight, "REPLACE")
	for index in sorted(marks, reverse=True):
		body.vertex_groups.remove(body.vertex_groups[index])
	# Small pieces bone heat left bare take their nearest weighted vertex's weights.
	weighted = [v for v in body.data.vertices if v.groups]
	tree = KDTree(len(weighted))
	for i, v in enumerate(weighted):
		tree.insert(v.co, i)
	tree.balance()
	for v in [v for v in body.data.vertices if not v.groups]:
		for g in weighted[tree.find(v.co)[1]].groups:
			body.vertex_groups[g.group].add([v.index], g.weight, "REPLACE")
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
	bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)
	bare = sum(1 for v in body.data.vertices if not v.groups)
	print("skinned: %d vertices, %d with no weight" % (len(body.data.vertices), bare))


def ring(centre: Vector, u: Vector, v: Vector, ru: float, rv: float, n: int, square: float = 0.0,
		bulge: tuple = (0.0, 0.0), phase: float = 0.0) -> list:
	"""[n] points round [centre] in the plane of [u] (half-width [ru]) and [v] (half-depth
	[rv]): an ellipse, squared toward a box by [square] (0..1), pushed out along +v by
	bulge[0] and along -v by bulge[1] (a fuller front or back), starting [phase] of a step
	round."""
	points = []
	for i in range(n):
		a = 2.0 * math.pi * (i + phase) / n
		c, s = math.cos(a), math.sin(a)
		# A superellipse: squarer as the exponent falls toward 0.
		e = 1.0 - 0.6 * square
		x = math.copysign(abs(c) ** e, c) * ru
		y = math.copysign(abs(s) ** e, s) * rv
		y += bulge[0] * max(0.0, s) ** 2 - bulge[1] * max(0.0, -s) ** 2
		points.append(centre + u * x + v * y)
	return points


class Part:
	"""A lofted part: rings in order, quads between them, the ends capped."""

	def __init__(self, name: str, region: str, rigid: str = "", follow: bool = False):
		self.name = name
		self.region = region
		self.rings = []
		# Weights: bone heat, unless [rigid] names the one bone it moves with (hair and the
		# face's pieces: the head) or it [follow]s the surface it lies on (the belt, the
		# collar: the torso's weights under it).
		self.rigid = rigid
		self.follow = follow
		# The bones it may move with (weighted by distance to each, nearest most).
		self.bones = []
		# Rings held to one bone whatever their distances say ({ring index: bone}): a
		# sleeve's end inside the shoulder stays with the clavicle as the arm turns.
		self.pins = {}
		# Rings shared with another bone at a weight ({ring index: (bone, weight)}): the top of
		# a sleeve half on the clavicle, so it turns only part way as the arm comes down.
		self.mixes = {}

	def add(self, points: list) -> "Part":
		self.rings.append(points)
		return self

	def mesh(self, J: dict, cap_start: bool = True, cap_end: bool = True):
		verts, faces = [], []
		n = len(self.rings[0])
		for r in self.rings:
			verts.extend(r)
		for k in range(len(self.rings) - 1):
			for i in range(n):
				a, b = k * n + i, k * n + (i + 1) % n
				faces.append((a, b, b + n, a + n))
		if cap_start:
			faces.append(tuple(reversed(range(n))))
		if cap_end:
			last = (len(self.rings) - 1) * n
			faces.append(tuple(range(last, last + n)))
		mesh = bpy.data.meshes.new(self.name)
		mesh.from_pydata(verts, [], faces)
		mesh.validate()
		obj = bpy.data.objects.new(self.name, mesh)
		bpy.context.scene.collection.objects.link(obj)
		obj["region"] = self.region
		if self.rigid:
			obj.vertex_groups.new(name=self.rigid).add(list(range(len(verts))), 1.0, "REPLACE")
		elif self.follow:
			obj.vertex_groups.new(name="_follow").add(list(range(len(verts))), 1.0, "REPLACE")
		else:
			weigh(obj, self.bones, J)
			for k, bone in self.pins.items():
				held = list(range(k * n, (k + 1) * n))
				for g in obj.vertex_groups:
					g.remove(held)
				obj.vertex_groups[bone].add(held, 1.0, "REPLACE")
			for k, (bone, share) in self.mixes.items():
				for i in range(k * n, (k + 1) * n):
					for g in obj.vertex_groups:
						try:
							w = g.weight(i)
						except RuntimeError:
							continue
						g.add([i], w * (1.0 - share), "REPLACE")
					obj.vertex_groups[bone].add([i], share, "ADD")
		return obj


## How sharply weights fall off with distance from a bone: higher, crisper joints.
FALLOFF = 4.0


def weigh(obj, bones: list, J: dict) -> None:
	"""Each vertex weighted among [bones] by its distance to each bone's segment (head to
	tail), as 1 / d^FALLOFF, the three nearest kept, summing to one: a smooth blend across a
	joint, and never a bone the part does not hang from."""
	from mathutils.geometry import intersect_point_line
	groups = {b: obj.vertex_groups.new(name=b) for b in bones}
	for v in obj.data.vertices:
		scores = []
		for b in bones:
			head, tail = J[b], J[b + ".tail"]
			closest, t = intersect_point_line(v.co, head, tail)
			t = min(max(t, 0.0), 1.0)
			d = (v.co - head.lerp(tail, t)).length
			scores.append((1.0 / (max(d, 0.005) ** FALLOFF), b))
		scores.sort(reverse=True)
		top = scores[:3]
		total = sum(w for w, _ in top)
		for w, b in top:
			groups[b].add([v.index], w / total, "REPLACE")


X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
FRONT = -Y


TORSO_BONES = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r", "thigh_l", "thigh_r"]


def torso(J: dict) -> Part:
	"""The body in its tunic: rings from the hem up to the base of the neck (torso_rings)."""
	p = Part("Tunic", per("Tunic", "Skin", "Tunic"))  # An orc's chest bare.
	p.bones = TORSO_BONES
	for r in torso_rings(J):
		p.add(r)
	return p


def torso_rings(J: dict) -> list:
	"""The tunic's rings of 12, hem to neck, by MORPH. Widths and depths (half, metres, at
	1.75 m) read off the concept's front: the hem flares to 0.20 across the hips, the waist
	0.15 at the belt, the chest 0.18, the shoulders' top 0.17 before the arms."""
	rings = []
	pelvis, s1, s2, s3, neck = J["pelvis"], J["spine_01"], J["spine_02"], J["spine_03"], J["neck_01"]
	hem = pelvis.z - 0.09
	stations = [
		# (height, half-width, half-depth, squareness, front bulge, back bulge, y shift)
		(hem, 0.205, 0.140, 0.35, 0.0, 0.0, 0.0),
		(hem + 0.07, 0.190, 0.128, 0.4, 0.0, 0.005, 0.0),
		(pelvis.z + 0.03, 0.170, 0.112, 0.4, 0.0, 0.015, 0.0),
		(s1.z, 0.155, 0.102, 0.45, 0.01, 0.0, -0.005),
		(s2.z, 0.165, 0.108, 0.5, 0.025, 0.0, -0.008),
		(s3.z - 0.03, 0.185, 0.115, 0.55, 0.035, 0.012, -0.012),
		(s3.z + 0.06, 0.200, 0.108, 0.65, 0.0, 0.012, -0.005),
		(neck.z - 0.02, 0.170, 0.088, 0.55, 0.0, 0.0, 0.0),
		(neck.z + 0.01, 0.105, 0.072, 0.3, 0.0, 0.0, 0.005),
		(neck.z + 0.03, 0.068, 0.064, 0.15, 0.0, 0.0, 0.008),
	]
	if female():
		# The woman's: a longer, fuller hem (to mid-thigh), wider hips, a narrower waist, the
		# bust (a fuller front at the chest), narrower shoulders and neck.
		hem = pelvis.z - 0.17
		stations = [
			(hem, 0.225, 0.150, 0.3, 0.0, 0.0, 0.0),
			(pelvis.z - 0.08, 0.205, 0.136, 0.35, 0.0, 0.008, 0.0),
			(pelvis.z + 0.02, 0.188, 0.120, 0.4, 0.0, 0.022, 0.0),
			(s1.z, 0.140, 0.094, 0.45, 0.005, 0.0, -0.005),
			(s2.z, 0.150, 0.100, 0.5, 0.040, 0.0, -0.008),
			(s3.z - 0.03, 0.166, 0.106, 0.55, 0.058, 0.008, -0.012),
			(s3.z + 0.06, 0.178, 0.100, 0.62, 0.008, 0.010, -0.005),
			(neck.z - 0.02, 0.152, 0.082, 0.55, 0.0, 0.0, 0.0),
			(neck.z + 0.01, 0.092, 0.064, 0.3, 0.0, 0.0, 0.005),
			(neck.z + 0.03, 0.058, 0.056, 0.15, 0.0, 0.0, 0.008),
		]
	for k, (z, w, d, sq, bf, bb, dy) in enumerate(stations):
		# MORPH: [0, 3) the hips and hem, [3, 5) the waist and belly, 5 the chest, [6, 8) the
		# shoulders, [8, 10) the neck's base.
		w, d = w * m("torso") * TORSO_WIDTH.get(PEOPLE, [1.0] * 10)[k], d * m("torso") * TORSO_DEPTH.get(PEOPLE, [1.0] * 10)[k]
		if k < 3:
			w *= m("hips")
		elif k < 5:
			w, d = w * m("waist"), d * m("waist")
			bf += m("belly") * (1.0 if k == 3 else 0.7)
		elif k == 5:
			w, d = w * m("chest"), d * m("chest")
			# Age lowers and flattens the chest: its fullness drops to the ring below.
			bf *= 1.0 - 0.5 * m("sag")
		elif k < 8:
			w *= m("shoulders")
		else:
			w, d = w * m("neck"), d * m("neck")
		rings.append(ring(Vector((0, dy, z)), X, FRONT, w, d, 12, sq, (bf, bb)))
	return rings


def sleeve(J: dict, side: str) -> Part:
	"""An arm in its sleeve, T-pose along X: from inside the shoulder to the wrist."""
	sign = 1.0 if side == "l" else -1.0
	p = Part("Sleeve_" + side, per("Tunic", "Skin", "Skin"))
	p.bones = ["spine_03", "clavicle_" + side, "upperarm_" + side, "lowerarm_" + side, "hand_" + side]
	sh, el, wr = J["upperarm_" + side], J["lowerarm_" + side], J["hand_" + side]
	along = (wr - sh).normalized()
	inner = sh - along * 0.07  # Inside the shoulder: the torso hides the join.
	# That end held to the clavicle: weighted by distance it took the upper arm's turn and
	# rose out of the shoulder as the arm came down.
	p.pins = {0: "clavicle_" + side}
	# The shoulder's cap (the ring past the joint) half with the clavicle: turned wholly with the
	# upper arm, its top rose above the shoulder's line as the arm came down (the base pair's
	# "shoulder tips", Jeff on its sheet; decision 419 amended).
	p.mixes = {1: ("clavicle_" + side, 0.5)}
	# Its top end (the two rings at the shoulder) flatter and a little lower, under the torso's
	# shoulder line: as high as the arm's, it stood above the shoulder when the arm came down.
	down = Vector((0.0, 0.0, -0.018))
	stations = [(inner + down, 0.052, 0.075), (sh + along * 0.03 + down, 0.060, 0.074), (sh.lerp(el, 0.45), 0.058, 0.058),
		(el, 0.048, 0.050), (el.lerp(wr, 0.5), 0.046, 0.044), (wr - along * 0.01, 0.040, 0.036)]
	k = pick(1.0, 0.86) * m("arms") * per(1.0, 1.45, 1.05)  # The woman's arms slighter, an orc's thick.
	for c, rv, ru in stations:
		# u forward, v up: the arm's front-to-back depth and its height.
		p.add(ring(c, FRONT, Z, ru * k, rv * k, 8, 0.3))
	return p


def leg(J: dict, side: str) -> Part:
	"""A leg in its trousers: from inside the hip to the boot top."""
	p = Part("Leg_" + side, "Trousers")
	p.bones = ["pelvis", "thigh_" + side, "calf_" + side, "foot_" + side]
	hip, knee, ankle = J["thigh_" + side], J["calf_" + side], J["foot_" + side]
	out = 1.0 if side == "l" else -1.0
	stations = [
		(hip + Vector((0, 0, 0.06)), 0.085, 0.090, -0.025),
		(hip + Vector((0, 0, -0.08)), 0.090, 0.094, -0.008),
		(hip.lerp(knee, 0.55), 0.075, 0.078, 0.0),
		(knee, 0.062, 0.066, 0.0),
		(knee.lerp(ankle, 0.35), 0.064, 0.066, 0.0),
		(knee.lerp(ankle, 0.75), 0.054, 0.056, 0.0),
		(ankle + Vector((0, 0, 0.04)), 0.050, 0.052, 0.0),
	]
	# The woman's legs: the thigh's top as full (her hips), slighter below.
	scale = pick([1.0] * 7, [1.04, 1.0, 0.95, 0.9, 0.9, 0.88, 0.88])
	for k, (c, ru, rv, dx) in enumerate(stations):
		back = {1: 0.018, 4: 0.012}.get(k, 0.0)  # The seat; the calf.
		f = scale[k] * m("legs") * (m("thighs") if k < 2 else 1.0) * per(1.0, 1.35, 0.95)
		p.add(ring(c + Vector((dx * out, 0, 0)), X, FRONT, ru * f, rv * f, 8, 0.25, (0.0, back)))
	return p


def boot(J: dict, side: str) -> Part:
	"""A boot: a shaft from below the knee to the ankle, then the foot to the toe, flat soled."""
	p = Part("Boot_" + side, per("Boots", "Boots", "Skin"))
	p.bones = ["calf_" + side, "foot_" + side, "ball_" + side]
	knee, ankle, ball, toe = J["calf_" + side], J["foot_" + side], J["ball_" + side], J["ball_" + side + ".tail"]
	top = knee.lerp(ankle, 0.30)
	x = ankle.x
	k = pick(1.0, 0.9) * per(1.0, 1.3, 1.15)  # The woman's boots narrower (their length is her feet's, the skeleton's).
	shaft = k * m("legs") * per(1.0, 1.05, 0.85)  # The shaft round the leg, as thick as it is.
	# The shaft: rings round the leg, a little wider than the trousers.
	for c, r in [(top, 0.072), (top + Vector((0, 0, -0.02)), 0.070), (top.lerp(ankle, 0.5), 0.064),
			(ankle + Vector((0, 0, 0.03)), 0.060)]:
		p.add(ring(c, X, FRONT, r * shaft, r * 1.05 * shaft, 8, 0.35))
	# The foot: rings across it, from the heel forward to the toe, sitting on the ground.
	heel_y = ankle.y + 0.07
	for y, w, h in [(heel_y - 0.01, 0.050, 0.095), (ankle.y, 0.054, 0.090), (ball.y + 0.03, 0.055, 0.068),
			(ball.y - 0.015, 0.052, 0.052), (toe.y + 0.03, 0.040, 0.036)]:
		p.add(ring(Vector((x, y, h * 0.5 + 0.005)), X, Z, w * k, h * 0.5, 8, 0.6))
	return p


def hand(J: dict, side: str) -> Part:
	"""A mitten, palm down, along X from the wrist: the fingers one block, the thumb forward."""
	sign = 1.0 if side == "l" else -1.0
	p = Part("Hand_" + side, "Skin")
	p.bones = ["lowerarm_" + side, "hand_" + side, "middle_01_" + side, "middle_02_" + side]
	wr = J["hand_" + side]
	k = pick(1.0, 0.88) * m("hands") * per(1.0, 1.3, 1.35)  # The woman's hands narrower and thinner.
	reach = per(1.0, *PROPORTIONS_OF("hands"))  # As long as the skeleton's fingers.
	for dx, w, h in [(-0.015, 0.036, 0.028), (0.02, 0.050, 0.027), (0.065, 0.053, 0.023), (0.105, 0.048, 0.018),
			(0.135, 0.034, 0.013)]:
		p.add(ring(wr + Vector((dx * reach * sign, 0, -0.005)), FRONT, Z, w * k, h * k, 8, 0.6))
	return p


def thumb(J: dict, side: str) -> Part:
	sign = 1.0 if side == "l" else -1.0
	p = Part("Thumb_" + side, "Skin")
	p.bones = ["hand_" + side, "thumb_01_" + side, "thumb_02_" + side]
	wr = J["hand_" + side]
	k = per(1.0, *PROPORTIONS_OF("hands"))
	base = wr + Vector((0.025 * sign, -0.035, -0.005)) * k
	tip = base + Vector((0.035 * sign, -0.03, -0.004)) * k
	for t, r in [(0.0, 0.014), (0.5, 0.012), (1.0, 0.008)]:
		c = base.lerp(tip, t)
		along = (tip - base).normalized()
		p.add(ring(c, Z, along.cross(Z).normalized(), r * m("hands") * k, r * m("hands") * k, 6))
	return p


def neck(J: dict) -> Part:
	p = Part("Neck", "Skin")
	p.bones = ["spine_03", "neck_01", "Head"]
	n, h = J["neck_01"], J["Head"]
	k = pick(1.0, 0.86) * m("neck") * per(1.0, 1.55, 0.8)  # The woman's neck slimmer, an orc's a bull's.
	for c, r, fwd in [(n + Vector((0, 0, -0.01)), 0.066, 0.0), (n.lerp(h, 0.5), 0.060, 0.008),
			(h + Vector((0, 0.005, 0.03)), 0.060, 0.014)]:
		p.add(ring(c + Vector((0, 0.008, 0)) + FRONT * fwd, X, FRONT, r * k, r * 1.05 * k, 8))
	return p


def head(J: dict) -> Part:
	"""The head, lofted from under the jaw to the crown: rings of 12, the front ones (the
	face) pushed and pulled into planes: a chin, the mouth's line, a nose, cheekbones, brows,
	the forehead. Proportions off the concept: 0.24 m jaw to crown (without hair), 0.15
	across, 0.20 front to back."""
	p = Part("Head", "Skin", rigid="Head")
	for r in head_rings(J):
		p.add(r)
	return p


## head_rings' heights (above the head bone, less 0.015): the jaw's underside, the chin,
## the mouth, the nose's tip line, the eyes, the brows, the forehead, the crown, the top.
HEAD_Z = (0.010, 0.040, 0.070, 0.102, 0.132, 0.158, 0.192, 0.222, 0.243)


def head_rings(J: dict) -> list:
	"""The head's rings of 12, jaw to crown (HEAD_Z), the face shaped (see head)."""
	rings = []
	base = J["Head"] + Vector((0, 0.0, -0.015))
	# (height above the head bone, half-width, half-depth, y centre, front push)
	stations = [
		(0.010, 0.048, 0.058, 0.015, 0.00),   # Under the jaw, at the neck.
		(0.040, 0.066, 0.082, -0.002, 0.025),  # The jaw and chin.
		(0.070, 0.074, 0.093, -0.006, 0.015),  # The mouth.
		(0.102, 0.078, 0.100, -0.006, 0.035),  # The nose's tip line.
		(0.132, 0.081, 0.102, -0.003, 0.008),  # Eyes and cheekbones.
		(0.158, 0.082, 0.104, 0.000, 0.014),  # Brows.
		(0.192, 0.077, 0.100, 0.004, 0.0),    # The forehead.
		(0.222, 0.062, 0.086, 0.008, 0.0),    # The crown's slope.
		(0.243, 0.034, 0.050, 0.010, 0.0),    # The top.
	]
	# The woman's head a touch smaller, her chin and nose less forward.
	kw, kd, kp = pick((1.0, 1.0, 1.0), (0.95, 0.97, 0.75))
	# An orc's lower face broad (the jaw, the chin, the mouth) and its brow a ridge; a
	# kobold's head narrow, its mouth and nose drawn out into a snout (SNOUT).
	jaw_wide = per({}, {0.040: 1.28, 0.070: 1.18, 0.102: 1.08}, {0.010: 0.8, 0.040: 0.72, 0.070: 0.7, 0.102: 0.72})
	for z, w, d, yc, push in stations:
		w, d, push = w * kw * jaw_wide.get(z, per(1.0, 1.04, 0.86)), d * kd, push * kp
		pts = ring(base + Vector((0, yc, z)), X, FRONT, w, d, 12, 0.3, (0.0, 0.012 if 0.09 < z < 0.23 else 0.0))
		# The face's middle point (straight ahead, index 3: +v, FRONT) pushed out: chin, nose
		# line, brows; its neighbours (2, 4: the eyes' columns) in at the eyes' height (the
		# sockets) and out at the brows' (the ridge); the cheeks (1, 5) out at the cheekbones.
		pts[3] = pts[3] + FRONT * push
		if abs(z - 0.132) < 0.01:
			pts[2] = pts[2] - FRONT * 0.012
			pts[4] = pts[4] - FRONT * 0.012
			pts[1] = pts[1] + FRONT * 0.006 + X * 0.004
			pts[5] = pts[5] + FRONT * 0.006 - X * 0.004
		if abs(z - 0.158) < 0.01:
			pts[2] = pts[2] + FRONT * 0.008
			pts[4] = pts[4] + FRONT * 0.008
		if abs(z - 0.040) < 0.01:
			# A squarer jaw: its corners out (the man's); the woman's in, toward a narrower chin.
			jaw = per(pick(0.006, -0.004), 0.016, 0.0)
			pts[1] = pts[1] + X * jaw
			pts[5] = pts[5] - X * jaw
		if PEOPLE == "orc" and abs(z - 0.158) < 0.01:
			for i in (2, 3, 4):
				pts[i] = pts[i] + FRONT * 0.022  # The brow's ridge.
		if PEOPLE == "kobold":
			out = SNOUT.get(z, 0.0)
			pts[3] = pts[3] + FRONT * out
			pts[2] = pts[2] + FRONT * out * 0.85
			pts[4] = pts[4] + FRONT * out * 0.85
			pts[1] = pts[1] + FRONT * out * 0.4
			pts[5] = pts[5] + FRONT * out * 0.4
		rings.append(pts)
	return rings


## A kobold's snout: how far its face's front comes forward, by head_rings' height.
SNOUT = {0.010: 0.02, 0.040: 0.075, 0.070: 0.095, 0.102: 0.09, 0.132: 0.035, 0.158: 0.01}


def PROPORTIONS_OF(key: str) -> tuple:
	"""PROPORTIONS' [key] for the orc and the kobold, in per's order."""
	return (PROPORTIONS["orc"].get(key, 1.0), PROPORTIONS["kobold"].get(key, 1.0))


def box(name: str, region: str, centre: Vector, size: Vector, front_taper: float = 1.0, rigid: str = "") -> Part:
	"""A small block: two rings of four, [front_taper] the front ring's scale."""
	p = Part(name, region, rigid=rigid)
	half = size * 0.5
	for dy, k in ((half.y, 1.0), (-half.y, front_taper)):
		c = centre + Vector((0, dy, 0))
		p.add([c + Vector((-half.x * k, 0, -half.z * k)), c + Vector((half.x * k, 0, -half.z * k)),
			c + Vector((half.x * k, 0, half.z * k)), c + Vector((-half.x * k, 0, half.z * k))])
	return p


def face(J: dict) -> list:
	"""The face's pieces on the head: a nose (a wedge), brows and eyes (dark), ears."""
	base = J["Head"] + Vector((0, 0.0, -0.015))
	# On the woman's smaller head (head()'s kw, kd): across by kw, front to back by kd; her
	# nose smaller, her brows thinner.
	kw, kd = pick((1.0, 1.0), (0.95, 0.97))
	at = lambda x, y, z: base + Vector((x * kw, y * kd, z))
	parts = []
	if PEOPLE == "kobold":
		return parts + kobold_face(J)
	nose = Part("Nose", "Skin", rigid="Head")
	top, tip = at(0, -0.100, 0.150), at(0, per(pick(-0.128, -0.124), -0.118), 0.098)
	for t, w in [(0.0, 0.010), (0.7, per(pick(0.016, 0.013), 0.024)), (1.0, per(pick(0.012, 0.010), 0.02))]:
		c = top.lerp(tip, t)
		nose.add([c + Vector((-w, 0.012, 0)), c + Vector((0, -0.004, 0)), c + Vector((w, 0.012, 0))])
	parts.append(nose)
	for side in (1.0, -1.0):
		parts.append(box("Brow", "Hair", at(0.030 * side, -0.100, 0.150), Vector((0.032, 0.012, pick(0.008, 0.005))), rigid="Head"))
		parts.append(box("Eye", "Belt", at(0.030 * side, -0.090, 0.130), Vector((0.016, 0.006, 0.008)), rigid="Head"))
		if PEOPLE == "orc":
			# Small ears swept back to a point; two tusks up from the lower jaw.
			parts.append(box("Ear", "Skin", at(0.088 * side, 0.030, 0.128), Vector((0.012, 0.060, 0.026)), 0.45, rigid="Head"))
			parts.append(spike("Tusk", "Bone", at(0.040 * side, -0.100, 0.046), at(0.047 * side, -0.112, 0.094), 0.010))
		else:
			parts.append(box("Ear", "Skin", at(0.080 * side, 0.004, 0.120), Vector((0.012, 0.030, pick(0.045, 0.040))), 0.8, rigid="Head"))
	return parts


def spike(name: str, region: str, base: Vector, tip: Vector, r: float, bone: str = "Head") -> Part:
	"""A cone from [base] to [tip], [r] across at the base: a tusk, a horn, a claw."""
	p = Part(name, region, rigid=bone)
	along = (tip - base).normalized()
	u = along.cross(Z if abs(along.z) < 0.9 else X).normalized()
	v = along.cross(u).normalized()
	for t, k in [(0.0, 1.0), (0.6, 0.6), (1.0, 0.12)]:
		p.add(ring(base.lerp(tip, t), u, v, r * k, r * k, 5))
	return p


def kobold_face(J: dict) -> list:
	"""A kobold's face on its snout (head_rings' SNOUT): nostrils at its end, eyes set to the
	sides under a ridge, two horns swept back from the crown, no ears."""
	base = J["Head"] + Vector((0, 0.0, -0.015))
	at = lambda x, y, z: base + Vector((x, y, z)) * 1.0
	parts = []
	for side in (1.0, -1.0):
		parts.append(box("Nostril", "Belt", at(0.018 * side, -0.188, 0.100), Vector((0.010, 0.006, 0.006)), rigid="Head"))
		parts.append(box("Eye", "Belt", at(0.048 * side, -0.104, 0.136), Vector((0.016, 0.010, 0.010)), rigid="Head"))
		parts.append(box("Brow", "Skin", at(0.050 * side, -0.104, 0.152), Vector((0.03, 0.02, 0.012)), 0.8, rigid="Head"))
		parts.append(spike("Horn", "Bone", at(0.040 * side, 0.030, 0.205), at(0.060 * side, 0.140, 0.235), 0.016))
	return parts


def tail(J: dict) -> Part:
	"""A kobold's tail: stiff, from under the back of its belt out and down behind it."""
	p = Part("Tail", "Skin")
	p.bones = ["pelvis", "spine_01"]
	pv = J["pelvis"]
	for c, r in [((0, 0.06, -0.01), 0.065), ((0, 0.20, -0.07), 0.052), ((0, 0.36, -0.15), 0.036),
			((0, 0.50, -0.21), 0.020), ((0, 0.60, -0.23), 0.006)]:
		p.add(ring(pv + Vector(c), X, Vector((0, 0.45, 1.0)).normalized(), r, r * 0.85, 8, 0.2))
	return p


def claws(J: dict, side: str) -> list:
	"""A kobold's digging claws: three, past the ends of its mitten's fingers."""
	sign = 1.0 if side == "l" else -1.0
	wr = J["hand_" + side]
	reach = per(1.0, *PROPORTIONS_OF("hands"))
	out = []
	for dy in (-0.028, 0.0, 0.028):
		base = wr + Vector((0.128 * reach * sign, dy, -0.008))
		out.append(spike("Claw", "Bone", base, base + Vector((0.07 * sign, 0.0, -0.035)), 0.016, "middle_02_" + side))
	return out


def kilt(J: dict) -> Part:
	"""An orc's kilt: cloth from its belt down to the middle of its thighs, over the hips."""
	p = Part("Kilt", "Tunic")
	p.bones = ["pelvis", "spine_01", "thigh_l", "thigh_r"]
	rings = torso_rings(J)
	knee = J["calf_l"].z
	low = J["pelvis"].z + (knee - J["pelvis"].z) * 0.5
	hem = rings[0]
	axis = Vector((0, 0, 0))
	for z, flare in [(low, 1.42), ((low + hem[0].z) * 0.5, 1.3)]:
		p.add([Vector((q.x * flare, q.y * flare, z)) for q in hem])
	for r, k in [(rings[0], 1.2), (rings[1], 1.12), (rings[2], 1.06), (rings[3], 1.03)]:
		p.add([Vector((q.x * k, q.y * k, q.z)) for q in r])
	return p


def harness(J: dict) -> list:
	"""An orc's harness: a leather strap from its right hip up across its chest to its left
	shoulder, and on across its back down to the hip again (the torso's rings, followed)."""
	rings = torso_rings(J)
	axis = Vector((0, 0, 0))

	def at(r, f):
		i = int(math.floor(f)) % len(r)
		return r[i].lerp(r[(i + 1) % len(r)], f - math.floor(f))

	out = []
	for name, start, end in [("Harness_Front", 4.6, 1.5), ("Harness_Back", 7.4, 10.5)]:
		p = Part(name, "Belt", follow=True)
		for k in range(3, 8):
			f = start + (end - start) * (k - 3) / 4.0
			a, b = at(rings[k], f - 0.28), at(rings[k], f + 0.28)
			p.add(slab([a, b], axis, 0.008, 0.002))
		out.append(p)
	return out


def collar(J: dict) -> Part:
	"""The tunic's V at the throat: skin, a wedge on the chest's front."""
	p = Part("Collar", "Skin", follow=True)
	n = J["neck_01"]
	y, x = pick(-0.097, -0.090), pick(0.048, 0.042)  # The woman's chest a little shallower at the throat.
	y *= m("torso") * m("neck")
	top_l, top_r, low = n + Vector((x, y + 0.012, 0.012)), n + Vector((-x, y + 0.012, 0.012)), n + Vector((0, y - 0.018, -0.115))
	p.add([top_l, top_r, low]).add([top_l + Vector((0, 0.03, 0)), top_r + Vector((0, 0.03, 0)), low + Vector((0, 0.03, 0))])
	return p


def hair(J: dict, nape: bool) -> Part:
	"""Hair: a cap over the crown and the back of the head, from the temples up; down to
	the [nape] at the back, or cropped above it."""
	p = Part("Hair", "Hair", rigid="Head")
	base = J["Head"]
	kw, kd = pick((1.0, 1.0), (0.95, 0.97))  # head()'s.
	rings = [(0.085, 0.070, 0.090, 0.022), (0.130, 0.085, 0.108, 0.008), (0.165, 0.087, 0.110, 0.003),
		(0.200, 0.082, 0.106, 0.006), (0.230, 0.066, 0.091, 0.010), (0.254, 0.036, 0.054, 0.012)]
	if nape:
		rings = [(0.045, 0.062, 0.080, 0.030)] + rings
	for z, w, d, yc in rings:
		pts = ring(base + Vector((0, yc, z - 0.015)), X, FRONT, w * kw, d * kd, 12, 0.3)
		# The hairline: the face's points (the front five) raised to the forehead, so the
		# lower rings wrap only the back and the sides.
		for i in (2, 3, 4):
			if z < 0.19:
				pts[i] = pts[i] + Z * (0.19 - z) + (-FRONT) * 0.02
		p.add(pts)
	return p


def bun(J: dict) -> Part:
	"""Hair bound up: a bun high on the back of the head."""
	p = Part("Bun", "Hair", rigid="Head")
	c = J["Head"] + Vector((0, 0.105, 0.150))
	out = Vector((0, 1, 0.35)).normalized()  # Back and a little up.
	u = X
	v = out.cross(u).normalized()
	for t, r in [(-0.02, 0.030), (0.0, 0.040), (0.025, 0.040), (0.045, 0.026), (0.055, 0.010)]:
		p.add(ring(c + out * t, u, v, r, r * 0.9, 8, 0.2))
	return p


def belt(J: dict) -> Part:
	p = Part("Belt", "Belt", follow=True)
	z = J["spine_01"].z
	w, d = pick((0.155, 0.105), (0.141, 0.096))  # Just over the tunic's waist (torso()'s s1 ring).
	w, d = w * m("torso") * m("waist"), d * m("torso") * m("waist")
	w, d = w * TORSO_WIDTH.get(PEOPLE, [1.0] * 10)[3] * per(1.0, 1.06, 1.0), d * TORSO_DEPTH.get(PEOPLE, [1.0] * 10)[3] * per(1.0, 1.06, 1.0)
	for dz, dw in [(-0.022, 0.001), (0.022, -0.001)]:
		p.add(ring(Vector((0, -0.005, z + dz)), X, FRONT, w + dw, d + dw, 12, 0.45, (0.01 + m("belly"), 0.0)))
	return p


def outward(p: Vector, axis: Vector) -> Vector:
	"""Level, away from the upright line through [axis]."""
	d = Vector((p.x - axis.x, p.y - axis.y, 0.0))
	return d.normalized() if d.length > 1e-6 else -FRONT


def slab(points: list, axis: Vector, out: float, inside: float) -> list:
	"""A ring that is a thin sheet: [points] pushed [out] from the upright line through
	[axis], then back along themselves [inside] under where they were (a beard over the
	jaw, an apron over the tunic). Closed, so it lofts and its faces turn outward."""
	front = [q + outward(q, axis) * out for q in points]
	back = [q - outward(q, axis) * inside for q in reversed(points)]
	return front + back


def beard(J: dict, full: bool) -> list:
	"""A beard over the jaw, ear to ear: from under the jaw (short) or a hanging point below
	the chin (full) up to the sideburns and the moustache, as the head's own rings, out."""
	p = Part("Beard", "Hair", rigid="Head")
	rings = head_rings(J)
	axis = J["Head"] + Vector((0, -0.004, 0))
	cols = range(0, 7)  # Ear (0, +X) round the front (3) to ear (6).
	jaw, chin, mouth, nose = rings[0], rings[1], rings[2], rings[3]
	# The top: sideburns to the nose line at the ears, falling across the cheeks to the
	# mouth's corners, the moustache between the mouth and the nose.
	top = [mouth[i].lerp(nose[i], {0: 1.0, 1: 0.35, 2: 0.15, 3: 0.55, 4: 0.15, 5: 0.35, 6: 1.0}[i]) for i in cols]
	rows = []
	if full:
		for drop, narrow, fwd in [(0.085, 0.4, 0.035), (0.045, 0.8, 0.02)]:
			rows.append([Vector((chin[i].x * narrow, chin[i].y - fwd, chin[i].z - drop)) for i in cols])
		rows += [[chin[i] for i in cols]]
	else:
		rows += [[jaw[i] for i in cols], [chin[i] for i in cols]]
	rows += [[mouth[i] for i in cols], top]
	out = 0.012 if full else 0.006
	for r in rows:
		p.add(slab(r, axis, out, 0.004))
	return [p]


def curtain(J: dict) -> Part:
	"""Long hair's fall down the back, from the back of the head to below the shoulders."""
	p = Part("Hair_Fall", "Hair")
	p.bones = ["Head", "neck_01", "spine_03"]
	h = J["Head"]
	axis = h + Vector((0, -0.2, 0))  # Out from in front: the sheet bows back.
	kw = pick(1.0, 0.95)
	for z, w, y in [(0.10, 0.080, 0.112), (0.04, 0.078, 0.104), (-0.04, 0.085, 0.112), (-0.12, 0.092, 0.128)]:
		pts = [h + Vector((w * kw * s, y + 0.008 * (1.0 - abs(s)), z)) for s in (-1.0, -0.5, 0.0, 0.5, 1.0)]
		p.add(slab(pts, axis, 0.006, 0.006))
	p.pins = {3: "Head"}  # The top, under the cap, with the head.
	return p


def hood(J: dict) -> list:
	"""A hood: a cloth cap over the head, open round the face and closed under it, its cowl
	down onto the shoulders."""
	p = Part("Hood", "Hat")
	p.bones = ["Head", "neck_01", "spine_03"]
	base = J["Head"] + Vector((0, 0, -0.015))
	kw, kd = pick((1.0, 1.0), (0.95, 0.97))
	for z, w, d, yc in [(-0.075, 0.150, 0.125, 0.015), (-0.02, 0.100, 0.112, 0.005), (0.045, 0.090, 0.112, 0.020),
			(0.100, 0.100, 0.122, 0.012), (0.150, 0.104, 0.126, 0.006), (0.200, 0.100, 0.124, 0.010),
			(0.240, 0.080, 0.106, 0.016), (0.270, 0.040, 0.060, 0.020)]:
		pts = ring(base + Vector((0, yc, z)), X, FRONT, w * kw, d * kd, 12, 0.3)
		# The face's opening: the middle of the front raised to the brow, the cheeks' sides
		# kept, on the rings from the chin up.
		if 0.03 < z < 0.2:
			for i in (2, 3, 4):
				pts[i] = pts[i] + Z * (0.2 - z) + (-FRONT) * 0.015
			# Its corners out to the temples, so the opening's sides clear the cheeks.
			pts[2] = pts[2] + X * 0.022
			pts[4] = pts[4] - X * 0.022
		elif z < 0.0 and z > -0.05:
			# Under the chin, tucked back under the jaw (the opening's lower edge).
			for i in (2, 3, 4):
				pts[i] = pts[i] + (-FRONT) * 0.05
		p.add(pts)
	return [p]


def brimmed_hat(J: dict) -> list:
	"""A hat with a round brim, sat on the brow."""
	p = Part("Hat", "Hat", rigid="Head")
	base = J["Head"] + Vector((0, 0.004, -0.015))
	kw, kd = pick((1.0, 1.0), (0.95, 0.97))
	for z, w, d in [(0.178, 0.170, 0.180), (0.188, 0.170, 0.180), (0.190, 0.092, 0.114), (0.262, 0.088, 0.108),
			(0.286, 0.062, 0.080)]:
		p.add(ring(base + Vector((0, 0, z)), X, FRONT, w * kw, d * kd, 12, 0.2))
	return [p]


def apron(J: dict) -> list:
	"""An apron: a bib from the chest over the belly and down past the hem to the knees, on
	the tunic's front."""
	p = Part("Apron", "Apron")
	p.bones = ["pelvis", "spine_01", "spine_02", "spine_03", "thigh_l", "thigh_r"]
	rings = torso_rings(J)[:6]  # Hem to chest.
	axis = Vector((0, 0, 0))

	def front(r):
		# The middle of the front: from a little outside the eyes' columns (2, 4) in.
		return [r[2].lerp(r[1], 0.15), r[2].lerp(r[3], 0.45), r[3], r[4].lerp(r[3], 0.45), r[4].lerp(r[5], 0.15)]

	hem = front(rings[0])
	knee = (J["calf_l"].z + 0.06)
	rows = []
	for z in (knee, (knee + hem[2].z) * 0.5):
		# Below the hem it hangs straight down, as wide as at the hem.
		rows.append([Vector((q.x, q.y, z)) for q in hem])
	rows += [front(r) for r in rings]
	for r in rows:
		p.add(slab(r, axis, 0.016, 0.0))
	return [p]


def miner_cap(J: dict) -> list:
	"""A kobold's miner's cap: leather over the crown behind its horns, a candle stub on it."""
	p = Part("Cap", "Hat", rigid="Head")
	base = J["Head"] + Vector((0, 0.01, -0.015))
	for z, w, d, yc in [(0.170, 0.078, 0.096, 0.004), (0.200, 0.084, 0.104, 0.006), (0.232, 0.072, 0.092, 0.010),
			(0.258, 0.040, 0.054, 0.012)]:
		p.add(ring(base + Vector((0, yc, z)), X, FRONT, w, d, 12, 0.3))
	candle = Part("Candle", "Bone", rigid="Head")
	for z, r in [(0.250, 0.016), (0.300, 0.016), (0.304, 0.008)]:
		candle.add(ring(base + Vector((0, -0.01, z)), X, FRONT, r, r, 6))
	return [p, candle]


## The parts a person may wear, by name: each its own mesh on the skeleton, shape-keyed
## as the body is, shown or not by the game. Bald is no hair part.
WEARABLES = {
	"Hair_Cropped": lambda J: [hair(J, nape=False)],
	"Hair_Bound": lambda J: [hair(J, nape=True), bun(J)],
	"Hair_Long": lambda J: [hair(J, nape=True), curtain(J)],
	"Beard_Short": lambda J: beard(J, full=False),
	"Beard_Full": lambda J: beard(J, full=True),
	"Hood": hood,
	"Hat_Brimmed": brimmed_hat,
	"Apron": apron,
}
## An ally's own (decision 478): an orc may crop or bind its hair (a topknot); a kobold wears
## its cap or goes bare-headed.
PEOPLE_WEARABLES = {
	"orc": ["Hair_Cropped", "Hair_Bound"],
	"kobold": ["Cap_Candle"],
}
WEARABLES["Cap_Candle"] = miner_cap


## Each region's material, made once.
_materials = {}


def assemble(J: dict, which: str = "Body"):
	"""The body (which "Body") or a WEARABLES part, by MORPH, as meshes on their bones,
	joined into one object named [which], a material a region. What moves with the head (the
	Head bone, or as near) grows by MORPH's "head" about the Head bone."""
	if which == "Body":
		parts = [torso(J), belt(J), neck(J), head(J)] + per([collar(J)], [], []) + face(J)
		parts += per([], [kilt(J)] + harness(J), [tail(J)])
		for side in ("l", "r"):
			parts += [sleeve(J, side), leg(J, side), boot(J, side), hand(J, side), thumb(J, side)]
			if PEOPLE == "kobold":
				parts += claws(J, side)
	else:
		parts = WEARABLES[which](J)
	# A kobold's head large for its body.
	grow = m("head") * per(1.0, 1.0, 1.55)
	for p in parts:
		if (p.rigid == "Head" or "Head" in p.bones) and grow != 1.0:
			p.rings = [[J["Head"] + (q - J["Head"]) * grow for q in r] for r in p.rings]
	objects = [p.mesh(J) for p in parts]
	for obj in objects:
		region = obj["region"]
		if region not in _materials:
			_materials[region] = bpy.data.materials.new(region)
		obj.data.materials.append(_materials[region])
	bpy.ops.object.select_all(action="DESELECT")
	for obj in objects:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = objects[0]
	if len(objects) > 1:
		bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.name = which
	# Every face outward (the lofts wind either way, by the side they're on and which way
	# their rings run): the game culls back faces.
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bm.to_mesh(body.data)
	bm.free()
	for poly in body.data.polygons:
		poly.use_smooth = False
	return body


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <UAL1.glb> <out.glb> [--height M] [--sex male|female] [--people human|orc|kobold]")
	ual, out = (os.path.abspath(p) for p in a[:2])
	global SEX, PEOPLE
	SEX = a[a.index("--sex") + 1] if "--sex" in a else "male"
	if SEX not in HEIGHTS:
		raise SystemExit("--sex is male or female")
	PEOPLE = a[a.index("--people") + 1] if "--people" in a else "human"
	if PEOPLE not in ("human", "orc", "kobold"):
		raise SystemExit("--people is human, orc or kobold")
	if PEOPLE != "human" and SEX != "male":
		raise SystemExit("--sex is a human's (an orc's and a kobold's bodies are one)")
	height = float(a[a.index("--height") + 1]) if "--height" in a else PEOPLE_HEIGHTS.get(PEOPLE, HEIGHTS[SEX])
	bpy.ops.wm.read_factory_settings(use_empty=True)
	if PEOPLE == "human":
		arm, J = skeleton(ual, BUILD_HEIGHT)
	else:
		arm, J = people_skeleton(ual, 1.0)
	global MORPH
	objects = []
	for which in ["Body"] + PEOPLE_WEARABLES.get(PEOPLE, [w for w in WEARABLES if w != "Cap_Candle"]):
		obj = assemble(J, which)
		# The shape keys: it built again by each KEYS' proportions.
		obj.shape_key_add(name="Basis", from_mix=False)
		for name, morph in KEYS.items():
			MORPH = morph
			other = assemble(J, which)
			MORPH = {}
			if len(other.data.vertices) != len(obj.data.vertices):
				raise SystemExit("%s key %s: %d vertices, %d unkeyed" % (which, name, len(other.data.vertices), len(obj.data.vertices)))
			key = obj.shape_key_add(name=name, from_mix=False)
			for v, w in zip(key.data, other.data.vertices):
				v.co = w.co.copy()
			mesh = other.data
			bpy.data.objects.remove(other)
			bpy.data.meshes.remove(mesh)
		obj.name = which  # The key builds took the name for a moment.
		objects.append(obj)
	if PEOPLE != "human":
		# Built at the UAL's BUILD_HEIGHT on the people's joints: scaled whole so the body's
		# top (its head's, not a cap's or a horn's) is at the height, its skeleton with it.
		from mathutils import Matrix
		body = objects[0]
		top = max(v.co.z for v in body.data.vertices)
		s = height / top
		for obj in objects:
			obj.data.transform(Matrix.Scale(s, 4), shape_keys=True)
		bpy.data.objects.remove(arm)
		arm, J = people_skeleton(ual, s)
		print("people %s: built %.3f m tall, scaled %.3f" % (PEOPLE, top, s))
	elif abs(height - BUILD_HEIGHT) > 1e-4:
		# Built at BUILD_HEIGHT: the meshes scaled to the height, onto the skeleton at it (the
		# weights are by bone name, so they carry over).
		from mathutils import Matrix
		for obj in objects:
			obj.data.transform(Matrix.Scale(height / BUILD_HEIGHT, 4), shape_keys=True)
		bpy.data.objects.remove(arm)
		arm, J = skeleton(ual, height)
	for obj in objects:
		skin(obj, arm, J)
		tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
		lo = min(v.co.z for v in obj.data.vertices)
		hi = max(v.co.z for v in obj.data.vertices)
		print("built %s: %d tris, %.3f..%.3f m" % (obj.name, tris, lo, hi))
	print("keys: %s" % "/".join(KEYS))
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	for obj in objects:
		obj.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_morph=True, export_morph_normal=False, export_animations=False)
	print("wrote %s" % out)


if __name__ == "__main__":
	main()
