// goblin.gdshader marking the stencil as it draws (Client3D._marking_copy, the hover outline,
// OUTLINE_STENCIL 1): a goblin's body under the cursor, drawn as it looks.
shader_type spatial;
stencil_mode write, compare_always, 1;

#include "res://art/models/characters/goblin.gdshaderinc"
