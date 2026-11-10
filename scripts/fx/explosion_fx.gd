class_name ExplosionFX
extends Node3D
## Explosions built from one-shot GPU particles (cheap on the Mobile renderer):
## light flash, fireball, rising smoke, sparks, flying debris chunks and the
## shockwave ring, plus camera shake by distance. `energy` = the blue power
## surge version (no smoke/debris). Everything frees itself after a few seconds.

static var _soft: GradientTexture2D
static var _mats: Dictionary = {}


static func spawn(tree: SceneTree, pos: Vector3, radius: float, energy: bool = false) -> void:
	var root := tree.current_scene
	if root == null:
		return
	var fx := ExplosionFX.new()
	root.add_child(fx)
	fx.global_position = pos
	fx._build(radius, energy)
	for node in tree.get_nodes_in_group(&"player"):
		var player := node as PlayerController
		if player:
			var near := clampf(1.0 - player.global_position.distance_to(pos) / (radius * 6.0), 0.0, 1.0)
			if near > 0.0:
				player.add_shake(near * (0.9 if energy else 1.2))


static func _soft_texture() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func _billboard(key: String, additive: bool) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m


func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / float(colors.size() - 1))
	g.offsets = offsets
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _emitter(count: int, life: float, size: float, mat: Material, process: ParticleProcessMaterial, mesh: Mesh = null) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.process_material = process
	if mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		quad.material = mat
		mesh = quad
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 50, 60))
	add_child(p)
	p.emitting = true
	return p


func _build(radius: float, energy: bool) -> void:
	var r := maxf(radius, 1.0)
	# Flash
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.75, 1.0) if energy else Color(1.0, 0.6, 0.25)
	light.light_energy = 9.0
	light.omni_range = r * 4.0
	light.position.y = 1.0
	add_child(light)
	var fade := create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	# Fireball (or energy burst)
	var fire := ParticleProcessMaterial.new()
	fire.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = r * 0.25
	fire.direction = Vector3.UP
	fire.spread = 180.0
	fire.initial_velocity_min = r * 0.8
	fire.initial_velocity_max = r * 2.0
	fire.gravity = Vector3(0, 2.0, 0)
	fire.damping_min = r * 1.5
	fire.damping_max = r * 2.5
	fire.scale_curve = _curve([Vector2(0, 0.4), Vector2(0.25, 1.0), Vector2(1, 1.3)])
	fire.color_ramp = _ramp([Color(0.7, 0.9, 1.0, 1.0), Color(0.3, 0.6, 1.0, 0.8), Color(0.1, 0.2, 0.6, 0.0)] if energy
		else [Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.55, 0.12, 0.9), Color(0.6, 0.15, 0.03, 0.5), Color(0.1, 0.08, 0.07, 0.0)])
	_emitter(26, 0.9, r * 0.9, _billboard("fire", true), fire)
	# Sparks
	var sparks := ParticleProcessMaterial.new()
	sparks.direction = Vector3.UP
	sparks.spread = 75.0
	sparks.initial_velocity_min = r * 3.0
	sparks.initial_velocity_max = r * 6.0
	sparks.gravity = Vector3(0, -14.0, 0)
	sparks.color_ramp = _ramp([Color(1, 1, 1, 1), Color(0.6, 0.85, 1.0, 1) if energy else Color(1.0, 0.7, 0.3, 1), Color(1, 0.4, 0.1, 0)])
	_emitter(40, 1.1, 0.12, _billboard("spark", true), sparks)
	# Shockwave ring
	Effects.ring(get_tree(), global_position + Vector3.UP * 0.3, r * 1.3, energy)
	if energy:
		_finish(1.6)
		return
	# Smoke
	var smoke := ParticleProcessMaterial.new()
	smoke.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = r * 0.4
	smoke.direction = Vector3.UP
	smoke.spread = 40.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 3.5
	smoke.gravity = Vector3(0, 0.8, 0)
	smoke.damping_min = 0.5
	smoke.damping_max = 1.0
	smoke.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.4)])
	smoke.color_ramp = _ramp([Color(0.2, 0.18, 0.16, 0.0), Color(0.16, 0.15, 0.14, 0.75), Color(0.25, 0.25, 0.25, 0.0)])
	var smoke_p := _emitter(14, 3.2, r * 1.1, _billboard("smoke", false), smoke)
	smoke_p.explosiveness = 0.7
	# Debris chunks
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.18, 0.12, 0.22)
	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.albedo_color = Color(0.08, 0.07, 0.065)
	chunk.material = chunk_mat
	var debris := ParticleProcessMaterial.new()
	debris.direction = Vector3.UP
	debris.spread = 60.0
	debris.initial_velocity_min = r * 2.0
	debris.initial_velocity_max = r * 4.0
	debris.gravity = Vector3(0, -16.0, 0)
	debris.angular_velocity_min = -540.0
	debris.angular_velocity_max = 540.0
	debris.particle_flag_rotate_y = true
	_emitter(10, 1.6, 0.0, null, debris, chunk)
	_finish(3.6)


func _finish(after: float) -> void:
	await get_tree().create_timer(after).timeout
	queue_free()
