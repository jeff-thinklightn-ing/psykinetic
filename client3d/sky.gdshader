// The outdoor sky (decision 744, environment): ProceduralSkyMaterial's
// gradient as it was (the same top, horizon and ground colours and curves,
// set by Client3D's look update), with the sun's disc and glow, the moon
// with its phase, the stars and a cloud layer under the weather on it. The
// radiance pass (the water's reflections) leaves the stars out. Nothing
// reads TIME: the sky redraws only when its uniforms change, as before.
shader_type sky;

uniform vec4 sky_top_color : source_color = vec4(0.385, 0.454, 0.55, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float sky_curve = 0.15;
uniform vec4 ground_bottom_color : source_color = vec4(0.2, 0.169, 0.133, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform float ground_curve = 0.02;

// The sun and the moon: the way to each (unit, the view's space), their
// colours (alpha: how much shows), the discs' sizes (radians).
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float sun_size = 0.02;
uniform float sun_glow = 0.4;
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec4 moon_color : source_color = vec4(0.85, 0.88, 1.0, 1.0);
uniform float moon_size = 0.03;
// The lit side's way across the disc (unit, square to moon_direction) and
// the phase's cosine: 1 new (none lit), 0 half, -1 full.
uniform vec3 moon_lit = vec3(1.0, 0.0, 0.0);
uniform float moon_terminator = -1.0;
uniform float stars = 0.0;

// The clouds: the cover's noise (R, tiled), the period it tiles over and
// the layer's height (m), the drift (m, the shadows' own), the cover
// (0..1), their colour and how far the sun's colour lights their edges.
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_period = 144.0;
uniform float cloud_height = 120.0;
uniform vec2 cloud_drift = vec2(0.0);
uniform float cloud_cover = 0.0;
uniform vec4 cloud_color : source_color = vec4(1.0);

float star_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 sky_gradient(vec3 eye) {
	float v_angle = acos(clamp(eye.y, -1.0, 1.0));
	float c = 1.0 - v_angle / (PI * 0.5);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	c = (v_angle - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / ground_curve), 0.0, 1.0));
	return mix(ground, sky, step(0.0, eye.y));
}

void sky() {
	vec3 eye = EYEDIR;
	vec3 color = sky_gradient(eye);
	if (eye.y > 0.0) {
		// The stars: one at most in each cell of a grid of directions, by a
		// hash; not in the reflections.
		if (stars > 0.001 && !AT_CUBEMAP_PASS) {
			vec3 grid = eye * 180.0;
			vec3 cell = floor(grid);
			float h = star_hash(cell);
			if (h > 0.996) {
				vec3 at = normalize(cell + 0.5 + (vec3(star_hash(cell + 1.7), star_hash(cell + 3.1), star_hash(cell + 5.3)) - 0.5) * 0.6);
				float off = acos(clamp(dot(eye, at), -1.0, 1.0));
				float twinkle = 0.5 + 0.5 * star_hash(cell + 9.2);
				color += vec3(0.9, 0.93, 1.0) * stars * twinkle * smoothstep(0.0022, 0.0004, off) * smoothstep(0.0, 0.1, eye.y);
			}
		}
		// The moon: its lit part by the phase, the rest the sky's.
		float moon_off = acos(clamp(dot(eye, moon_direction), -1.0, 1.0));
		if (moon_color.a > 0.001 && moon_off < moon_size * 1.2) {
			vec3 side = moon_lit;
			vec3 up = cross(moon_direction, side);
			vec2 disc = vec2(dot(eye - moon_direction, side), dot(eye - moon_direction, up)) / moon_size;
			float r = length(disc);
			float inside = smoothstep(1.0, 0.92, r);
			float lit = smoothstep(-0.06, 0.06, disc.x - moon_terminator * sqrt(max(1.0 - disc.y * disc.y, 0.0)));
			float seas = 0.85 + 0.15 * star_hash(floor(vec3(disc * 4.0, 1.0)));
			color = mix(color, moon_color.rgb * seas, inside * lit * moon_color.a);
			color += moon_color.rgb * 0.08 * moon_color.a * smoothstep(1.2, 1.0, r) * (1.0 - inside);
		}
		// The sun: a disc and its glow, wider near the horizon.
		float sun_off = acos(clamp(dot(eye, sun_direction), -1.0, 1.0));
		float disc = smoothstep(sun_size, sun_size * 0.8, sun_off);
		float glow = exp(-sun_off / (sun_glow * (1.0 + 2.0 * (1.0 - smoothstep(0.0, 0.3, sun_direction.y))))) * 0.35;
		color += sun_color.rgb * sun_color.a * (disc * 4.0 + glow);
		// The clouds: a layer cloud_height up over the camera, the noise
		// cut by the cover; thinning into the haze toward the horizon, lit
		// at their edges toward the sun.
		if (cloud_cover > 0.001) {
			vec2 at = POSITION.xz + eye.xz * cloud_height / max(eye.y, 0.01);
			float n = texture(cloud_noise, (at - cloud_drift) / cloud_period).r;
			float low = 1.0 - 1.1 * cloud_cover;
			float cover = smoothstep(low, low + 0.17, n);
			float far = smoothstep(0.0, 0.12, eye.y);
			vec3 cloud = cloud_color.rgb + sun_color.rgb * sun_color.a * glow * 0.8;
			color = mix(color, mix(sky_horizon_color.rgb, cloud, 0.4 + 0.6 * far), cover * (0.55 + 0.45 * far));
		}
	}
	COLOR = color;
}
