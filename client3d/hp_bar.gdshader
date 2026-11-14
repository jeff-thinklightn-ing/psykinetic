// A creature's HP bar: a flat quad that always faces the camera, drawn
// over everything (no depth test). The left `fill` of it is `fill_color`,
// the rest dark, inside a thin darker border; `alpha` fades the whole bar.
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, blend_mix;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.35, 0.85, 0.35, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billboard: the model's position, the camera's axes.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 size = vec2(dFdx(UV.x), dFdy(UV.y));
	bool border = UV.x < abs(size.x) * 1.5 || UV.x > 1.0 - abs(size.x) * 1.5
			|| UV.y < abs(size.y) * 1.5 || UV.y > 1.0 - abs(size.y) * 1.5;
	vec3 colour = UV.x <= fill ? fill_color.rgb : vec3(0.1, 0.1, 0.11);
	ALBEDO = border ? vec3(0.02) : colour;
	ALPHA = alpha * 0.92;
}
