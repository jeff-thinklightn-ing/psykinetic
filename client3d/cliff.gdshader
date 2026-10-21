shader_type spatial;
// Cliff faces (Client3D._add_cliffs): their vertex colours, rough, both sides
// drawn, as their plain material was, under the sky's light on the floor as
// the ground beside them (decision 513 amended: unlit by it a face glowed
// pale through the night); and seen through where they stand
// between the camera and the player (sight.gdshaderinc, decision 549).
render_mode cull_disabled;

#include "res://client3d/sight.gdshaderinc"

// The ground's sky_floor (Client3D._set_sky_floor): the sky's light on the
// outdoor floor as a brightness, worked in sRGB as the ground works it; 1
// indoors, where the ground is lit by the cell's own lights alone.
uniform float sky_floor = 1.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (sight_cut_here(world, FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = COLOR.rgb * pow(sky_floor, 2.2);
	ROUGHNESS = 1.0;
}
