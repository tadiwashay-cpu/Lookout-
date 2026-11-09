// Light camera motion blur: smears along the camera's turn direction and
// zooms slightly outward at speed. 6 taps — cheap enough for mobile.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 blur_dir = vec2(0.0);
uniform float radial = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = blur_dir + (uv - vec2(0.5)) * radial;
	vec3 col = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float t = float(i) / 5.0 - 0.5;
		col += texture(screen_tex, uv + dir * t).rgb;
	}
	COLOR = vec4(col / 6.0, 1.0);
}
