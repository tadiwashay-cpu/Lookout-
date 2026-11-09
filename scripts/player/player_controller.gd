class_name PlayerController
extends CharacterBody3D
## The hero. Third-person or first-person camera (player's choice, saved),
## camera-relative movement, dodge, and a fist combo system with auto-aim,
## hit-stop and screen shake so melee feels weighty on a touchscreen.
##
## Drop a rigged .glb into `model_scene` to replace the placeholder body.
## If the model has an AnimationPlayer, clips named idle / walk / run /
## punch_1 / punch_2 / punch_3 / punch_heavy / dodge / hit / knocked_out
## are played automatically.

signal attack_landed(target: Node3D, damage: float, combo_step: int)
signal knocked_out
signal respawned
signal vehicle_changed(vehicle: DrivableCar)
signal nearby_vehicle_changed(vehicle: DrivableCar)

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const VEHICLE_LAYER := 32
const LOOK_SCALE := 0.0045
const INTERACT_RANGE := 3.4

@export_group("Movement")
@export var run_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var acceleration: float = 22.0
@export var air_control: float = 0.35
@export var jump_velocity: float = 5.4
@export var turn_speed: float = 12.0

@export_group("Dodge")
@export var dodge_speed: float = 12.0
@export var dodge_time: float = 0.26
@export var dodge_cooldown: float = 0.55

@export_group("Camera")
@export var third_person_distance: float = 3.6
@export var shoulder_offset: float = 0.55
@export var eye_height: float = 1.62
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 55.0
@export var mouse_sensitivity: float = 0.0025
@export var stick_look_speed: float = 3.2
@export var camera_fov: float = 72.0

@export_group("Combat")
@export var max_health: float = 150.0
@export var light_damage: Array[float] = [10.0, 11.0, 20.0]
@export var heavy_damage: float = 28.0
@export var punch_reach: float = 1.0
@export var punch_radius: float = 0.8
@export var input_buffer_time: float = 0.25
@export var combo_reset_time: float = 0.45
@export var auto_aim_range: float = 3.2
@export var respawn_delay: float = 3.0

@export_group("Visuals")
## Rigged character model (.glb). Leave empty to use the placeholder.
@export var model_scene: PackedScene
## Imported glTF characters usually face +Z; Godot's forward is -Z.
@export var model_yaw_offset_deg: float = 180.0
## The model is scaled so its height matches this (metres), feet on the ground.
@export var model_height: float = 1.85

var health: HealthComponent
var current_vehicle: DrivableCar
var nearby_vehicle: DrivableCar
var _left_vehicle_frame := -1

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_point: Vector3
var _yaw: float = 0.0
var _pitch: float = -0.2
var _model_yaw: float = 0.0
var _camera_mode: int = 0
var _shake: float = 0.0

var _pivot: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _model: Node3D
var _anim_player: AnimationPlayer
var _fist_l: Node3D
var _fist_r: Node3D
var _fist_rest_l := Vector3.ZERO
var _fist_rest_r := Vector3.ZERO

var _attacking := false
var _attack_elapsed := 0.0
var _attack_active_at := 0.0
var _attack_duration := 0.0
var _attack_damage := 0.0
var _attack_heavy := false
var _attack_hit_done := false
var _combo_step := 0
var _combo_window := 0.0
var _buffered_attack: StringName = &""
var _buffer_timer := 0.0

var _dodge_timer := 0.0
var _dodge_cooldown_timer := 0.0
var _dodge_dir := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = PLAYER_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60.0)
	_spawn_point = global_position
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_model_yaw = _yaw

	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = max_health
	add_child(health)
	health.died.connect(_on_died)

	_build_collision()
	_build_model()
	_build_camera()

	_camera_mode = GameSettings.camera_mode
	GameSettings.camera_mode_changed.connect(_apply_camera_mode)
	_apply_camera_mode(_camera_mode, true)


# ---------------------------------------------------------------- input / look

func _exit_tree() -> void:
	# A hit-stop interrupted by a scene change must not leave the game in slow motion.
	Engine.time_scale = 1.0


func is_alive() -> bool:
	return not health.is_dead


## Goons ignore a player who is inside a car.
func is_targetable() -> bool:
	return is_alive() and current_vehicle == null


## Called by TouchControls (drag on the right half of the screen).
func add_look_input(delta_px: Vector2) -> void:
	if current_vehicle:
		current_vehicle.add_look_input(delta_px)
		return
	var s := LOOK_SCALE * GameSettings.look_sensitivity
	_rotate_view(-delta_px.x * s, -delta_px.y * s)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if current_vehicle:
			current_vehicle.add_look_input(motion.relative)
		else:
			_rotate_view(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _rotate_view(yaw_delta: float, pitch_delta: float) -> void:
	_yaw = wrapf(_yaw + yaw_delta, -PI, PI)
	_pitch = clampf(_pitch + pitch_delta, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		_rotate_view(-stick.x * stick_look_speed * delta, -stick.y * stick_look_speed * delta)

	_pivot.position = Vector3(0.0, eye_height, 0.0)
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)

	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.6, 0.0)
		var amount := _shake * _shake
		_camera.h_offset = randf_range(-1.0, 1.0) * amount
		_camera.v_offset = randf_range(-1.0, 1.0) * amount
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


# ------------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if health.is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return

	_tick_timers(delta)

	if Input.is_action_just_pressed(&"toggle_camera"):
		GameSettings.toggle_camera_mode()

	_update_nearby_vehicle()
	if Input.is_action_just_pressed(&"interact") and nearby_vehicle and not _attacking \
			and Engine.get_physics_frames() != _left_vehicle_frame:
		nearby_vehicle.enter(self)
		return

	var input_vec := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_dir := Basis(Vector3.UP, _yaw) * Vector3(input_vec.x, 0.0, input_vec.y)

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if _dodge_timer > 0.0:
		velocity.x = _dodge_dir.x * dodge_speed
		velocity.z = _dodge_dir.z * dodge_speed
	else:
		var target_speed := run_speed * input_vec.length()
		if Input.is_action_pressed(&"sprint") and input_vec.length() > 0.1:
			target_speed = sprint_speed
		if _attacking:
			target_speed *= 0.2
		var target_velocity := Vector3.ZERO
		if move_dir.length() > 0.01:
			target_velocity = move_dir.normalized() * target_speed
		var accel := acceleration if is_on_floor() else acceleration * air_control
		var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_velocity, accel * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	if Input.is_action_just_pressed(&"jump") and is_on_floor() and not _attacking:
		velocity.y = jump_velocity

	if Input.is_action_just_pressed(&"dodge"):
		_try_dodge(move_dir)

	_read_attack_input()
	_update_attack(delta)
	move_and_slide()
	_update_model(move_dir, delta)

	if global_position.y < -40.0:
		_respawn()


func _tick_timers(delta: float) -> void:
	_dodge_timer = maxf(_dodge_timer - delta, 0.0)
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	if _buffer_timer <= 0.0:
		_buffered_attack = &""


func _try_dodge(move_dir: Vector3) -> void:
	if _dodge_cooldown_timer > 0.0 or not is_on_floor():
		return
	_attacking = false
	_dodge_dir = move_dir.normalized() if move_dir.length() > 0.1 else Basis(Vector3.UP, _model_yaw) * Vector3.BACK
	_dodge_timer = dodge_time
	_dodge_cooldown_timer = dodge_cooldown
	_play_anim(&"dodge")


func _update_model(move_dir: Vector3, delta: float) -> void:
	if _camera_mode == GameSettings.FIRST_PERSON:
		_model_yaw = _yaw
	elif move_dir.length() > 0.1 and not _attacking and _dodge_timer <= 0.0:
		var target_yaw := atan2(-move_dir.x, -move_dir.z)
		_model_yaw = lerp_angle(_model_yaw, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	_model.rotation.y = _model_yaw

	if _attacking or _dodge_timer > 0.0:
		return
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if speed > run_speed + 0.5:
		_play_anim(&"run")
	elif speed > 0.3:
		_play_anim(&"walk")
	else:
		_play_anim(&"idle")


# --------------------------------------------------------------------- combat

func _read_attack_input() -> void:
	if Input.is_action_just_pressed(&"punch_light"):
		_buffered_attack = &"light"
		_buffer_timer = input_buffer_time
	elif Input.is_action_just_pressed(&"punch_heavy"):
		_buffered_attack = &"heavy"
		_buffer_timer = input_buffer_time

	if _buffered_attack != &"" and not _attacking and _dodge_timer <= 0.0:
		_start_attack(_buffered_attack == &"heavy")
		_buffered_attack = &""
		_buffer_timer = 0.0


func _start_attack(heavy: bool) -> void:
	_attacking = true
	_attack_elapsed = 0.0
	_attack_hit_done = false
	_attack_heavy = heavy
	if heavy:
		_combo_step = 0
		_attack_damage = heavy_damage
		_attack_active_at = 0.28
		_attack_duration = 0.62
	else:
		if _combo_window <= 0.0:
			_combo_step = 0
		_combo_step = (_combo_step % light_damage.size()) + 1
		_attack_damage = light_damage[_combo_step - 1]
		_attack_active_at = 0.12
		_attack_duration = 0.34 if _combo_step < light_damage.size() else 0.5
	_face_nearest_enemy()
	_animate_punch()


func _update_attack(delta: float) -> void:
	if not _attacking:
		_combo_window = maxf(_combo_window - delta, 0.0)
		return
	_attack_elapsed += delta
	if not _attack_hit_done and _attack_elapsed >= _attack_active_at:
		_attack_hit_done = true
		_perform_hit()
	if _attack_elapsed >= _attack_duration:
		_attacking = false
		_combo_window = combo_reset_time


func _is_finisher() -> bool:
	return _attack_heavy or _combo_step == light_damage.size()


func _perform_hit() -> void:
	var forward := Basis(Vector3.UP, _model_yaw) * Vector3.FORWARD
	var shape := SphereShape3D.new()
	shape.radius = punch_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position + Vector3.UP * 1.1 + forward * punch_reach)
	params.collision_mask = ENEMY_LAYER
	params.exclude = [get_rid()]

	var landed := false
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 8):
		var target = hit.get("collider")
		if target == null or not target.has_method(&"take_hit"):
			continue
		var knockback := forward * (7.0 if _is_finisher() else 2.5)
		target.take_hit(_attack_damage, knockback, self, _is_finisher())
		# Heavy punches count as finishers too (reported as the final combo step).
		attack_landed.emit(target, _attack_damage, light_damage.size() if _is_finisher() else _combo_step)
		landed = true

	if landed:
		_hit_stop(0.08 if _is_finisher() else 0.045)
		_shake = 0.55 if _is_finisher() else 0.3
		GameSettings.vibrate(35 if _is_finisher() else 15)


func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _face_nearest_enemy() -> void:
	var facing := Basis(Vector3.UP, _model_yaw) * Vector3.FORWARD
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Node3D
		if enemy == null or (enemy.has_method(&"is_alive") and not enemy.call(&"is_alive")):
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > auto_aim_range or dist < 0.01:
			continue
		var alignment := facing.dot(offset / dist)
		if alignment < -0.2:
			continue
		var score := dist - alignment * 1.5
		if score < best_score:
			best_score = score
			best = enemy
	if best:
		var to_enemy := best.global_position - global_position
		_model_yaw = atan2(-to_enemy.x, -to_enemy.z)
		_model.rotation.y = _model_yaw


## Hits from goons, police, etc.
func take_hit(damage: float, knockback: Vector3, attacker: Node3D, heavy: bool = false) -> void:
	if health.is_dead or _dodge_timer > 0.0 or current_vehicle:
		return
	health.take_damage(damage, attacker)
	velocity += knockback
	_shake = 0.4
	GameSettings.vibrate(40)
	if heavy:
		_attacking = false
	_play_anim(&"hit")


func _on_died() -> void:
	if current_vehicle:
		current_vehicle.exit()
	_attacking = false
	_play_anim(&"knocked_out")
	if _anim_player == null:
		create_tween().tween_property(_model, "rotation:x", -PI * 0.5, 0.4)
	knocked_out.emit()
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
	_model.rotation.x = 0.0
	health.revive()
	WantedSystem.clear()
	respawned.emit()


# ------------------------------------------------------------------ vehicles

func _update_nearby_vehicle() -> void:
	var best: DrivableCar = null
	var best_dist := INTERACT_RANGE
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var car := node as DrivableCar
		if car == null or not car.can_enter():
			continue
		var dist := car.global_position.distance_to(global_position)
		if dist < best_dist:
			best_dist = dist
			best = car
	if best != nearby_vehicle:
		nearby_vehicle = best
		nearby_vehicle_changed.emit(nearby_vehicle)


## Called by DrivableCar.enter().
func start_driving(car: DrivableCar) -> void:
	current_vehicle = car
	nearby_vehicle = null
	nearby_vehicle_changed.emit(null)
	_attacking = false
	_dodge_timer = 0.0
	_combo_step = 0
	_combo_window = 0.0
	_buffered_attack = &""
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	set_process(false)
	vehicle_changed.emit(car)


## Called by DrivableCar.exit().
func stop_driving(exit_position: Vector3, facing_yaw: float) -> void:
	current_vehicle = null
	_left_vehicle_frame = Engine.get_physics_frames()
	global_position = exit_position
	velocity = Vector3.ZERO
	visible = true
	collision_layer = PLAYER_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	_yaw = facing_yaw
	_model_yaw = facing_yaw
	set_physics_process(true)
	set_process(true)
	_camera.make_current()
	vehicle_changed.emit(null)


# --------------------------------------------------------------------- camera

func _apply_camera_mode(mode: int, instant: bool = false) -> void:
	_camera_mode = mode
	var first_person := mode == GameSettings.FIRST_PERSON
	var target_length := 0.0 if first_person else third_person_distance
	var target_offset := 0.0 if first_person else shoulder_offset
	_set_model_shadow_only(_model, first_person)
	if instant:
		_spring.spring_length = target_length
		_spring.position.x = target_offset
		return
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_spring, "spring_length", target_length, 0.25)
	tween.tween_property(_spring, "position:x", target_offset, 0.25)


func _set_model_shadow_only(node: Node, shadow_only: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	for child in node.get_children():
		_set_model_shadow_only(child, shadow_only)


# -------------------------------------------------------------- scene building

func _build_collision() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.85
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.925
	add_child(shape)


func _build_camera() -> void:
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	add_child(_pivot)

	_spring = SpringArm3D.new()
	_spring.name = "SpringArm"
	_spring.collision_mask = WORLD_LAYER | VEHICLE_LAYER
	_spring.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_spring.shape = probe
	_spring.add_excluded_object(get_rid())
	_pivot.add_child(_spring)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = camera_fov
	_camera.near = 0.05
	_camera.far = 800.0
	_spring.add_child(_camera)
	_camera.make_current()


func _build_model() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	if model_scene:
		var holder := Node3D.new()
		holder.rotation.y = deg_to_rad(model_yaw_offset_deg)
		_model.add_child(holder)
		var instance := model_scene.instantiate() as Node3D
		holder.add_child(instance)
		_fit_model_height(instance)
		var players := holder.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_anim_player = players[0] as AnimationPlayer
		return
	_build_placeholder_body()


## Scales an imported model to `model_height` and puts its feet at y = 0,
## whatever units the source file used.
func _fit_model_height(instance: Node3D) -> void:
	var bounds := _collect_bounds(instance, Transform3D.IDENTITY)
	if bounds.size.y <= 0.001:
		return
	var s := model_height / bounds.size.y
	instance.scale *= s
	instance.position = Vector3(-bounds.get_center().x * s, -bounds.position.y * s, -bounds.get_center().z * s)


## Bounds of every mesh under `node`, in the space of node's parent.
func _collect_bounds(node: Node, parent_xform: Transform3D) -> AABB:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	var result := AABB()
	var has_result := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		result = xform * (node as MeshInstance3D).mesh.get_aabb()
		has_result = true
	for child in node.get_children():
		var child_bounds := _collect_bounds(child, xform)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = child_bounds if not has_result else result.merge(child_bounds)
		has_result = true
	return result


## Blocky stand-in matching the concept: chrome armour, dark undersuit,
## flared boots, pointed shoulder plates.
func _build_placeholder_body() -> void:
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.8, 0.81, 0.84)
	chrome.metallic = 1.0
	chrome.roughness = 0.16
	var undersuit := StandardMaterial3D.new()
	undersuit.albedo_color = Color(0.07, 0.07, 0.08)
	undersuit.metallic = 0.5
	undersuit.roughness = 0.45
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.4, 0.24, 0.16)
	skin.roughness = 0.65
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color(0.1, 0.07, 0.05)
	hair.roughness = 0.9

	_add_box(Vector3(0.5, 0.55, 0.3), Vector3(0, 1.3, 0), chrome)              # chest
	_add_box(Vector3(0.36, 0.22, 0.26), Vector3(0, 0.95, 0), chrome)           # pelvis
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(0.15, 0.42, 0.17), Vector3(0.12 * side, 0.68, 0), undersuit)   # thigh
		_add_box(Vector3(0.26, 0.48, 0.32), Vector3(0.13 * side, 0.24, -0.02), chrome)  # flared boot
		var pad := _add_box(Vector3(0.24, 0.12, 0.26), Vector3(0.36 * side, 1.58, 0), chrome)
		pad.rotation.z = deg_to_rad(-25.0 * side)                                       # shoulder plate
		_add_box(Vector3(0.12, 0.36, 0.12), Vector3(0.37 * side, 1.3, 0), undersuit)    # upper arm

	_fist_l = _add_box(Vector3(0.17, 0.17, 0.34), Vector3(-0.37, 1.02, -0.06), chrome)
	_fist_r = _add_box(Vector3(0.17, 0.17, 0.34), Vector3(0.37, 1.02, -0.06), chrome)
	_fist_rest_l = _fist_l.position
	_fist_rest_r = _fist_r.position

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.36
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0, 1.8, 0)
	_model.add_child(head)

	var hair_cap := MeshInstance3D.new()
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.18
	hair_mesh.height = 0.2
	hair_mesh.is_hemisphere = true
	hair_cap.mesh = hair_mesh
	hair_cap.material_override = hair
	hair_cap.position = Vector3(0, 1.86, 0.01)
	_model.add_child(hair_cap)


func _add_box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	_model.add_child(instance)
	return instance


# ------------------------------------------------------------------ animation

func _play_anim(anim_name: StringName) -> bool:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return false
	if _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name, 0.12)
	return true


func _animate_punch() -> void:
	var clip := &"punch_heavy" if _attack_heavy else StringName("punch_%d" % _combo_step)
	if _play_anim(clip):
		return
	if _fist_l == null:
		# Imported model without animations yet: a quick body lunge so punches still read.
		var lunge := Vector3(0.0, 0.0, -0.35 if _attack_heavy else -0.2).rotated(Vector3.UP, _model_yaw)
		var body_tween := create_tween()
		body_tween.tween_property(_model, "position", lunge, _attack_active_at)
		body_tween.tween_property(_model, "position", Vector3.ZERO, maxf(_attack_duration - _attack_active_at, 0.05))
		return
	var use_right := _attack_heavy or _combo_step % 2 == 1
	var fist := _fist_r if use_right else _fist_l
	var rest := _fist_rest_r if use_right else _fist_rest_l
	var reach := Vector3(0.0, 0.12, -0.8 if _attack_heavy else -0.65)
	var tween := create_tween()
	tween.tween_property(fist, "position", rest + reach, _attack_active_at) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(fist, "position", rest, maxf(_attack_duration - _attack_active_at, 0.05))
