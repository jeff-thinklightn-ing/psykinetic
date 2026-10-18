// The goblin's drawing (decision 494), shared by goblin.gdshader and goblin_marking.gdshader
// (the same, marking the stencil for the hover outline).

uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D shine : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D marks : hint_default_black, filter_linear_mipmap, repeat_disable;

instance uniform vec3 skin = vec3(0.0, 1.0, 1.0);
instance uniform vec4 gear = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform vec3 mark = vec3(0.0);

const vec3 SCAR = vec3(0.80, 0.72, 0.62);
const vec3 STRIPES = vec3(0.88, 0.86, 0.80);
const vec3 HAND = vec3(0.62, 0.18, 0.12);

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 c = texture(paint, UV).rgb;
	vec3 hsv = rgb2hsv(c);
	// Its skin: the green texels (hue about 0.17 to 0.45, some colour in them).
	float green = smoothstep(0.15, 0.20, hsv.x) * (1.0 - smoothstep(0.42, 0.48, hsv.x)) * smoothstep(0.12, 0.2, hsv.y);
	vec3 shifted = hsv2rgb(vec3(fract(hsv.x + skin.x), clamp(hsv.y * skin.y, 0.0, 1.0), clamp(hsv.z * skin.z, 0.0, 1.0)));
	vec3 out_c = mix(c, shifted, green);
	// Its gear: the rest but the eyes' bright yellow and the near-black, tinted keeping its shading.
	float eyes = step(0.10, hsv.x) * step(hsv.x, 0.17) * step(0.55, hsv.y);
	float gear_part = (1.0 - green) * (1.0 - eyes) * smoothstep(0.04, 0.10, hsv.z);
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 tinted = gear.rgb * lum / max(dot(gear.rgb, vec3(0.3, 0.59, 0.11)), 0.05);
	out_c = mix(out_c, tinted, gear.a * gear_part);
	// A mark.
	vec3 m = texture(marks, UV).rgb * mark;
	out_c = mix(out_c, SCAR, m.r);
	out_c = mix(out_c, STRIPES, m.g);
	out_c = mix(out_c, HAND, m.b);
	ALBEDO = out_c;
	// As its own material had it: roughness the shine's green, no metal (its metallic 0).
	ROUGHNESS = texture(shine, UV).g;
	METALLIC = 0.0;
}
