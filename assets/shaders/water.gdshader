shader_type spatial;
render_mode cull_disabled;

uniform vec3 deep : source_color = vec3(0.02, 0.12, 0.18);
uniform vec3 shallow : source_color = vec3(0.08, 0.3, 0.35);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.6;
	VERTEX.y += sin(wpos.x * 0.05 + t) * 0.25 + sin(wpos.z * 0.07 + t * 1.3) * 0.2;
}

void fragment() {
	float t = TIME * 0.05;
	vec2 p = wpos.xz * 0.04;
	float w = sin(p.x * 7.0 + t * 20.0) * 0.5 + sin(p.y * 9.0 - t * 15.0) * 0.5;
	vec3 n = normalize(vec3(cos(p.x * 7.0 + t * 20.0) * 0.15, 1.0, cos(p.y * 9.0 - t * 15.0) * 0.15));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ALBEDO = mix(deep, shallow, 0.3 + w * 0.1);
	ROUGHNESS = 0.05;
	METALLIC = 0.3;
	SPECULAR = 0.8;
}
