shader_type spatial;
render_mode cull_disabled;
// Asphalt ribbon. UV.x runs across the road (0..1), UV.y along it in metres.

uniform sampler2D asphalt_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float width = 14.0;
uniform float lanes = 2.0;          // per direction

void fragment() {
	vec2 uv = vec2(UV.x * width, UV.y) * 0.25;
	vec3 c = texture(asphalt_d, uv).rgb * 0.8;
	float x = UV.x * width;
	float along = UV.y;
	float paint = 0.0;
	// Edge lines.
	paint += step(0.45, x) * step(x, 0.6) + step(width - 0.6, x) * step(x, width - 0.45);
	// Double yellow centre.
	float cx = abs(x - width * 0.5);
	float yellow = step(0.1, cx) * step(cx, 0.25);
	// Dashed lane dividers.
	float lane_w = (width * 0.5) / lanes;
	for (float i = 1.0; i < 4.0; i += 1.0) {
		if (i < lanes) {
			float d = abs(cx - lane_w * i);
			paint += step(d, 0.08) * step(fract(along / 9.0), 0.5);
		}
	}
	vec3 white = vec3(0.85);
	c = mix(c, white, clamp(paint, 0.0, 1.0) * 0.9);
	c = mix(c, vec3(0.85, 0.65, 0.12), yellow * 0.9);
	ALBEDO = c;
	NORMAL_MAP = texture(asphalt_n, uv).rgb;
	ROUGHNESS = mix(0.82, 0.5, clamp(paint + yellow, 0.0, 1.0));
}
