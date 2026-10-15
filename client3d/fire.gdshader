shader_type spatial;
// Fire on the ground (Client3D._add_fire): a glowing patch a little wider
// than its cell, its edge ragged by noise and flickering, so fire cells side
// by side run together and none shows as a square. The wind (decision 309)
// drags it downwind: the patch reaches further that way, its flicker
// running with it.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 fire : source_color = vec3(1.0, 0.45, 0.1);
uniform float glow = 2.0;
global uniform vec4 wind;

varying vec3 world;
varying vec3 centre;

float wave(vec2 p) {
	return sin(p.x * 1.7 + sin(p.y * 2.3)) * sin(p.y * 1.9 + sin(p.x * 1.3));
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	centre = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 from_centre = (UV - 0.5) * 2.0;
	// Downwind of the centre (in world xz), the patch is drawn shrunk toward
	// it, so it reaches further that way.
	vec2 off = world.xz - centre.xz;
	float along = dot(off, wind.xy);
	float stretch = 1.0 + 0.8 * wind.z * step(0.0, along);
	vec2 bent = off + wind.xy * along * (1.0 / stretch - 1.0);
	from_centre *= length(bent) / max(length(off), 0.0001);
	vec2 flow = -wind.xy * wind.z * TIME * 1.5;
	float edge = 0.78 + 0.16 * wave((world.xz + flow) * 3.0 + vec2(TIME * 0.7, -TIME * 0.5));
	float inside = 1.0 - smoothstep(edge - 0.3, edge, length(from_centre));
	float flicker = 0.85 + 0.15 * wave(world.zx * 5.0 + TIME * 2.1);
	ALBEDO = fire * glow * flicker * mix(0.75, 1.25, inside);
	ALPHA = inside;
}
