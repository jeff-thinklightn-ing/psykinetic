shader_type spatial;
// The ground, one mesh per chunk (Client3D._build_ground): a vertex at every
// cell corner, its light and heat in CUSTOM0 (r: brightness, g: warmth, the
// cells around the corner averaged), so both fade smoothly from cell to cell;
// b: at the foot of a drop, a: at its top, so a ledge's foot is shaded and
// its edge caught by the light.
// Which ground is where comes from kinds, a texel a cell (r grass, g dirt,
// b stone, a sand), read where the noise pushes it, so kinds meet along
// ragged borders, not cell edges. Everything else is noise (noise_tex, made
// at run time): no texture assets.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D kinds : filter_linear, repeat_disable;
// The world cell at kinds' texel (0, 0), and the texture's size in cells.
uniform vec2 kinds_origin;
uniform vec2 kinds_size;
uniform vec3 grass : source_color = vec3(0.21, 0.6, 0.25);
uniform vec3 dirt : source_color = vec3(0.45, 0.35, 0.22);
uniform vec3 stone : source_color = vec3(0.56, 0.56, 0.54);
uniform vec3 sand : source_color = vec3(0.78, 0.7, 0.5);
uniform vec3 warm : source_color = vec3(1.0, 0.5, 0.2);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// Where the water is, a texel a cell like kinds (Client3D._build_ground):
// the bed and the shore beside it darker, wet.
uniform sampler2D water : hint_default_black, filter_linear, repeat_disable;
// Outdoors, the forest's floor (the mask's g): the land runs into it along
// a ragged line.
uniform vec3 forest_floor : source_color = vec3(0.17, 0.26, 0.14);
// Outdoors, the sky's light on the floor (as a brightness, like CUSTOM0's
// r, which then holds the cell's own sources alone): the floor is lit to
// the brighter of the two, so a torch's pool shows at night and the hour
// changes one number, not every cell (decision 304). 0 indoors.
uniform float sky_floor = 0.0;

varying vec3 world;
varying vec2 shade;
varying vec2 relief;

// Smooth noise 0..1 with about one feature per unit of p, read from
// noise_tex (FastNoiseLite, made at run time, 64 features across before it
// repeats), turned at an odd angle so no repeat lines up with the cells.
float noise(vec2 p) {
	return texture(noise_tex, mat2(vec2(0.913, 0.408), vec2(-0.408, 0.913)) * p / 64.0).r;
}

float fbm(vec2 p) {
	float total = 0.0;
	float amount = 0.5;
	// Each octave turned, so no axis lines up with the grid.
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		total += amount * noise(p);
		p = turn * p * 2.03 + 11.7;
		amount *= 0.5;
	}
	return total;
}

// Two numbers 0..1 for a lattice point, by integer mixing: exact however
// far from the origin.
vec2 hash2(vec2 p) {
	uvec2 v = uvec2(ivec2(p)) * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	return vec2(v) / 4294967295.0;
}

// Cobbles: the distance to the nearest stone's edge (small at the joints)
// and that stone's own random tint.
vec2 cobbles(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	float tint = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 at = vec2(float(x), float(y));
			vec2 seed = hash2(i + at);
			float d = length(at + 0.15 + 0.7 * seed - f);
			if (d < nearest) {
				second = nearest;
				nearest = d;
				tint = seed.x;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2(second - nearest, tint);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shade = CUSTOM0.rg;
	relief = CUSTOM0.ba;
}

void fragment() {
	vec2 at = world.xz;
	// Where the kinds are read: pushed about by up to most of a cell, so a
	// border wanders across cells.
	vec2 push = vec2(fbm(at * 0.45), fbm(at * 0.45 + 31.0)) - 0.5;
	vec2 uv = (at - kinds_origin + 0.5 + push * 1.1) / kinds_size;
	vec4 weights = texture(kinds, uv);
	// Each kind's own ragged edge, then the strongest kept, with a short
	// soft band where two meet.
	weights += (vec4(noise(at * 2.3), noise(at * 2.3 + 5.0), noise(at * 2.3 + 9.0), noise(at * 2.3 + 13.0)) - 0.5) * 0.35;
	float strongest = max(max(weights.r, weights.g), max(weights.b, weights.a));
	weights = max(weights - (strongest - 0.18), vec4(0.0));
	weights /= max(weights.r + weights.g + weights.b + weights.a, 0.0001);

	// Each kind's look, worked out only where it shows.
	float fine = noise(at * 7.0);
	vec3 colour = vec3(0.0);
	if (weights.r > 0.0) {
		vec3 here = grass * (0.82 + 0.36 * fbm(at * 0.18)) * (0.92 + 0.16 * fine);
		here = mix(here, here * vec3(1.12, 1.05, 0.7), smoothstep(0.55, 0.75, noise(at * 0.31 + 3.0)));
		colour += here * weights.r;
	}
	if (weights.g > 0.0) {
		colour += dirt * (0.85 + 0.3 * fbm(at * 0.6 + 7.0)) * (0.9 + 0.2 * noise(at * 9.0)) * weights.g;
	}
	if (weights.b > 0.0) {
		vec2 cobble = cobbles(mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * at * 1.6);
		vec3 here = stone * (0.86 + 0.2 * cobble.y) * (0.94 + 0.12 * fine);
		colour += here * mix(0.62, 1.0, smoothstep(0.02, 0.12, cobble.x)) * weights.b;
	}
	if (weights.a > 0.0) {
		colour += sand * (0.92 + 0.12 * noise(at * 0.5 + 21.0))
				* (0.96 + 0.08 * noise(vec2(at.x * 1.5 + at.y * 0.4, at.y * 6.0))) * weights.a;
	}

	colour *= mix(1.0, 0.5, relief.x) * (1.0 + 0.14 * relief.y);
	float wet = smoothstep(0.25, 0.6, texture(water, (at - kinds_origin + 0.5) / kinds_size).r);
	colour = mix(colour, colour * vec3(0.5, 0.58, 0.62), wet);
	float forest = smoothstep(0.35, 0.65, texture(water, uv).g + (noise(at * 1.9 + 40.0) - 0.5) * 0.35);
	colour = mix(colour, forest_floor * (0.8 + 0.4 * fbm(at * 0.4 + 50.0)), forest);

	// Light and heat as the old floor had them, worked out in sRGB.
	vec3 lit = pow(colour, vec3(1.0 / 2.2)) * max(shade.r, sky_floor);
	vec3 warm_srgb = pow(warm, vec3(1.0 / 2.2));
	ALBEDO = pow(mix(lit, warm_srgb, shade.g), vec3(2.2));
	EMISSION = pow(warm_srgb * shade.g, vec3(2.2));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
