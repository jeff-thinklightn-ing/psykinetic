shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_always, cull_disabled;
// The depth of a grown forest's trees inside the see-through round the
// player, drawn before season_see's colour so a faded crown shows its
// nearest surface only, as a near wall's depth pass does (decision 188).

#include "res://client3d/see_through.gdshaderinc"

void vertex() {
	see_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (see_weight(INV_VIEW_MATRIX) <= see_bayer(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
