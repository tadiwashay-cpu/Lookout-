class_name Grenade
extends RigidBody3D
## Thrown from a car: bounces once or twice, then blows (1.8 s fuse).

signal blew(pos: Vector3)

var _fuse := 1.8


func _ready() -> void:
	mass = 1.0
	collision_layer = 0
	collision_mask = Game.L_WORLD | Game.L_CARS
	contact_monitor = true
	max_contacts_reported = 1
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.mesh = Mats.prop("stick_grenade")["mesh"]
	mesh.scale = Vector3.ONE * 2.5
	add_child(mesh)
	body_entered.connect(func(b: Node) -> void:
		if b is Car:
			_fuse = minf(_fuse, 0.05))


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0:
		Fx.explosion(get_parent(), global_position, false)
		blew.emit(global_position)
		queue_free()
