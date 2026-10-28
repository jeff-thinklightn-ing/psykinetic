shader_type spatial;
// A chimney's smoke (Flames.chimney_smoke, decision 710): one quad turned to
// the camera over the chimney's top, a pale stream that rises, widens,
// drifts downwind (decision 309) and thins out by its top. Lit, unlike a
// flame's wisp (smoke.gdshader), so it is pale by day and dim at night; its
// every edge soft, so the quad never shows.
render_mode blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

global uniform vec4 wind;
instance uniform float seed = 0.0;
// How much it hides at most.
const float MOST = 0.55;

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
	// Faces the camera, upright; bends downwind toward its top.
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	float up = 1.0 - UV.y;
	vec3 world = centre + right * VERTEX.x * size + vec3(0.0, VERTEX.y * size, 0.0)
			+ vec3(wind.x, 0.0, wind.y) * up * up * 1.2 * (0.3 + wind.z) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float t = TIME * 0.5 + seed;
	vec2 at = vec2(UV.x, 1.0 - UV.y);
	// Narrow at the pot, widening as it rises; its edge broken by noise.
	float wisp = noise(vec2(at.x * 4.0 + seed, at.y * 3.0 - t * 1.6));
	float billow = noise(vec2(at.x * 2.0 - seed, at.y * 1.5 - t * 0.9));
	float half_width = mix(0.08, 0.38, at.y) * (0.75 + 0.5 * billow);
	float body = 1.0 - smoothstep(half_width * 0.4, half_width, abs(at.x - 0.5 + (wisp - 0.5) * 0.25 * at.y));
	float fade = smoothstep(0.0, 0.12, at.y) * (1.0 - smoothstep(0.35, 0.95, at.y));
	float edges = smoothstep(0.0, 0.12, at.x) * smoothstep(1.0, 0.88, at.x);
	ALBEDO = vec3(0.62, 0.6, 0.57);  // A pale warm grey, lit.
	NORMAL = vec3(0.0, 0.0, 1.0);  // Toward the camera: lit as the light falls on the view.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = MOST * body * fade * edges * (0.65 + 0.35 * wisp);
}
