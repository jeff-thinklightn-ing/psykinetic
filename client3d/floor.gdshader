shader_type spatial;
// The floor, drawn by one MultiMesh per chunk and kind (Client3D._build_floor):
// what the kit's floor material draws (StandardMaterial3D's defaults, rough,
// not metallic), with each cell's colour from its instance colour (linear,
// the kind's colour shaded by the light and heat on it) and its glow from
// its custom data (linear emission).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D texture_albedo : source_color, filter_nearest_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

varying vec3 glow;

void vertex() {
	glow = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = COLOR.rgb * texture(texture_albedo, UV).rgb;
	METALLIC = metallic;
	SPECULAR = specular;
	ROUGHNESS = roughness;
	EMISSION = glow;
}
