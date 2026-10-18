// The see-through round the player in a grown forest (GrownTrees, decision
// 467; Jeff: "use transparency that moves with player to see through the
// tree tops since its a isometric game"): how far a fragment is inside it,
// 0 outside to 1 within, by its distance from the line from the player's
// body (focus) toward the camera, soft over see_soft at see_radius; only
// what is above the player's knees, and on the camera's side of them.
// season_cut's opaque pass leaves what is inside out, season_see draws it
// faded as a near wall is (decision 188), season_see_depth its depth first.

uniform vec3 focus = vec3(-10000.0, 0.0, -10000.0);
uniform float see_radius = 4.5;
uniform float see_soft = 2.0;
// From how high above the body's middle to how high it is all in.
uniform float see_from = -0.4;
uniform float see_full = 0.8;
varying vec3 see_world;

float see_bayer(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[q.y * 4 + q.x]) + 0.5) / 16.0;
}

float see_weight(mat4 inv_view) {
	vec3 back = normalize((inv_view * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec3 d = see_world - focus;
	float along = dot(d, back);
	float r = length(d - back * along);
	float w = 1.0 - smoothstep(see_radius - see_soft, see_radius, r);
	w *= smoothstep(see_from, see_full, d.y);
	w *= smoothstep(-0.6, 0.4, along);
	return w;
}
