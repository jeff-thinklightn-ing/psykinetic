shader_type spatial;
// The human bodies (decisions 243, 388): one surface, one material, every body.
// The vertex colour says which part a face is, one-hot: red skin, green hair,
// blue tunic, alpha trousers; each takes its colour from the instance (set per
// body: its own skin and hair, the player's tunic). A face in none (belt,
// boots) is on art-kit's palette by its UVs. One material shared by all, so
// bodies batch and cast their shadows in one pass each.

uniform sampler2D palette : source_color, filter_nearest;
instance uniform vec4 skin : source_color = vec4(0.77, 0.57, 0.46, 1.0);
instance uniform vec4 hair : source_color = vec4(0.34, 0.25, 0.21, 1.0);
instance uniform vec4 tunic : source_color = vec4(0.52, 0.50, 0.39, 1.0);
instance uniform vec4 trousers : source_color = vec4(0.32, 0.24, 0.18, 1.0);

void fragment() {
	vec4 part = COLOR;
	vec3 own = skin.rgb * part.r + hair.rgb * part.g + tunic.rgb * part.b + trousers.rgb * part.a;
	float tinted = clamp(part.r + part.g + part.b + part.a, 0.0, 1.0);
	ALBEDO = mix(texture(palette, UV).rgb, own, tinted);
	ROUGHNESS = 0.9;
}
