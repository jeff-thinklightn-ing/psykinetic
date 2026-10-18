shader_type spatial;
// The ground, one mesh per chunk (Client3D._build_ground): a vertex at every
// cell corner, its light and heat in CUSTOM0 (r: brightness, g: warmth, the
// cells around the corner averaged), so both fade smoothly from cell to cell;
// b: at the foot of a drop, a: at its top, so a ledge's foot is shaded and
// its edge caught by the light.
// Which ground is where comes from kinds, a texel a cell (r grass, g dirt,
// b stone, a sand), read where the noise pushes it, so kinds meet along
// ragged borders, not cell edges. Each kind's look is noise (noise_tex,
// made at run time) until its ground.<kind> texture has art (decision 437),
// then that texture in world metres, a slow swell on it against the tile's
// repeat; everything over the kinds (the season, wet, the forest's edge,
// light and heat) is the same either way.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D kinds : filter_linear, repeat_disable;
// The world cell at kinds' texel (0, 0), and the texture's size in cells.
uniform vec2 kinds_origin;
uniform vec2 kinds_size;
uniform vec3 grass : source_color = vec3(0.21, 0.6, 0.25);
uniform vec3 dirt : source_color = vec3(0.45, 0.35, 0.22);
uniform vec3 stone : source_color = vec3(0.56, 0.56, 0.54);
uniform vec3 sand : source_color = vec3(0.78, 0.7, 0.5);
uniform vec3 warm : source_color = vec3(1.0, 0.5, 0.2);
// The kinds' own textures (ground.<kind>, decision 437), each read at the
// world xz over its tile (metres: r grass, g dirt, b stone, a sand) while
// its flag is on.
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool grass_own = false;
uniform bool dirt_own = false;
uniform bool stone_own = false;
uniform bool sand_own = false;
uniform vec4 kind_tiles = vec4(4.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// Where the water is, a texel a cell like kinds (Client3D._build_ground):
// the bed and the shore beside it darker, wet.
uniform sampler2D water : hint_default_black, filter_linear, repeat_disable;
// Outdoors, the forest's floor (the mask's g): the land runs into it along
// a ragged line.
uniform vec3 forest_floor : source_color = vec3(0.17, 0.26, 0.14);
// Past pine stands, the needles' own texture there (decision 423's
// ground.needles), so the land's edge meets the floor beyond it.
uniform sampler2D needles_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool needles_own = false;
uniform float needles_tile = 4.0;
uniform float needles_shade = 0.7;
// Outdoors, the sky's light on the floor (as a brightness, like CUSTOM0's
// r, which then holds the cell's own sources alone): the floor is lit to
// the brighter of the two, so a torch's pool shows at night and the hour
// changes one number, not every cell (decision 304). 0 indoors.
uniform float sky_floor = 0.0;
// Under a forest's canopy (decision 477): its cover, a texel a cell like
// kinds (Client3D.canopy_texture, black where there is none), and the sky's
// light on the floor under a full roof, so the floor is lit as the sim
// lights it (Fields.ambient_at): sky_floor in the open, sky_floor_roof
// under the crowns.
uniform sampler2D canopy : hint_default_black, filter_linear, repeat_disable;
uniform float sky_floor_roof = 0.0;
// The floor sets (Client3D._floor_sets, decision 285), a byte a cell like
// kinds but read cell by cell, so a floor ends at the walls' line: 0 the
// ground's own look, 1 wood (planks), 2 stone (flagstones), 3 cave (rock).
// Each in its swatch, or its floor.<set> texture (4 m a tile) once it has
// one.
uniform sampler2D floors : filter_nearest, repeat_disable;
uniform vec3 floor_wood : source_color = vec3(0.54, 0.42, 0.28);
uniform vec3 floor_stone : source_color = vec3(0.59, 0.58, 0.55);
uniform vec3 floor_cave : source_color = vec3(0.42, 0.4, 0.38);
uniform sampler2D floor_wood_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_cave_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool floor_wood_own = false;
uniform bool floor_stone_own = false;
uniform bool floor_cave_own = false;

varying vec3 world;
// The season (decision 362): x green, y turn (autumn), z snow cover. Grass
// dries toward straw out of season and turns in autumn; snow lies where the
// ground faces up (slopes and steps stay bare), never on a building's floor.
global uniform vec4 season;
varying float up;
varying vec2 shade;
varying vec2 relief;

// Smooth noise 0..1 with about one feature per unit of p, read from
// noise_tex (FastNoiseLite, made at run time, 64 features across before it
// repeats), turned at an odd angle so no repeat lines up with the cells.
float noise(vec2 p) {
	return texture(noise_tex, mat2(vec2(0.913, 0.408), vec2(-0.408, 0.913)) * p / 64.0).r;
}

float fbm(vec2 p) {
	float total = 0.0;
	float amount = 0.5;
	// Each octave turned, so no axis lines up with the grid.
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		total += amount * noise(p);
		p = turn * p * 2.03 + 11.7;
		amount *= 0.5;
	}
	return total;
}

// Two numbers 0..1 for a lattice point, by integer mixing: exact however
// far from the origin.
vec2 hash2(vec2 p) {
	uvec2 v = uvec2(ivec2(p)) * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	return vec2(v) / 4294967295.0;
}

// Cobbles: the distance to the nearest stone's edge (small at the joints)
// and that stone's own random tint.
vec2 cobbles(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	float tint = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 at = vec2(float(x), float(y));
			vec2 seed = hash2(i + at);
			float d = length(at + 0.15 + 0.7 * seed - f);
			if (d < nearest) {
				second = nearest;
				nearest = d;
				tint = seed.x;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2(second - nearest, tint);
}

// Boards (or slabs) laid in rows row deep, each about run
// long, every row shifted: how far p is from the nearest joint (in
// metres) and the board's own random tint.
vec2 boards(vec2 p, float row, float run) {
	float r = floor(p.y / row);
	vec2 seed = hash2(vec2(r, 7.0));
	float size = run * (0.7 + 0.6 * seed.x);
	float along = p.x / size + seed.y;
	float across = fract(p.y / row);
	float joint = min(min(across, 1.0 - across) * row, min(fract(along), 1.0 - fract(along)) * size);
	return vec2(joint, hash2(vec2(r, floor(along) + 101.0)).x);
}

// [param tex] at [param at] over [param tile] metres, with the pixel's own
// rate of change (worked out before any branch, so its mipmap is right
// where kinds meet), under a slow swell so the tile's repeat doesn't show
// as a grid.
vec3 tiled(sampler2D tex, vec2 at, float tile, vec2 dx, vec2 dy, float salt) {
	return textureGrad(tex, at / tile, dx / tile, dy / tile).rgb * (0.86 + 0.28 * fbm(at * 0.18 + salt));
}

vec3 floor_look(int floor_set, vec2 at, float fine) {
	if (floor_set == 1) {
		if (floor_wood_own) {
			return texture(floor_wood_tex, at / 4.0).rgb;
		}
		vec2 board = boards(at, 0.2, 1.6);
		vec3 here = floor_wood * (0.8 + 0.32 * board.y) * (0.93 + 0.14 * noise(vec2(at.x * 0.9, at.y * 28.0)));
		return here * mix(0.5, 1.0, smoothstep(0.004, 0.016, board.x));
	}
	if (floor_set == 2) {
		if (floor_stone_own) {
			return texture(floor_stone_tex, at / 4.0).rgb;
		}
		vec2 slab = boards(mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0)) * at, 0.7, 0.9);
		vec3 here = floor_stone * (0.84 + 0.22 * slab.y) * (0.92 + 0.16 * fbm(at * 1.3 + slab.y * 9.0)) * (0.95 + 0.1 * fine);
		return here * mix(0.58, 1.0, smoothstep(0.012, 0.04, slab.x));
	}
	if (floor_cave_own) {
		return texture(floor_cave_tex, at / 4.0).rgb;
	}
	return floor_cave * (0.72 + 0.42 * fbm(at * 0.7 + 60.0)) * (0.9 + 0.2 * noise(at * 5.0 + 3.0));
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	shade = CUSTOM0.rg;
	relief = CUSTOM0.ba;
}

void fragment() {
	vec2 at = world.xz;
	// Where the kinds are read: pushed about by up to most of a cell, so a
	// border wanders across cells.
	vec2 push = vec2(fbm(at * 0.45), fbm(at * 0.45 + 31.0)) - 0.5;
	vec2 uv = (at - kinds_origin + 0.5 + push * 1.1) / kinds_size;
	vec4 weights = texture(kinds, uv);
	// Each kind's own ragged edge, then the strongest kept, with a short
	// soft band where two meet.
	weights += (vec4(noise(at * 2.3), noise(at * 2.3 + 5.0), noise(at * 2.3 + 9.0), noise(at * 2.3 + 13.0)) - 0.5) * 0.35;
	float strongest = max(max(weights.r, weights.g), max(weights.b, weights.a));
	weights = max(weights - (strongest - 0.18), vec4(0.0));
	weights /= max(weights.r + weights.g + weights.b + weights.a, 0.0001);

	// Each kind's look, worked out only where it shows.
	float fine = noise(at * 7.0);
	vec2 dx = dFdx(at);
	vec2 dy = dFdy(at);
	vec3 colour = vec3(0.0);
	if (weights.r > 0.0) {
		vec3 here = grass_own ? tiled(grass_tex, at, kind_tiles.r, dx, dy, 0.0)
				: grass * (0.82 + 0.36 * fbm(at * 0.18)) * (0.92 + 0.16 * fine);
		here = mix(here, here * vec3(1.12, 1.05, 0.7), smoothstep(0.55, 0.75, noise(at * 0.31 + 3.0)));
		float grey = clamp(dot(here, vec3(0.3, 0.55, 0.15)) * 3.0, 0.6, 1.3);
		here = mix(here, vec3(0.3, 0.25, 0.1) * grey, (1.0 - season.x) * 0.5);
		here = mix(here, vec3(0.34, 0.17, 0.04) * grey, season.y * 0.3 * smoothstep(0.35, 0.7, noise(at * 0.5 + 60.0)));
		colour += here * weights.r;
	}
	if (weights.g > 0.0) {
		colour += (dirt_own ? tiled(dirt_tex, at, kind_tiles.g, dx, dy, 7.0)
				: dirt * (0.85 + 0.3 * fbm(at * 0.6 + 7.0)) * (0.9 + 0.2 * noise(at * 9.0))) * weights.g;
	}
	if (weights.b > 0.0 && stone_own) {
		colour += tiled(stone_tex, at, kind_tiles.b, dx, dy, 13.0) * weights.b;
	} else if (weights.b > 0.0) {
		vec2 cobble = cobbles(mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * at * 1.6);
		vec3 here = stone * (0.86 + 0.2 * cobble.y) * (0.94 + 0.12 * fine);
		colour += here * mix(0.62, 1.0, smoothstep(0.02, 0.12, cobble.x)) * weights.b;
	}
	if (weights.a > 0.0 && sand_own) {
		colour += tiled(sand_tex, at, kind_tiles.a, dx, dy, 21.0) * weights.a;
	} else if (weights.a > 0.0) {
		colour += sand * (0.92 + 0.12 * noise(at * 0.5 + 21.0))
				* (0.96 + 0.08 * noise(vec2(at.x * 1.5 + at.y * 0.4, at.y * 6.0))) * weights.a;
	}

	ivec2 cell = ivec2(floor(at - kinds_origin + 0.5));
	int floor_set = int(round(texelFetch(floors, clamp(cell, ivec2(0), ivec2(kinds_size) - 1), 0).r * 255.0));
	if (floor_set > 0) {
		colour = floor_look(floor_set, at, fine);
	}

	colour *= mix(1.0, 0.5, relief.x) * (1.0 + 0.14 * relief.y);
	float wet = smoothstep(0.25, 0.6, texture(water, (at - kinds_origin + 0.5) / kinds_size).r);
	colour = mix(colour, colour * vec3(0.5, 0.58, 0.62), wet);
	float forest = smoothstep(0.35, 0.65, texture(water, uv).g + (noise(at * 1.9 + 40.0) - 0.5) * 0.35);
	// Under a grown forest's roof (decisions 466, 467) the grass is needles
	// where the cover passes a half, raggedly; the path's dirt and the
	// floors stay.
	float roof = texture(canopy, (at - kinds_origin + 0.5) / kinds_size).r;
	if (floor_set == 0) {
		forest = max(forest, smoothstep(0.45, 0.75, roof + (noise(at * 1.3 + 70.0) - 0.5) * 0.3) * weights.r);
	}
	vec3 under_trees = needles_own ? textureGrad(needles_tex, at / needles_tile, dx / needles_tile, dy / needles_tile).rgb * needles_shade
			: forest_floor * (0.8 + 0.4 * fbm(at * 0.4 + 50.0));
	colour = mix(colour, under_trees, forest);
	if (floor_set == 0) {
		// Less snow lies under the roof: a third under full cover.
		float drift = (0.85 + 0.3 * fbm(at * 0.7 + 80.0)) * (1.0 - 0.7 * roof);
		colour = mix(colour, vec3(0.9, 0.93, 0.97), clamp(season.z * drift, 0.0, 1.0) * smoothstep(0.75, 0.95, up) * (1.0 - wet));
	}

	// Light and heat as the old floor had them, worked out in sRGB.
	float sky_here = mix(sky_floor, sky_floor_roof, roof);
	vec3 lit = pow(colour, vec3(1.0 / 2.2)) * max(shade.r, sky_here);
	vec3 warm_srgb = pow(warm, vec3(1.0 / 2.2));
	ALBEDO = pow(mix(lit, warm_srgb, shade.g), vec3(2.2));
	EMISSION = pow(warm_srgb * shade.g, vec3(2.2));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
