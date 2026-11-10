shader_type canvas_item;
// Radial speed blur around the edges of the screen; the centre (the car)
// stays sharp. Only drawn above 150 km/h, so it costs nothing otherwise.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 dir = SCREEN_UV - vec2(0.5, 0.55);
	float mask = smoothstep(0.2, 0.55, length(dir)) * amount;
	if (mask < 0.02) {
		discard;
	}
	vec3 col = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		col += texture(screen_tex, SCREEN_UV - dir * float(i) * 0.014 * mask).rgb;
	}
	COLOR = vec4(col / 6.0, clamp(mask * 1.4, 0.0, 1.0));
}
