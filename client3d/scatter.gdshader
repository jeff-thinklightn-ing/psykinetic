shader_type spatial;
// The soft scatter (tufts, flowers, reeds; Client3D._scatter_material): as
// the plain scatter's material (vertex colours times each instance's, rough,
// both sides drawn), bent in the wind (decision 309): the higher a vertex,
// the further downwind, in gusts that roll across the ground.
render_mode cull_disabled, shadows_disabled;

global uniform vec4 wind;
// How far full wind bends a tip one unit up (in the mesh's own units).
uniform float bend = 0.35;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	COLOR.rgb = to_linear(COLOR.rgb);
	vec2 at = MODEL_MATRIX[3].xz;
	float phase = dot(at, wind.xy) * 0.6 - TIME * (1.2 + 2.0 * wind.z);
	float gust = 0.65 + 0.35 * sin(phase) + 0.12 * sin(TIME * 3.1 + at.x * 1.7 + at.y * 2.3);
	float height = max(VERTEX.y, 0.0);
	vec3 way = inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	VERTEX += way * (bend * wind.z * gust * height * height);
	VERTEX.y -= 0.3 * bend * wind.z * gust * height * height * height;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
