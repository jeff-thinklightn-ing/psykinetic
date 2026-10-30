// A far landmark (650, terrain's side): drawn at its true place, or pulled
// in along its line from the camera and scaled to look the same (FAR_DRAW),
// so the haze can't be the fog's (it would fog it by where it is drawn, not
// where it stands): the fog off, its own haze_share of the sky's horizon
// colour by its true distance, set per landmark.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 haze : source_color = vec3(0.7, 0.75, 0.8);
// The day's light on it, 0 (night) to 1, as the look last set it.
uniform float light = 1.0;
instance uniform vec3 body : source_color = vec3(0.4);
instance uniform float haze_share = 0.0;

void fragment() {
	// A plain light from above and one side, so its faces read apart.
	vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float shade = 0.72 + 0.2 * up.y + 0.08 * up.x;
	ALBEDO = mix(body * shade * light, haze, haze_share);
}
