shader_type spatial;
// The soft scatter (tufts, flowers, reeds; Client3D._scatter_material): as
// the plain scatter's material (vertex colours times each instance's, rough,
// both sides drawn), bent in the wind (decision 309): the higher a vertex,
// the further downwind, in gusts that roll across the ground. Each
// instance's custom data (Client3D._scatter_build): r how much of the
// season's snow lies on it (less under a forest's roof; decision 467), g one
// over its mesh's height, so snow lies on its tips whatever its size, b how
// light its dried straw is (the roof's shade: the scatter takes no shadow).
render_mode cull_disabled, shadows_disabled;

global uniform vec4 wind;
// The season (decision 362): x green, y turn (autumn), z snow cover.
global uniform vec4 season;
varying float up;
varying float snow_cover;
varying float straw_light;
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
	up = clamp(height * INSTANCE_CUSTOM.g, 0.0, 1.0);
	snow_cover = INSTANCE_CUSTOM.r;
	straw_light = INSTANCE_CUSTOM.b;
	vec3 way = inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	VERTEX += way * (bend * wind.z * gust * height * height);
	VERTEX.y -= 0.3 * bend * wind.z * gust * height * height * height;
}

void fragment() {
	// Out of season the green dries toward straw, in autumn it turns, and
	// snow lies on the tops.
	vec3 colour = COLOR.rgb;
	float grey = dot(colour, vec3(0.3, 0.55, 0.15));
	colour = mix(colour, vec3(0.62, 0.55, 0.34) * (0.6 + grey) * straw_light, (1.0 - season.x) * 0.6);
	colour = mix(colour, vec3(0.78, 0.4, 0.12) * (0.6 + grey), season.y * 0.55);
	colour = mix(colour, vec3(0.9, 0.93, 0.97), season.z * smoothstep(0.45, 0.95, up) * 0.8 * snow_cover);
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
