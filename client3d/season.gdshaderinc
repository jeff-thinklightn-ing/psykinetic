// What the trees, the forest's floors and the canopy past them draw with
// (decision 362's season, terrain's side; Client3D.season_material): their
// own colour (a texture, a colour, the vertex colours), and then, as the
// global season says, foliage dries toward straw out of season and turns in
// autumn (only for a broadleaf's, leaf on; foliage told by its green), and
// snow lies on what faces up. NEAR: the see-through copy, faded.

global uniform vec4 season;
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_texture = false;
uniform bool use_vertex_color = false;
uniform bool vertex_srgb = true;
uniform bool leaf = false;
uniform float roughness = 0.9;
uniform float alpha = 1.0;
// A ground texture tiled in world metres (a floor plane of any size: the
// needles' floor, decision 423), world_tile metres a tile; off at 0.
uniform sampler2D tile_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float world_tile = 0.0;
varying float up;
varying vec2 world_xz;
#ifdef CUTAWAY
// A grown forest's trees (GrownTrees, decision 467): the see-through round
// the player. The opaque pass leaves out what is in it (dithered at its
// edge); SEE_THROUGH draws only that, faded toward alpha as a near wall is.
#include "res://client3d/see_through.gdshaderinc"
#endif

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
#ifdef CUTAWAY
	see_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif
}

void fragment() {
#ifdef CUTAWAY
	float see = see_weight(INV_VIEW_MATRIX);
#ifdef SEE_THROUGH
	if (see <= see_bayer(FRAGCOORD.xy)) {
		discard;
	}
#else
	if (see > see_bayer(FRAGCOORD.xy)) {
		discard;
	}
#endif
#endif
	vec3 colour = albedo_color.rgb;
	if (use_texture) {
		colour *= texture(albedo_texture, UV).rgb;
	}
	if (world_tile > 0.0) {
		colour *= texture(tile_texture, world_xz / world_tile).rgb;
	}
	if (use_vertex_color) {
		colour *= vertex_srgb ? to_linear(COLOR.rgb) : COLOR.rgb;
	}
	if (leaf) {
		// Each tree its own autumn, by where it stands: gold, orange or
		// rust; the light and dark of its foliage kept.
		float foliage = smoothstep(0.004, 0.02, colour.g - max(colour.r, colour.b));
		float shade = clamp(dot(colour, vec3(0.3, 0.55, 0.15)) * 4.0, 0.5, 1.4);
		float which = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 turned = which < 0.4 ? vec3(0.55, 0.32, 0.03) : (which < 0.8 ? vec3(0.6, 0.17, 0.02) : vec3(0.36, 0.06, 0.02));
		vec3 dried = mix(colour, vec3(0.3, 0.24, 0.09) * shade, (1.0 - season.x) * 0.55);
		dried = mix(dried, turned * shade, season.y * 0.75);
		colour = mix(colour, dried, foliage);
	}
	colour = mix(colour, vec3(0.9, 0.93, 0.97), season.z * smoothstep(0.3, 0.8, up) * 0.85);
	ALBEDO = colour;
	ROUGHNESS = roughness;
#ifdef NEAR
	ALPHA = alpha;
#endif
#ifdef SEE_THROUGH
	ALPHA = mix(1.0, alpha, see);
#endif
}
