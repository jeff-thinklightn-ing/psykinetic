# A rigged animal from Quaternius's Ultimate Animated Animal Pack (CC0) made a creature
# slot's art as it stands (no new mesh, no new rig): its meshes joined into one, scaled
# whole to the slot's height (its clips' moves with it), its colours put on art-kit's palette
# by its own material regions (coat, belly, dark parts, hooves, antlers, eyes, nose) under
# the one material "palette", its clips once each by their plain names; saved as the slot's
# .blend, for tools/blender/export_slot.py to export. Pairs with tools/creature_rig.py, which
# puts another mesh on such a rig.
#
#   blender -b -P tools/animal_palette.py -- <animal .gltf> <out .blend> --height M
#       [--swatch MATERIAL=ROW,COL ...] [--rows ROWS]
#
# Each material takes the swatch nearest its colour (the glTF's linear colour as sRGB, by
# hue twice its lightness, tools/body_build.py's distance) among the palette rows --rows
# (default 0,1,2,3,5: skin, stone, wood, straw, cloth and leather), unless --swatch names
# one. The swatches chosen are printed.
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from creature_rig import fcurves  # noqa: E402

PALETTE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "kit", "palette.png")


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def srgb(linear: float) -> float:
	return 12.92 * linear if linear <= 0.0031308 else 1.055 * linear ** (1 / 2.4) - 0.055


def distance(a: Vector, b: Vector) -> float:
	ga, gb = sum(a) / 3.0, sum(b) / 3.0
	hue = (a - Vector((ga, ga, ga))) - (b - Vector((gb, gb, gb)))
	return 2.0 * hue.length + abs(ga - gb)


def swatches(rows: list) -> tuple:
	"""The palette's swatch colours {(row, col): Vector} in [rows], and its row count."""
	image = bpy.data.images.load(PALETTE)
	w, h = image.size
	pixels = list(image.pixels)
	size = w // 8
	count = round(h / size)
	out = {}
	for row in rows:
		for col in range(8):
			x, y = col * size + size // 2, h - 1 - (row * size + size // 2)
			i = (y * w + x) * 4
			out[(row, col)] = Vector(pixels[i:i + 3])
	bpy.data.images.remove(image)
	return out, count


def main() -> None:
	a = args()
	if len(a) < 2 or "--height" not in a:
		raise SystemExit("usage: -- <animal .gltf> <out .blend> --height M [--swatch MAT=ROW,COL ...] [--rows ROWS]")
	src, out = os.path.abspath(a[0]), os.path.abspath(a[1])
	height = float(a[a.index("--height") + 1])
	rows = [int(r) for r in a[a.index("--rows") + 1].split(",")] if "--rows" in a else [0, 1, 2, 3, 5]
	chosen = {}
	i = 0
	while i < len(a):
		if a[i] == "--swatch":
			name, at = a[i + 1].split("=")
			r, c = at.split(",")
			chosen[name] = (int(r), int(c))
			i += 2
		else:
			i += 1
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=src)
	arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
	# A mesh hung on a bone (the stag's antlers on its Head) skinned to that bone, whole.
	for obj in [o for o in bpy.data.objects if o.type == "MESH" and o.parent is arm and o.parent_type == "BONE"]:
		bone = obj.parent_bone
		world = obj.matrix_world.copy()
		obj.parent = None
		obj.matrix_world = world
		obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
		obj.modifiers.new("Armature", "ARMATURE").object = arm
	# Its skinned meshes (not the importer's bone shapes).
	meshes = [o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
	# Unparented, transforms kept, so the armature can be scaled and applied whole.
	for obj in [arm] + meshes:
		world = obj.matrix_world.copy()
		obj.parent = None
		obj.matrix_world = world
	for obj in list(bpy.data.objects):
		if obj not in meshes and obj is not arm:
			bpy.data.objects.remove(obj)
	# Colours: each face's material's swatch, as UVs onto the palette. The glTF's own
	# colours, read from the file (the importer may route them through other nodes).
	import json
	given = {}
	if src.endswith(".gltf"):
		for m in json.load(open(src, encoding="utf-8")).get("materials", []):
			factor = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
			given[m.get("name", "")] = Vector([srgb(v) for v in factor[:3]])
	palette, count = swatches(rows)
	picked = {}
	for obj in meshes:
		mesh = obj.data
		if not mesh.uv_layers:
			mesh.uv_layers.new(name="UVMap")
		uv = mesh.uv_layers.active.data
		for poly in mesh.polygons:
			material = mesh.materials[poly.material_index] if mesh.materials else None
			name = material.name if material else ""
			if name not in picked:
				if name in chosen:
					picked[name] = chosen[name]
				else:
					colour = given.get(name.split(".0")[0] if name not in given else name, Vector((1, 1, 1)))
					if name not in given and material and material.node_tree:
						for node in material.node_tree.nodes:
							if node.type == "BSDF_PRINCIPLED":
								colour = Vector([srgb(v) for v in node.inputs["Base Color"].default_value[:3]])
					picked[name] = min(palette, key=lambda at: distance(palette[at], colour))
			row, col = picked[name]
			for li in poly.loop_indices:
				uv[li].uv = ((col + 0.5) / 8.0, 1.0 - (row + 0.5) / count)
		mesh.materials.clear()
		mesh.materials.append(bpy.data.materials.get("palette") or bpy.data.materials.new("palette"))
	print("swatches: %s" % {name: picked[name] for name in sorted(picked)})
	# One mesh, skinned as it was.
	bpy.ops.object.select_all(action="DESELECT")
	for obj in meshes:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.parent = arm
	# Scaled whole to the height: the armature, the mesh and every clip's moves.
	top = max((body.matrix_world @ v.co).z for v in body.data.vertices)
	low = min((body.matrix_world @ v.co).z for v in body.data.vertices)
	s = height / (top - low)
	from creature_rig import scale_reference  # noqa: E402
	body.parent = None
	scale_reference(arm, body, s)
	body.parent = arm
	body.matrix_parent_inverse = arm.matrix_world.inverted()
	for mod in body.modifiers:
		if mod.type == "ARMATURE":
			mod.object = arm
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
	for poly in body.data.polygons:
		poly.use_smooth = False
	tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
	print("built: %d tris, %.3f m tall (scaled %.3f), clips %s" % (tris, height, s, sorted(keep)))
	bpy.context.scene["source"] = "%s (Quaternius, Ultimate Animated Animal Pack, CC0 1.0), its own mesh, rig and clips; recoloured onto the palette by tools/animal_palette.py" % os.path.basename(src)
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=out)
	print("wrote %s" % out)


if __name__ == "__main__":
	main()
