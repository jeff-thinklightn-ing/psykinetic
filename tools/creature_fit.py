# Rigs an image-to-mesh creature (art-gen's TRELLIS meshes by the goblin's recipe, standing arms
# down as in its concept) to the Universal Animation Library's skeleton, so every humanoid clip
# and Client3D socket fits it as it does the generator's bodies (the coordinator's route trial,
# decision 478 amended). Its joints are given by hand, read off the mesh (--joints, a JSON of the
# left side's and the middle's joints in metres, as the mesh stands: its face toward -Y, its left
# +X, Z up; the right side mirrored), since its arms touch its body and can't be found by gaps.
#
#   blender -b -P tools/creature_fit.py -- <mesh .glb> <UAL1.glb> <out .glb> --joints <joints.json>
#       [--rigid pelvis:XABS:YMIN:ZMAX] [--weights heat|distance] [--debug]
#
# The skeleton: the UAL's at the mesh's height, its joints moved to the given ones; its arms
# straight out along X from the shoulder as the UAL stands (T-pose), as long as the mesh's.
# The weights: the arms posed down onto the mesh's, Blender's automatic (heat) weights taken in
# that pose, then the mesh posed with the arms back up into the T-pose and kept so: the result
# rests in T-pose like every other humanoid here. --rigid holds the vertices within XABS of the
# middle, behind YMIN and below ZMAX wholly to the pelvis (a tail: heat would hang it on the
# thighs). The mesh keeps its own material and texture.
import json
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from body_gen import skeleton  # noqa: E402

## The joints a --joints file gives (each bone's head), "_l" ones mirrored to "_r".
MIDDLE = ["pelvis", "spine_03", "neck_01", "Head", "Head.tail"]
## The distance weights' falloff (body_gen's FALLOFF), where heat finds no solution.
FALLOFF = 4.0
## Each limb's bones may blend with these of the trunk where they join it.
JOINS = {"arm_l": ("spine_03",), "arm_r": ("spine_03",), "leg_l": ("pelvis",), "leg_r": ("pelvis",)}


def limb_of(bone: str) -> str:
	"""Which limb [bone] belongs to: arm_l, arm_r, leg_l, leg_r, or the trunk."""
	for part in ("clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"):
		if bone.startswith(part + "_"):
			return "arm_" + bone[-1]
	for part in ("thigh", "calf", "foot", "ball"):
		if bone.startswith(part + "_"):
			return "leg_" + bone[-1]
	return "trunk"
SIDES = ["clavicle", "upperarm", "lowerarm", "hand", "thigh", "calf", "foot", "ball"]


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def main() -> None:
	a = args()
	mesh_path, ual, out = (os.path.abspath(p) for p in a[:3])
	joints = json.load(open(a[a.index("--joints") + 1], encoding="utf-8"))
	rigid = a[a.index("--rigid") + 1].split(":") if "--rigid" in a else None
	# "distance": every vertex by its limb's bones' distances, no heat (a fist against a thigh
	# that heat gave both to tears in the T-pose).
	weights = a[a.index("--weights") + 1] if "--weights" in a else "heat"
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=mesh_path)
	body = [o for o in bpy.data.objects if o.type == "MESH"][0]
	# One surface again: glTF splits a vertex wherever its UVs or normals part, and heat weighting
	# fails on the islands (the UVs are per face corner, so they survive the weld).
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	bm.to_mesh(body.data)
	bm.free()
	height = max((body.matrix_world @ v.co).z for v in body.data.vertices)
	arm, J = skeleton(ual, height)
	want = {}
	for name in MIDDLE:
		want[name] = Vector(joints[name])
	for side, sign in (("l", 1.0), ("r", -1.0)):
		for part in SIDES:
			x, y, z = joints[part + "_l"]
			want["%s_%s" % (part, side)] = Vector((x * sign, y, z))
	want["spine_01"] = want["pelvis"].lerp(want["spine_03"], 0.33)
	want["spine_02"] = want["pelvis"].lerp(want["spine_03"], 0.66)
	# The T-pose: each arm out along the UAL's own arm from its shoulder, as long as the mesh's.
	down = {}
	for side in ("l", "r"):
		sh, el, wr = (want["%s_%s" % (p, side)] for p in ("upperarm", "lowerarm", "hand"))
		down[side] = (sh.copy(), el.copy(), wr.copy())
		u_dir = (J["lowerarm_" + side] - J["upperarm_" + side]).normalized()
		l_dir = (J["hand_" + side] - J["lowerarm_" + side]).normalized()
		want["lowerarm_" + side] = sh + u_dir * (el - sh).length
		want["hand_" + side] = want["lowerarm_" + side] + l_dir * (wr - el).length
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	bones = arm.data.edit_bones
	old = {b.name: (b.head.copy(), b.tail.copy()) for b in bones}
	k = height / max(0.001, max(J[n].z for n in J if not n.endswith(".tail")))
	new = {}

	def place(b):
		if b.name in want:
			new[b.name] = want[b.name]
		elif b.parent is None:
			new[b.name] = old[b.name][0] * k
		else:
			p = b.parent.name
			scale = k
			if p.startswith("hand_") or any(p.startswith(f) for f in ("thumb_", "index_", "middle_", "ring_", "pinky_")):
				side = p[-1]
				scale = (want["hand_" + side] - want["lowerarm_" + side]).length / max(0.001, (J["hand_" + side] - J["lowerarm_" + side]).length)
			new[b.name] = new[p] + (old[b.name][0] - old[p][0]) * scale
		for c in b.children:
			place(c)

	for b in bones:
		b.use_connect = False
	for b in [b for b in bones if b.parent is None]:
		place(b)
	for b in bones:
		h, t = old[b.name]
		child = next((c for c in b.children if (old[c.name][0] - t).length < 1e-4), None)
		if b.name == "Head":
			tail = want["Head.tail"]
		elif child is not None:
			tail = new[child.name]
		else:
			tail = new[b.name] + (t - h) * k
		b.head, b.tail = new[b.name], tail
	t_rest = {b.name: (b.head.copy(), b.tail.copy(), b.roll) for b in bones}
	bpy.ops.object.mode_set(mode="OBJECT")
	t_matrix = {b.name: b.matrix_local.copy() for b in arm.data.bones}
	# The arms posed down onto the mesh's.
	bpy.ops.object.mode_set(mode="POSE")
	for side in ("l", "r"):
		sh, el, wr = down[side]
		for bone, at, to in (("upperarm_" + side, sh, el), ("lowerarm_" + side, el, wr)):
			pb = arm.pose.bones[bone]
			head = pb.head.copy()
			now = (pb.tail - pb.head).normalized()
			q = now.rotation_difference((to - at).normalized())
			pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
			bpy.context.view_layer.update()
	bpy.ops.pose.armature_apply(selected=False)
	if "--debug" in a:
		for side in ("l",):
			for name, target in zip(("upperarm_", "lowerarm_", "hand_"), down[side]):
				b = arm.data.bones[name + side]
				print("DEBUG %s%s head %s target %s tail %s" % (name, side, tuple(round(c, 3) for c in arm.matrix_world @ b.head_local),
					tuple(round(c, 3) for c in target), tuple(round(c, 3) for c in arm.matrix_world @ b.tail_local)))
			for name in ("middle_01_", "middle_04_leaf_", "clavicle_"):
				b = arm.data.bones[name + side]
				print("DEBUG %s%s head %s tail %s" % (name, side, tuple(round(c, 3) for c in arm.matrix_world @ b.head_local),
					tuple(round(c, 3) for c in arm.matrix_world @ b.tail_local)))
	bpy.ops.object.mode_set(mode="OBJECT")
	# Heat weights in that pose.
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.parent_set(type="ARMATURE_AUTO" if weights == "heat" else "ARMATURE_NAME")
	bare = sum(1 for v in body.data.vertices if not v.groups)
	if bare:
		# Where heat found no solution (a TRELLIS mesh's folds and touching parts): each bare
		# vertex weighted by its distance to the deforming bones' segments, as they stand in
		# this pose, the three nearest kept (body_gen's weigh), 1 / d^FALLOFF.
		from mathutils.geometry import intersect_point_line
		segments = []
		for b in arm.data.bones:
			if b.name == "root" or "_leaf" in b.name:
				continue
			segments.append((b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local))
		groups = {name: body.vertex_groups.get(name) or body.vertex_groups.new(name=name) for name, _, _ in segments}
		for v in body.data.vertices:
			if v.groups:
				continue
			p = body.matrix_world @ v.co
			scores = []
			for name, h, t in segments:
				closest, f = intersect_point_line(p, h, t)
				f = min(max(f, 0.0), 1.0)
				d = (p - h.lerp(t, f)).length
				scores.append((1.0 / max(d, 0.005) ** FALLOFF, name))
			scores.sort(reverse=True)
			# Only its nearest bone's own limb (an arm, a leg, the trunk): a hand hanging by a
			# thigh would otherwise take both, and tear when the arm rises into the T-pose.
			chain = limb_of(scores[0][1])
			top = [s for s in scores if limb_of(s[1]) == chain or s[1] in JOINS.get(chain, ())][:3]
			total = sum(w for w, _ in top)
			for w, name in top:
				groups[name].add([v.index], w / total, "REPLACE")
	if "--debug" in a:
		from collections import Counter
		names = {g.index: g.name for g in body.vertex_groups}
		hand = arm.matrix_world @ arm.data.bones["hand_r"].head_local
		near = Counter()
		for v in body.data.vertices:
			if ((body.matrix_world @ v.co) - hand).length < 0.12 and v.groups:
				near[names[max(v.groups, key=lambda g: g.weight).group]] += 1
		print("DEBUG near hand_r:", near.most_common(6), "vertices", len(body.data.vertices))
	if rigid:
		bone, xabs, ymin, zmax = rigid[0], float(rigid[1]), float(rigid[2]), float(rigid[3])
		names = {g.index: g.name for g in body.vertex_groups}

		def strongest(v):
			return names[max(v.groups, key=lambda g: g.weight).group] if v.groups else ""

		held = [v.index for v in body.data.vertices if abs((body.matrix_world @ v.co).x) < xabs
			and (body.matrix_world @ v.co).y > ymin and (body.matrix_world @ v.co).z < zmax]
		for g in body.vertex_groups:
			g.remove(held)
		(body.vertex_groups.get(bone) or body.vertex_groups.new(name=bone)).add(held, 1.0, "REPLACE")
		print("rigid: %d vertices on %s" % (len(held), bone))
	# Faces bridging an arm to a leg (a TRELLIS mesh fuses a hand to a thigh where they touch) cut,
	# leaving a small gap there rather than a tear when the arm rises.
	import bmesh
	names = {g.index: g.name for g in body.vertex_groups}
	limb = [limb_of(names[max(v.groups, key=lambda g: g.weight).group]) if v.groups else "trunk" for v in body.data.vertices]
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bridges = [f for f in bm.faces if {limb[v.index][:3] for v in f.verts} >= {"arm", "leg"}]
	bmesh.ops.delete(bm, geom=bridges, context="FACES_ONLY")
	bm.to_mesh(body.data)
	bm.free()
	print("cut: %d faces bridging an arm to a leg" % len(bridges))
	# Back up into the T-pose, the mesh with it, and kept so.
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="POSE")
	order = []

	def walk(b):
		order.append(b.name)
		for c in b.children:
			walk(c)

	for b in [b for b in arm.data.bones if b.parent is None]:
		walk(b)
	for name in order:
		arm.pose.bones[name].matrix = t_matrix[name]
		bpy.context.view_layer.update()
	bpy.ops.object.mode_set(mode="OBJECT")
	if "--debug" in a:
		down_pos = [(body.matrix_world @ v.co).copy() for v in body.data.vertices]
	bpy.context.view_layer.objects.active = body
	modifier = [m for m in body.modifiers if m.type == "ARMATURE"][0]
	bpy.ops.object.modifier_apply(modifier=modifier.name)
	if "--debug" in a:
		names = {g.index: g.name for g in body.vertex_groups}
		vs = body.data.vertices
		def top(v):
			return names[max(v.groups, key=lambda g: g.weight).group] if v.groups else "-"
		shown = 0
		for e in body.data.edges:
			i, j = e.vertices
			if (vs[i].co - vs[j].co).length > 0.15 and shown < 12:
				shown += 1
				print("DEBUG long edge %.2f: %s %s (%s) -- %s %s (%s)" % ((vs[i].co - vs[j].co).length,
					tuple(round(c, 2) for c in down_pos[i]), top(vs[i]), [(names[g.group], round(g.weight, 2)) for g in vs[i].groups][:3],
					tuple(round(c, 2) for c in down_pos[j]), top(vs[j]), [(names[g.group], round(g.weight, 2)) for g in vs[j].groups][:3]))
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for b in arm.data.edit_bones:
		b.head, b.tail, b.roll = t_rest[b.name]
	bpy.ops.object.mode_set(mode="POSE")
	for pb in arm.pose.bones:
		pb.matrix_basis = Matrix.Identity(4)
	bpy.ops.object.mode_set(mode="OBJECT")
	body.modifiers.new("Armature", "ARMATURE").object = arm
	arm.name = "Armature"
	tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
	print("fitted: %d tris, %.2f m, %d vertices unweighted by heat" % (tris, height, bare))
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True, export_skins=True,
		export_animations=False)
	print("wrote %s" % out)


if __name__ == "__main__":
	main()
