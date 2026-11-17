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
// A dye over the part's own colour by its alpha (419 amended (2): a hood worn with a cape takes
// the cape's, PersonLook.dye_hood); alpha 0, the default, leaves the picture as it was.
instance uniform vec4 dye : source_color = vec4(0.0);

// The hair's darker root (ROOTLABEL, the shading row): hair is darker along the hairline, so a cap
// reads as hair against a face of its own hue. UV2 is the mesh's "hairline" layer (tools/body_gen.py's
// write_hairline): x the distance in metres from the cap's hairline, y 1 on a hair cap and 0 on everything
// else (a beard, a brow, the bun, the fall, the body), so only the cap darkens. At the line the hair is
// ROOT_DARK of its colour, back to its own by ROOT_BAND (the cap's lower half, short of its crown, about 14.5 cm
// from the line; at 3 cm it did not show, the cap's quads coarser than the band); hair lighter than the face
// darkens less (by its light over the face's, to ROOT_PALE of it at PALE_SPAN over), so a pale crown keeps its distance.
const float ROOT_BAND = 0.09;
const float ROOT_DARK = 0.5;
const float ROOT_PALE = 0.3;
const float PALE_SPAN = 1.0;

float light_of(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 part = COLOR;
	float root = UV2.y * (1.0 - smoothstep(0.0, ROOT_BAND, UV2.x));
	float over = light_of(hair.rgb) / max(light_of(skin.rgb), 0.01) - 1.0;
	float pale = mix(1.0, ROOT_PALE, clamp(over / PALE_SPAN, 0.0, 1.0));
	vec3 hair_seen = hair.rgb * mix(1.0, ROOT_DARK, root * pale);
	vec3 own = skin.rgb * part.r + hair_seen * part.g + tunic.rgb * part.b + trousers.rgb * part.a;
	float tinted = clamp(part.r + part.g + part.b + part.a, 0.0, 1.0);
	ALBEDO = mix(mix(texture(palette, UV).rgb, own, tinted), dye.rgb, dye.a);
	ROUGHNESS = 0.9;
}
