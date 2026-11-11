shader_type spatial;
render_mode cull_disabled;
// The modelled city: vertex colours. Walls that came in black get a paint
// colour per block, and windows light up at night.

uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Flat normals from the surface itself: parts of the model came without
	// usable normals and rendered black.
	vec3 n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	if (n.z < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	vec3 c = COLOR.rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float wall = step(abs(world_normal.y), 0.5) * step(0.8, world_pos.y);
	float dark = 1.0 - smoothstep(0.05, 0.25, lum);
	// Paint for black walls: one colour per city block.
	float pick = hash(vec3(floor(world_pos.x / 44.0), 0.0, floor(world_pos.z / 44.0)));
	vec3 paint = vec3(0.55, 0.22, 0.16);                                  // brick
	paint = mix(paint, vec3(0.74, 0.66, 0.5), step(0.2, pick));            // sandstone
	paint = mix(paint, vec3(0.2, 0.42, 0.46), step(0.4, pick));            // teal
	paint = mix(paint, vec3(0.42, 0.45, 0.52), step(0.6, pick));           // slate
	paint = mix(paint, vec3(0.8, 0.76, 0.68), step(0.8, pick));            // cream
	c = mix(c, c * 1.8 + paint * 0.45, dark * wall);   // keeps the hue, lifts it out of black
	ALBEDO = c;
	ROUGHNESS = 0.85;
	// Windows at night: blue glass, plus a grid of rooms on the painted walls.
	float glass = smoothstep(0.03, 0.14, COLOR.b - max(COLOR.r, COLOR.g));
	float room = hash(floor(world_pos * vec3(0.45, 0.33, 0.45)));
	vec3 in_cell = fract(world_pos * vec3(0.45, 0.33, 0.45));
	float pane = step(0.25, in_cell.y) * step(in_cell.y, 0.8);
	float lit = max(glass, dark * pane) * wall * step(2.5, world_pos.y) * step(0.55, room);
	EMISSION = lit * night * vec3(1.0, 0.8, 0.48) * 1.6;
}
