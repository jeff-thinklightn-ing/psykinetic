shader_type spatial;
// Water, a mesh a body (Client3D._build_water), over its cells and the land
// round them. Where it shows: the shore field (decision 553,
// Client3D.shore_image: rounded corners, round ponds, streams winding within
// their cells) over a half, read SHORE_WARP aside by a noise; the field and
// the warp keep it within Client3D.SHORE_BOUND of the cells' true edge, so a
// cell that is land never looks drowned nor a water cell dry. A water laid
// as a curve (559, terrain's side) has its field from the curve itself, its
// edge at the curve's half width, never from its cells. How deep: half the
// distance into the water (depth_tex: Client3D._curve_field, or
// _water_depth for a water without a curve).
// Foam on the land side of the shore; deeper and less clear toward the
// middle; ripples that drift. A stream is a ribbon along its path
// (decision 557, Client3D._build_ribbons): its ripples run the way its
// points' colour says (r, g; how fast, b), two phases of the flow
// cross-faded so they never stretch, white where it falls (a); it leaves
// a pond's water (the mask's r, not a) to the pond's body. Over a ford
// (the mask's b) it is pale and clear over the stones, with foam where the
// current meets them.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D water : filter_linear, repeat_disable;
// The world cell at the mask's texel (0, 0), and the mask's size in cells.
uniform vec2 mask_origin;
uniform vec2 mask_size;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.25, 0.55, 0.7);
uniform vec3 deep : source_color = vec3(0.08, 0.22, 0.42);
uniform vec3 foam : source_color = vec3(0.85, 0.92, 0.95);
// A stream's ribbon (decision 557): its flow in its points' colours.
uniform bool ribbon = false;
// A water drawn from its curve (559, terrain's side): its fords' shallows
// in UV's x, not the mask's cells; a tall fall's curtain (570) UV's y 1,
// and a stream's end in another water fading out (UV's y under a half).
uniform bool curved = false;
// The shore field, Client3D.SHORE_RES texels a cell over the mask's cells.
uniform sampler2D shore : hint_default_black, filter_linear, repeat_disable;
// The water's depth at the shore field's texels (559, terrain's side): half
// the distance into it, out to two cells (Client3D._depth_image).
uniform sampler2D depth_tex : hint_default_black, filter_linear, repeat_disable;

varying vec3 world;
varying vec4 running;

// As the ground's: smooth noise 0..1, about a feature a unit of p.
float noise(vec2 p) {
	return texture(noise_tex, mat2(vec2(0.913, 0.408), vec2(-0.408, 0.913)) * p / 64.0).r;
}

// Client3D.SHORE_WARP: how far aside (cells) the shore field is read.
const float SHORE_WARP = 0.1;
const float FOAM = 0.1;
// How fast a stream runs (m/s), and how long each phase of its flow lasts
// (s) before it fades out and starts again.
const float FLOW_SPEED = 0.6;
const float FLOW_CYCLE = 1.6;

// The surface at [at] at time [t]: the ripples' slope (xy), and a churn
// (z) that the foam breaks up by.
vec3 surface(vec2 at, float t) {
	float churn = noise(at * 4.0 + vec2(t * 3.0, -t * 2.0));
	vec2 a = at * 1.3 + vec2(t, t * 0.7);
	vec2 b = at * 2.2 - vec2(t * 0.8, t * 0.4);
	float e = 0.08;
	vec2 slope = vec2(noise(a + vec2(e, 0.0)) - noise(a - vec2(e, 0.0)), noise(a + vec2(0.0, e)) - noise(a - vec2(0.0, e)))
			+ vec2(noise(b + vec2(e, 0.0)) - noise(b - vec2(e, 0.0)), noise(b + vec2(0.0, e)) - noise(b - vec2(0.0, e)));
	return vec3(slope, churn);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	running = ribbon ? COLOR : vec4(0.5, 0.5, 0.0, 0.0);
}

void fragment() {
	vec2 at = world.xz;
	// The shore: the field's half, read a little aside; about a cell from
	// dry to wet, so a half less it is about how far into the water.
	vec2 aside = vec2(noise(at * 0.9) - 0.5, noise(at * 0.9 + 17.0) - 0.5) * 2.0 * SHORE_WARP;
	float into = texture(shore, (at + aside - mask_origin + 0.5) / mask_size).r - 0.5;
	if (into < -FOAM) {
		discard;
	}
	vec2 uv = (at - mask_origin + 0.5) / mask_size;
	// A ribbon leaves a pond's water to the pond's body.
	vec4 cell = texelFetch(water, clamp(ivec2(round(at)) - ivec2(round(mask_origin)), ivec2(0), ivec2(round(mask_size)) - 1), 0);
	if (ribbon && cell.r > 0.5 && cell.a < 0.5) {
		discard;
	}
	float inside = smoothstep(-0.02, 0.03, into);
	// How deep: half the distance into the water (from the curve, or a
	// water without one from its cells), Client3D._depth_image.
	float depth = smoothstep(0.15, 1.2, texture(depth_tex, (at - mask_origin + 0.5) / mask_size).r * 2.0);
	float t = TIME * 0.12;
	// Down a stream the surface drifts with the water, in two phases: each
	// carried FLOW_SPEED along and faded out as the other comes in.
	vec2 way = (running.rg * 2.0 - 1.0) * running.b * 2.0;
	float phase = fract(TIME / FLOW_CYCLE);
	float other = fract(phase + 0.5);
	float swap = abs(phase - 0.5) * 2.0;
	vec3 moving = mix(surface(at - way * FLOW_SPEED * FLOW_CYCLE * phase, t),
			surface(at - way * FLOW_SPEED * FLOW_CYCLE * other + vec2(0.5) * length(way), t), swap);
	vec2 slope = moving.xy;
	float churn = moving.z;
	// A ford: shallow and clear, the stones showing, foam across it where
	// the current meets them and flecks on it.
	float shoal = smoothstep(0.15, 0.85, curved ? UV.x : texture(water, uv).b);
	depth *= 1.0 - shoal;
	vec3 colour = mix(shallow, deep, depth);
	// The foam: a band at the shore, on the land side, broken up and drifting.
	float band = smoothstep(-FOAM, -FOAM * 0.4, into) * (1.0 - smoothstep(0.0, 0.06, into));
	band *= smoothstep(0.3, 0.6, churn);
	float riffle = shoal * (1.0 - shoal) * 4.0 * smoothstep(0.35, 0.6, churn) * min(length(way) * 2.0, 1.0);
	float flecks = shoal * smoothstep(0.7, 0.85, churn) * 0.35;
	// A fall: white water down its step, not a band across it: streaks
	// drawn out along the flow and carried down it, and white where it
	// breaks over the stones (fixed spots), both thinning toward the step's
	// ends (running.a) and broken up by the churn.
	vec2 down = length(way) > 0.001 ? normalize(way) : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	vec2 along = vec2(dot(at, across) * 3.5, dot(at, down) * 0.8 - TIME * FLOW_SPEED * 1.5);
	// A tall fall's curtain (Client3D._build_curve_ribbon): its streaks
	// down its height, falling fast, every bit of it white.
	float curtain = curved ? step(0.5, UV.y) : 0.0;
	if (curtain > 0.5) {
		along = vec2(dot(at, across) * 3.5, world.y * 0.5 + TIME * FLOW_SPEED * 4.0);
		churn = max(churn, 0.6);
	}
	float streaks = smoothstep(0.42, 0.62, noise(along * 9.0));
	float stones = smoothstep(0.58, 0.7, noise(at * 6.0 + 31.0));
	float fall = smoothstep(0.15, 0.6, running.a) * max(streaks, stones) * smoothstep(0.15, 0.5, churn);
	band = max(max(band, fall), max(riffle, flecks));
	colour = mix(colour, foam, band);
	ALBEDO = colour;
	ALPHA = max(inside * mix(0.6, 0.88, depth) * mix(1.0, 0.4, shoal), band * 0.85);
	if (curved && UV.y < 0.5) {
		ALPHA *= 1.0 - UV.y * 2.0;
	}
	// Ripples: the noise's slope, two layers drifting apart.
	// A curtain keeps its own facing (down the stream), rippled a little.
	if (curtain < 0.5) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x * 1.5, 1.0, -slope.y * 1.5)), 0.0)).xyz);
	} else {
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(slope.x * 0.6, 0.0, slope.y * 0.6, 0.0)).xyz);
	}
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
