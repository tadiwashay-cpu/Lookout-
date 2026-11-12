shader_type spatial;
// Open-world ground: grass, forest floor, sand and rock blended by slope,
// height and region masks (vertex colour: r = forest, g = sand, b = urban).

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy * s).rgb * w.x + texture(t, p.xz * s).rgb * w.y + texture(t, p.xy * s).rgb * w.z;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	// Break tiling: a second, rotated lookup at a different scale.
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * wpos.xz * tile * 0.37;
	// Poly Haven grass photos are dry and yellow: tint towards a living green,
	// and vary it in large patches so fields don't look flat.
	float patchy = texture(grass2_d, wpos.xz * 0.004).g;
	vec3 grass = mix(texture(grass_d, uv).rgb, texture(grass2_d, uv2 * 2.0).rgb, 0.45);
	grass *= mix(vec3(0.62, 0.95, 0.45), vec3(0.78, 0.92, 0.5), patchy);
	vec3 forest = texture(forest_d, uv * 1.3).rgb * vec3(0.75, 0.85, 0.6);
	vec3 sand = texture(sand_d, uv).rgb;
	vec3 urban = texture(urban_d, uv * 1.6).rgb;
	vec3 rock = tri(rock_d, wpos, wnorm, tile * 0.5);
	float slope = 1.0 - wnorm.y;
	float rockiness = smoothstep(0.18, 0.38, slope) + smoothstep(90.0, 160.0, wpos.y) * 0.6;
	vec3 c = mix(grass, forest, COLOR.r);
	c = mix(c, sand, COLOR.g);
	c = mix(c, urban, COLOR.b);
	c = mix(c, rock, clamp(rockiness, 0.0, 1.0));
	float snow = smoothstep(snow_line, snow_line + 40.0, wpos.y) * smoothstep(0.55, 0.25, slope);
	c = mix(c, vec3(0.9, 0.92, 0.95), snow);
	ALBEDO = c * 0.85;
	vec3 n = mix(texture(grass_n, uv).rgb, texture(rock_n, wpos.xz * tile * 0.5).rgb, clamp(rockiness, 0.0, 1.0));
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.95, 0.4, snow);
}
