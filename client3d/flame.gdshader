shader_type spatial;
// A torch's flame (Client3D._torch_flame): a glowing drop that flickers and
// leans with the wind (decision 309), its top furthest.
render_mode cull_back, shadows_disabled;

global uniform vec4 wind;
uniform vec3 flame : source_color = vec3(1.0, 0.72, 0.38);
uniform float glow = 3.0;

void vertex() {
	float up = clamp(VERTEX.y / 0.1, -1.0, 1.0) * 0.5 + 0.5;
	float flicker = 0.8 + 0.2 * sin(TIME * 9.0 + MODEL_MATRIX[3].x * 5.0) * sin(TIME * 6.3 + MODEL_MATRIX[3].z * 3.0);
	// Drawn taller than round, and pushed over downwind.
	VERTEX.y += up * up * 0.06 * (1.0 - 0.5 * wind.z);
	vec3 way = inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	VERTEX += way * (up * up * 0.12 * wind.z * flicker);
}

void fragment() {
	ALBEDO = flame;
	EMISSION = flame * glow;
}
