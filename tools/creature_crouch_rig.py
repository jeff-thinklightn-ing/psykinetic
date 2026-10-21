import bpy, sys
from mathutils import Vector
# Art-kit's crouched kobold (digitigrade rest: knee forward, hock high behind, the foot's long
# bone forward and down to the ball) rigged: the leg bones moved to its empties (knee_x, hock_x,
# ankle_x = the ball), its Body weighted from the straight-legged kobold (nearest face) above the
# legs, the legs weighted afresh by distance to their own bones; parts rigid on their bones.
#   blender -b kobold_by_hand.blend -P rig_kobold_crouch.py -- <weights' .blend> <its object> <out .glb>
a = sys.argv[sys.argv.index("--") + 1:]
kit, source, out = a[0], a[1], a[2]
arm = bpy.data.objects["Armature"]
arm.data.pose_position = "REST"
E = {o.name: o.matrix_world.translation.copy() for o in bpy.data.objects if o.type == "EMPTY"}
inv = arm.matrix_world.inverted()

# The legs' bones onto the empties.
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for s in ("l", "r"):
	knee, hock, ball = (inv @ E["%s_%s" % (n, s)] for n in ("knee", "hock", "ankle"))
	toe_dir = (eb["ball_" + s].tail - eb["ball_" + s].head)
	toe_len = toe_dir.length
	toe_dir.z = 0.0
	toe_dir = toe_dir.normalized() if toe_dir.length > 1e-6 else Vector((0, -1, 0))
	for b in ("thigh", "calf", "foot", "ball"):
		eb["%s_%s" % (b, s)].use_connect = False
	eb["thigh_" + s].tail = knee
	eb["calf_" + s].head = knee
	eb["calf_" + s].tail = hock
	eb["foot_" + s].head = hock
	eb["foot_" + s].tail = ball
	eb["ball_" + s].head = ball
	eb["ball_" + s].tail = ball + toe_dir * toe_len
bpy.ops.object.mode_set(mode="OBJECT")
bones = {b.name: (arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones}
hip_z = bones["thigh_l"][0].z

body = bpy.data.objects["Body"]
for o in list(bpy.data.objects):
	if o.type == "EMPTY" or o.name.startswith("Slot_") or o.name == "pick":  # (Its weapon is the game's, socketed.)
		bpy.data.objects.remove(o)
with bpy.data.libraries.load(kit) as (src, dst):
	dst.objects = [source]
ref = dst.objects[0]
bpy.context.scene.collection.objects.link(ref)
ref.parent = None
ref.modifiers.clear()


def world_fix(o):
	m = o.matrix_world.copy()
	o.parent = None
	o.matrix_world = m
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


parts = {o.name: o.parent_bone for o in bpy.data.objects if o.type == "MESH" and o.parent == arm and o.parent_type == "BONE"}
for o in [o for o in bpy.data.objects if o.type == "MESH" and o is not ref]:
	world_fix(o)
for g in ref.vertex_groups:
	if g.name not in body.vertex_groups:
		body.vertex_groups.new(name=g.name)
dt = body.modifiers.new("weights", "DATA_TRANSFER")
dt.object = ref
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier=dt.name)


def seg(p, a, b):
	ab = b - a
	t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
	return (p - (a + ab * t)).length


LEG = ("thigh", "calf", "foot", "ball")
groups = {g.index: g.name for g in body.vertex_groups}
legs = 0
for v in body.data.vertices:
	p = body.matrix_world @ v.co
	leg_w = sum(g.weight for g in v.groups if groups[g.group].split("_")[0] in LEG)
	behind = p.y > 0.06  # The tail's root and the tail, behind the hips: the transfer's (the pelvis).
	if behind or (leg_w < 0.5 and p.z > hip_z - 0.06):
		continue
	s = "l" if p.x >= 0 else "r"
	d = {b: seg(p, *bones["%s_%s" % (b, s)]) for b in LEG}
	near = sorted(d, key=d.get)[:2]
	w = {b: 1.0 / max(d[b], 0.004) ** 4 for b in near}
	# Up at the hip the pelvis shares it.
	up = max(0.0, min(1.0, (p.z - (hip_z - 0.06)) / 0.08))
	total = sum(w.values())
	for g in list(v.groups):
		body.vertex_groups[groups[g.group]].remove([v.index])
	for b in near:
		body.vertex_groups["%s_%s" % (b, s)].add([v.index], (1.0 - 0.5 * up) * w[b] / total, "REPLACE")
	if up > 0.0:
		body.vertex_groups["pelvis"].add([v.index], 0.5 * up, "REPLACE")
	legs += 1
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
for name, bone in parts.items():
	o = bpy.data.objects[name]
	if name == "loincloth":
		for b in ("pelvis", "thigh_l", "thigh_r"):
			o.vertex_groups.new(name=b)
		for v in o.data.vertices:
			p = o.matrix_world @ v.co
			if p.z > hip_z:
				o.vertex_groups["pelvis"].add([v.index], 1.0, "REPLACE")
			else:
				side = "thigh_l" if p.x > 0 else "thigh_r"
				f = min(1.0, (hip_z - p.z) / 0.12)
				o.vertex_groups["pelvis"].add([v.index], 1.0 - f * 0.7, "REPLACE")
				o.vertex_groups[side].add([v.index], f * 0.7, "REPLACE")
	else:
		o.vertex_groups.new(name=bone).add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
unweighted = sum(1 for v in body.data.vertices if not v.groups)
bpy.data.objects.remove(ref)
bpy.ops.object.select_all(action="DESELECT")
for name in list(parts) + ["Body"]:
	bpy.data.objects[name].select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.parent = arm
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
arm.data.pose_position = "POSE"
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
body.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True, export_skins=True,
	export_animations=False, export_image_format="AUTO")
print("crouch: %d tris, %d leg vertices weighted afresh, %d unweighted, materials %s, parts %s, wrote %s" % (
	tris, legs, unweighted, [m.name for m in body.data.materials], parts, out))
