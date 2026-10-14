shader_type spatial;
// Water, a mesh a body (Client3D._build_water), over its cells and the land
// round them. Where it shows: the distance to the edge of the water's cells
// (the mask, a texel a cell, 1 for water; worked out from the 9 cells round
// the point), the shore where it equals a noise of at most SHORE_WANDER: it
// never strays further than that from the cells' true edge, whatever their
// shape, so a cell that is land never looks drowned nor a water cell dry.
// Foam on the land side of the shore; deeper and less clear toward the
// middle; ripples that drift.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D water : filter_linear, repeat_disable;
// The world cell at the mask's texel (0, 0), and the mask's size in cells.
uniform vec2 mask_origin;
uniform vec2 mask_size;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.25, 0.55, 0.7);
uniform vec3 deep : source_color = vec3(0.08, 0.22, 0.42);
uniform vec3 foam : source_color = vec3(0.85, 0.92, 0.95);

varying vec3 world;

// As the ground's: smooth noise 0..1, about a feature a unit of p.
float noise(vec2 p) {
	return texture(noise_tex, mat2(vec2(0.913, 0.408), vec2(-0.408, 0.913)) * p / 64.0).r;
}

const float SHORE_WANDER = 0.2;
const float FOAM = 0.1;

bool is_water(ivec2 cell) {
	ivec2 texel = clamp(cell - ivec2(round(mask_origin)), ivec2(0), ivec2(round(mask_size)) - 1);
	return texelFetch(water, texel, 0).r > 0.5;
}

// How far [at] is inside the water's cells (less than 0: outside, on land),
// out to a cell and a half.
float into_water(vec2 at) {
	ivec2 cell = ivec2(round(at));
	bool inside = is_water(cell);
	float nearest = 1.5;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			ivec2 other = cell + ivec2(x, y);
			if (is_water(other) != inside) {
				vec2 off = max(abs(at - vec2(other)) - 0.5, vec2(0.0));
				nearest = min(nearest, length(off));
			}
		}
	}
	return inside ? nearest : -nearest;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 at = world.xz;
	// The shore: where the distance into the water is the wander here.
	float wander = clamp((noise(at * 0.9) - 0.5) * 1.6 + (noise(at * 3.1 + 5.0) - 0.5) * 0.4, -1.0, 1.0) * SHORE_WANDER;
	float into = into_water(at) - wander;
	if (into < -FOAM) {
		discard;
	}
	float inside = smoothstep(-0.02, 0.03, into);
	float depth = smoothstep(0.15, 1.2, into);
	float t = TIME * 0.12;
	float churn = noise(at * 4.0 + vec2(t * 3.0, -t * 2.0));
	vec3 colour = mix(shallow, deep, depth);
	// The foam: a band at the shore, on the land side, broken up and drifting.
	float band = smoothstep(-FOAM, -FOAM * 0.4, into) * (1.0 - smoothstep(0.0, 0.06, into));
	band *= smoothstep(0.3, 0.6, churn);
	colour = mix(colour, foam, band);
	ALBEDO = colour;
	ALPHA = max(inside * mix(0.6, 0.88, depth), band * 0.85);
	// Ripples: the noise's slope, two layers drifting apart.
	vec2 a = at * 1.3 + vec2(t, t * 0.7);
	vec2 b = at * 2.2 - vec2(t * 0.8, t * 0.4);
	float e = 0.08;
	vec2 slope = vec2(noise(a + vec2(e, 0.0)) - noise(a - vec2(e, 0.0)), noise(a + vec2(0.0, e)) - noise(a - vec2(0.0, e)))
			+ vec2(noise(b + vec2(e, 0.0)) - noise(b - vec2(e, 0.0)), noise(b + vec2(0.0, e)) - noise(b - vec2(0.0, e)));
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x * 1.5, 1.0, -slope.y * 1.5)), 0.0)).xyz);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
