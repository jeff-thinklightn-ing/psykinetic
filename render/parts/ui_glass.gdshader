shader_type canvas_item;
// UiGlass's frost (decision 854): the world behind the pane, blurred (nine taps
// on a soft mip of the screen) and half its colour taken out, so a pane over
// grass reads as glass, not as more grass. The pane's tint is drawn over this.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
// The blur's reach in screen pixels at 1080 lines (the mock's 22 canvas units),
// scaled with the window's height.
uniform float reach = 11.0;
uniform float grey = 0.55;

void fragment() {
	float pixels = reach * (1.0 / SCREEN_PIXEL_SIZE.y) / 1080.0;
	vec2 step = SCREEN_PIXEL_SIZE * pixels;
	float lod = max(log2(pixels) - 0.5, 0.0);
	vec3 sum = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			sum += textureLod(screen, SCREEN_UV + vec2(float(x), float(y)) * step, lod).rgb;
		}
	}
	vec3 c = sum / 9.0;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g), grey), COLOR.a);
}
