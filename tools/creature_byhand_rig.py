import bpy, sys
# Art-kit's hand-made orc rigged for a clip sheet (a trial, not landed): the Body weighted from
# the kit's Orc_work on the same Armature (nearest face), each bone-parented part joined in rigid
# on its bone, the flaps of the loincloth below the hips taking the thighs' weights; written as a
# .glb with its two materials and their images.
#   blender -b <hand .blend> -P rig_byhand.py -- <weights' .blend> <its object> <out .glb> [part to leave out ...]
a = sys.argv[sys.argv.index("--") + 1:]
kit, source, out, leave = a[0], a[1], a[2], a[3:]
arm = bpy.data.objects["Armature"]
arm.data.pose_position = "REST"
body = bpy.data.objects["Body"]
for o in list(bpy.data.objects):
	if o.type == "EMPTY" or o.name.startswith("Slot_") or o.name in leave:
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


# The parts' bones, before they are unparented.
parts = {o.name: o.parent_bone for o in bpy.data.objects if o.type == "MESH" and o.parent == arm and o.parent_type == "BONE"}
print("byhand: parts", parts)
for o in [o for o in bpy.data.objects if o.type == "MESH" and o not in (ref,)]:
	world_fix(o)
for g in ref.vertex_groups:
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
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
pelvis_z = (arm.matrix_world @ arm.data.bones["thigh_l"].head_local).z
for name, bone in parts.items():
	o = bpy.data.objects[name]
	if name == "loincloth":
		# The belt on the pelvis, the flaps below the hips with the thigh on their side.
		for b in ("pelvis", "thigh_l", "thigh_r"):
			o.vertex_groups.new(name=b)
		for v in o.data.vertices:
			p = o.matrix_world @ v.co
			if p.z > pelvis_z:
				o.vertex_groups["pelvis"].add([v.index], 1.0, "REPLACE")
			else:
				side = "thigh_l" if p.x > 0 else "thigh_r"
				f = min(1.0, (pelvis_z - p.z) / 0.25)
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
print("byhand: %d tris, %d body vertices unweighted, materials %s, wrote %s" % (tris, unweighted, [m.name for m in body.data.materials], out))
