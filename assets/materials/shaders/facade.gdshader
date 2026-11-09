// Procedural building facade: wall colour + a grid of windows per floor,
// computed from world position so merged (batched) buildings get windows
// without textures or extra geometry. Cheap enough for mobile.
shader_type spatial;

uniform vec4 wall_color : source_color = vec4(0.45, 0.25, 0.18, 1.0);
uniform vec4 window_color : source_color = vec4(0.06, 0.07, 0.08, 1.0);
uniform vec4 trim_color : source_color = vec4(0.55, 0.52, 0.47, 1.0);
uniform float floor_height = 3.2;
uniform float window_spacing = 2.4;
uniform vec2 window_size = vec2(0.5, 0.58);   // fraction of bay width / floor height
uniform float ground_floor = 4.0;              // shopfront band height
uniform float window_metal = 0.0;              // >0 for glass towers
uniform float lit_chance = 0.12;               // windows with a warm light on

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec3 col = wall_color.rgb;
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	// Grime gets darker toward the street.
	col *= mix(0.78, 1.0, clamp(world_pos.y / 12.0, 0.0, 1.0));
	if (n.y < 0.5) {
		float u = n.x > n.z ? world_pos.z : world_pos.x;
		float y = world_pos.y;
		if (y < ground_floor) {
			// Shopfront: dark glass band with a trim line above.
			float band = step(0.6, y) * step(y, ground_floor - 0.6);
			col = mix(col, window_color.rgb * 1.3, band * 0.85);
			col = mix(col, trim_color.rgb, step(ground_floor - 0.35, y));
		} else {
			float fy = (y - ground_floor) / floor_height;
			vec2 cell = vec2(u / window_spacing, fy);
			vec2 f = fract(cell);
			vec2 half_size = window_size * 0.5;
			float win = step(abs(f.x - 0.5), half_size.x) * step(abs(f.y - 0.45), half_size.y);
			float lit = step(1.0 - lit_chance, hash(floor(cell)));
			vec3 glass = mix(window_color.rgb, vec3(0.95, 0.75, 0.45), lit * 0.8);
			col = mix(col, glass, win);
			rough = mix(rough, 0.15, win);
			metal = mix(metal, window_metal, win);
			emit = vec3(0.9, 0.62, 0.32) * lit * win * 0.35;
			// Sills / floor lines.
			float sill = step(abs(f.y - 0.12), 0.03) * step(abs(f.x - 0.5), half_size.x + 0.05);
			col = mix(col, trim_color.rgb, sill * 0.7);
		}
	} else {
		col = col * 0.55;   // roofs: tar and gravel
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
