# A hand-made body's skin given room for marks (decision 529 amended): art-kit paints a body in
# flat swatches (each face's UVs gathered on one texel of a small strip), which body_marks.py has
# no room to draw into. Its skin's faces are unwrapped afresh (Smart UV Project; the faces on
# art-kit's palette keep their UVs), and the swatches baked into a paint of SIZE, so the game's
# paint looks the same and the marks have the skin's own area.
#   blender -b -P tools/paint_bake.py -- <rigged .glb> <out .glb> [--size PX]
# The out .glb carries the baked paint as its skin material's image (creature_finish.py takes it).
import os
import sys

import bpy

SIZE = 512
PALETTE = "palette"


def main() -> None:
	a = sys.argv[sys.argv.index("--") + 1:]
	src, out = os.path.abspath(a[0]), os.path.abspath(a[1])
	size = int(a[a.index("--size") + 1]) if "--size" in a else SIZE
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=src)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.polygons))
	mesh = body.data
	skins = [i for i, m in enumerate(mesh.materials) if m is not None and m.name.split(".")[0] != PALETTE]
	if len(skins) != 1:
		raise SystemExit("%d skin materials: one wanted" % len(skins))
	skin = mesh.materials[skins[0]]
	old = mesh.uv_layers.active
	old_name = old.name
	new = mesh.uv_layers.new(name="paint")
	# The new layer starts as a copy of the old: the palette's faces keep theirs.
	mesh.uv_layers.active = new
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="DESELECT")
	body.active_material_index = skins[0]
	bpy.ops.object.material_slot_select()
	# Welded first (a .glb comes in split at every flat face, each face its own island).
	bpy.ops.mesh.remove_doubles(threshold=1e-5)
	bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
	bpy.ops.object.mode_set(mode="OBJECT")
	# The swatches baked through the old UVs into an image on the new.
	nodes, links = skin.node_tree.nodes, skin.node_tree.links
	swatch = next(n for n in nodes if n.type == "TEX_IMAGE" and n.image)
	swatch.interpolation = "Closest"
	by_old = nodes.new("ShaderNodeUVMap")
	by_old.uv_map = old_name
	links.new(by_old.outputs["UV"], swatch.inputs["Vector"])
	emit = nodes.new("ShaderNodeEmission")
	links.new(swatch.outputs["Color"], emit.inputs["Color"])
	output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
	shader_link = [l for l in links if l.to_node == output and l.to_socket.name == "Surface"]
	surface_from = shader_link[0].from_socket if shader_link else None
	links.new(emit.outputs["Emission"], output.inputs["Surface"])
	image = bpy.data.images.new("paint", size, size)
	image.colorspace_settings.name = swatch.image.colorspace_settings.name
	target = nodes.new("ShaderNodeTexImage")
	target.image = image
	nodes.active = target
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.samples = 1
	scene.cycles.device = "CPU"
	scene.render.bake.margin = 4
	bpy.ops.object.bake(type="EMIT", uv_layer="paint")
	# The skin drawn from the baked paint on the new UVs; the old layer gone.
	for n in (by_old, emit, target):
		nodes.remove(n)
	swatch.image = image
	swatch.interpolation = "Linear"
	if surface_from is not None:
		links.new(surface_from, output.inputs["Surface"])
	mesh.uv_layers.remove(mesh.uv_layers[old_name])
	mesh.uv_layers["paint"].active = True
	mesh.uv_layers["paint"].active_render = True
	image.pack()
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_animations=False, export_image_format="AUTO")
	print("baked %s: skin %s on %d faces, paint %d px, wrote %s" % (src, skin.name,
		sum(1 for p in mesh.polygons if p.material_index == skins[0]), size, out))


if __name__ == "__main__":
	main()
