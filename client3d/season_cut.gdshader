shader_type spatial;
render_mode cull_disabled;
// Season-coloured (season.gdshaderinc), a grown forest's trees, opaque but
// for the see-through round the player (see_through.gdshaderinc; GrownTrees,
// decision 467); both faces, as a pad of needles is one sheet.

#define CUTAWAY
#include "res://client3d/season.gdshaderinc"
