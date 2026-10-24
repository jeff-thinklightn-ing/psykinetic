// Seeing the player through ground that hides them (decision 549): where
// the relief stands between the camera and the local player (Client3D's
// _update_sight), the ground, cliff faces and scatter on that line thin to a
// screen-door, SIGHT_KEEP of them left, so the rock reads faded and the
// player shows through it; opaque throughout (no sorting), as a faded wall
// keeps NEAR_ALPHA. Nothing while sight_cut is 0 (a level with no relief:
// always).
//   sight_focus: xyz the player's middle, w their feet's height;
//   sight_toward: xyz from the player toward the camera (unit);
//   sight_cut: how far the cut is in, eased 0..1.
global uniform vec4 sight_focus;
global uniform vec4 sight_toward;
global uniform float sight_cut;

// The line's reach round (m), how far over the feet ground must stand to be
// cut (m), and the share of it left.
const float SIGHT_RADIUS = 1.3;
const float SIGHT_ABOVE = 0.4;
const float SIGHT_KEEP = 0.3;

// A 4x4 ordered dither's threshold at screen pixel [pixel], 0..1: an even
// screen-door, no noise crawling (the sight cut's, and a chunk's appearing,
// decision 660).
float sight_dither(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int index = x + y * 4;
	float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (bayer[index] + 0.5) / 16.0;
}

// Whether the fragment at [world] (its screen pixel [pixel]) is cut away.
bool sight_cut_here(vec3 world, vec2 pixel) {
	if (sight_cut <= 0.0 || world.y < sight_focus.w + SIGHT_ABOVE) {
		return false;
	}
	vec3 off = world - sight_focus.xyz;
	float along = dot(off, sight_toward.xyz);
	if (along <= 0.0) {
		return false;
	}
	float across = length(off - sight_toward.xyz * along);
	float inside = (1.0 - smoothstep(SIGHT_RADIUS * 0.6, SIGHT_RADIUS, across)) * sight_cut;
	return sight_dither(pixel) < inside * (1.0 - SIGHT_KEEP);
}
