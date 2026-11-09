class_name Grenade
extends RigidBody3D
## Thrown grenade. Bounces, then explodes: damages anything with take_hit,
## shoves physics bodies, and slows cars (Street Race). Only the thrower's
## device applies damage; other devices spawn a visual-only copy.

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const VEHICLE_LAYER := 32

@export var fuse_time: float = 2.2
@export var radius: float = 7.0
@export var max_damage: float = 90.0

var thrower: Node3D
var visual_only := false
var _time := 0.0
var _exploded := false


func _ready() -> void:
	mass = 0.4
	collision_layer = 0
	collision_mask = WORLD_LAYER | VEHICLE_LAYER
	continuous_cd = true
	var sphere := SphereShape3D.new()
	sphere.radius = 0.07
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	add_child(shape)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var body := MeshInstance3D.new()
	body.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.22, 0.14)
	material.roughness = 0.6
	body.material_override = material
	add_child(body)
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.35
	bounce.friction = 0.8
	physics_material_override = bounce


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= fuse_time and not _exploded:
		_explode()


func _explode() -> void:
	_exploded = true
	Effects.explosion(get_tree(), global_position, radius)
	if not visual_only:
		_apply_blast()
	queue_free()


func _apply_blast() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position)
	params.collision_mask = PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	params.exclude = [get_rid()]
	var done := {}
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 32):
		var target = hit.get("collider")
		if target == null or done.has(target):
			continue
		done[target] = true
		var offset: Vector3 = (target as Node3D).global_position - global_position
		var falloff := clampf(1.0 - offset.length() / radius, 0.0, 1.0)
		var push := (offset.normalized() + Vector3.UP * 0.6).normalized() * 10.0 * falloff
		if target is DrivableCar:
			var car := target as DrivableCar
			if car.has_meta(&"remote_peer"):
				# Another player's car: tell their device.
				Net.send_slow(int(car.get_meta(&"remote_peer")), 2.5)
				Net.send_damage(int(car.get_meta(&"remote_peer")), max_damage * falloff * 0.5)
				continue
			car.apply_central_impulse(push * car.mass * 0.4)
			car.apply_slow(2.5)
		elif target.has_method(&"take_hit"):
			var damage := max_damage * falloff
			if target == thrower:
				damage *= 0.5
			target.take_hit(damage, push, thrower, true)
