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
# Jeff's p1 of art-gen's redo v7, "sleek scaly climber, long tail": slight, a long snout, swept
# ears, a crest, clawed hands, a long whip tail, a loincloth; light red shading to purple on
# its limbs and tail, the scales in the faceting). On
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
## A person's surface smooth-shaded, an edge whose faces turn more than this (degrees) kept sharp
## (419 amended; --sharp-angle for a trial).
SHARP_ANGLE = 55.0


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
	"orc": {"legs": 0.84, "arms": 1.16, "shoulders": 1.7, "hips": 1.2, "spine": 1.0, "neck": 0.9,
		"hands": 1.5, "feet": 1.3},
	"kobold": {"legs": 0.66, "arms": 1.0, "shoulders": 1.05, "hips": 0.92, "spine": 0.84, "neck": 0.55,
		"hands": 1.55, "feet": 1.6},
}
## Each lofted part's density by people (Part.densify): its rings' points and the rings between
## stations each this many times over (the orc's revision, 478 amended: rounder at about 10k
## triangles of its 12k budget; the humans and the kobold as built). A ring of fewer than
## DENSE_MIN points is left (the face's little boxes, the chain's links).
DENSITY_OF = (2, 1)
DENSE_MIN = 5
## The torso's rings (torso_rings' ten) widened or narrowed by people: across, front to back.
TORSO_WIDTH = {
	"orc": [1.2, 1.18, 1.18, 1.3, 1.5, 1.85, 2.05, 2.05, 2.3, 1.8],
	"kobold": [1.0, 0.98, 0.95, 0.86, 0.94, 1.08, 1.1, 1.08, 0.9, 0.9],
}
TORSO_DEPTH = {
	"orc": [1.2, 1.2, 1.25, 1.35, 1.5, 1.7, 1.75, 1.7, 1.85, 1.6],
	"kobold": [1.08, 1.04, 1.0, 0.98, 1.04, 1.1, 1.0, 0.95, 0.88, 0.88],
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
ADDED = ("belly", "sag", "nose", "brow", "cheeks", "eyes")


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
	# The face's planes (decision 480), each 0..1 from the base face: a broad, square jaw; a
	# long nose, its tip further out and lower; a heavy brow ridge; high cheekbones, out
	# and forward; deep-set eyes, the sockets further in under the brow.
	"jaw": {"jaw": 1.2},
	"nose": {"nose": 1.0},
	"brow": {"brow": 1.0},
	"cheeks": {"cheeks": 1.0},
	"eyes": {"eyes": 1.0},
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
		# Its last ring joined back to its first, no caps: a loop (a chain's link).
		self.closed = False
		# Left as built by densify (a small part: a finger, a toe, a rivet).
		self.sparse = False

	def add(self, points: list) -> "Part":
		self.rings.append(points)
		return self

	def densify(self, d: int) -> None:
		"""Each ring [d] times its points round a smooth closed curve, and [d] - 1 rings put
		between each two along a smooth path (Catmull-Rom both ways): rounder sections, more
		segments, the part's shape kept. Rings of fewer than DENSE_MIN points are left."""
		if d <= 1 or self.closed or self.sparse or len(self.rings[0]) < DENSE_MIN:
			return

		def cr(p0, p1, p2, p3, t):
			t2, t3 = t * t, t * t * t
			return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

		rings = []
		for r in self.rings:
			n = len(r)
			out = []
			for i in range(n):
				for s in range(d):
					out.append(r[i].copy() if s == 0 else cr(r[i - 1], r[i], r[(i + 1) % n], r[(i + 2) % n], s / d))
			rings.append(out)
		m = len(rings)
		along = []
		for k in range(m):
			along.append(rings[k])
			if k == m - 1:
				break
			a, b = rings[max(0, k - 1)], rings[min(m - 1, k + 2)]
			for s in range(1, d):
				along.append([cr(a[i], rings[k][i], rings[k + 1][i], b[i], s / d) for i in range(len(rings[k]))])
		self.rings = along
		self.pins = {k * d: bone for k, bone in self.pins.items()}
		self.mixes = {k * d: mix for k, mix in self.mixes.items()}

	def mesh(self, J: dict, cap_start: bool = True, cap_end: bool = True):
		self.densify(per(1, *DENSITY_OF))
		verts, faces = [], []
		n = len(self.rings[0])
		for r in self.rings:
			verts.extend(r)
		for k in range(len(self.rings) - (0 if self.closed else 1)):
			nxt = (k + 1) % len(self.rings)
			for i in range(n):
				faces.append((k * n + i, k * n + (i + 1) % n, nxt * n + (i + 1) % n, nxt * n + i))
		if cap_start and not self.closed:
			faces.append(tuple(reversed(range(n))))
		if cap_end and not self.closed:
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
	p = Part("Tunic", per("Tunic", "Skin", "Skin"))  # An orc's chest bare, a kobold's.
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
	# A kobold's arms its limbs' purple (the "Trousers" tint; decision 478's restyle).
	p = Part("Sleeve_" + side, per("Tunic", "Skin", "Trousers"))
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
	if PEOPLE == "orc":
		# The revision (478 amended): a capped deltoid, the biceps, an elbow, a heavy forearm
		# swelling below it, the wrist thick.
		stations = [(inner + down, 0.052, 0.075), (sh + along * 0.03 + down, 0.066, 0.080), (sh.lerp(el, 0.3), 0.060, 0.062),
			(sh.lerp(el, 0.6), 0.062, 0.060), (el, 0.046, 0.048), (el.lerp(wr, 0.3), 0.058, 0.054),
			(el.lerp(wr, 0.65), 0.050, 0.046), (wr - along * 0.01, 0.040, 0.036)]
	k = pick(1.0, 0.86) * m("arms") * per(1.0, 2.4, 1.45)  # The woman's arms slighter, an orc's massive.
	for c, rv, ru in stations:
		# u forward, v up: the arm's front-to-back depth and its height.
		p.add(ring(c, FRONT, Z, ru * k, rv * k, 8, 0.3))
	return p


def leg(J: dict, side: str) -> Part:
	"""A leg in its trousers: from inside the hip to the boot top."""
	p = Part("Leg_" + side, per("Trousers", "Skin", "Trousers"))  # An orc's legs bare.
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
		back = per({1: 0.018, 4: 0.012}, {1: 0.03, 4: 0.05, 5: 0.02}, {1: 0.018, 4: 0.012}).get(k, 0.0)  # The seat; the calf.
		f = scale[k] * m("legs") * (m("thighs") if k < 2 else 1.0) * per(1.0, [1.9, 1.9, 1.85, 1.55, 1.75, 1.45, 1.32][k], 1.45 if k < 3 else 1.4)
		# (2) A kobold's leg digitigrade on the same bones: the knee a little forward, the hock
		# (three quarters down the calf) well back, the shin slanting down and forward from it.
		bend = per(0.0, 0.0, [0.0, 0.0, -0.01, -0.045, -0.01, 0.075, 0.03][k])
		p.add(ring(c + Vector((dx * out, bend, 0)), X, FRONT, ru * f, rv * f, 8, 0.25, (0.0, back)))
	return p


def boot(J: dict, side: str) -> Part:
	"""A boot: a shaft from below the knee to the ankle, then the foot to the toe, flat soled."""
	p = Part("Boot_" + side, per("Boots", "Skin", "Trousers"))  # An orc's feet bare.
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


def orc_foot(J: dict, side: str) -> list:
	"""An orc's bare foot (the revision, 478 amended: "the calves and feet shaped"): out of
	the ankle, a rounded heel behind it, the instep high, broad across the ball; five toes,
	the big one inside, on the ball's bone."""
	p = Part("Foot_" + side, "Skin")
	p.bones = ["calf_" + side, "foot_" + side, "ball_" + side]
	ankle, ball, toe = J["foot_" + side], J["ball_" + side], J["ball_" + side + ".tail"]
	x = ankle.x
	k = 1.3
	# Its top tucked inside the leg's end (leg()'s last ring, 0.04 over the ankle), so no cuff.
	for c, r in [(ankle + Vector((0, 0, 0.08)), 0.042), (ankle + Vector((0, 0, 0.04)), 0.046), (ankle + Vector((0, 0.004, 0.0)), 0.05)]:
		p.add(ring(c, X, FRONT, r * k, r * 1.04 * k, 8, 0.25))
	for y, w, h in [(ankle.y + 0.085, 0.040, 0.075), (ankle.y + 0.055, 0.050, 0.100), (ankle.y - 0.02, 0.054, 0.105),
			(ball.y + 0.06, 0.060, 0.072), (ball.y + 0.01, 0.066, 0.050), (ball.y - 0.025, 0.062, 0.038)]:
		p.add(ring(Vector((x, y, h * 0.5 + 0.004)), X, Z, w * k, h * 0.5, 8, 0.45))
	out = [p]
	inner = -1.0 if x > 0 else 1.0  # Toward the body's middle.
	for dx, r, length in [(0.044, 0.019, 0.056), (0.017, 0.014, 0.050), (-0.004, 0.0135, 0.045), (-0.024, 0.0125, 0.040),
			(-0.043, 0.0115, 0.034)]:
		t = Part("Toe", "Skin", rigid="ball_" + side)
		t.sparse = True
		base = Vector((x + dx * inner * k, ball.y - 0.015, r * k + 0.004))
		for f, kk, dz in [(0.0, 1.0, 0.0), (0.6, 0.95, -0.002), (1.0, 0.7, -0.006)]:
			t.add(ring(base + Vector((0, -length * k * f, dz)), X, Z, r * k * kk, r * k * kk * 0.85, 6, 0.3))
		out.append(t)
	return out


def kobold_foot(J: dict, side: str) -> list:
	"""A kobold's foot, as the leg's digitigrade bend goes on: from the hock-high ankle down
	and forward along its long sole to the toes, the heel off the ground; four claws."""
	p = Part("Foot_" + side, "Trousers")
	p.bones = ["calf_" + side, "foot_" + side, "ball_" + side]
	ankle, ball, toe = J["foot_" + side], J["ball_" + side], J["ball_" + side + ".tail"]
	x = ankle.x
	for y, z, w, h in [(ankle.y + 0.03, ankle.z + 0.03, 0.050, 0.050), (ankle.y - 0.01, ankle.z - 0.01, 0.052, 0.046),
			(ball.y + 0.04, 0.045, 0.060, 0.040), (ball.y - 0.01, 0.025, 0.066, 0.030), (toe.y + 0.02, 0.016, 0.060, 0.022)]:
		p.add(ring(Vector((x, y, z)), X, Z, w, h * 0.5, 8, 0.5))
	out = [p]
	for dx in (-0.042, -0.014, 0.014, 0.042):
		base = Vector((x + dx, toe.y + 0.01, 0.014))
		out.append(spike("Toe_Claw", "Bone", base, base + Vector((dx * 0.25, -0.05, -0.012)), 0.012, "ball_" + side))
	return out


def hand(J: dict, side: str) -> Part:
	"""A mitten, palm down, along X from the wrist: the fingers one block, the thumb forward."""
	sign = 1.0 if side == "l" else -1.0
	p = Part("Hand_" + side, "Skin")
	p.bones = ["lowerarm_" + side, "hand_" + side, "middle_01_" + side, "middle_02_" + side]
	wr = J["hand_" + side]
	k = pick(1.0, 0.88) * m("hands") * per(1.0, 1.75, 1.6)  # The woman's hands narrower and thinner.
	reach = per(1.0, *PROPORTIONS_OF("hands"))  # As long as the skeleton's fingers.
	stations = [(-0.015, 0.036, 0.028), (0.02, 0.050, 0.027), (0.065, 0.053, 0.023), (0.105, 0.048, 0.018),
		(0.135, 0.034, 0.013)]
	if PEOPLE == "orc":
		# The palm to the knuckles only, its fingers their own (fingers()).
		stations = [(-0.015, 0.034, 0.026), (0.02, 0.044, 0.026), (0.065, 0.047, 0.024), (0.105, 0.045, 0.020)]
	for dx, w, h in stations:
		p.add(ring(wr + Vector((dx * reach * sign, 0, -0.005)), FRONT, Z, w * k, h * k, 8, 0.6))
	return p


def fingers(J: dict, side: str) -> list:
	"""An orc's four fingers and its thumb (the revision, 478 amended: "hands with fingers"):
	each a thick tapering loft along its own bones from inside the palm, weighted to them,
	so the clips' fists close them."""
	out = []
	for name, r in [("index", 0.019), ("middle", 0.020), ("ring", 0.019), ("pinky", 0.016), ("thumb", 0.022)]:
		p = Part("Finger_" + side, "Skin")
		p.sparse = True
		bones = [name + "_0%d_" % i + side for i in (1, 2, 3)]
		p.bones = ["hand_" + side] + bones
		leaf = J[name + "_04_leaf_" + side]
		points = [J[b] for b in bones] + [leaf]
		# From back in the palm (the thumb's root inside the hand's heel).
		start = points[0] + (points[0] - points[1]).normalized() * (0.012 if name == "thumb" else 0.025)
		path = [start] + points
		along = (leaf - points[0]).normalized()
		u = along.cross(Z).normalized() if abs(along.z) < 0.9 else X
		v = u.cross(along).normalized()
		for i, c in enumerate(path):
			k = [1.05, 1.0, 0.94, 0.86, 0.72][i]
			p.add(ring(c + Vector((0, 0, -0.004)), u, v, r * k, r * k * 0.85, 6, 0.3))
		p.pins = {0: "hand_" + side}
		out.append(p)
	return out


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
	stations = [(n + Vector((0, 0, -0.01)), 0.066, 0.0), (n.lerp(h, 0.5), 0.060, 0.008),
		(h + Vector((0, 0.005, 0.03)), 0.060, 0.014)]
	if PEOPLE == "orc":
		# The revision (478 amended): a neck to be seen, broad at its foot where the
		# trapezius slopes into the shoulders, thick up into the jaw.
		stations = [(n + Vector((0, 0.01, -0.04)), 0.085, 0.0), (n + Vector((0, 0.005, -0.005)), 0.068, 0.0),
			(n.lerp(h, 0.5), 0.058, 0.006), (h + Vector((0, 0.005, 0.03)), 0.060, 0.014)]
	for c, r, fwd in stations:
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
	if PEOPLE == "orc":
		return orc_head_rings(J)
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
	jaw_wide = per({}, {}, {0.010: 0.8, 0.040: 0.72, 0.070: 0.7, 0.102: 0.72})
	for z, w, d, yc, push in stations:
		w, d, push = w * kw * jaw_wide.get(z, per(1.0, 1.04, 0.86)), d * kd, push * kp
		if z < 0.08:
			w *= 1.0 + (m("jaw") - 1.0) * (1.0 if z > 0.02 else 0.6)  # The jaw's key: the chin and jaw wider.
		if abs(z - 0.102) < 0.01:
			push += 0.014 * m("nose")
		if abs(z - 0.158) < 0.01:
			push += 0.010 * m("brow")
		pts = ring(base + Vector((0, yc, z)), X, FRONT, w, d, 12, 0.3, (0.0, 0.012 if 0.09 < z < 0.23 else 0.0))
		# The face's middle point (straight ahead, index 3: +v, FRONT) pushed out: chin, nose
		# line, brows; its neighbours (2, 4: the eyes' columns) in at the eyes' height (the
		# sockets) and out at the brows' (the ridge); the cheeks (1, 5) out at the cheekbones.
		pts[3] = pts[3] + FRONT * push
		if abs(z - 0.132) < 0.01:
			pts[2] = pts[2] - FRONT * (0.012 + 0.008 * m("eyes"))
			pts[4] = pts[4] - FRONT * (0.012 + 0.008 * m("eyes"))
			cheek = 0.006 + 0.008 * m("cheeks")
			pts[1] = pts[1] + FRONT * cheek + X * (0.004 + 0.006 * m("cheeks"))
			pts[5] = pts[5] + FRONT * cheek - X * (0.004 + 0.006 * m("cheeks"))
		if abs(z - 0.158) < 0.01:
			pts[2] = pts[2] + FRONT * (0.008 + 0.010 * m("brow"))
			pts[4] = pts[4] + FRONT * (0.008 + 0.010 * m("brow"))
		if abs(z - 0.040) < 0.01:
			# A squarer jaw: its corners out (the man's); the woman's in, toward a narrower chin.
			jaw = per(pick(0.006, -0.004), 0.016, 0.0)
			pts[1] = pts[1] + X * jaw
			pts[5] = pts[5] - X * jaw
		if PEOPLE == "kobold":
			out = SNOUT.get(z, 0.0)
			if abs(z - 0.070) < 0.01:
				# The mouth's line: the snout's sides drawn in between the jaw and the muzzle.
				pts[2] = pts[2] + X * 0.012
				pts[4] = pts[4] - X * 0.012
			pts[3] = pts[3] + FRONT * out
			pts[2] = pts[2] + FRONT * out * 0.85
			pts[4] = pts[4] + FRONT * out * 0.85
			pts[1] = pts[1] + FRONT * out * 0.4
			pts[5] = pts[5] + FRONT * out * 0.4
		rings.append(pts)
	return rings


## An orc's head (the revision, 478 amended: "the head bigger with a jaw and brow"), off
## Jeff's p2 front and side: (height above the head bone less 0.015, half-width, the face's
## front, the back of the head, squareness), under the jaw to the top. The jaw as wide as the
## skull and thrust forward past it, the lower lip out, the nose's line back, the eyes deep
## under a ridge of brow, the forehead sloping back to a low crown.
ORC_HEAD = [
	(-0.008, 0.074, -0.070, 0.026, 0.3),  # Under the jaw, at the neck.
	(0.030, 0.098, -0.108, 0.050, 0.45),  # The jaw and the chin.
	(0.056, 0.104, -0.122, 0.064, 0.45),  # The lower lip, the tusks' roots.
	(0.080, 0.098, -0.104, 0.072, 0.4),   # The upper lip.
	(0.104, 0.094, -0.100, 0.078, 0.4),   # Under the nose, the cheeks.
	(0.124, 0.092, -0.094, 0.082, 0.4),   # The eyes.
	(0.146, 0.090, -0.102, 0.082, 0.4),   # The brow's ridge.
	(0.170, 0.084, -0.086, 0.080, 0.4),   # The forehead, sloping back.
	(0.196, 0.068, -0.054, 0.068, 0.3),   # The crown.
	(0.214, 0.036, -0.012, 0.036, 0.2),   # The top.
]


def orc_head_rings(J: dict) -> list:
	"""The orc's head rings of 12 (ORC_HEAD), by MORPH's face keys: the jaw wider, the brow
	heavier, the cheeks fuller, the eyes deeper."""
	base = J["Head"] + Vector((0, 0.0, -0.015))
	rings = []
	for z, w, front, back, sq in ORC_HEAD:
		if z < 0.06:
			w *= m("jaw")
		if abs(z - 0.104) < 0.01:
			w *= 1.0 + 0.5 * (m("cheeks") - 1.0)
		if abs(z - 0.146) < 0.01:
			front -= 0.01 * (m("brow") - 1.0)
		d = (back - front) * 0.5
		pts = ring(base + Vector((0, (front + back) * 0.5, z)), X, FRONT, w, d, 12, sq)
		if abs(z - 0.124) < 0.01:
			# The sockets: the eyes' columns back under the brow.
			for i in (2, 4):
				pts[i] = pts[i] - FRONT * (0.012 + 0.006 * (m("eyes") - 1.0))
		if abs(z - 0.146) < 0.01:
			# The ridge across, not only at the middle.
			for i in (2, 4):
				pts[i] = pts[i] + FRONT * 0.007
		if 0.02 < z < 0.07:
			# The jaw's corners out under the cheeks, a heavy square chin.
			pts[1] = pts[1] + X * 0.01 + FRONT * 0.012
			pts[5] = pts[5] - X * 0.01 + FRONT * 0.012
			pts[2] = pts[2] + FRONT * 0.01
			pts[4] = pts[4] + FRONT * 0.01
		rings.append(pts)
	return rings


## A kobold's snout: how far its face's front comes forward, by head_rings' height.
SNOUT = {0.010: 0.03, 0.040: 0.11, 0.070: 0.125, 0.102: 0.12, 0.132: 0.045, 0.158: 0.012}


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
	top, tip = at(0, -0.100 - 0.008 * m("brow"), 0.150), at(0, per(pick(-0.128, -0.124), -0.118) - 0.014 * m("nose"), 0.098 - 0.008 * m("nose"))
	if PEOPLE == "orc":
		# Broad and flat, its tip just out from the upper lip's line.
		top, tip = at(0, -0.090, 0.140), at(0, -0.124 - 0.01 * m("nose"), 0.096)
	for t, w in [(0.0, 0.010), (0.7, per(pick(0.016, 0.013), 0.034)), (1.0, per(pick(0.012, 0.010), 0.03))]:
		c = top.lerp(tip, t)
		nose.add([c + Vector((-w, 0.012, 0)), c + Vector((0, -0.004, 0)), c + Vector((w, 0.012, 0))])
	parts.append(nose)
	for side in (1.0, -1.0):
		if PEOPLE == "orc":
			# Small eyes deep in their sockets under the ridge; no brows (the ridge is them).
			parts.append(box("Eye", "Belt", at(0.034 * side, -0.090, 0.124), Vector((0.016, 0.006, 0.008)), rigid="Head"))
			parts.append(box("Ear", "Skin", at(0.090 * side, 0.036, 0.132), Vector((0.012, 0.055, 0.03)), 0.35, rigid="Head"))
			parts.append(tusk(at(0.046 * side, -0.118, 0.040), side))
			continue
		parts.append(box("Brow", "Hair", at(0.030 * side, -0.100 - 0.010 * m("brow"), 0.150), Vector((0.032, 0.012, pick(0.008, 0.005))), rigid="Head"))
		parts.append(box("Eye", "Belt", at(0.030 * side, -0.090 + 0.008 * m("eyes"), 0.130), Vector((0.016, 0.006, 0.008)), rigid="Head"))
		parts.append(box("Ear", "Skin", at(0.080 * side, 0.004, 0.120), Vector((0.012, 0.030, pick(0.045, 0.040))), 0.8, rigid="Head"))
	return parts


def tusk(base: Vector, side: float) -> Part:
	"""An orc's tusk (the revision, 478 amended: "modelled, not pegs"): thick at the lower
	jaw, curving up past the upper lip, out and a little back, to a blunt point."""
	p = Part("Tusk", "Bone", rigid="Head")
	path = [(Vector((0, 0, 0)), 1.0), (Vector((0.004, -0.010, 0.026)), 0.92), (Vector((0.011, -0.012, 0.052)), 0.78),
		(Vector((0.020, -0.006, 0.074)), 0.55), (Vector((0.028, 0.006, 0.090)), 0.18)]
	for i, (d, k) in enumerate(path):
		c = base + Vector((d.x * side, d.y, d.z))
		nxt = path[min(i + 1, len(path) - 1)][0] - path[max(i - 1, 0)][0]
		along = Vector((nxt.x * side, nxt.y, nxt.z)).normalized()
		u = along.cross(X).normalized()
		v = along.cross(u).normalized()
		p.add(ring(c, u, v, 0.019 * k, 0.016 * k, 6, 0.2))
	return p


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
	sides under a ridge, long ears swept back, a crest of spines from the brow over the crown
	(the "Hair" tint: its little fur)."""
	base = J["Head"] + Vector((0, 0.0, -0.015))
	at = lambda x, y, z: base + Vector((x, y, z)) * 1.0
	parts = []
	for side in (1.0, -1.0):
		parts.append(box("Nostril", "Belt", at(0.018 * side, -0.218, 0.100), Vector((0.010, 0.006, 0.006)), rigid="Head"))
		parts.append(box("Eye", "Belt", at(0.048 * side, -0.104, 0.136), Vector((0.016, 0.010, 0.010)), rigid="Head"))
		parts.append(box("Brow", "Skin", at(0.050 * side, -0.104, 0.152), Vector((0.03, 0.02, 0.012)), 0.8, rigid="Head"))
		parts.append(spike("Ear", "Skin", at(0.072 * side, 0.020, 0.150), at(0.175 * side, 0.110, 0.180), 0.030))
	for y, z, lean in [(-0.035, 0.232, 0.025), (0.0, 0.245, 0.035), (0.035, 0.240, 0.04), (0.07, 0.222, 0.045),
			(0.10, 0.195, 0.045)]:
		for x, up in [(0.0, 0.038), (0.02, 0.025), (-0.02, 0.025)]:
			parts.append(spike("Crest", "Hair", at(x, y, z - abs(x) * 0.4), at(x * 1.5, y + lean, z + up), 0.014))
	for side in (1.0, -1.0):
		# Teeth: two at the front of the jaw, over the lip.
		parts.append(spike("Tooth", "Bone", at(0.022 * side, -0.198, 0.062), at(0.024 * side, -0.203, 0.040), 0.007))
	return parts


def ruff(J: dict) -> list:
	"""A kobold's ruff: spines down the back of its neck to its shoulders (its little fur)."""
	n, s3 = J["neck_01"], J["spine_03"]
	out = []
	for t, x in [(0.2, 0.0), (0.5, 0.0), (0.8, 0.0), (0.7, 0.04), (0.7, -0.04)]:
		c = s3.lerp(n, t) + Vector((x, 0.07, 0.02))
		out.append(spike("Ruff", "Hair", c, c + Vector((x * 0.5, 0.03, 0.015)), 0.012, "neck_01" if t > 0.5 else "spine_03"))
	return out


def tail(J: dict) -> Part:
	"""A kobold's tail: long and whip-thin, from under the back of its belt down behind it and
	curling up at its tip; held with the hips (rigid on the pelvis), so the legs swing clear."""
	p = Part("Tail", "Trousers", rigid="pelvis")
	pv = J["pelvis"]
	path = [((0, 0.02, -0.06), 0.115), ((0, 0.18, -0.15), 0.095), ((0, 0.38, -0.28), 0.072), ((0, 0.60, -0.38), 0.052),
		((0, 0.84, -0.40), 0.038), ((0, 1.06, -0.32), 0.027), ((0, 1.22, -0.16), 0.018), ((0, 1.28, 0.02), 0.010),
		((0, 1.24, 0.16), 0.003)]
	for k, (c, r) in enumerate(path):
		a = Vector(path[max(0, k - 1)][0])
		b = Vector(path[min(len(path) - 1, k + 1)][0])
		along = (b - a).normalized()
		v = along.cross(X).normalized()
		p.add(ring(pv + Vector(c), X, v, r, r * 0.85, 8, 0.2))
	return p


def claws(J: dict, side: str) -> list:
	"""A kobold's digging claws: three, past the ends of its mitten's fingers."""
	sign = 1.0 if side == "l" else -1.0
	wr = J["hand_" + side]
	reach = per(1.0, *PROPORTIONS_OF("hands"))
	out = []
	for dy in (-0.045, -0.015, 0.015, 0.045):
		base = wr + Vector((0.132 * reach * sign, dy, -0.008))
		out.append(spike("Claw", "Bone", base, base + Vector((0.075 * sign, 0.0, -0.04)), 0.017, "middle_02_" + side))
	return out


def kilt(J: dict, drop: float = 0.5, name: str = "Kilt", wide: float = 1.0) -> Part:
	"""An orc's kilt: cloth from its belt down to the middle of its thighs ([drop] of the way to
	the knee), over the hips; a kobold's loincloth, shorter."""
	p = Part(name, "Tunic")
	p.bones = ["pelvis", "spine_01", "thigh_l", "thigh_r"]
	rings = torso_rings(J)
	knee = J["calf_l"].z
	low = J["pelvis"].z + (knee - J["pelvis"].z) * drop
	hem = rings[0]
	axis = Vector((0, 0, 0))
	for z, flare in [(low, 1.42 * wide), ((low + hem[0].z) * 0.5, 1.3 * wide)]:
		p.add([Vector((q.x * flare, q.y * flare, z)) for q in hem])
	for r, k in [(rings[0], 1.2 * wide), (rings[1], 1.12 * wide), (rings[2], 1.06 * (1 + (wide - 1) * 0.5)), (rings[3], 1.03)]:
		p.add([Vector((q.x * k, q.y * k, q.z)) for q in r])
	return p


def loincloth(J: dict) -> list:
	"""An orc's loincloth (the revision, 478 amended: "hanging, not flaring"): a short wrap
	under the belt, close round the hips, and a flap front and back hanging straight down
	from it to above the knees, a little narrower at the hem, the hem ragged."""
	rings = torso_rings(J)
	wrap = Part("Loincloth", "Tunic")
	wrap.bones = ["pelvis", "spine_01", "thigh_l", "thigh_r"]
	for r, k, dz in [(rings[0], 1.1, -0.03), (rings[0], 1.06, 0.0), (rings[1], 1.05, 0.0), (rings[2], 1.04, 0.0), (rings[3], 1.03, 0.0)]:
		wrap.add([Vector((q.x * k, q.y * k, q.z + dz)) for q in r])
	out = [wrap]
	top = J["spine_01"].z - 0.03
	hem = J["calf_l"].z + 0.07
	front = min(q.y for q in rings[0]) * 1.18
	back = max(q.y for q in rings[0]) * 1.1
	for name, y, w, drop, sign in [("Flap_Front", front, 0.17, 0.0, -1.0), ("Flap_Back", back, 0.19, 0.06, 1.0)]:
		p = Part(name, "Tunic")
		p.bones = ["pelvis", "thigh_l", "thigh_r"]
		p.pins = {0: "pelvis", 1: "pelvis"}
		low = hem + drop
		xs = (-1.0, -0.5, 0.0, 0.5, 1.0)
		for f in (0.0, 0.2, 0.5, 0.8, 1.0):
			z = top + (low - top) * f
			width = w * (1.0 - 0.12 * f)
			# The hem ragged: its points at their own lengths.
			rag = [0.0, -0.05, -0.015, -0.06, -0.01] if f == 1.0 else [0.0] * 5
			# Hung off the belly at its top, then straight down, clear of the thighs.
			yy = y + sign * 0.02
			fronts = [Vector((x * width, yy, z + d)) for x, d in zip(xs, rag)]
			backs = [Vector((x * width, yy - sign * 0.014, z + d)) for x, d in zip(xs, rag)]
			p.add(fronts + list(reversed(backs)))
		out.append(p)
	return out


def harness(J: dict) -> list:
	"""An orc's harness: a leather strap from its right hip up across its chest to its left
	shoulder, and on across its back down to the hip again (the torso's rings, followed)."""
	rings = torso_rings(J)
	axis = Vector((0, 0, 0))

	def at(r, f):
		i = int(math.floor(f)) % len(r)
		return r[i].lerp(r[(i + 1) % len(r)], f - math.floor(f))

	out = []
	for name, start, end in [("Chain_Front", 4.6, 1.5), ("Chain_Back", 7.4, 10.5)]:
		if PEOPLE == "orc":
			out += chain(rings, at, start, end)
			continue
		# Jeff's p2 (478 restyled): a heavy iron chain where the strap was, its links in
		# alternate bands of the iron and the belt's dark.
		for k in range(3, 8):
			# A link from this ring of the torso to the next, along the diagonal.
			p = Part("%s_%d" % (name, k), "Iron" if k % 2 else "Belt", follow=True)
			for kk in (k, k + 1):
				f = start + (end - start) * (kk - 3) / 5.0
				a, b = at(rings[kk], f - 0.3), at(rings[kk], f + 0.3)
				p.add(slab([a, b], axis, 0.03, 0.002))
			out.append(p)
	return out


## A chain's links (the revision, 478 amended: "the chain as links"): this many a strand
## (spaced evenly along it, the same count in every shape key's build), each this long and
## wide outside, its iron this thick, riding this far off the skin.
LINKS = 11
LINK_LENGTH = 0.092
LINK_WIDTH = 0.058
LINK_IRON = 0.015
LINK_OFF = 0.026


def chain(rings: list, at, start: float, end: float) -> list:
	"""The orc's chain from [start] to [end] round the torso's rings 3 to 8 (harness's
	path): a strap of the belt's leather under it, and links along it, each turned a quarter
	from the last, lying on the skin and following its weights."""
	axis = Vector((0, 0, 0))
	path = []
	for kk in range(3, 9):
		f = start + (end - start) * (kk - 3) / 5.0
		path.append(at(rings[kk], f))
	strap = Part("Strap", "Belt", follow=True)
	for kk in range(3, 9):
		f = start + (end - start) * (kk - 3) / 5.0
		strap.add(slab([at(rings[kk], f - 0.22), at(rings[kk], f + 0.22)], axis, 0.008, 0.002))
	out = [strap]
	# Even steps along the polyline.
	lengths = [0.0]
	for a, b in zip(path, path[1:]):
		lengths.append(lengths[-1] + (b - a).length)
	total, i = lengths[-1], 0
	step = total / LINKS
	for n in range(LINKS):
		t = step * (n + 0.5)
		while lengths[i + 1] < t:
			i += 1
		a, b = path[i], path[i + 1]
		c = a.lerp(b, (t - lengths[i]) / (lengths[i + 1] - lengths[i]))
		tangent = (b - a).normalized()
		normal = outward(c, axis)
		normal = (normal - tangent * normal.dot(tangent)).normalized()
		c = c + normal * LINK_OFF
		side = tangent.cross(normal).normalized()
		# Alternate links lie flat on the skin and stand up from it.
		across = side if len(out) % 2 else normal
		plane = tangent.cross(across).normalized()
		p = Part("Link", "Iron", follow=True)
		p.closed = True
		ra, rb = (LINK_LENGTH - LINK_IRON) * 0.5, (LINK_WIDTH - LINK_IRON) * 0.5
		for s in range(8):
			ang = 2.0 * math.pi * s / 8
			centre = c + tangent * math.cos(ang) * ra + across * math.sin(ang) * rb
			radial = (tangent * math.cos(ang) * rb + across * math.sin(ang) * ra).normalized()
			p.add(ring(centre, radial, plane, LINK_IRON * 0.5, LINK_IRON * 0.5, 4, 0.0, phase=0.5))
		out.append(p)
	return out


def shoulder_plate(J: dict) -> list:
	"""An orc's iron shoulder plate (Jeff's p2; the revision, 478 amended: "an edged plate
	with rivets"): a domed cap over its left shoulder and two lames stepping down and out
	over the arm, each a band of iron with a thick turned edge and a row of rivets, rigid on
	the clavicle."""
	sh = J["upperarm_l"]
	out = []
	# (top, bottom, half-width, half-depth, out along x at the bottom)
	for i, (top, bottom, w, d, dx) in enumerate([(0.12, 0.02, 0.155, 0.160, 0.05), (0.05, -0.04, 0.165, 0.168, 0.085),
			(-0.01, -0.10, 0.170, 0.170, 0.12)]):
		p = Part("Plate_%d" % i, "Iron", rigid="clavicle_l")
		if i == 0:
			# The dome over the shoulder's top, rounding down into the cap's side.
			for dz, k in ((0.07, 0.3), (0.055, 0.62), (0.03, 0.82)):
				p.add(ring(sh + Vector((0.01, 0.0, top + dz)), X, FRONT, w * k, d * k, 10, 0.45))
		for f in (0.0, 0.5, 1.0):
			z = top + (bottom - top) * f
			k = 0.86 + 0.14 * f
			p.add(ring(sh + Vector((dx * (0.4 + 0.6 * f), 0.0, z)), X, FRONT, w * k, d * k, 10, 0.5))
		out.append(p)
		# The turned edge: a thick roll round the bottom.
		c = sh + Vector((dx, 0.0, bottom))
		edge = Part("Plate_Edge", "Iron", rigid="clavicle_l")
		for dz, k in ((0.012, 1.0), (0.0, 1.06), (-0.012, 1.0)):
			edge.add(ring(c + Vector((0, 0, dz)), X, FRONT, w * k, d * k, 10, 0.5))
		out.append(edge)
		# Rivets: a row a little above the edge, round the outside of the shoulder.
		for a in (-1.0, -0.5, 0.0, 0.5, 1.0):
			ang = a * 1.2
			n = Vector((math.cos(ang), -math.sin(ang) * 0.95, 0.0)).normalized()
			at = c + Vector((n.x * w * 1.04, n.y * d * 1.04, 0.03))
			rivet = spike("Rivet", "Belt", at - n * 0.004, at + n * 0.012, 0.011, "clavicle_l")
			rivet.sparse = True
			out.append(rivet)
	buckle = box("Buckle", "Iron", J["spine_01"] + Vector((0.0, -0.21, 0.0)), Vector((0.11, 0.03, 0.09)), rigid="spine_01")
	return out + [buckle]


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


def hood(J: dict, name: str = "Hood", region: str = "Hat") -> list:
	"""A hood: a cloth cap over the head, open round the face and closed under it, its cowl
	down onto the shoulders."""
	p = Part(name, region)
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


def vest(J: dict) -> list:
	"""A sleeveless leather vest over the tunic, from the belt to the shoulders, open down the
	front (its front middle left out: a sheet round the back and sides)."""
	p = Part("Vest", "Vest")
	p.bones = TORSO_BONES
	rings = torso_rings(J)
	axis = Vector((0, 0, 0))
	for k in range(3, 8):
		# Points 4 round to 14 (two past 12, wrapped) of the ring: from right of the front,
		# round the right side, the back and the left side, to left of the front.
		r = rings[k]
		side = [r[i % 12] for i in range(4, 15)]
		p.add(slab(side, axis, 0.012, 0.0))
	return [p]


def coat(J: dict) -> list:
	"""A long coat over the tunic: the tunic's shape a little out from it, from the shoulders
	down past the hem to the knees, flaring."""
	p = Part("Coat", "Coat")
	p.bones = TORSO_BONES + ["calf_l", "calf_r"]
	rings = torso_rings(J)
	knee = J["calf_l"].z - 0.03
	hem = rings[0]
	for z, flare in [(knee, 1.22), ((knee + hem[0].z) * 0.5, 1.12)]:
		p.add([Vector((q.x * flare, q.y * flare, z)) for q in hem])
	for k in range(0, 8):
		out = 1.04 if k < 7 else 1.03
		p.add([Vector((q.x * out, q.y * out, q.z + (0.004 if k >= 6 else 0.0))) for q in rings[k]])
	return [p]


def cape(J: dict) -> list:
	"""A short cape over the shoulders: from round the neck out over the shoulders' tops and
	down to the chest in front and the shoulder blades behind."""
	p = Part("Cape", "Cape")
	p.bones = ["spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r"]
	n, s3 = J["neck_01"], J["spine_03"]
	for z, w, d, sq in [(s3.z - 0.10, 0.25, 0.16, 0.3), (s3.z - 0.02, 0.255, 0.15, 0.35), (s3.z + 0.07, 0.235, 0.13, 0.45),
			(n.z - 0.01, 0.17, 0.105, 0.4), (n.z + 0.025, 0.085, 0.08, 0.2)]:
		p.add(ring(Vector((0, 0.005, z)), X, FRONT, w * m("shoulders") * m("torso"), d * m("torso"), 12, sq))
	return [p]


def rolled_sleeves(J: dict) -> list:
	"""Sleeves rolled to the elbows: the forearms bare (skin over the sleeve's forearm), a
	roll of cloth at each elbow."""
	out = []
	for side in ("l", "r"):
		el, wr = J["lowerarm_" + side], J["hand_" + side]
		along = (wr - el).normalized()
		k = pick(1.0, 0.86) * m("arms")
		arm = Part("Forearm_" + side, "Skin")
		arm.bones = ["lowerarm_" + side, "hand_" + side]
		for c, rv, ru in [(el + along * 0.02, 0.052, 0.054), (el.lerp(wr, 0.5), 0.050, 0.048), (wr - along * 0.012, 0.044, 0.040)]:
			arm.add(ring(c, FRONT, Z, ru * k, rv * k, 8, 0.3))
		roll = Part("Roll_" + side, "Tunic")
		roll.bones = ["upperarm_" + side, "lowerarm_" + side]
		for c, r in [(el - along * 0.03, 0.060), (el + along * 0.03, 0.062)]:
			roll.add(ring(c, FRONT, Z, r * k, r * k, 8, 0.3))
		out += [arm, roll]
	return out


def soft_cap(J: dict) -> list:
	"""A labourer's soft cap: cloth over the crown, a little slouched to the back."""
	p = Part("Cap", "Hat", rigid="Head")
	base = J["Head"] + Vector((0, 0.008, -0.015))
	kw, kd = pick((1.0, 1.0), (0.95, 0.97))
	for z, w, d, yc in [(0.172, 0.090, 0.112, 0.004), (0.200, 0.094, 0.118, 0.010), (0.232, 0.086, 0.112, 0.022),
			(0.256, 0.060, 0.084, 0.030), (0.268, 0.026, 0.040, 0.034)]:
		p.add(ring(base + Vector((0, yc, z)), X, FRONT, w * kw, d * kd, 12, 0.25))
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


## Armour (decision pending, items' armour): one covering per look, over the tunic, in the
## "Tunic" region so the game tints each by its item's colour on its own mesh. They are built
## from the body's own rings, so they fit every build and key as the garb does.


def _out(r: list, k: float, dz: float = 0.0, margin: float = 0.0, belly: float = 0.0) -> list:
	"""A ring of the torso's, [k] times as far out from the centre line and [margin] more,
	[dz] up, its front pushed [belly] further (over the belt's buckle)."""
	c = Vector((0.0, sum(q.y for q in r) / len(r), r[0].z))
	out = []
	for q in r:
		away = Vector((q.x, q.y - c.y, 0.0))
		way = away.normalized() if away.length > 1e-6 else Vector()
		front = max(0.0, -way.y) ** 2
		out.append(Vector((c.x + away.x * k + way.x * margin, c.y + away.y * k + way.y * margin - belly * front, q.z + dz)))
	return out


def _shell(J: dict, name: str, rows: range, out: float, hem: list = None) -> Part:
	"""A shell over the torso, its rings [rows] of torso_rings [out] times as far out; [hem]
	(heights below the tunic's hem, each with its flare) hang below it first."""
	p = Part(name, "Tunic")
	p.bones = TORSO_BONES + (["calf_l", "calf_r"] if hem and min(z for z, _ in hem) < J["calf_l"].z + 0.05 else [])
	rings = torso_rings(J)
	for z, flare in hem or []:
		p.add([Vector((q.x * flare, q.y * flare, z)) for q in rings[0]])
	for k in rows:
		# Clear of the belt, which stands proud of the tunic at the waist (and the belly's
		# front under it): a margin round the hips and waist, the front pushed out there.
		margin = 0.016 if 2 <= k <= 4 else 0.004
		p.add(_out(rings[k], out if k < 7 else out - 0.01, 0.004 if k >= 6 else 0.0, margin,
			m("belly") * 0.8 + 0.01 if k == 2 else 0.0))
	return p


def _arm(J: dict, side: str, name: str, at: list, scale: float, square: float = 0.3, shoulder: bool = False) -> Part:
	"""Rings round [side]'s arm at [at] ((place 0 shoulder .. 1 elbow .. 2 wrist, its half-height,
	its half-depth), the sleeve's sizes) times [scale]; [shoulder] holds its first ring to the
	clavicle and the next half with it, as the sleeve's top is."""
	sh, el, wr = J["upperarm_" + side], J["lowerarm_" + side], J["hand_" + side]
	along = (wr - sh).normalized()
	p = Part(name, "Tunic")
	p.bones = (["spine_03", "clavicle_" + side] if shoulder else []) + ["upperarm_" + side, "lowerarm_" + side, "hand_" + side]
	k = pick(1.0, 0.86) * m("arms") * scale
	down = Vector((0.0, 0.0, -0.018))
	for t, rv, ru in at:
		if t < 0.0:
			c = sh + along * (0.07 * t) + down  # Inside the shoulder.
		elif t <= 1.0:
			c = sh.lerp(el, t) + (down if t < 0.1 else Vector())
		else:
			c = el.lerp(wr, t - 1.0)
		p.add(ring(c, FRONT, Z, ru * k, rv * k, 8, square))
	if shoulder:
		p.pins = {0: "clavicle_" + side}
		p.mixes = {1: ("clavicle_" + side, 0.5)}
	return p


def _shin(J: dict, side: str, name: str, at: list, scale: float, square: float = 0.35) -> Part:
	"""Rings round [side]'s shin at [at] ((place 0 knee .. 1 ankle, half-width, half-depth)),
	over the boot's shaft, times [scale]."""
	knee, ankle = J["calf_" + side], J["foot_" + side]
	p = Part(name, "Tunic")
	p.bones = ["thigh_" + side, "calf_" + side, "foot_" + side]
	k = pick(1.0, 0.9) * m("legs") * scale
	for t, ru, rv in at:
		p.add(ring(knee.lerp(ankle, t), X, FRONT, ru * k, rv * k, 8, square, (0.012 * k, 0.0)))
	return p


def leather_armour(J: dict) -> list:
	"""Leather: a jerkin over the tunic from its hem to the shoulders, bracers on the forearms,
	greaves on the shins over the boots."""
	out = [_shell(J, "Jerkin", range(0, 8), 1.06)]
	for side in ("l", "r"):
		out.append(_arm(J, side, "Bracer_" + side, [(1.2, 0.050, 0.052), (1.55, 0.048, 0.048), (1.92, 0.044, 0.042)], 1.22))
		out.append(_shin(J, side, "Greave_" + side, [(0.06, 0.074, 0.078), (0.3, 0.080, 0.084), (0.62, 0.070, 0.072)], 1.1))
	return out


def mail_armour(J: dict) -> list:
	"""Mail: a long shirt to mid-thigh, its sleeves to the elbow."""
	hem = torso_rings(J)[0][0].z
	out = [_shell(J, "Mail_Shirt", range(0, 8), 1.05, [(hem - pick(0.16, 0.10), 1.1), (hem - pick(0.08, 0.05), 1.07)])]
	for side in ("l", "r"):
		out.append(_arm(J, side, "Mail_Sleeve_" + side, [(-1.0, 0.052, 0.075), (0.05, 0.060, 0.074), (0.45, 0.058, 0.058),
			(1.05, 0.050, 0.052)], 1.12, shoulder=True))
	return out


def plate_armour(J: dict) -> list:
	"""Plate: a cuirass with its skirt of plates, pauldrons over the shoulders, vambraces,
	cuisses on the thighs and greaves on the shins; squarer than cloth."""
	hem = torso_rings(J)[0][0].z
	cuirass = _shell(J, "Cuirass", range(0, 8), 1.09, [(hem - 0.07, 1.12)])
	out = [cuirass]
	for side in ("l", "r"):
		out.append(_arm(J, side, "Pauldron_" + side, [(-1.0, 0.070, 0.085), (0.0, 0.088, 0.096), (0.22, 0.082, 0.086),
			(0.4, 0.066, 0.066)], 1.15, 0.45, shoulder=True))
		out.append(_arm(J, side, "Vambrace_" + side, [(1.15, 0.050, 0.054), (1.55, 0.048, 0.048), (1.92, 0.044, 0.042)], 1.28, 0.5))
		hip, knee = J["thigh_" + side], J["calf_" + side]
		sign = 1.0 if side == "l" else -1.0
		cuisse = Part("Cuisse_" + side, "Tunic")
		cuisse.bones = ["pelvis", "thigh_" + side, "calf_" + side]
		k = pick(1.0, 0.98) * m("legs") * m("thighs") * 1.16
		for c, ru, rv in [(hip + Vector((-0.008 * sign, 0, -0.06)), 0.090, 0.094), (hip.lerp(knee, 0.55), 0.076, 0.079),
				(knee + Vector((0, 0, 0.03)), 0.066, 0.070)]:
			cuisse.add(ring(c, X, FRONT, ru * k, rv * k, 8, 0.5))
		out.append(cuisse)
		out.append(_shin(J, side, "Plate_Greave_" + side, [(0.04, 0.074, 0.078), (0.3, 0.082, 0.086), (0.66, 0.072, 0.074)], 1.16, 0.55))
	return out


def robes(J: dict) -> list:
	"""Robes: from the shoulders down past the knees to the shins, flaring; full sleeves,
	wider at the wrist."""
	knee, ankle = J["calf_l"], J["foot_l"]
	hem = torso_rings(J)[0][0].z
	shin = knee.lerp(ankle, 0.55).z
	out = [_shell(J, "Robe", range(0, 8), 1.04, [(shin, 1.32), (knee.z, 1.2), ((knee.z + hem) * 0.5, 1.1)])]
	for side in ("l", "r"):
		out.append(_arm(J, side, "Robe_Sleeve_" + side, [(-1.0, 0.052, 0.075), (0.05, 0.060, 0.074), (0.45, 0.058, 0.058),
			(1.0, 0.052, 0.054), (1.5, 0.056, 0.056), (1.95, 0.066, 0.064)], 1.1, shoulder=True))
	return out


## A worn cloak (788's back slot, look "cloak"; the coordinator: "longer, to the calf, and
## fuller" than a townsman's cape): from round the neck over the shoulders, down the back and
## sides to the calf, open in front below the throat. Each ring a thin C (CLOAK_THICK through)
## round the back, spanning CLOAK_SPANS of a turn: nearly closed at the neck, wrapping the
## sides lower down, so the arms swing out of its open front. Its rings at and below the hips
## move with the pelvis alone (pins), hung clear of the legs behind.
CLOAK_THICK = 0.012


def cloak_ring(centre: Vector, w: float, d: float, span: float, n: int = 16) -> list:
	"""A C of [n] points round [centre] behind it (+Y), [w] half-wide and [d] deep, over [span]
	of a turn: the outer arc, then the inner back along it CLOAK_THICK in."""
	half = math.pi * span
	outer, inner = [], []
	for i in range(n // 2):
		a = -half + 2.0 * half * i / (n // 2 - 1)
		outer.append(centre + X * math.sin(a) * w + Y * math.cos(a) * d)
		inner.append(centre + X * math.sin(a) * (w - CLOAK_THICK) + Y * math.cos(a) * (d - CLOAK_THICK))
	return outer + list(reversed(inner))


def cloak(J: dict, strapped: bool = False) -> list:
	p = Part("Cloak", "Tunic")
	p.bones = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r"]
	n, s3, s1, pelvis = J["neck_01"], J["spine_03"], J["spine_01"], J["pelvis"]
	knee, ankle = J["calf_l"], J["foot_l"]
	hem = torso_rings(J)[0][0].z
	ws, wt = m("shoulders") * m("torso"), m("torso")
	# (height, half-width, depth, centre's y behind, span of a turn)
	rows = [(n.z + 0.025, 0.088 * ws, 0.082 * wt, 0.005, 0.94), (n.z - 0.01, 0.175 * ws, 0.11 * wt, 0.005, 0.9),
		(s3.z + 0.07, 0.245 * ws, 0.14 * wt, 0.01, 0.78), (s3.z - 0.02, 0.27 * ws, 0.16 * wt, 0.015, 0.66),
		(s3.z - 0.10, 0.275 * ws, 0.17 * wt, 0.02, 0.6), (s1.z, 0.27 * wt, 0.18 * wt, 0.03, 0.58),
		(pelvis.z, 0.27 * wt, 0.19 * wt, 0.04, 0.58), (hem, 0.275 * wt, 0.2 * wt, 0.06, 0.58),
		(knee.z, 0.29 * wt, 0.21 * wt, 0.09, 0.58), (knee.lerp(ankle, 0.45).z, 0.3 * wt, 0.22 * wt, 0.11, 0.58)]
	if strapped:
		# Rows enough over the hips that the bag's ease bends the cloak there and not to the knee.
		def between(a, b, t):
			return tuple(x + (y - x) * t for x, y in zip(a, b))
		# From the spine's row to the knee's (the bag, its strap's ends just under the belt, hangs
		# within them), each gap in thirds: the same count for every body, so its keys match.
		top = rows.index(next(r for r in rows if r[0] == s1.z))
		low = rows.index(next(r for r in rows if r[0] == knee.z))
		dense = []
		for k in range(top, low):
			dense += [rows[k], between(rows[k], rows[k + 1], 1.0 / 3.0), between(rows[k], rows[k + 1], 2.0 / 3.0)]
		rows = rows[:top] + dense + rows[low:]
	for k, (z, w, d, back, span) in enumerate(rows):
		p.add(cloak_ring(Vector((0.0, back, z)), w, d, span, CLOAK_STRAPPED_ROUND if strapped else 16))
		if z <= pelvis.z + 0.001:
			p.pins[k] = "pelvis"
	if strapped:
		_ease_over_strap(J, p, rows)
		_ease_over_bag(J, p)
	return [p]


## Worn_Cloak_Strapped (819 amended, the satchel): the cloak shown while a satchel is worn, eased
## out where the strap runs under it (over the tunic; a vest, coat or leather; mail or robes), so
## the strap shows only in the cloak's open front and never through it. A strap point nearer than
## CLOAK_OVER_STRAP to the cloak's inside (or past it) moves the face it is nearest out along that
## face's normal, its four corners and their twins on the other sheet together, till none is (at
## most CLOAK_EASE_PASSES passes): on the shoulder's slope that lifts the cloak a little, where a
## level push would have stood it far out.
CLOAK_OVER_STRAP = 0.004
CLOAK_EASE_PASSES = 12
CLOAK_EDGE_IN = math.radians(4.0)
CLOAK_EASED_OVER = ("Worn_Strap", "Worn_Strap_Over")


## The bag the strapped cloak also eases over (819am2): art-kit's worn.satchel's bounds in its frame
## (Client3D._bag_frame: the origin midway between the strap's two ends, +x toward the front end,
## +y up, +z out). Each cloak vertex over it, in each fit's frame a cloak may cover (the cape is
## hidden under one), moves out along that frame's +z till it is CLOAK_OVER_BAG past the bag's front,
## less and less over BAG_FEATHER past its sides, top and bottom; on the bag's side only (never
## mirrored as the strap's ease is), so the cloak is fuller over the bag and nowhere else.
BAG_HALF_WIDE, BAG_TOP, BAG_BOTTOM = 0.113, 0.024, -0.19
## The bag's front by height (819 amended (4)): art-kit's worn.satchel v2 tilts its foot 5 degrees out
## from the thigh, so its front leaves 0.094 (the draft's flat front) for 0.107 at the flap's tongue and
## buckle. Pairs of (height, outermost z across the bag at it, buckle included), art-kit's table, read
## from the top down as the most any height above has reached: a cloak falling over the bag hangs
## from its fullest point and never tucks back under the rounded foot. Linear between them, held past
## the ends; never under the draft's 0.094, so the cloak is as before at the bag's top.
BAG_FRONT_MIN = 0.094
## A woman's bag hangs its foot swung out about its rings (Client3D.BAG_TILT_WOMAN, the same angle;
## the rings at BAG_RING_HEIGHT): its front at height y further out by (ring - y) * sin, the cloak with it.
BAG_TILT_FEMALE = math.radians(6.0)
BAG_RING_HEIGHT = 0.014
BAG_FRONT_BY_HEIGHT = ((0.024, 0.089), (0.0, 0.093), (-0.04, 0.097), (-0.08, 0.100), (-0.12, 0.106),
	(-0.15, 0.107), (-0.185, 0.095))


def _bag_front(y: float) -> float:
	swing = max(BAG_RING_HEIGHT - y, 0.0) * math.sin(BAG_TILT_FEMALE) if female() else 0.0
	return _bag_front_upright(y) + swing


def _bag_front_upright(y: float) -> float:
	pts = []
	reach = BAG_FRONT_MIN
	for h, z in BAG_FRONT_BY_HEIGHT:
		reach = max(reach, z)
		pts.append((h, reach))
	if y >= pts[0][0]:
		return pts[0][1]
	for (h0, z0), (h1, z1) in zip(pts, pts[1:]):
		if y >= h1:
			return z0 + (z1 - z0) * (h0 - y) / (h0 - h1)
	return pts[-1][1]
BAG_FEATHER = 0.10
## The cloak's rows over the bag taper in and out (819 amended (5), the coordinator's word on the
## game's stills: a sharp dark fold at the bag's foot, a ledge at its top): under the foot it falls
## from the bag's fullest point and comes back to the body over BAG_FALL, and above the top it leaves
## the back over BAG_RISE, not BAG_FEATHER, so no row turns more than about 30 degrees from the one
## beside it (the worst was 43 at the woman's foot and 47 at her top; her rows there are 4 to 7 cm apart).
BAG_FALL = 0.40
BAG_RISE = 0.20
## Past the bag's bounds still eased in full (the cloak's faces are flat between its vertices: round
## the bag's front corner, where the cloak turns toward the side, the face beyond cut the corner).
BAG_PAD = 0.03
## The strapped cloak's vertices round each ring (the plain cloak's 16): its faces fit the bag.
CLOAK_STRAPPED_ROUND = 24
CLOAK_OVER_BAG = 0.010
BAG_UNDER_CLOAK = ("Worn_Strap", "Worn_Strap_Over", "Worn_Strap_Sleeved", "Worn_Strap_Plate")


def _ease_over_bag(J: dict, p: Part) -> None:
	frames = []
	for name in BAG_UNDER_CLOAK:
		r = strap(J, name)[0].rings
		front = sum(r[0], Vector()) / len(r[0])
		back = sum(r[-1], Vector()) / len(r[-1])
		mid = (front + back) / 2.0
		x = Vector((front.x - back.x, front.y - back.y, 0.0)).normalized()
		z = x.cross(Vector((0.0, 0.0, 1.0)))
		if z.dot(Vector((mid.x, mid.y, 0.0))) < 0.0:
			z = -z
		frames.append((mid, x, z))

	def fade(past: float, over: float = BAG_FEATHER) -> float:
		t = min(max(past / over, 0.0), 1.0)
		return 1.0 - t * t * (3.0 - 2.0 * t)

	def fade_height(y: float) -> float:
		if y < BAG_BOTTOM - BAG_PAD:
			return fade(BAG_BOTTOM - BAG_PAD - y, BAG_FALL)
		return fade(y - BAG_TOP - BAG_PAD, BAG_RISE)

	for k, ring in enumerate(p.rings):
		n = len(ring)
		# Measured on the inner sheet (what the bag meets), moved with its twin on the outer.
		for i in range(n // 2, n):
			v = ring[i]
			move = Vector()
			for mid, x, z in frames:
				d = v - mid
				bz = d.dot(z)
				if bz <= 0.0:
					continue
				w = fade(abs(d.dot(x)) - BAG_HALF_WIDE - BAG_PAD) * fade_height(d.z)
				need = (_bag_front(d.z) + CLOAK_OVER_BAG - bz) * w
				if need > move.length:
					move = z * need
			p.rings[k][i] = v + move
			p.rings[k][n - 1 - i] = ring[n - 1 - i] + move


def _ease_over_strap(J: dict, p: Part, rows: list) -> None:
	from mathutils.bvhtree import BVHTree
	samples = []
	for name in CLOAK_EASED_OVER:
		r = strap(J, name)[0].rings
		for k in range(len(r)):
			samples += r[k]
			if k + 1 < len(r):
				samples += [a.lerp(b, 0.5) for a, b in zip(r[k], r[k + 1])]
	n = len(p.rings[0])
	half = n // 2
	# Only what the cloak covers: a strap point in its open front (round from the back further than
	# the C's span at its height, less CLOAK_EDGE_IN) is meant to show.
	covered = []
	for q in samples:
		for k in range(len(rows) - 1):
			(z0, _w0, _d0, b0, s0), (z1, _w1, _d1, b1, s1) = rows[k], rows[k + 1]
			if z1 <= q.z <= z0:
				v = (z0 - q.z) / (z0 - z1)
				back, span = b0 + (b1 - b0) * v, s0 + (s1 - s0) * v
				if abs(math.atan2(q.x, q.y - back)) < math.pi * span - CLOAK_EDGE_IN:
					covered.append((q, back))
				break
	faces = [(k, i) for k in range(len(p.rings) - 1) for i in range(n)]
	for _pass in range(CLOAK_EASE_PASSES):
		verts = [q for r in p.rings for q in r]
		tree = BVHTree.FromPolygons(verts, [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for k, i in faces])
		push = {}
		for q, back in covered:
			# The face over it: level out from the upright line through the ring's centre.
			axis = Vector((0.0, back, q.z))
			way = Vector((q.x, q.y - back, 0.0))
			if way.length < 1e-6:
				continue
			loc, normal, index, _t = tree.ray_cast(axis, way.normalized(), 1.0)
			if loc is None:
				continue
			k, i = faces[index]
			if normal.dot(way) < 0.0:
				normal = -normal
			need = (q - loc).dot(normal) + CLOAK_OVER_STRAP
			if need <= 0.0:
				continue
			for kk in (k, k + 1):
				for ii in (i, (i + 1) % n):
					col = ii if ii < half else n - 1 - ii
					key = (kk, col)
					if key not in push or need > push[key][0]:
						push[key] = (need, normal.copy())
		if not push:
			break
		for (k, col), (need, normal) in push.items():
			for ii in (col, n - 1 - col):
				p.rings[k][ii] = p.rings[k][ii] + normal * need


SOFT_SOLE = 0.002
SOFT_PAST = 0.008
SOFT_FULL = 1.1


def soft_boot(J: dict, side: str) -> Part:
	"""Soft boots (788's feet slot, look "boots_soft"): over the body's own boots, a little
	fuller, the shaft's top turned down in a loose cuff."""
	b = boot(J, side)
	p = Part("Worn_Boot_" + side, "Tunic")
	p.bones = b.bones
	rings = []
	shaft = 4  # boot()'s shaft rings; the foot's after, heel to toe.
	for k, r in enumerate(b.rings):
		c = Vector((sum((q.x for q in r), 0.0) / len(r), sum((q.y for q in r), 0.0) / len(r), sum((q.z for q in r), 0.0) / len(r)))
		if k < shaft:
			rings.append([c + (q - c) * (1.14 if k == 0 else SOFT_FULL) for q in r])
			continue
		# The foot: fuller round it, its sole SOFT_SOLE under the boot's, its heel and toe past them.
		floor = min(q.z for q in r)
		along = -SOFT_PAST if k == len(b.rings) - 1 else SOFT_PAST if k == shaft else 0.0  # FRONT is -Y.
		rings.append([Vector((c.x + (q.x - c.x) * SOFT_FULL, c.y + (q.y - c.y) * SOFT_FULL + along, floor - SOFT_SOLE + (q.z - floor) * SOFT_FULL))
			for q in r])
	top = rings[0]
	c = Vector((sum((q.x for q in top), 0.0) / len(top), sum((q.y for q in top), 0.0) / len(top), top[0].z))
	cuff = [c + (q - c) * 1.1 + Vector((0, 0, 0.012)) for q in top]
	p.rings = [cuff] + rings
	return p


## A satchel's strap (819 amended, the satchel; the coordinator's approval of pc-character's
## design): a leather band from the bag at the right hip's back quarter up across the chest,
## over the left shoulder between the neck and the shoulder's point, and down across the back
## to the bag again. Skinned as the torso is, so it bends and twists with the chest; the bag
## itself is art on the "bag" socket at its two ends (Client3D). Each Worn_Strap* lies over
## what the body wears under it (STRAP_FITS: the tunic alone; the vest, coat or leather; mail or
## robes, their sleeves' tops over the shoulder; the garb's cape; plate, its pauldron), pushed
## out along the torso's normal past the outermost of them (at its middle and both edges) and
## STRAP_CLEAR more. Under a worn cloak the cloak is eased over it (Worn_Cloak_Strapped).
## STRAP_HALF half-wide, STRAP_THICK thick.
STRAP_CLEAR = 0.003
STRAP_HALF = 0.018
STRAP_THICK = 0.004
## Its path on the torso's rings: (ring, place round it), the ring fractional between two of
## torso_rings' (2 just under the belt .. 7.8 on the shoulder's top, halfway from the neck to the
## shoulder's point), the place 0 the left side, 3 the front, 6 the right, 9 (or -3) the back.
## The two ends are the bag's lugs, either side of the right hip's back quarter (8.25), 0.16 m apart
## as art-kit's worn.satchel's tabs are: back of
## the right side, so the bag's front edge clears the lantern hung forward of belt_r while a
## satchel is worn (Client3D.LANTERN_BY_BAG; the coordinator's ruling, option A).
STRAP_PATH = [(2.0, 7.4), (3.0, 6.25), (4.0, 5.0), (5.0, 3.7), (6.0, 2.3), (7.1, 1.1), (7.8, 0.0),
	(7.3, -1.6), (6.5, -2.2), (5.5, -2.6), (4.5, -2.8), (3.5, -2.85), (2.0, -2.9)]
STRAP_STEPS = 3
## How far in from the tunic a push-out starts and how far out it looks.
STRAP_IN, STRAP_REACH = 0.03, 0.16
## A gap this wide past a surface ends the push-out (what lies beyond is another thing).
STRAP_GAP = 0.01
## Each strap and what it goes over (WEARABLES' names; the body itself always).
STRAP_FITS = {
	"Worn_Strap": [],
	"Worn_Strap_Over": ["Vest", "Coat", "Armour_Leather"],
	"Worn_Strap_Sleeved": ["Armour_Mail", "Armour_Robes"],
	"Worn_Strap_Cape": ["Cape"],
	"Worn_Strap_Plate": ["Armour_Plate"],
}


def _bvh(parts: list):
	"""The parts' lofts as one BVH tree (as Part.mesh builds them, capped), no object made."""
	from mathutils.bvhtree import BVHTree
	verts, faces = [], []
	for p in parts:
		p.densify(per(1, *DENSITY_OF))
		n, base = len(p.rings[0]), len(verts)
		for r in p.rings:
			verts.extend(r)
		for k in range(len(p.rings) - (0 if p.closed else 1)):
			nxt = (k + 1) % len(p.rings)
			for i in range(n):
				faces.append((base + k * n + i, base + k * n + (i + 1) % n, base + nxt * n + (i + 1) % n, base + nxt * n + i))
		if not p.closed:
			faces.append(tuple(base + i for i in reversed(range(n))))
			last = base + (len(p.rings) - 1) * n
			faces.append(tuple(range(last, last + n)))
	# Every face outward (the lofts wind either way), so a ray tells a way out from a way in.
	import bmesh
	bm = bmesh.new()
	for q in verts:
		bm.verts.new(q)
	bm.verts.ensure_lookup_table()
	for f in faces:
		try:
			bm.faces.new([bm.verts[i] for i in f])
		except ValueError:
			pass  # A cap's ring that repeats a point.
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	tree = BVHTree.FromBMesh(bm)
	bm.free()
	return tree


def _outside(tree, start: Vector, ray: Vector, reach: float) -> float:
	"""How far along [ray] from [start] (inside what it lies on) it comes out for good: the first
	way out (a face looking along the ray) followed by nothing, or by a way in more than STRAP_GAP
	on (another thing apart: a T-posed arm beside the shoulder), not by another way out (still
	inside something that overlaps). 0 if it never comes out."""
	hits, t = [], 0.0
	while t < reach:
		hit = tree.ray_cast(start + ray * t, ray, reach - t)
		if hit[0] is None:
			break
		t += hit[3]
		hits.append((t, hit[1].dot(ray) > 0.0))
		t += 1e-4
	for j, (t, out) in enumerate(hits):
		if not out:
			continue
		if j + 1 == len(hits) or (not hits[j + 1][1] and hits[j + 1][0] - t > STRAP_GAP):
			return t
	return max((t for t, out in hits if out), default=0.0)


def strap(J: dict, name: str = "Worn_Strap") -> list:
	fit = STRAP_FITS[name]
	rings = torso_rings(J)

	def at(r, f):
		i = int(math.floor(f)) % len(r)
		return r[i].lerp(r[(i + 1) % len(r)], f - math.floor(f))

	def surface(k, f):
		kk = min(int(math.floor(k)), len(rings) - 2)
		return at(rings[kk], f).lerp(at(rings[kk + 1], f), k - kk)

	def cr(p0, p1, p2, p3, t):
		return tuple(0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t
			+ (-a + 3.0 * b - 3.0 * c + d) * t * t * t) for a, b, c, d in zip(p0, p1, p2, p3))

	path = []
	n = len(STRAP_PATH)
	for i in range(n - 1):
		p0, p1, p2, p3 = (STRAP_PATH[max(0, i - 1)], STRAP_PATH[i], STRAP_PATH[i + 1], STRAP_PATH[min(n - 1, i + 2)])
		for s in range(STRAP_STEPS):
			path.append(cr(p0, p1, p2, p3, s / STRAP_STEPS))
	path.append(STRAP_PATH[-1])
	# What it lies over: the body's torso, belt, collar, neck and sleeves, and the fit's parts.
	under = [torso(J), belt(J), neck(J), sleeve(J, "l"), sleeve(J, "r")] + per([collar(J)], [], [])
	for wearable in fit:
		under += WEARABLES[wearable](J)
	under_tree = _bvh(under)
	e = 0.05
	bases, normals = [], []
	for k, f in path:
		q = surface(k, f)
		normal = (surface(k, f + e) - surface(k, f - e)).cross(surface(k + e, f) - surface(k - e, f)).normalized()
		if normal.dot(Vector((q.x, q.y, 0.0))) < 0.0:
			normal = -normal
		bases.append(q)
		normals.append(normal)
	# Across the run on the torso, so its edges are fitted as well as its middle (a 3.6 cm band
	# on a curved shoulder: fitted down the middle, its edges dipped in and stood out).
	acrosses = []
	for j, normal in enumerate(normals):
		run = (bases[min(j + 1, len(bases) - 1)] - bases[max(j - 1, 0)]).normalized()
		acrosses.append(normal.cross(run).normalized())
	offsets = []
	for q, normal, across in zip(bases, normals, acrosses):
		pushed = 0.0
		for side in (-1.0, 0.0, 1.0):
			start = q + across * (STRAP_HALF * side) - normal * STRAP_IN
			pushed = max(pushed, _outside(under_tree, start, normal, STRAP_IN + STRAP_REACH) - STRAP_IN)
		offsets.append(pushed + STRAP_CLEAR)
	# Smoothed along its run, never in past where it was pushed.
	offsets = [max(o, sum(offsets[max(0, j - 1):j + 2]) / len(offsets[max(0, j - 1):j + 2])) for j, o in enumerate(offsets)]
	points = [q + normal * o for q, normal, o in zip(bases, normals, offsets)]
	p = Part(name, "Tunic")
	p.bones = TORSO_BONES
	for j, normal in enumerate(normals):
		q, across = points[j], acrosses[j]
		a, b = q + across * STRAP_HALF, q - across * STRAP_HALF
		p.add([a, b, b + normal * STRAP_THICK, a + normal * STRAP_THICK])
	return [p]


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
	# Garb (decision 480): a person's clothes over the tunic, and a labourer's cap.
	"Vest": vest,
	"Coat": coat,
	"Cape": cape,
	"Sleeves_Rolled": rolled_sleeves,
	"Cap_Soft": soft_cap,
	# Armour: one covering per look (Items.armour_of's), worn in place of the garb.
	"Armour_Leather": leather_armour,
	"Armour_Mail": mail_armour,
	"Armour_Plate": plate_armour,
	"Armour_Robes": robes,
	# Worn gear (788's worn slots; Items.worn_of(id)["look"], the coordinator's approval): in the
	# "Tunic" region, each on its own mesh, so the game tints it its item's colour as armour is.
	"Worn_Hood": lambda J: hood(J, "Worn_Hood", "Tunic"),
	"Worn_Cloak": cloak,
	"Worn_Boots": lambda J: [soft_boot(J, "l"), soft_boot(J, "r")],
}
# The satchel's straps (no look word: one shown while the bag slot holds one, by what is worn
# under it) and the cloak eased over them.
for _fit in STRAP_FITS:
	WEARABLES[_fit] = lambda J, _fit=_fit: strap(J, _fit)
WEARABLES["Worn_Cloak_Strapped"] = lambda J: cloak(J, strapped=True)
## An ally's own (decision 478): an orc may crop or bind its hair (a topknot); a kobold wears
## its cap or goes bare-headed.
PEOPLE_WEARABLES = {
	"orc": [],  # Bald (Jeff's p2).
	"kobold": [],  # Kobolds see in the dark: no cap, no lamp (Jeff's p1).
}
WEARABLES["Cap_Candle"] = miner_cap


## Each region's material, made once.
_materials = {}


## A kobold's scales as banding (the coordinator on the p1 sheet: "faceting alone reads as
## plain"): on its back, tail and shins, every other band of SCALE_BAND (metres, as built) a
## darker colour (the crest's, the "Hair" tint); its belly pale (the "Belly" region, on the
## palette).
SCALE_BAND = 0.035


def kobold_bands(body, J: dict) -> None:
	def material(name):
		if name not in _materials:
			_materials[name] = bpy.data.materials.new(name)
		mats = [m.name.split(".")[0] for m in body.data.materials]
		if name not in mats:
			body.data.materials.append(_materials[name])
			mats.append(name)
		return mats.index(name)

	names = [m.name.split(".")[0] for m in body.data.materials]
	pelvis, chest, knee_z = J["pelvis"], J["spine_03"], J["calf_l"].z
	dark, belly = material("Hair"), material("Belly")
	for poly in body.data.polygons:
		region = names[poly.material_index] if poly.material_index < len(names) else ""
		c, n = poly.center, poly.normal
		band = int(math.floor((c.z + c.y) / SCALE_BAND)) % 2 == 0
		if region == "Skin" and pelvis.z < c.z < chest.z + 0.05 and n.y < -0.55 and abs(c.x) < 0.11:
			poly.material_index = belly
		elif region in ("Skin", "Trousers") and n.y > 0.35 and c.z > pelvis.z - 0.05 and band:
			poly.material_index = dark  # The back and the tail's top.
		elif region == "Trousers" and c.y > pelvis.y + 0.1 and n.z > 0.3 and band:
			poly.material_index = dark  # The tail.
		elif region == "Trousers" and c.z < knee_z and n.y < -0.3 and band:
			poly.material_index = dark  # The shins' fronts.


def assemble(J: dict, which: str = "Body"):
	"""The body (which "Body") or a WEARABLES part, by MORPH, as meshes on their bones,
	joined into one object named [which], a material a region. What moves with the head (the
	Head bone, or as near) grows by MORPH's "head" about the Head bone."""
	if which == "Body":
		parts = [torso(J), belt(J), neck(J), head(J)] + per([collar(J)], [], []) + face(J)
		parts += per([], loincloth(J) + harness(J) + shoulder_plate(J), [tail(J), kilt(J, 0.4, "Loincloth", 1.22)] + ruff(J))
		for side in ("l", "r"):
			parts += [sleeve(J, side), leg(J, side), hand(J, side)]
			parts += fingers(J, side) if PEOPLE == "orc" else [thumb(J, side)]
			parts += kobold_foot(J, side) if PEOPLE == "kobold" else orc_foot(J, side) if PEOPLE == "orc" else [boot(J, side)]
			if PEOPLE == "kobold":
				parts += claws(J, side)
	else:
		parts = WEARABLES[which](J)
	# A kobold's head large for its body.
	grow = m("head") * per(1.0, 1.62, 1.55)
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
	if which == "Body" and PEOPLE == "kobold":
		kobold_bands(body, J)  # Once its faces look outward.
	if PEOPLE == "human":
		# Smooth-shaded, edges sharper than SHARP_ANGLE kept sharp (419 amended: flat facets each took
		# one value from the sun and broke a face or a chest into light and dark patches in the game's
		# light; C:/dev/review/pc-character/light_faces_close.png).
		for poly in body.data.polygons:
			poly.use_smooth = True
		body.data.set_sharp_from_angle(angle=math.radians(SHARP_ANGLE))
	else:
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
	global SHARP_ANGLE
	SHARP_ANGLE = float(a[a.index("--sharp-angle") + 1]) if "--sharp-angle" in a else SHARP_ANGLE
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
