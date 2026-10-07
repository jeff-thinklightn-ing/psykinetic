// A wall face with soft circular cutouts: wherever a creature stands behind
// it, the face fades to CUTOUT_FLOOR at the creature's centre and back to
// opaque at RADIUS, so the creature shows through. Centres are in canvas
// (world) space, strengths 0..1 as the cutout animates in and out.
shader_type canvas_item;

const int MAX_CUTOUTS = 8;
const float CUTOUT_FLOOR = 0.25;

uniform int count = 0;
uniform float radius = 32.0;
uniform vec2 centers[8];
uniform float strengths[8];

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float keep = 1.0;
	for (int i = 0; i < MAX_CUTOUTS; i++) {
		if (i >= count) {
			break;
		}
		float d = distance(world_pos, centers[i]);
		float hole = smoothstep(radius, 0.0, d) * strengths[i];
		keep = min(keep, 1.0 - (1.0 - CUTOUT_FLOOR) * hole);
	}
	COLOR.a *= keep;
}
