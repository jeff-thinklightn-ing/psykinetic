# Rigs a body mesh (a TRELLIS.2 model, cleaned up) to the Universal Animation Library's own
# skeleton, so every UAL clip plays on it at the proportions it was made for (decision 150's
# pipeline: the game imports it through bonemaps/ual.tres onto SkeletonProfileHumanoid).
#
#   blender -b -P tools/body_rig.py -- <mesh .glb/.obj/.blend> <UAL1.glb> <out.glb>
#       [--object NAME] [--height M] [--weights heat|transfer] [--set LANDMARK=VALUE ...]
#
# The mesh should stand as the UAL mannequin stands (its rest pose): a T-pose, arms level and
# in line with the shoulders, palms down, legs straight and parallel, feet forward. It is
# turned to face Blender's -Y as the mannequin does (found from its feet: the toes are ahead
# of the ankles), stood on z = 0, centred, and scaled to --height if given.
#
# The fit: the same landmarks are measured on the mesh and on the mannequin (the crotch, the
# arms' line, the armpits, the fingertips, the legs' centres, the heels and toes), and every
# bone of the UAL armature is moved by piecewise-linear maps between the two: heights through
# the crotch and the arms' line, the arms' bones out along them, the legs' apart, the feet's
# along them. A landmark the mesh hides (a skirt hanging between the legs hides the crotch)
# can be given with --set, in metres once the mesh is stood and scaled (e.g. --set crotch=0.34).
#
# Weights: "heat" (the default) is Blender's automatic weights. "transfer" warps the mannequin
# by the same maps, each vertex by the part its heaviest bone belongs to, and copies its skin
# weights to the mesh by the nearest face; on TRELLIS bodies, whose arms join the torso
# further out than the mannequin's, it gave the shoulder's top to the upper arm, which then
# rose in a point whenever the arm came down. Heat follows the mesh's own shape.
#
# The output is the armature (named "Armature", as the game's import expects) and the mesh,
# skinned, with no clips; tools/body_build.py then decimates it, facets it and adds the
# lean/heavy shape keys.
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ARM = ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")
LEG = ("thigh", "calf")
FOOT = ("foot", "ball")


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def part(bone: str) -> str:
	if any(bone.startswith(p) for p in ARM):
		return "arm"
	if bone.startswith("clavicle"):
		return "clavicle"
	if any(bone.startswith(p) for p in LEG):
		return "leg"
	if any(bone.startswith(p) for p in FOOT):
		return "foot"
	return "torso"


def world_points(obj) -> list:
	return [obj.matrix_world @ v.co for v in obj.data.vertices]


def lerp_map(points: list, value: float) -> float:
	"""Piecewise-linear through [(from, to), ...] sorted by from; straight on past the ends."""
	for i in range(1, len(points)):
		a, b = points[i - 1], points[i]
		if value <= b[0] or i == len(points) - 1:
			t = (value - a[0]) / (b[0] - a[0]) if b[0] != a[0] else 0.0
			return a[1] + (b[1] - a[1]) * t
	return value


def landmarks(obj) -> dict:
	"""The body's landmarks, measured alike on any mesh standing as the mannequin does."""
	pts = world_points(obj)
	height = max(p.z for p in pts)
	bvh = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
	# The crotch: the lowest height at which a ray straight through the middle, front to back,
	# meets the body (below it, it passes between the legs).
	crotch = None
	z = 0.15 * height
	while z < 0.75 * height:
		hit = bvh.ray_cast(Vector((0.0, -10.0, z)), Vector((0.0, 1.0, 0.0)))
		if hit[0] is not None:
			crotch = z
			break
		z += 0.002 * height
	if crotch is None:
		raise SystemExit("no crotch found: are the legs apart?")
	tip = max(p.x for p in pts)  # The left fingertips (the left side is +x).
	along = [p for p in pts if 0.55 * tip <= p.x <= 0.65 * tip]
	arm_z = sum(p.z for p in along) / len(along)
	under = min(p.z for p in along)
	slab = [p.x for p in pts if p.x > 0.0 and abs(p.z - (under - 0.01 * height)) < 0.006 * height and p.x < 0.5 * tip]
	armpit = max(slab) if slab else 0.12 * height
	knee_slab = [p.x for p in pts if p.x > 0.0 and abs(p.z - 0.5 * crotch) < 0.01 * height]
	leg_x = sum(knee_slab) / len(knee_slab)
	sole = [p for p in pts if p.z < 0.04 * height and p.x > 0.0]
	toe = min(p.y for p in sole)  # Front is -y.
	heel = max(p.y for p in sole)
	return {"height": height, "crotch": crotch, "tip": tip, "arm_z": arm_z, "armpit": armpit,
		"leg_x": leg_x, "toe": toe, "heel": heel}


class Fit:
	"""Maps a point of the mannequin to the body, by the part it belongs to."""

	def __init__(self, m: dict, n: dict):
		self.m, self.n = m, n
		self.s = n["height"] / m["height"]
		self.z_map = [(0.0, 0.0), (m["crotch"], n["crotch"]), (m["arm_z"], n["arm_z"]), (m["height"], n["height"])]
		self.x_arm = [(0.0, 0.0), (m["armpit"], n["armpit"]), (m["tip"], n["tip"])]
		self.y_foot = [(m["toe"], n["toe"]), (m["heel"], n["heel"])]

	def point(self, p: Vector, where: str) -> Vector:
		side = 1.0 if p.x >= 0.0 else -1.0
		x = abs(p.x)
		if where == "arm":
			return Vector((side * lerp_map(self.x_arm, x), p.y * self.s, p.z - self.m["arm_z"] + self.n["arm_z"]))
		if where == "clavicle":
			return Vector((side * x * self.n["armpit"] / self.m["armpit"], p.y * self.s, lerp_map(self.z_map, p.z)))
		if where in ("leg", "foot"):
			y = lerp_map(self.y_foot, p.y) if where == "foot" else p.y * self.s
			return Vector((side * x * self.n["leg_x"] / self.m["leg_x"], y, lerp_map(self.z_map, p.z)))
		return Vector((p.x * self.n["armpit"] / self.m["armpit"], p.y * self.s, lerp_map(self.z_map, p.z)))


def face_forward(obj) -> None:
	"""Turns the mesh about z so its toes point to -y, as the mannequin's do."""
	pts = world_points(obj)
	height = max(p.z for p in pts) - min(p.z for p in pts)
	low = min(p.z for p in pts)
	sole = [p for p in pts if p.z < low + 0.03 * height]
	ankle = [p for p in pts if low + 0.06 * height < p.z < low + 0.09 * height]
	ahead = (sum((p for p in sole), Vector()) / len(sole)) - (sum((p for p in ankle), Vector()) / len(ankle))
	ahead.z = 0.0
	turns = {(0, -1): 0.0, (1, 0): -90.0, (0, 1): 180.0, (-1, 0): 90.0}
	axis = (round(ahead.x / ahead.length), 0) if abs(ahead.x) > abs(ahead.y) else (0, round(ahead.y / ahead.length))
	# In Euler first: a glTF import's object turns by quaternion, and its rotation_euler alone
	# would be ignored.
	obj.rotation_mode = "XYZ"
	obj.rotation_euler.z += math.radians(turns[axis])
	print("toes pointed %s; turned %.0f degrees to face -y" % (axis, turns[axis]))
	bpy.context.view_layer.update()


def stand(obj, height) -> None:
	"""Feet on z = 0, centred on x and y, scaled to height (metres) if given; all applied."""
	bpy.context.view_layer.objects.active = obj
	obj.select_set(True)
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	pts = world_points(obj)
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	scale = height / (hi.z - lo.z) if height else 1.0
	feet = [p for p in pts if p.z < lo.z + 0.1 * (hi.z - lo.z)]
	centre = Vector(((lo.x + hi.x) * 0.5, sum(p.y for p in feet) / len(feet), lo.z))
	for v in obj.data.vertices:
		v.co = (v.co - centre) * scale
	obj.data.update()


def load_mesh(path: str, name) -> object:
	before = set(bpy.data.objects)
	if path.endswith(".blend"):
		with bpy.data.libraries.load(path) as (src, dst):
			dst.objects = [n for n in src.objects]
		for obj in dst.objects:
			if obj is not None and obj.type == "MESH":
				bpy.context.scene.collection.objects.link(obj)
	elif path.endswith(".obj"):
		bpy.ops.wm.obj_import(filepath=path)
	else:
		bpy.ops.import_scene.gltf(filepath=path)
	new = [o for o in bpy.data.objects if o not in before]
	meshes = [o for o in new if o.type == "MESH" and (name is None or o.name == name)]
	for obj in new:
		if obj not in meshes:
			bpy.data.objects.remove(obj)
	if not meshes:
		raise SystemExit("no mesh%s in %s" % (" named " + name if name else "", path))
	for obj in meshes:
		obj.parent = None
		obj.modifiers.clear()
		obj.vertex_groups.clear()
		if obj.data.shape_keys:
			obj.shape_key_clear()
	bpy.ops.object.select_all(action="DESELECT")
	for obj in meshes:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.name = "Body"
	# One surface: a textured mesh comes split along its UV seams (each a
	# vertex twice), which bone heat sees as separate pieces and leaves
	# unweighted. The UVs are the faces' corners', so welding keeps them.
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(body.data)
	before = len(bm.verts)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bm.to_mesh(body.data)
	bm.free()
	if len(body.data.vertices) < before:
		print("welded: %d vertices to %d" % (before, len(body.data.vertices)))
	return body


def load_ual(path: str) -> tuple:
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=path)
	new = [o for o in bpy.data.objects if o not in before]
	arm = [o for o in new if o.type == "ARMATURE"][0]
	mannequin = [o for o in new if o.name.startswith("Mannequin")][0]
	for obj in new:
		if obj not in (arm, mannequin):
			bpy.data.objects.remove(obj)
	if arm.animation_data:
		arm.animation_data_clear()
	for action in list(bpy.data.actions):
		bpy.data.actions.remove(action)
	arm.name = "Armature"
	return arm, mannequin


def fit_armature(arm, fit: Fit) -> None:
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	m = arm.matrix_world
	inv = m.inverted()
	moved = {}
	for bone in arm.data.edit_bones:
		where = part(bone.name)
		moved[bone.name] = (inv @ fit.point(m @ bone.head, where), inv @ fit.point(m @ bone.tail, where))
	for bone in arm.data.edit_bones:
		bone.use_connect = False
	for bone in arm.data.edit_bones:
		bone.head, bone.tail = moved[bone.name]
	bpy.ops.object.mode_set(mode="OBJECT")


def warp_mannequin(mannequin, fit: Fit) -> None:
	"""The mannequin reshaped by the fit, each vertex by the part of its heaviest bone."""
	mannequin.modifiers.clear()
	names = {g.index: g.name for g in mannequin.vertex_groups}
	mw = mannequin.matrix_world
	inv = mw.inverted()
	for v in mannequin.data.vertices:
		heaviest = max(v.groups, key=lambda g: g.weight, default=None)
		where = part(names[heaviest.group]) if heaviest else "torso"
		v.co = inv @ fit.point(mw @ v.co, where)
	mannequin.data.update()


def transfer_weights(mannequin, body) -> None:
	for group in mannequin.vertex_groups:
		body.vertex_groups.new(name=group.name)
	mod = body.modifiers.new("Weights", "DATA_TRANSFER")
	mod.object = mannequin
	mod.use_vert_data = True
	mod.data_types_verts = {"VGROUP_WEIGHTS"}
	mod.vert_mapping = "POLYINTERP_NEAREST"
	mod.layers_vgroup_select_src = "ALL"
	mod.layers_vgroup_select_dst = "NAME"
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.modifier_apply(modifier=mod.name)
	# At most four bones a vertex (what the game skins with), the rest dropped, the four
	# summing to one.
	for v in body.data.vertices:
		# Copied out first: v.groups changes under the removals.
		kept = sorted(((g.group, g.weight) for g in v.groups), key=lambda gw: gw[1], reverse=True)
		for group, _ in kept[4:]:
			body.vertex_groups[group].remove([v.index])
		total = sum(w for _, w in kept[:4])
		if total > 0.0:
			for group, w in kept[:4]:
				body.vertex_groups[group].add([v.index], w / total, "REPLACE")


## Below the crotch, a vertex keeps no weight from the other leg's bones, and below the
## knee none but its own leg's: bone heat lets legs that touch (thighs close together, boots
## side by side) share weights, and gives a boot's heel to "root" (which lies along the
## ground there and never moves with a foot), so a foot dragged the other boot, or left its
## heel behind, as it stepped. A vertex left with none takes its own leg's bone at its height.
def own_side_legs(body, arm, crotch: float) -> None:
	mw = arm.matrix_world
	bones = arm.data.bones
	left = 1.0 if (mw @ bones["thigh_l"].head_local).x > 0.0 else -1.0
	legs = {s: {b.name for b in bones if b.name.endswith("_" + s) and part(b.name) in ("leg", "foot")} for s in "lr"}
	knee = {s: (mw @ bones["calf_" + s].head_local).z for s in "lr"}
	ankle = {s: (mw @ bones["foot_" + s].head_local).z for s in "lr"}
	names = {g.index: g.name for g in body.vertex_groups}
	moved, bare = 0, 0
	for v in body.data.vertices:
		p = body.matrix_world @ v.co
		if p.z > crotch:
			continue
		side = "l" if p.x * left > 0.0 else "r"
		other = legs["r" if side == "l" else "l"]
		below_knee = p.z < knee[side]
		for g in [(g.group, g.weight) for g in v.groups]:
			name = names[g[0]]
			if g[1] > 0.0 and (name in other or name == "root" or (below_knee and name not in legs[side])):
				body.vertex_groups[g[0]].remove([v.index])
				moved += 1
		if not any(g.weight > 0.0 for g in v.groups):
			bone = "thigh_" if p.z > knee[side] else "calf_" if p.z > ankle[side] else "foot_"
			body.vertex_groups[bone + side].add([v.index], 1.0, "REPLACE")
			bare += 1
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)
	print("legs: %d weights from the other leg removed, %d vertices given their own" % (moved, bare))


def main() -> None:
	a = args()
	if len(a) < 3:
		raise SystemExit("usage: -- <mesh> <UAL1.glb> <out.glb> [--object NAME] [--height M] [--weights transfer|heat]")
	mesh_path, ual_path, out = (os.path.abspath(p) for p in a[:3])
	name, height, weights, given = None, None, "heat", {}
	rest = a[3:]
	for i in range(0, len(rest), 2):
		if rest[i] == "--object":
			name = rest[i + 1]
		elif rest[i] == "--height":
			height = float(rest[i + 1])
		elif rest[i] == "--weights":
			weights = rest[i + 1]
		elif rest[i] == "--set":
			key, value = rest[i + 1].split("=")
			given[key] = float(value)
		else:
			raise SystemExit("unknown argument %s" % rest[i])
	bpy.ops.wm.read_factory_settings(use_empty=True)
	body = load_mesh(mesh_path, name)
	face_forward(body)
	stand(body, height)
	arm, mannequin = load_ual(ual_path)
	m = landmarks(mannequin)
	n = landmarks(body)
	n.update(given)
	for key in m:
		print("%-7s mannequin %7.3f  body %7.3f%s" % (key, m[key], n[key], " (given)" if key in given else ""))
	fit = Fit(m, n)
	fit_armature(arm, fit)
	bpy.ops.object.select_all(action="DESELECT")
	if weights == "heat":
		bpy.data.objects.remove(mannequin)
		body.select_set(True)
		arm.select_set(True)
		bpy.context.view_layer.objects.active = arm
		bpy.ops.object.parent_set(type="ARMATURE_AUTO")
		own_side_legs(body, arm, fit.n["crotch"])
	else:
		warp_mannequin(mannequin, fit)
		transfer_weights(mannequin, body)
		bpy.data.objects.remove(mannequin)
		body.parent = arm
		mod = body.modifiers.new("Armature", "ARMATURE")
		mod.object = arm
	if not any(body.data.materials):
		# A shape-only mesh (TRELLIS): matte grey until body_build colours it.
		material = bpy.data.materials.new("Body")
		material.diffuse_color = (0.6, 0.6, 0.6, 1.0)
		material.roughness = 1.0
		material.metallic = 0.0
		bsdf = material.node_tree.nodes.get("Principled BSDF") if material.node_tree else None
		if bsdf:
			bsdf.inputs["Base Color"].default_value = material.diffuse_color
			bsdf.inputs["Roughness"].default_value = 1.0
			bsdf.inputs["Metallic"].default_value = 0.0
		body.data.materials.append(material)
	unweighted = sum(1 for v in body.data.vertices if not v.groups)
	print("rigged: %d vertices, %d with no weight" % (len(body.data.vertices), unweighted))
	bpy.data.orphans_purge(do_recursive=True)
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_animations=False, export_extras=True,
		export_vertex_color="ACTIVE")  # A mesh's own colours (art-gen's projection) kept for body_build.
	print("wrote %s" % out)


main()
