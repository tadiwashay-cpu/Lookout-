shader_type spatial;
// Open-world ground: grass, forest floor, sand and rock blended by slope,
// height and region masks (vertex colour: r = forest, g = sand, b = urban).
// Mobile budget: a grass pixel costs 3 texture reads; the other layers are
// only read where their mask is non-zero (regions are large, so the GPU's
// branches stay coherent).

uniform sampler2D grass_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass2_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D urban_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.12;
uniform float snow_line = 200.0;

varying vec3 wpos;
varying vec3 wnorm;
varying float far_fade;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	far_fade = smoothstep(80.0, 160.0, length(wpos - CAMERA_POSITION_WORLD));
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	float slope = 1.0 - wnorm.y;
	float rockiness = clamp(smoothstep(0.18, 0.38, slope) + smoothstep(90.0, 160.0, wpos.y) * 0.6, 0.0, 1.0);
	// Grass, with large-scale tint patches (tiny mip, nearly free).
	float patchy = texture(grass2_d, wpos.xz * 0.004).g;
	vec3 c = mix(texture(grass_d, uv).rgb, texture(grass2_d, uv * 0.37).rgb, 0.45);
	c *= mix(vec3(0.62, 0.95, 0.45), vec3(0.78, 0.92, 0.5), patchy);
	if (COLOR.r > 0.01) {
		c = mix(c, texture(forest_d, uv * 1.3).rgb * vec3(0.75, 0.85, 0.6), COLOR.r);
	}
	if (COLOR.g > 0.01) {
		c = mix(c, texture(sand_d, uv).rgb, COLOR.g);
	}
	if (COLOR.b > 0.01) {
		c = mix(c, texture(urban_d, uv * 1.6).rgb, COLOR.b);
	}
	if (rockiness > 0.01) {
		// Steep faces: project from the side so cliffs don't stretch.
		vec2 ruv = abs(wnorm.x) > abs(wnorm.z) ? wpos.zy : wpos.xy;
		ruv = mix(wpos.xz, ruv, smoothstep(0.3, 0.6, slope)) * tile * 0.5;
		c = mix(c, texture(rock_d, ruv).rgb, rockiness);
	}
	float snow = smoothstep(snow_line, snow_line + 40.0, wpos.y) * smoothstep(0.55, 0.25, slope);
	c = mix(c, vec3(0.9, 0.92, 0.95), snow);
	ALBEDO = c * 0.85;
	// Normal detail only up close (far away it just shimmers).
	if (far_fade < 0.99) {
		vec3 n = rockiness > 0.5 ? texture(rock_n, wpos.xz * tile * 0.5).rgb : texture(grass_n, uv).rgb;
		NORMAL_MAP = mix(n, vec3(0.5, 0.5, 1.0), far_fade);
		NORMAL_MAP_DEPTH = 0.8;
	}
	ROUGHNESS = mix(0.95, 0.4, snow);
}
