// A body wet (decision 775; Jeff: wading "makes character get wet"): an overlay over every mesh of
// a wet body, darkening and glossing it below the line the water reached (world height), or all
// over from rain. Each wet body has its own material of it (WetLook.material_of), set while it is
// wet and dropped when dry: instance uniforms don't reach a material_overlay (probed, 775).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

// The water line, world y; below it the body is wet by wet_amount (0..1).
uniform float wet_line = -1000.0;
uniform float wet_amount = 0.0;
// Wet all over (rain), 0..1.
uniform float wet_all = 0.0;

// How dark the wettest cloth goes below a wading line, and rain's all-over soak (a touch lighter);
// how soft the line's edge is, and the darker band just under it, the water's mark (m). Tuned from
// the stills to about 40% darker at the game's camera (the coordinator's ask), the shine adding back.
const float DARKEN = 0.78;
const float RAIN_DARKEN = 0.62;
const float EDGE = 0.03;
const float BAND = 0.06;
const float BAND_DARKEN = 0.18;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float below = 1.0 - smoothstep(wet_line - EDGE, wet_line + EDGE, world_y);
	float waded = below * wet_amount;
	// The mark: a band just under the line, darkest at it.
	float band = waded * (1.0 - smoothstep(0.0, BAND, wet_line - world_y)) * step(world_y, wet_line + EDGE);
	float wet = max(waded, wet_all);
	if (wet <= 0.002) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = clamp(max(waded * DARKEN, wet_all * RAIN_DARKEN) + band * BAND_DARKEN, 0.0, 0.9);
	// Glossy while wet; the shine goes first as it dries, the dark after.
	ROUGHNESS = mix(0.65, 0.06, smoothstep(0.3, 1.0, wet));
	SPECULAR = 0.9;
}
