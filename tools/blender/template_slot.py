# Makes a slot's Blender template from its grey box (tools/art_template.ps1 runs it):
#   blender -b --python tools/blender/template_slot.py -- <grey.glb> <out.blend> <palette.png>
#       <slot> <size x> <size y> <size z> <kind> <swatch column> <swatch row> <swatches across>
# The grey box comes in as the game makes it (its boxes, moving parts at their pivots, sockets),
# every mesh takes the one "palette" material with its UVs inside one swatch (grey stone), faces
# flat-shaded, and a "guide" collection holds the slot's outline as a wireframe box, to model
# inside; tools/blender/export_slot.py leaves the guide out. Sizes are the slot's, in glTF axes
# (y up); Blender's are z up, so a slot's y is Blender's z and its z is Blender's -y.
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
glb, out, palette, slot = args[0], args[1], args[2], args[3]
size = [float(value) for value in args[4:7]]
kind = args[7]
column, row, across = int(args[8]), int(args[9]), int(args[10])

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["slot"] = slot
scene["source"] = ""

bpy.ops.import_scene.gltf(filepath=glb)

material = bpy.data.materials.new("palette")
material.use_nodes = True
nodes = material.node_tree.nodes
shader = nodes.get("Principled BSDF")
shader.inputs["Roughness"].default_value = 0.9
image = nodes.new("ShaderNodeTexImage")
image.image = bpy.data.images.load(palette)
image.interpolation = "Closest"
material.node_tree.links.new(image.outputs["Color"], shader.inputs["Base Color"])

# The swatch's middle, in Blender's UVs (v up from the image's bottom).
u = (column + 0.5) / across
v = 1.0 - (row + 0.5) / across

for obj in list(bpy.data.objects):
    if obj.type != "MESH":
        continue
    mesh = obj.data
    mesh.materials.clear()
    mesh.materials.append(material)
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    for loop in mesh.uv_layers.active.data:
        loop.uv = (u, v)
    for polygon in mesh.polygons:
        polygon.use_smooth = False

guide = bpy.data.collections.new("guide")
scene.collection.children.link(guide)
low_y = -size[1] if kind == "floor" else 0.0
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, low_y + size[1] * 0.5))
outline = bpy.context.active_object
outline.name = "guide_outline"
outline.scale = (size[0], size[2], size[1])
outline.display_type = "WIRE"
outline.hide_render = True
outline.hide_select = True
for collection in list(outline.users_collection):
    collection.objects.unlink(outline)
guide.objects.link(outline)

bpy.ops.wm.save_as_mainfile(filepath=out)
print("template %s saved to %s" % (slot, out))
