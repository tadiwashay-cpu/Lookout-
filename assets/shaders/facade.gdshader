shader_type spatial;
// Buildings drawn from unit boxes in MultiMeshes: the wall texture and the
// window grid come from world position, so one material serves every size.
// INSTANCE_CUSTOM: rgb = tint, a = seed.

uniform sampler2D wall_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_d : source_color, filter_linear_mipmap, repeat_enable;
uniform float wall_scale = 0.25;
uniform float window_w = 3.2;
uniform float floor_h = 3.4;
uniform float night = 0.0;
uniform float glass = 0.7;           // how much of each bay is glass

varying vec3 wpos;
varying vec3 lnorm;
varying vec4 custom;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	custom = INSTANCE_CUSTOM;
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec3 n = lnorm;
	if (n.y > 0.6) {
		ALBEDO = texture(roof_d, wpos.xz * 0.2).rgb * 0.85;
		ROUGHNESS = 0.9;
	} else {
		float u = abs(n.x) > abs(n.z) ? wpos.z : wpos.x;
		vec2 uv = vec2(u, wpos.y) * wall_scale;
		vec3 wall = texture(wall_d, uv).rgb * mix(vec3(1.0), custom.rgb, 0.55);
		float ground = step(wpos.y, 4.6);
		vec2 cell = vec2(u / window_w, (wpos.y - 0.6) / floor_h);
		vec2 f = fract(cell);
		float win = step(0.5 - glass * 0.5, f.x) * step(f.x, 0.5 + glass * 0.5) * step(0.22, f.y) * step(f.y, 0.86);
		win *= step(4.2, wpos.y);
		// Shop windows on the ground floor.
		float shop = ground * step(0.6, wpos.y) * step(wpos.y, 3.8) * step(0.08, fract(u / 6.0)) * step(fract(u / 6.0), 0.92);
		float any_win = max(win, shop * custom.a);
		vec3 glass_col = mix(vec3(0.03, 0.04, 0.05), vec3(0.14, 0.18, 0.22), smoothstep(0.0, 1.0, f.y));
		ALBEDO = mix(wall, glass_col, any_win);
		ROUGHNESS = mix(0.85, 0.08, any_win);
		METALLIC = any_win * 0.6;
		NORMAL_MAP = mix(texture(wall_n, uv).rgb, vec3(0.5, 0.5, 1.0), any_win);
		float room = hash(floor(vec3(cell, u * 0.0) + vec3(floor(wpos.x * 0.05), 0.0, floor(wpos.z * 0.05)) + custom.a * 17.0));
		EMISSION = any_win * step(0.45, room) * night * mix(vec3(1.0, 0.72, 0.4), vec3(0.7, 0.8, 1.0), step(0.85, room)) * 0.55 * step(0.62, room + 0.15);
	}
}
