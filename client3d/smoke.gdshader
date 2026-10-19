shader_type spatial;
// A flame's smoke (Flames, decision 523): one quad turned to the camera over
// the flame, a faint grey wisp that rises, drifts downwind (decision 309) and
// is gone by its top; it comes and goes, never a column.
render_mode blend_mix, unshaded, cull_disabled, shadows_disabled, depth_draw_never;

global uniform vec4 wind;
instance uniform float seed = 0.0;
// How much it hides at most: faint.
const float MOST = 0.15;

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
	// Faces the camera, upright; leans downwind toward its top.
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	float up = VERTEX.y / 1.6 + 0.5;
	vec3 world = centre + right * VERTEX.x * size + vec3(0.0, VERTEX.y * size, 0.0)
			+ vec3(wind.x, 0.0, wind.y) * up * up * 0.6 * wind.z * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float t = TIME * 0.6 + seed;
	vec2 at = vec2(UV.x, 1.0 - UV.y);
	float wisp = noise(vec2(at.x * 3.0 + seed, at.y * 2.0 - t * 1.4));
	float body = 1.0 - smoothstep(0.15, 0.5, abs(at.x - 0.5 + (wisp - 0.5) * 0.4 * at.y));
	float fade = smoothstep(0.0, 0.2, at.y) * (1.0 - smoothstep(0.45, 1.0, at.y));
	float puff = smoothstep(0.35, 0.75, noise(vec2(seed, t * 0.5)) * 0.6 + wisp * 0.6);
	ALBEDO = vec3(0.15, 0.135, 0.12);  // A warm mid grey, linear.
	ALPHA = MOST * body * fade * puff;
}
