# Exports an art slot's .blend to its .glb, as the game reads it: glTF binary, +Y up,
# modifiers applied, custom properties kept (as glTF extras), no images, a rigged slot's
# clips (its actions) with it. Run by tools/art_drop.ps1 and
# tools/art_preview:
#   blender -b <slot>.blend --python tools/blender/export_slot.py -- <slot>.glb
# The template's "guide" collection (the slot's outline, tools/blender/template_slot.py) is
# left out: its objects are removed from this run's copy before exporting, never from the
# saved .blend.
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1]
guide = bpy.data.collections.get("guide")
if guide is not None:
    for obj in list(guide.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
# The game swaps only a material named exactly "palette" (ArtKit.PALETTE_NAME): a second one
# made in a file that already held one comes out "palette.001" and draws grey-white (896
# amended (3)). In this run's copy, each such material in use is folded onto "palette" (or
# renamed to it, if there is none), and said so; fix the .blend too.
palette = bpy.data.materials.get("palette")
for mat in list(bpy.data.materials):
    base, _, suffix = mat.name.partition(".")
    if base == "palette" and suffix.isdigit() and mat.users > 0:
        if palette is None:
            print("export_slot: material %s renamed palette" % mat.name)
            mat.name = "palette"
            palette = mat
        else:
            print("export_slot: material %s folded onto palette" % mat.name)
            mat.user_remap(palette)
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    export_extras=True,
    export_animations=True,
    export_cameras=False,
    export_lights=False,
    # No images: the game swaps the "palette" material for the shared one (decision 261), and
    # an embedded image would be extracted by Godot's import into the slot's folder.
    export_image_format="NONE",
)
print("exported %s" % out)
