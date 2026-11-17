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

// The hair's darker root (419 amended (12), the shading row): hair is darker along the hairline, so a cap
// reads as hair against a face of its own hue. UV2 is the mesh's "hairline" layer (tools/body_gen.py's
// write_hairline): x the distance in metres from the cap's hairline, y 1 on a hair cap and 0 on everything
// else (a beard, a brow, the bun, the fall, the body), so only the cap darkens. At the line the hair is
// ROOT_DARK of its colour, back to its own by ROOT_BAND (7 cm up the cap, short of its crown; at 3 cm it did not
// show, the cap's quads coarser than the band; "deep", the coordinator's pick on root3_69ca53c76 over 9 cm at 0.5).
// Only hair near the face's own light needs it: the full root while the hair's light is at most ROOT_FULL_TO of the
// skin's, none from ROOT_NONE_FROM (blond and grey on the pale skins, drawn close to the face's light by heads by day,
// keep their crown as it was). And only by day: by dusk the carried lantern lights the crown and not the face, so a
// darker hairline moved the crown toward the face (take 3 at 19:00, the sim's daylight 0.21); the root is full from
// ROOT_DAY_FULL of the open sky's daylight (hair_root_day, Client3D's look_day on an outdoor level, 0 in a room or
// underground), where the lantern begins to show (1 - Client3D.LANTERN_DAY_LEAST), none at or under ROOT_DAY_NONE
// (the sun about 1 degree up), between them a ramp. hair_root_full 1 holds it full whatever the hour
// (the character window's body, where a hair colour is picked to read as it will by day).
const float ROOT_BAND = 0.07;
const float ROOT_DARK = 0.55;
const float ROOT_FULL_TO = 0.55;
const float ROOT_NONE_FROM = 0.85;
const float ROOT_DAY_NONE = 0.64;
const float ROOT_DAY_FULL = 0.98;
global uniform float hair_root_day;
instance uniform float hair_root_full = 0.0;

float light_of(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec4 part = COLOR;
	float root = UV2.y * (1.0 - smoothstep(0.0, ROOT_BAND, UV2.x));
	float near_face = light_of(hair.rgb) / max(light_of(skin.rgb), 0.01);
	float spared = smoothstep(ROOT_FULL_TO, ROOT_NONE_FROM, near_face);
	float by_day = smoothstep(ROOT_DAY_NONE, ROOT_DAY_FULL, max(hair_root_day, hair_root_full));
	vec3 hair_seen = hair.rgb * mix(1.0, ROOT_DARK, root * (1.0 - spared) * by_day);
	vec3 own = skin.rgb * part.r + hair_seen * part.g + tunic.rgb * part.b + trousers.rgb * part.a;
	float tinted = clamp(part.r + part.g + part.b + part.a, 0.0, 1.0);
	ALBEDO = mix(mix(texture(palette, UV).rgb, own, tinted), dye.rgb, dye.a);
	ROUGHNESS = 0.9;
}
