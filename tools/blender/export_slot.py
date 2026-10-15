# Exports an art slot's .blend to its .glb, as the game reads it: glTF binary, +Y up,
# modifiers applied, custom properties kept (as glTF extras). Run by tools/art_drop.ps1 and
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
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    export_extras=True,
    export_animations=False,
    export_cameras=False,
    export_lights=False,
)
print("exported %s" % out)
