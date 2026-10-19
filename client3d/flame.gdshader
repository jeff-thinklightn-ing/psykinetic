shader_type spatial;
// A flame (Flames, decision 523): three crossed quads, the flame filling the
// lower part (Flames.REACH: UV y 0 at its foot, 1 at the quads' top). Its
// shape is a tongue narrowing upward, torn by noise that scrolls up; its
// colour art-kit's row 7, from the bone core through ffd27a, ffb861 and
// e8792e to the deep red b8322a at the tips. A few embers rise out of it and
// fade. The whole leans downwind (decision 309), its top furthest.
render_mode blend_mix, unshaded, cull_disabled, shadows_disabled, depth_draw_never;

global uniform vec4 wind;
instance uniform float seed = 0.0;
// How bright it is drawn (over 1: the glow catches it).
uniform float glow = 1.15;
// Where the flame ends, of the quads' height.
const float TOP = 0.62;
// The swatches as art-kit gives them (sRGB); the shader works in linear
// light, so each is turned to linear where it is used (to_linear).
const vec3 BONE = vec3(0.957, 0.937, 0.902);
const vec3 YELLOW = vec3(1.0, 0.824, 0.478);
const vec3 AMBER = vec3(1.0, 0.722, 0.380);
const vec3 FLAME = vec3(0.910, 0.475, 0.180);
const vec3 RED = vec3(0.722, 0.196, 0.165);

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

varying float up;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	up = UV.y;
	vec3 way = inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	float sway = 0.75 + 0.25 * sin(TIME * 3.0 + seed);
	VERTEX += way * (up * up * 0.35 * (0.3 + wind.z) * sway);
}

void fragment() {
	float t = TIME + seed * 0.37;
	vec2 at = vec2(UV.x, UV.y / TOP);
	// Torn by noise scrolling up, more toward the top.
	float tear = noise(vec2(at.x * 3.0 + seed, at.y * 2.5 - t * 2.6)) - 0.5;
	float lick = noise(vec2(at.x * 6.0 - seed, at.y * 4.0 - t * 4.1)) - 0.5;
	float across = abs(at.x - 0.5 + (tear * 0.5 + lick * 0.2) * at.y) * 2.0;
	// The tongue: widest a little above the foot, to a point at the top.
	float width = smoothstep(0.0, 0.18, at.y) * (1.0 - smoothstep(0.25, 1.0, at.y) * 0.92) * 0.85;
	float heat = clamp(1.0 - across / max(width, 0.001), 0.0, 1.0) * (1.0 - smoothstep(0.7, 1.05, at.y + tear * 0.4));
	vec3 colour = mix(RED, FLAME, smoothstep(0.05, 0.35, heat));
	colour = mix(colour, AMBER, smoothstep(0.4, 0.65, heat));
	colour = mix(colour, YELLOW, smoothstep(0.65, 0.88, heat));
	// Only the heart near the foot goes toward bone, never all the way.
	colour = mix(colour, BONE, smoothstep(0.9, 1.0, heat) * (1.0 - at.y) * 0.5);
	float alpha = smoothstep(0.02, 0.2, heat);
	// Embers: a few sparks rising from the flame's top through the rest of
	// the quad, drifting and fading.
	for (int i = 0; i < 4; i++) {
		float own = hash(vec2(float(i), seed));
		float rise = fract(t * (0.35 + 0.25 * own) + own);
		vec2 spark = vec2(0.5 + (own - 0.5) * 0.5 + sin(t * 2.0 + own * 9.0) * 0.08 * rise, mix(TOP * 0.7, 1.0, rise));
		float near = 1.0 - smoothstep(0.0, 0.022, length((UV - spark) * vec2(1.0, 0.6)));
		float spark_alpha = near * (1.0 - rise);
		colour = mix(colour, YELLOW, spark_alpha * step(alpha, 0.5));
		alpha = max(alpha, spark_alpha);
	}
	ALBEDO = to_linear(colour) * glow;
	ALPHA = alpha;
}
