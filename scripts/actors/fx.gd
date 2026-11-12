class_name Fx
extends RefCounted
## One-shot visual effects: hit sparks, surge shockwaves, explosions, smoke.
## Every effect frees itself.

static var _spark_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D


static func _materials() -> void:
	if _spark_mat:
		return
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat = _spark_mat.duplicate()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL


static func _burst(parent: Node, pos: Vector3, amount: int, color: Color, speed: float, size: float, life: float, gravity: float, mat: Material) -> CPUParticles3D:
	if parent == null:
		return null
	_materials()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3.DOWN * gravity
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.2
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func sparks(parent: Node, pos: Vector3, color: Color) -> void:
	_materials()
	_burst(parent, pos, 14, color, 6.0, 0.6, 0.35, 9.0, _spark_mat)


static func shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	if parent == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 24
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.5, 0.8, 1.0, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.4, 0.75, 1.0)
	m.emission_energy_multiplier = 4.0
	ring.material_override = m
	parent.add_child(ring)
	ring.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.light_energy = 6.0
	light.omni_range = radius * 2.0
	ring.add_child(light)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, radius * 0.4, radius), 0.45).from(Vector3.ONE * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	_materials()
	_burst(parent, pos, 30, Color(0.6, 0.85, 1.0), 12.0, 0.9, 0.5, 0.0, _spark_mat)
	CameraRig.shake_at(pos, 0.9)


static func explosion(parent: Node, pos: Vector3, big: bool = true) -> void:
	if parent == null:
		return
	_materials()
	_burst(parent, pos, 40 if big else 18, Color(1.0, 0.55, 0.15), 14.0 if big else 8.0, 3.0 if big else 1.6, 0.7, -2.0, _spark_mat)
	_burst(parent, pos + Vector3.UP, 26, Color(0.12, 0.11, 0.1, 0.85), 5.0, 6.0 if big else 3.0, 2.4, -1.5, _smoke_mat)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 12.0 if big else 6.0
	light.omni_range = 30.0 if big else 14.0
	parent.add_child(light)
	light.global_position = pos + Vector3.UP * 1.5
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.9)
	tw.tween_callback(light.queue_free)
	Sfx.play("explosion", pos, 6.0 if big else 0.0)
	CameraRig.shake_at(pos, 1.2 if big else 0.6)


## A smoke plume that follows `parent_node` (damaged engines).
static func plume(parent_node: Node3D, offset: Vector3, fire: bool) -> CPUParticles3D:
	_materials()
	var p := CPUParticles3D.new()
	p.amount = 18 if fire else 14
	p.lifetime = 0.8 if fire else 1.8
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3.UP * 1.5
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.4
	quad.material = _spark_mat if fire else _smoke_mat
	p.mesh = quad
	var ramp := Gradient.new()
	var c := Color(1.0, 0.5, 0.1) if fire else Color(0.2, 0.2, 0.2, 0.7)
	ramp.set_color(0, c)
	ramp.set_color(1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = ramp
	p.position = offset
	parent_node.add_child(p)
	return p
