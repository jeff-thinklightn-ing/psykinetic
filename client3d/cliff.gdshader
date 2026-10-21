shader_type spatial;
// Cliff faces (Client3D._add_cliffs): their vertex colours, rough, both sides
// drawn, as their plain material was; and seen through where they stand
// between the camera and the player (sight.gdshaderinc, decision 549).
render_mode cull_disabled;

#include "res://client3d/sight.gdshaderinc"

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (sight_cut_here(world, FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
