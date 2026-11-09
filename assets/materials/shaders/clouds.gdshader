// High cloud layer: scrolling noise, soft edges, tinted by time of day.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float coverage = 0.48;
uniform float softness = 0.18;
uniform vec2 wind = vec2(0.004, 0.002);
uniform float scale = 0.0009;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * scale + wind * TIME;
	float n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.7 + 0.3).r * 0.35;
	float a = smoothstep(coverage, coverage + softness, n);
	// Fade toward the horizon so the edge of the plane never shows.
	float d = length(world_pos.xz - CAMERA_POSITION_WORLD.xz);
	a *= 1.0 - smoothstep(1400.0, 2100.0, d);
	ALBEDO = tint.rgb * mix(0.82, 1.0, n);
	ALPHA = a * tint.a;
}
