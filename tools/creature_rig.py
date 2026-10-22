# Rigs a four-legged creature mesh (a TRELLIS.2 model) to a reference animal's skeleton and
# clips (a Quaternius animal: one skinned mesh on an "AnimalArmature" with its actions), so
# the reference's clips play on the new body: fitted, weighted, faceted and coloured on
# art-kit's palette, ready for the creature's art slot.
#
#   blender -b -P tools/creature_rig.py -- <mesh .glb> <reference .glb> <out.glb>
#       [--height M] [--length M] [--tris N] [--turn DEGREES] [--colours SWATCHES] [--no-tail]
#
# The mesh should stand four-square as the reference does: legs straight down and apart,
# head toward -Y (Blender's front; --turn 180 if it faces +Y). It is centred, stood on z = 0,
# scaled to --height if given, and its body (everything above the belly) lengthened to
# --length (snout to rump) if given, the legs carried along whole, not stretched.
#
# The fit: on both the mesh and the reference's own mesh the same landmarks are measured
# (the four feet, the belly under the middle, the back over it, the snout and the rump, the
# highest point), and every point (bones, and the reference's mesh for the weights) is moved
# by piecewise-linear maps between the two, along the length through snout, front feet, hind
# feet and rump, up through the belly and the back, out through the feet. The reference is
# first scaled whole to the mesh's height, its clips' moves with it, so a clip's bob or lunge
# is the same in proportion. Weights: the reference's mesh, warped by the fit, gives each
# vertex its bones by the nearest face (POLYINTERP_NEAREST), at most four, summing to one.
#
# Colours (--colours): faces are sorted into regions by shape, and each region's UVs put on
# one swatch of art/kit/palette.png (art-kit's convention: 16 px swatches, 8 a row, u = (col
# + 0.5) / 8, v = 1 - (row + 0.5) / rows, rows read from the image, which grows) under the
# one material "palette". The .blend is saved beside the .glb, as the slot's source. SWATCHES is
# region=row,col pairs, comma-free between pairs: e.g. body=5,5 underside=5,4 hooves=5,7.
# Regions: hooves (the bottom of the legs), underside (faces looking down, under the belly
# line), body (the rest).
#
# --no-tail: for a body whose tail is a stub (a sheep on the cow's rig): every weight on the
# reference's tail bones (named Tail...) given to the tail's root's parent, so its clips' tail swing
# doesn't drag the rump out into a spike.
#
# The output: the armature (the reference's name) with every clip, once each by its plain
# name ("Walk", not "AnimalArmature|Walk"), and the mesh, flat-shaded.
import os
import sys

import bpy
from mathutils import Vector

## How much of the height counts as a foot when finding the feet.
FOOT_BAND = 0.06
## How far up the legs the hooves' colour goes, as a share of the height.
HOOF_BAND = 0.07


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def tris(obj) -> int:
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def points(obj) -> list:
	return [obj.matrix_world @ v.co for v in obj.data.vertices]


def load_mesh(path: str):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	new = [o for o in bpy.data.objects if o not in before]
	meshes = [o for o in new if o.type == "MESH"]
	for obj in new:
		if obj not in meshes:
			bpy.data.objects.remove(obj)
	bpy.ops.object.select_all(action="DESELECT")
	for obj in meshes:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.parent = None
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	body.vertex_groups.clear()
	body.modifiers.clear()
	body.name = "Body"
	return body


def load_reference(path: str) -> tuple:
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	new = [o for o in bpy.data.objects if o not in before]
	arm = [o for o in new if o.type == "ARMATURE"][0]
	skins = [o for o in new if o.type == "MESH" and any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers)]
	ref = max(skins, key=lambda o: len(o.data.vertices))
	# The armature without its parent empties, its transform kept.
	world = arm.matrix_world.copy()
	arm.parent = None
	arm.matrix_world = world
	for obj in new:
		if obj not in (arm, ref):
			bpy.data.objects.remove(obj)
	return arm, ref


## The reference scaled whole by s: the armature object, its mesh, and every clip's
## location keys (they are in the bones' own units, which the scale changes).
def scale_reference(arm, ref, s: float) -> None:
	from mathutils import Matrix
	world = ref.matrix_world.copy()
	ref.parent = None
	ref.matrix_world = world
	for obj in (arm, ref):
		obj.matrix_world = Matrix.Scale(s, 4) @ obj.matrix_world
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	ref.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	for action in bpy.data.actions:
		for curve in fcurves(action):
			if curve.data_path.endswith(".location") or curve.data_path == "location":
				for key in curve.keyframe_points:
					key.co.y *= s
					key.handle_left.y *= s
					key.handle_right.y *= s


## An action's F-curves, through Blender 5's layered actions (slots and channelbags).
def fcurves(action) -> list:
	if hasattr(action, "layers") and action.layers:
		out = []
		for layer in action.layers:
			for strip in layer.strips:
				for bag in strip.channelbags:
					out.extend(bag.fcurves)
		return out
	return list(action.fcurves)


def bounds(pts: list) -> tuple:
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return lo, hi


def stand(body, height: float) -> None:
	lo, hi = bounds(points(body))
	s = height / (hi.z - lo.z) if height else 1.0
	centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
	for v in body.data.vertices:
		v.co = (v.co - centre) * s
	body.data.update()


## The four feet's centres (x, y, 0): the lowest points in four clusters (k-means, seeded
## from points far apart), so a body standing a little turned still shows its four feet.
def foot_centres(pts: list) -> list:
	lo, hi = bounds(pts)
	low = [Vector((p.x, p.y, 0.0)) for p in pts if p.z < lo.z + FOOT_BAND * (hi.z - lo.z)]
	if len(low) < 4:
		raise SystemExit("too few points near the ground to find four feet")
	centres = [low[0]]
	while len(centres) < 4:
		centres.append(max(low, key=lambda p: min((p - c).length for c in centres)))
	for _ in range(20):
		groups = [[] for _ in centres]
		for p in low:
			groups[min(range(4), key=lambda i: (p - centres[i]).length)].append(p)
		centres = [sum(g, Vector()) / len(g) if g else c for g, c in zip(groups, centres)]
	return centres


## The feet by name: front (toward -Y) and hind, l (+X) and r.
def feet(pts: list) -> dict:
	centres = sorted(foot_centres(pts), key=lambda c: c.y)
	out = {}
	for end, pair in (("front", centres[:2]), ("hind", centres[2:])):
		pair.sort(key=lambda c: c.x)
		out[end + "_r"], out[end + "_l"] = pair
	return out


## Turned about z so the line from the front feet to the hind feet runs along +Y (the head
## toward -Y, as the reference stands), then stood again.
def square(body, height: float) -> None:
	import math
	from mathutils import Matrix
	f = feet(points(body))
	along = (f["hind_l"] + f["hind_r"]) / 2 - (f["front_l"] + f["front_r"]) / 2
	angle = math.atan2(along.x, along.y)  # From +Y to the body's line, clockwise seen from above.
	if abs(angle) > 1e-3:
		body.data.transform(Matrix.Rotation(angle, 4, "Z"))
		body.data.update()
		print("squared: turned %.1f degrees" % math.degrees(angle))
	stand(body, height)


## The landmarks of [param obj] (world space). The belly and the back are found by rays
## up and down the centre line between the legs: a low-poly mesh may have no vertex there.
def landmarks(obj) -> dict:
	from mathutils.bvhtree import BVHTree
	pts = points(obj)
	lo, hi = bounds(pts)
	f = feet(pts)
	front = (f["front_l"].y + f["front_r"].y) / 2
	hind = (f["hind_l"].y + f["hind_r"].y) / 2
	foot_x = (f["front_l"].x - f["front_r"].x + f["hind_l"].x - f["hind_r"].x) / 4
	half = (hi.x - lo.x) / 2
	tree = BVHTree.FromPolygons(pts, [list(p.vertices) for p in obj.data.polygons])
	bellies, backs = [], []
	for k in range(1, 8):
		y = front + (hind - front) * (0.25 + 0.5 * k / 8)
		up = tree.ray_cast(Vector((0.0, y, lo.z - 1.0)), Vector((0, 0, 1)))[0]
		down = tree.ray_cast(Vector((0.0, y, hi.z + 1.0)), Vector((0, 0, -1)))[0]
		if up is not None:
			bellies.append(up.z)
		if down is not None:
			backs.append(down.z)
	if not bellies or not backs:
		raise SystemExit("no belly or back found between the legs")
	bellies.sort()
	backs.sort()
	return {
		"snout": lo.y, "front": front, "hind": hind, "rump": hi.y,
		"belly": bellies[len(bellies) // 2], "back": backs[len(backs) // 2], "top": hi.z,
		"foot_x": foot_x, "half": half,
	}


def piecewise(x: float, src: list, dst: list) -> float:
	if x <= src[0]:
		return dst[0] + (x - src[0]) * ((dst[1] - dst[0]) / (src[1] - src[0]))
	for i in range(len(src) - 1):
		if x <= src[i + 1] or i == len(src) - 2:
			t = (x - src[i]) / (src[i + 1] - src[i])
			return dst[i] + t * (dst[i + 1] - dst[i])
	return x


class Fit:
	def __init__(self, a: dict, b: dict):
		self.ys = ([a["snout"], a["front"], a["hind"], a["rump"]], [b["snout"], b["front"], b["hind"], b["rump"]])
		self.zs = ([0.0, a["belly"], a["back"], a["top"]], [0.0, b["belly"], b["back"], b["top"]])
		self.xs = ([0.0, a["foot_x"], a["half"]], [0.0, b["foot_x"], b["half"]])

	def point(self, p: Vector) -> Vector:
		x = piecewise(abs(p.x), *self.xs)
		return Vector((x if p.x >= 0 else -x, piecewise(p.y, *self.ys), piecewise(p.z, *self.zs)))


## The body lengthened to [param length] snout to rump: above the belly, the stretch is
## spread between the front and hind feet; below it, each leg moves whole with its foot.
def lengthen(body, length: float) -> None:
	m = landmarks(body)
	extra = length - (m["rump"] - m["snout"])
	if abs(extra) < 1e-4:
		return
	span = m["hind"] - m["front"]
	middle = (m["front"] + m["hind"]) / 2

	def shift(y: float) -> float:  # How far a point at y moves, above the belly.
		if y <= m["front"]:
			return -extra / 2
		if y >= m["hind"]:
			return extra / 2
		return -extra / 2 + extra * (y - m["front"]) / span

	for v in body.data.vertices:
		if v.co.z < m["belly"]:
			# A leg: moved with its own foot, front or hind.
			v.co.y += -extra / 2 if v.co.y < middle else extra / 2
		else:
			v.co.y += shift(v.co.y)
	body.data.update()
	print("lengthened %.3f -> %.3f m" % (m["rump"] - m["snout"], length))


def fit_armature(arm, fit: Fit) -> None:
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	m = arm.matrix_world
	inv = m.inverted()
	for bone in arm.data.edit_bones:
		offset = bone.tail - bone.head  # Kept: the bone's direction and length (its roll too).
		was = m @ bone.head
		bone.head = inv @ fit.point(m @ bone.head)
		bone.tail = bone.head + offset
		print("  %-16s (%.3f %.3f %.3f) -> (%.3f %.3f %.3f)" % (bone.name, *was, *(m @ bone.head)))
	bpy.ops.object.mode_set(mode="OBJECT")


def warp(obj, fit: Fit) -> None:
	inv = obj.matrix_world.inverted()
	for v in obj.data.vertices:
		v.co = inv @ fit.point(obj.matrix_world @ v.co)
	obj.data.update()


def drop_tail(body, arm) -> int:
	"""The tail bones' weights onto the tail's root's parent; the vertices moved."""
	tails = [b for b in arm.data.bones if b.name.startswith("Tail")]
	if not tails:
		return 0
	root = min(tails, key=lambda b: len(b.parent_recursive))
	keeper = root.parent.name
	if keeper not in body.vertex_groups:
		body.vertex_groups.new(name=keeper)
	into = body.vertex_groups[keeper]
	names = {b.name for b in tails}
	indices = {g.index: g.name for g in body.vertex_groups if g.name in names}
	moved = 0
	for v in body.data.vertices:
		weight = sum(e.weight for e in v.groups if e.group in indices)
		if weight <= 0.0:
			continue
		have = next((e.weight for e in v.groups if e.group == into.index), 0.0)
		into.add([v.index], have + weight, "REPLACE")
		moved += 1
	for name in indices.values():
		body.vertex_groups.remove(body.vertex_groups[name])
	return moved


def transfer_weights(ref, body, arm) -> None:
	for group in ref.vertex_groups:
		body.vertex_groups.new(name=group.name)
	mod = body.modifiers.new("Weights", "DATA_TRANSFER")
	mod.object = ref
	mod.use_vert_data = True
	mod.data_types_verts = {"VGROUP_WEIGHTS"}
	mod.vert_mapping = "POLYINTERP_NEAREST"
	mod.layers_vgroup_select_src = "ALL"
	mod.layers_vgroup_select_dst = "NAME"
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.modifier_apply(modifier=mod.name)
	bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
	bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
	body.parent = arm
	mod = body.modifiers.new("Armature", "ARMATURE")
	mod.object = arm


def decimate(body, target: int) -> None:
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	fins = sum(1 for e in bm.edges if len(e.link_faces) > 2)
	if fins:
		# Faces inside the body (TRELLIS leaves them): a face no ray from it gets out of,
		# either way along its normal or a little off it, is inside, and goes.
		from mathutils.bvhtree import BVHTree
		tree = BVHTree.FromBMesh(bm)
		inside = []
		for face in bm.faces:
			n = face.normal
			side = n.orthogonal().normalized()
			rays = [n, -n, (n + 0.5 * side).normalized(), (-n + 0.5 * side).normalized(),
				(n - 0.5 * side).normalized(), (-n - 0.5 * side).normalized()]
			if all(tree.ray_cast(face.calc_center_median() + d * 1e-4, d)[0] is not None for d in rays):
				inside.append(face)
		bmesh.ops.delete(bm, geom=inside, context="FACES")
		bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
		print("removed %d faces inside the body (%d edges had more than two faces)" % (len(inside), fins))
	bm.to_mesh(body.data)
	bm.free()
	ratio = min(1.0, target / max(1, tris(body)))
	if ratio < 1.0:
		mod = body.modifiers.new("Decimate", "DECIMATE")
		mod.ratio = ratio
		mod.use_collapse_triangulate = True
		mod.use_symmetry = True
		mod.symmetry_axis = "X"
		bpy.context.view_layer.objects.active = body
		bpy.ops.object.modifier_apply(modifier=mod.name)
	for poly in body.data.polygons:
		poly.use_smooth = False


def colour(body, swatches: dict, rows: int) -> None:
	m = landmarks(body)
	lo, hi = bounds(points(body))
	mesh = body.data
	if not mesh.uv_layers:
		mesh.uv_layers.new(name="UVMap")
	uv = mesh.uv_layers.active.data
	counts = {}
	for poly in mesh.polygons:
		centre = poly.center
		if centre.z < lo.z + HOOF_BAND * (hi.z - lo.z) and "hooves" in swatches:
			region = "hooves"
		elif poly.normal.z < -0.5 and centre.z < m["belly"] + 0.25 * (m["back"] - m["belly"]) and "underside" in swatches:
			region = "underside"
		else:
			region = "body"
		counts[region] = counts.get(region, 0) + 1
		row, col = swatches[region]
		at = ((col + 0.5) / 8.0, 1.0 - (row + 0.5) / rows)
		for li in poly.loop_indices:
			uv[li].uv = at
	mesh.materials.clear()
	material = bpy.data.materials.get("palette") or bpy.data.materials.new("palette")
	mesh.materials.append(material)
	print("colours: %s" % counts)


def main() -> None:
	a = args()
	if len(a) < 3:
		raise SystemExit("usage: -- <mesh .glb> <reference .glb> <out.glb> [--height M] [--length M] [--tris N] [--turn DEG] [--colours region=row,col ...]")
	mesh_path, ref_path, out = (os.path.abspath(p) for p in a[:3])
	height, length, target, turn, swatches, no_tail = None, None, 0, 0.0, {}, False
	rest = a[3:]
	i = 0
	while i < len(rest):
		if rest[i] == "--height":
			height = float(rest[i + 1])
			i += 2
		elif rest[i] == "--length":
			length = float(rest[i + 1])
			i += 2
		elif rest[i] == "--tris":
			target = int(rest[i + 1])
			i += 2
		elif rest[i] == "--turn":
			turn = float(rest[i + 1])
			i += 2
		elif rest[i] == "--no-tail":
			no_tail = True
			i += 1
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
		# On the mesh's own data: a glTF import's object turns by quaternion, so its
		# rotation_euler (which this once set) was ignored and the mesh never turned.
		import math
		from mathutils import Matrix
		body.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
		body.data.update()
	stand(body, height)
	square(body, height)
	if length:
		lengthen(body, length)
	if target:
		decimate(body, target)
	arm, ref = load_reference(ref_path)
	lo, hi = bounds(points(ref))
	b_lo, b_hi = bounds(points(body))
	scale_reference(arm, ref, (b_hi.z - b_lo.z) / (hi.z - lo.z))
	ma, mb = landmarks(ref), landmarks(body)
	for key in ma:
		print("%-7s reference %7.3f  body %7.3f" % (key, ma[key], mb[key]))
	fit = Fit(ma, mb)
	fit_armature(arm, fit)
	warp(ref, fit)
	transfer_weights(ref, body, arm)
	if no_tail:
		print("no tail: %d vertices' tail weights onto its root's parent" % drop_tail(body, arm))
	bpy.data.objects.remove(ref)
	unweighted = sum(1 for v in body.data.vertices if not v.groups)
	print("rigged: %d vertices, %d with no weight, %d tris" % (len(body.data.vertices), unweighted, tris(body)))
	if swatches:
		# The rows as the palette has them now (square swatches, 8 a row): it grows.
		palette = bpy.data.images.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "kit", "palette.png"))
		rows = round(palette.size[1] / (palette.size[0] / 8))
		bpy.data.images.remove(palette)
		print("palette: %d rows" % rows)
		colour(body, swatches, rows)
	# Each clip once, by its plain name.
	keep = {}
	for action in list(bpy.data.actions):
		plain = action.name.split("|")[-1]
		if plain in keep:
			bpy.data.actions.remove(action)
		else:
			keep[plain] = action
	for plain, action in keep.items():
		action.name = plain
		action.use_fake_user = True
	print("clips: %s" % sorted(keep))
	# The source beside it (art-kit commits a slot's .blend with its .glb).
	bpy.context.scene["source"] = "%s fitted to %s by tools/creature_rig.py" % (os.path.basename(mesh_path), os.path.basename(ref_path))
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(out)[0] + ".blend")
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_animations=True, export_animation_mode="ACTIONS", export_extras=True)
	print("wrote %s" % out)


if __name__ == "__main__":  # Run by blender -P; tools/rabbit_rig.py imports its pieces.
	main()
