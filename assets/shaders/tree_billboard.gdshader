shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float sway = 0.15;

void vertex() {
	float h = clamp(VERTEX.y / 9.0, 0.0, 1.0);
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.x += sin(TIME * 1.3 + o.x * 0.1 + o.z * 0.13) * sway * h * h;
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.15, 0.2, 0.1);
}
