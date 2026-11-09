class_name Effects
extends RefCounted
## Cheap, mobile-friendly combat effects (unshaded, short-lived, no particles).

static var _tracer_mat: StandardMaterial3D
static var _flash_mat: StandardMaterial3D
static var _spark_mat: StandardMaterial3D
static var _blast_mat: StandardMaterial3D
static var _surge_mat: StandardMaterial3D


static func _unshaded(color: Color, alpha: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _init_materials() -> void:
	if _tracer_mat:
		return
	_tracer_mat = _unshaded(Color(1.0, 0.85, 0.5, 0.75))
	_flash_mat = _unshaded(Color(1.0, 0.8, 0.4, 0.9))
	_spark_mat = _unshaded(Color(1.0, 0.75, 0.35, 1.0))
	_blast_mat = _unshaded(Color(1.0, 0.55, 0.2, 0.7))
	_surge_mat = _unshaded(Color(0.45, 0.75, 1.0, 0.55))


static func _spawn(tree: SceneTree, node: Node3D, pos: Vector3) -> void:
	var root := tree.current_scene
	if root == null:
		return
	root.add_child(node)
	node.global_position = pos


static func tracer(tree: SceneTree, from: Vector3, to: Vector3) -> void:
	_init_materials()
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, length)
	var line := MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = _tracer_mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(tree, line, (from + to) * 0.5)
	var up := Vector3.UP if absf((to - from).normalized().dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	line.look_at(to, up)
	tree.create_timer(0.05).timeout.connect(line.queue_free)


static func muzzle_flash(tree: SceneTree, pos: Vector3) -> void:
	_init_materials()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 6
	mesh.rings = 3
	var flash := MeshInstance3D.new()
	flash.mesh = mesh
	flash.material_override = _flash_mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(tree, flash, pos)
	tree.create_timer(0.04).timeout.connect(flash.queue_free)


static func impact(tree: SceneTree, pos: Vector3) -> void:
	_init_materials()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var spark := MeshInstance3D.new()
	spark.mesh = mesh
	spark.material_override = _spark_mat
	_spawn(tree, spark, pos)
	var tween := spark.create_tween()
	tween.tween_property(spark, "scale", Vector3.ONE * 0.1, 0.15)
	tween.tween_callback(spark.queue_free)


static func explosion(tree: SceneTree, pos: Vector3, radius: float) -> void:
	_ring(tree, pos, radius, _blast_mat_get(), 0.35)


static func surge(tree: SceneTree, pos: Vector3, radius: float) -> void:
	_init_materials()
	_ring(tree, pos, radius, _surge_mat, 0.3)


static func _blast_mat_get() -> StandardMaterial3D:
	_init_materials()
	return _blast_mat


static func _ring(tree: SceneTree, pos: Vector3, radius: float, material: Material, time: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var ball := MeshInstance3D.new()
	ball.mesh = mesh
	ball.material_override = material
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.3
	_spawn(tree, ball, pos)
	var tween := ball.create_tween()
	tween.tween_property(ball, "scale", Vector3.ONE * radius, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ball, "scale", Vector3.ONE * radius * 1.05, 0.1)
	tween.tween_callback(ball.queue_free)
