class_name Pedestrian
extends CharacterBody3D
## Civilian NPC (low-poly man). Wanders, panics and runs from crimes and
## gunfire, and calls it in: hurting one raises your heat.

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const CIVILIAN_LAYER := 16
const VEHICLE_LAYER := 32

const SKIN := [Color(0.42, 0.26, 0.17), Color(0.62, 0.45, 0.33), Color(0.28, 0.17, 0.11), Color(0.75, 0.58, 0.46)]
const CLOTHES := [Color(0.2, 0.22, 0.26), Color(0.35, 0.18, 0.14), Color(0.55, 0.52, 0.45), Color(0.15, 0.25, 0.2), Color(0.45, 0.4, 0.32), Color(0.12, 0.12, 0.13)]

var health: HealthComponent
var rig: CharacterRig
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _goal := Vector3.ZERO
var _panic := 0.0
var _flee_from := Vector3.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _action_lock := 0.0


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"civilians")
	collision_layer = CIVILIAN_LAYER
	collision_mask = WORLD_LAYER | PLAYER_LAYER | VEHICLE_LAYER
	health = HealthComponent.new()
	health.max_health = 40.0
	add_child(health)
	health.died.connect(_on_died)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)
	rig = CharacterRig.new()
	rig.armed = false
	add_child(rig)
	if _rng.randf() < 0.8:
		# Quaternius city people (their own outfits, no tint needed).
		var id := GameSettings.random_civilian(_rng)
		rig.setup(id, _rng.randf_range(1.62, 1.74) if id.begins_with("civ_f") else _rng.randf_range(1.72, 1.88))
	else:
		rig.setup("npc", _rng.randf_range(1.65, 1.9))
		rig.tint([SKIN[_rng.randi() % SKIN.size()], CLOTHES[_rng.randi() % CLOTHES.size()]])
	_new_goal()
	WantedSystem.crime_reported.connect(_on_crime)


func is_alive() -> bool:
	return not health.is_dead


func _new_goal() -> void:
	var angle := _rng.randf() * TAU
	_goal = global_position + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(10.0, 30.0)


func _on_crime(_severity: float, at: Vector3) -> void:
	if not health.is_dead and at.distance_to(global_position) < 45.0:
		_panic = _rng.randf_range(6.0, 10.0)
		_flee_from = at


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if health.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	var move := Vector3.ZERO
	var speed := 1.5   # matches the walk clip's stride (1.51 m/s)
	if _panic > 0.0:
		_panic -= delta
		move = (global_position - _flee_from)
		move.y = 0.0
		move = move.normalized()
		speed = 4.8
	elif _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0 and _action_lock <= 0.0 and rig.has_clip(&"walk_start"):
			rig.replay(&"walk_start", 1.2, 0.15)   # step off from standing
			_action_lock = 0.5
	else:
		move = _goal - global_position
		move.y = 0.0
		if move.length() < 1.5:
			_wait = _rng.randf_range(1.5, 5.0)
			_new_goal()
			move = Vector3.ZERO
			if rig.has_clip(&"walk_stop"):
				rig.replay(&"walk_stop", 1.2, 0.15)   # plant the feet, then idle
				_action_lock = 0.55
		else:
			move = move.normalized()
	move = _avoid(move)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(move * speed, 8.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	if move.length() > 0.1:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-move.x, -move.z), clampf(6.0 * delta, 0.0, 1.0))
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	_action_lock = maxf(_action_lock - delta, 0.0)
	if _action_lock <= 0.0:
		rig.play_locomotion(0.0, flat.length())


func _avoid(move: Vector3) -> Vector3:
	if move.length() < 0.1:
		return move
	var from := global_position + Vector3.UP * 0.6
	var query := PhysicsRayQueryParameters3D.create(from, from + move * 2.0, WORLD_LAYER | VEHICLE_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return move
	_new_goal()
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	return (move + normal * 1.5).normalized()


func take_hit(damage: float, knockback: Vector3, attacker: Node3D, _heavy: bool = false) -> void:
	if health.is_dead:
		return
	health.take_damage(damage, attacker)
	velocity += knockback
	_panic = 10.0
	_flee_from = attacker.global_position if attacker else global_position
	if attacker is PlayerController or attacker is DrivableCar:
		WantedSystem.report_crime(WantedSystem.CRIME_ASSAULT_CIVILIAN, global_position)
	if not health.is_dead:
		rig.replay(rig.hit_clip(), 1.6, 0.05)
		_action_lock = 0.6


func _on_died() -> void:
	remove_from_group(&"civilians")
	collision_layer = 0
	collision_mask = WORLD_LAYER
	rig.replay([&"death_back", &"death_front"][_rng.randi() % 2] if rig.has_clip(&"death_back") else &"death", 1.2, 0.1)
	await get_tree().create_timer(12.0).timeout
	if is_inside_tree():
		queue_free()
