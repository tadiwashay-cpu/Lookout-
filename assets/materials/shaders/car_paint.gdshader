// Repaints a car without touching its trim.
// The pack bakes paint into the albedo texture, so we treat saturated
// pixels as "paint" and recolour them, keeping their shading; chrome,
// rubber, grilles and lights (low saturation) keep their original colour.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;   // untextured models (procedural supercars) = plain paint
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_orm = false;
uniform vec4 paint_color : source_color = vec4(1.0);
uniform float repaint = 1.0;          // 0 = factory colour, 1 = full repaint
uniform float paint_roughness = 0.28; // clear-coat look

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float hi = max(base.r, max(base.g, base.b));
	float lo = min(base.r, min(base.g, base.b));
	float saturation = (hi - lo) / max(hi, 0.0001);
	float mask = smoothstep(0.22, 0.5, saturation) * repaint;
	vec3 painted = paint_color.rgb * clamp(hi * 1.35, 0.0, 1.3);
	ALBEDO = mix(base, painted, mask);

	float rough = 0.55;
	float metal = 0.0;
	if (has_orm) {
		vec4 orm = texture(orm_tex, UV);
		rough = orm.g;
		metal = orm.b;
	}
	ROUGHNESS = mix(rough, paint_roughness, mask);
	METALLIC = mix(metal, 0.35, mask);
}
