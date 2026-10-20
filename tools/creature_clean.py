# Cleans a TRELLIS.2 body before its rig (decision 529's route; the coordinator after Jeff's
# hand clean-up of the orc kit): what Jeff did by hand, by script, so no raw topology reaches
# him or the game. From art-gen's painted mesh (standing arms down, as creature_fit.py takes it):
#   1. joined and welded (glTF's seams split every face: the kit's orc was 5,553 loose triangles);
#   2. loose shells under --shell of the biggest's vertices dropped;
#   3. given thickness where it is a sheet (Solidify, --thick m, inward), so the remesh closes it;
#   4. voxel remeshed (--voxel m): one watertight surface, holes closed, slivers gone;
#      the remesh's own loose bits dropped again, its stairs smoothed a little;
#   5. remeshed to clean quads (QuadriFlow, --quads faces; a collapse to twice that many
#      triangles if QuadriFlow fails);
#   6. unwrapped (Smart UV Project) and its paint baked from the raw mesh onto the new UVs
#      (Cycles, the diffuse colour only, from the raw mesh near it: --paint px);
#   7. written as a .glb with its paint embedded, for creature_fit.py.
#
#   blender -b -P tools/creature_clean.py -- <raw .glb> <out .glb> [--quads N] [--voxel M]
#       [--thick M] [--shell F] [--paint PX]
import os
import sys
import time

import bmesh
import bpy


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(a: list, name: str, default):
	return type(default)(a[a.index(name) + 1]) if name in a else default


def tris(obj) -> int:
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def shells(obj) -> list:
	"""Each loose part's vertex indices, biggest first."""
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.verts.ensure_lookup_table()
	seen, out = set(), []
	for v in bm.verts:
		if v.index in seen:
			continue
		part, stack = [], [v]
		while stack:
			x = stack.pop()
			if x.index in seen:
				continue
			seen.add(x.index)
			part.append(x.index)
			stack.extend(e.other_vert(x) for e in x.link_edges)
		out.append(part)
	bm.free()
	return sorted(out, key=len, reverse=True)


def drop_small(obj, fraction: float) -> int:
	parts = shells(obj)
	small = [i for part in parts[1:] if len(part) < fraction * len(parts[0]) for i in part]
	if small:
		bm = bmesh.new()
		bm.from_mesh(obj.data)
		bm.verts.ensure_lookup_table()
		bmesh.ops.delete(bm, geom=[bm.verts[i] for i in small], context="VERTS")
		bm.to_mesh(obj.data)
		bm.free()
	return len([p for p in parts[1:] if len(p) < fraction * len(parts[0])])


def apply(obj, kind: str, **settings):
	mod = obj.modifiers.new(kind, kind)
	for k, v in settings.items():
		setattr(mod, k, v)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_apply(modifier=mod.name)


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <raw .glb> <out .glb> [--quads N] [--voxel M] [--thick M] [--shell F] [--paint PX]")
	src, out = os.path.abspath(a[0]), os.path.abspath(a[1])
	quads, voxel, thick = opt(a, "--quads", 5000), opt(a, "--voxel", 0.012), opt(a, "--thick", 0.015)
	shell, paint_px = opt(a, "--shell", 0.02), opt(a, "--paint", 1024)
	t0 = time.time()
	steps = []
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=src)
	meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	for o in bpy.data.objects:
		if o.type != "MESH":
			bpy.data.objects.remove(o)
	bpy.ops.object.select_all(action="DESELECT")
	for o in meshes:
		o.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	raw = bpy.context.view_layer.objects.active
	raw.parent = None
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	raw.name = "Raw"
	steps.append("raw %d tris, %d vertices" % (tris(raw), len(raw.data.vertices)))

	# 1-2: a copy welded, its loose bits gone (the raw kept as the paint's source).
	body = raw.copy()
	body.data = raw.data.copy()
	bpy.context.scene.collection.objects.link(body)
	body.name = "Body"
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
	bm.to_mesh(body.data)
	bm.free()
	dropped = drop_small(body, shell)
	steps.append("welded to %d vertices, %d loose shells dropped" % (len(body.data.vertices), dropped))

	# 3-4: thickness, then one closed surface.
	apply(body, "SOLIDIFY", thickness=thick, offset=-1.0, use_rim=True)
	apply(body, "REMESH", mode="VOXEL", voxel_size=voxel, adaptivity=0.0)
	dropped = drop_small(body, 0.05)
	apply(body, "SMOOTH", factor=0.5, iterations=2)
	steps.append("voxel %.3f: %d tris, %d of its loose bits dropped" % (voxel, tris(body), dropped))

	# 5: clean quads.
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	before = len(body.data.polygons)
	try:
		bpy.ops.object.quadriflow_remesh(target_faces=quads, use_preserve_sharp=False, use_preserve_boundary=False,
			use_mesh_symmetry=False, smooth_normals=False, seed=1)
	except RuntimeError as error:
		print("quadriflow failed (%s): a collapse instead" % error)
	if len(body.data.polygons) == before:
		apply(body, "DECIMATE", ratio=min(1.0, 2.0 * quads / max(1, tris(body))), use_collapse_triangulate=True)
		steps.append("collapsed to %d tris" % tris(body))
	else:
		steps.append("quadriflow: %d faces, %d tris" % (len(body.data.polygons), tris(body)))

	# 6: UVs and the paint baked across.
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004)
	bpy.ops.object.mode_set(mode="OBJECT")
	paint = bpy.data.images.new("%s_paint" % os.path.splitext(os.path.basename(out))[0], paint_px, paint_px)
	mat = bpy.data.materials.new("paint")
	mat.use_nodes = True
	node = mat.node_tree.nodes.new("ShaderNodeTexImage")
	node.image = paint
	mat.node_tree.links.new(node.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
	mat.node_tree.nodes.active = node
	body.data.materials.clear()
	body.data.materials.append(mat)
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = 1
	bake = sc.render.bake
	bake.use_selected_to_active = True
	bake.cage_extrusion = 0.03
	bake.max_ray_distance = 0.08
	bake.margin = 4
	bake.use_pass_direct = False
	bake.use_pass_indirect = False
	bake.use_pass_color = True
	bpy.ops.object.select_all(action="DESELECT")
	raw.select_set(True)
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	tb = time.time()
	bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_selected_to_active=True, cage_extrusion=0.03,
		max_ray_distance=0.08, margin=4)
	steps.append("baked its paint at %d px in %.0f s" % (paint_px, time.time() - tb))
	paint.pack()

	# 7: out, the raw gone.
	bpy.data.objects.remove(raw)
	for p in body.data.polygons:
		p.use_smooth = False
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True, export_image_format="AUTO")
	steps.append("wrote %s: %d tris in %.0f s" % (out, tris(body), time.time() - t0))
	for s in steps:
		print("clean: " + s)


if __name__ == "__main__":
	main()
