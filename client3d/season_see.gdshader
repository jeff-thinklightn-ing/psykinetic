shader_type spatial;
render_mode cull_disabled, depth_draw_never;
// Season-coloured (season.gdshaderinc), a grown forest's trees inside the
// see-through round the player only, faded toward alpha (the near walls'
// NEAR_ALPHA) as they are further in (see_through.gdshaderinc; GrownTrees,
// decision 467). Drawn after season_see_depth, so only the nearest surface
// shows (decision 188).

#define CUTAWAY
#define SEE_THROUGH
#include "res://client3d/season.gdshaderinc"
