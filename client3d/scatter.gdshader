shader_type spatial;
// The soft scatter (tufts, flowers, reeds; Client3D._scatter_material): as
// the plain scatter's material (vertex colours times each instance's, rough,
// both sides drawn), bent in the wind (decision 309): the higher a vertex,
// the further downwind, in gusts that roll across the ground. Each
// instance's custom data (Client3D._scatter_build): r how much of the
// season's snow lies on it (less under a forest's roof; decision 467), g one
// over its mesh's height, so snow lies on its tips whatever its size, b how
// light its dried straw is (the roof's shade: the scatter takes no shadow),
// a 1 if it sinks into the snow: SNOW_SINK of its height under full cover,
// more or less by where it stands (some gone, some a few straw tips). Tall
// grass trampled (decision 508, terrain's side: its instance colour's alpha
// 0) is a pressed mat, its blades laid down flat one way (as feet pushed
// them, by where it stands), still in the wind and drier.
render_mode cull_disabled, shadows_disabled;

#include "res://client3d/sight.gdshaderinc"

global uniform vec4 wind;
// The season (decision 362): x green, y turn (autumn), z snow cover.
global uniform vec4 season;
varying float up;
varying vec3 world;
varying float snow_cover;
varying float straw_light;
varying float trodden;
// How far full wind bends a tip one unit up (in the mesh's own units).
uniform float bend = 0.35;
// How much of a plant's height full snow buries, and how much that varies
// from one to the next.
const float SNOW_SINK = 0.7;
const float SNOW_SINK_SPREAD = 0.35;
// How white its tips go under full snow: faint, so the open reads as snow
// with grass poking through.
const float SNOW_TIPS = 0.35;
// How high a trampled blade's tip still stands (of its height), and how
// much of its height lies out along the ground.
const float MAT_HEIGHT = 0.08;
const float MAT_SPREAD = 0.6;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

// The scatter lifted as the ground's grass (decision 532, Jeff: "tone 8
// approved, good improvement"): turned GRASS_HUE degrees toward green, its
// saturation and value raised, in linear light about the grey axis.
const float GRASS_HUE = 20.0;
const float GRASS_SAT = 1.45;
const float GRASS_VAL = 1.22;

vec3 hue_turn(vec3 c, float degrees) {
	float a = radians(degrees);
	vec3 k = vec3(0.57735);
	return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

vec3 lift(vec3 c, float sat, float val) {
	float grey = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return clamp(mix(vec3(grey), c, sat) * val, 0.0, 1.0);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	COLOR.rgb = to_linear(COLOR.rgb);
	COLOR.rgb = lift(max(hue_turn(COLOR.rgb, GRASS_HUE), vec3(0.0)), GRASS_SAT, GRASS_VAL);
	vec2 at = MODEL_MATRIX[3].xz;
	float phase = dot(at, wind.xy) * 0.6 - TIME * (1.2 + 2.0 * wind.z);
	float gust = 0.65 + 0.35 * sin(phase) + 0.12 * sin(TIME * 3.1 + at.x * 1.7 + at.y * 2.3);
	float height = max(VERTEX.y, 0.0);
	up = clamp(height * INSTANCE_CUSTOM.g, 0.0, 1.0);
	snow_cover = INSTANCE_CUSTOM.r;
	straw_light = INSTANCE_CUSTOM.b;
	trodden = 1.0 - step(0.5, COLOR.a);
	float pushed = fract(sin(dot(floor(at), vec2(39.3468, 11.135))) * 43758.5453) * 6.2832;
	vec3 laid = inverse(mat3(MODEL_MATRIX)) * vec3(cos(pushed), 0.0, sin(pushed));
	VERTEX.xz += normalize(laid.xz) * height * MAT_SPREAD * trodden;
	VERTEX.y = mix(VERTEX.y, VERTEX.y * MAT_HEIGHT, trodden);
	vec3 way = inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y);
	float sway = 1.0 - trodden;
	VERTEX += way * (bend * wind.z * gust * height * height) * sway;
	VERTEX.y -= 0.3 * bend * wind.z * gust * height * height * height * sway;
	float drift = fract(sin(dot(floor(at * 3.0), vec2(12.9898, 78.233))) * 43758.5453);
	float buried = season.z * snow_cover * INSTANCE_CUSTOM.a * (SNOW_SINK + (drift - 0.5) * 2.0 * SNOW_SINK_SPREAD);
	VERTEX.y -= buried / max(INSTANCE_CUSTOM.g, 0.001);
}

void fragment() {
	// Seen through where it hides the player (decision 549).
	if (sight_cut_here(world, FRAGCOORD.xy)) {
		discard;
	}
	// Out of season the green dries toward straw, in autumn it turns, and
	// snow lies on the tops.
	vec3 colour = COLOR.rgb;
	float grey = dot(colour, vec3(0.3, 0.55, 0.15));
	colour = mix(colour, vec3(0.62, 0.55, 0.34) * (0.6 + grey) * straw_light, max((1.0 - season.x) * 0.6, trodden * 0.35));
	colour *= 1.0 - trodden * 0.15;
	colour = mix(colour, vec3(0.78, 0.4, 0.12) * (0.6 + grey), season.y * 0.55);
	colour = mix(colour, vec3(0.9, 0.93, 0.97), season.z * smoothstep(0.45, 0.95, up) * SNOW_TIPS * snow_cover);
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
