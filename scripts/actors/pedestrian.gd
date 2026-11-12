class_name Pedestrian
extends Fighter
## City people walking the sidewalks. They flinch, fight back if you push
## your luck, or run off. Free rigged Quaternius characters (CC0).

var waypoints: Array[Vector3] = []
var _goal := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _scared := 0.0
var _angry: Fighter


func _ready() -> void:
	_rng.randomize()
	model_path = Humanoid.random_npc(_rng)
	model_height = 1.68 if model_path.contains("civ_f") else 1.78
	max_health = 45.0
	super._ready()
	add_to_group(&"civilians")
	run_speed = 1.4
	sprint_speed = 5.5
	_pick_goal()


func _pick_goal() -> void:
	if waypoints.is_empty():
		_goal = global_position + Vector3(_rng.randf_range(-20, 20), 0, _rng.randf_range(-20, 20))
	else:
		_goal = waypoints[_rng.randi() % waypoints.size()]


func _wants_move() -> Vector3:
	if _angry and is_instance_valid(_angry) and _angry.alive:
		var d := _angry.global_position - global_position
		d.y = 0.0
		return d.normalized() if d.length() > 1.6 else Vector3.ZERO
	var to := _goal - global_position
	to.y = 0.0
	if to.length() < 2.0:
		_pick_goal()
	return to.normalized() * (1.0 if _scared > 0.0 else 0.45)


func _wants_sprint() -> bool:
	return _scared > 0.0


func _face_target() -> Fighter:
	return _angry


func _physics_process(delta: float) -> void:
	_scared = maxf(_scared - delta, 0.0)
	super._physics_process(delta)
	if _angry and _rng.randf() < 0.03 and _angry.global_position.distance_to(global_position) < 1.9:
		punch()


func receive_hit(damage: float, push: Vector3, attacker: Fighter, heavy: bool) -> void:
	super.receive_hit(damage, push, attacker, heavy)
	if alive and attacker:
		if _rng.randf() < 0.3:
			_angry = attacker
		else:
			_scared = 8.0
			var away := global_position - attacker.global_position
			_goal = global_position + away.normalized() * 40.0


func _ko(attacker: Fighter) -> void:
	super._ko(attacker)
	var t := get_tree().create_timer(8.0)
	t.timeout.connect(queue_free)
