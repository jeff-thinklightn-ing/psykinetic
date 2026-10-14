# Exports an art slot's .blend to its .glb, as the game reads it: glTF binary, +Y up,
# modifiers applied, custom properties kept (as glTF extras). Run by tools/art_drop.ps1:
#   blender -b <slot>.blend --python tools/blender/export_slot.py -- <slot>.glb
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1]
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
