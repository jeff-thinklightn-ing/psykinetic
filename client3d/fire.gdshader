shader_type spatial;
// Fire on the ground (Client3D._add_fire): a glowing patch a little wider
// than its cell, its edge ragged by noise and flickering, so fire cells side
// by side run together and none shows as a square.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 fire : source_color = vec3(1.0, 0.45, 0.1);
uniform float glow = 2.0;

varying vec3 world;

float wave(vec2 p) {
	return sin(p.x * 1.7 + sin(p.y * 2.3)) * sin(p.y * 1.9 + sin(p.x * 1.3));
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 from_centre = (UV - 0.5) * 2.0;
	float edge = 0.78 + 0.16 * wave(world.xz * 3.0 + vec2(TIME * 0.7, -TIME * 0.5));
	float inside = 1.0 - smoothstep(edge - 0.3, edge, length(from_centre));
	float flicker = 0.85 + 0.15 * wave(world.zx * 5.0 + TIME * 2.1);
	ALBEDO = fire * glow * flicker * mix(0.75, 1.25, inside);
	ALPHA = inside;
}
