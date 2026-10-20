# A creature_fit.py body made a model of the game's own (decision 529): its mesh named
# "Body", its one material named for its people (Client3D draws it in that people's
# <name>_body.tres, the goblin's shader over its paint), its paint saved beside it as
# <name>_paint.png and left out of the .glb, the .blend saved beside the .glb as its source.
#   blender -b -P tools/creature_finish.py -- <fitted .glb> <out .glb> <name>
import os
import sys

import bpy


def main() -> None:
	a = sys.argv[sys.argv.index("--") + 1:]
	if len(a) < 3:
		raise SystemExit("usage: -- <fitted .glb> <out .glb> <name>")
	src, out, name = os.path.abspath(a[0]), os.path.abspath(a[1]), a[2]
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=src)
	for o in list(bpy.data.objects):
		if o.name.startswith("Icosphere"):
			bpy.data.objects.remove(o)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	arm.name = "Armature"
	meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	if len(meshes) != 1:
		raise SystemExit("%d meshes: one wanted" % len(meshes))
	body = meshes[0]
	body.name = "Body"
	body.data.name = name
	images = [n.image for m in body.data.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
	if not images:
		raise SystemExit("no paint on %s" % src)
	paint = images[0]
	paint_path = os.path.join(os.path.dirname(out), "%s_paint.png" % name)
	paint.filepath_raw = paint_path
	paint.file_format = "PNG"
	paint.save()
	paint_size = tuple(paint.size)
	# One material, named for the body's own in the game, with no image (the game's has it).
	material = bpy.data.materials.new(name)
	body.data.materials.clear()
	body.data.materials.append(material)
	for image in list(bpy.data.images):
		bpy.data.images.remove(image)
	for action in list(bpy.data.actions):
		bpy.data.actions.remove(action)
	bpy.context.scene["source"] = "%s, finished by tools/creature_finish.py (paint: %s)" % (os.path.basename(src), os.path.basename(paint_path))
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(out)[0] + ".blend")
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	body.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
		export_skins=True, export_animations=False, export_image_format="NONE", export_extras=True)
	tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
	print("finished %s: %d tris, paint %s %s" % (out, tris, paint_path, paint_size))


if __name__ == "__main__":
	main()
