shader_type spatial;
// Car lamps when front and rear share one material: the glow colour comes
// from which end of the car the pixel is on (model space: front is -Z,
// the car pack faces -Z). White heads, red tails. `glow` 0 = off (day).
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float glow = 0.0;
uniform float split_z = 0.0;
varying float side;

void vertex() {
	side = VERTEX.z - split_z;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * albedo.rgb;
	ALBEDO = base;
	ROUGHNESS = 0.2;
	vec3 lamp = side > 0.0 ? vec3(1.0, 0.08, 0.04) : vec3(1.0, 0.95, 0.85);
	EMISSION = lamp * glow * (0.35 + 0.65 * dot(base, vec3(0.33)));
}
