// A far landmark (650, terrain's side): drawn at its true place, or pulled
// in along its line from the camera and scaled to look the same (FAR_DRAW),
// so the haze can't be the fog's (it would fog it by where it is drawn, not
// where it stands): the fog off, and its haze worked out here from its true
// distance (true_distance, set per landmark) on the scene's own curve (623
// amended (3); Client3D.far_haze is the same): the low camera's depth fog,
// depth_begin to depth_end, out to hand_over, then lighter, rising from
// there toward most (or the fog there, if thicker) over span; mixed toward
// the scene fog's colour.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 haze : source_color = vec3(0.7, 0.75, 0.8);
// The day's light on it, 0 (night) to 1, as the look last set it.
uniform float light = 1.0;
uniform float depth_begin = 150.0;
uniform float depth_end = 280.0;
uniform float hand_over = 120.0;
uniform float most = 0.85;
uniform float span = 450.0;
instance uniform vec3 body : source_color = vec3(0.4);
instance uniform float true_distance = 0.0;

float fog_at(float d) {
	return clamp((d - depth_begin) / max(depth_end - depth_begin, 0.001), 0.0, 1.0);
}

void fragment() {
	// A plain light from above and one side, so its faces read apart.
	vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float shade = 0.72 + 0.2 * up.y + 0.08 * up.x;
	float share = fog_at(true_distance);
	if (true_distance > hand_over) {
		float at_hand = fog_at(hand_over);
		share = at_hand + (max(most, at_hand) - at_hand) * (1.0 - exp(-(true_distance - hand_over) / span));
	}
	ALBEDO = mix(body * shade * light, haze, share);
}
