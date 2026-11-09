class_name PlayerController
extends CharacterBody3D
## The player: X Bot or Y Bot (chosen in the menu).
##  * third- or first-person camera (saved setting), aim zoom
##  * armed (rifle): character faces the camera and strafes; tap FIRE,
##    RELOAD, GRENADE, SURGE (power-surge blast)
##  * unarmed (fists): punch combos — used when weapons are locked
##    (e.g. the Clean Hands mission)
##  * cars: walk up and tap ENTER (E / F on a keyboard)
## Health, damage and deaths are reported over the network in multiplayer.

signal attack_landed(target: Node3D, damage: float, combo_step: int)
signal knocked_out
signal respawned
signal vehicle_changed(vehicle: DrivableCar)
signal nearby_vehicle_changed(vehicle: DrivableCar)
signal ammo_changed(in_mag: int, reserve: int)
signal loadout_changed

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const VEHICLE_LAYER := 32
const LOOK_SCALE := 0.0045
const INTERACT_RANGE := 3.4

@export_group("Movement")
@export var run_speed: float = 4.3
@export var sprint_speed: float = 6.2
@export var aim_speed: float = 2.3
@export var acceleration: float = 20.0
@export var air_control: float = 0.35
@export var jump_velocity: float = 5.2
@export var turn_speed: float = 12.0

@export_group("Camera")
@export var third_person_distance: float = 3.4
@export var aim_distance: float = 1.7
@export var shoulder_offset: float = 0.6
@export var eye_height: float = 1.6
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 55.0
@export var mouse_sensitivity: float = 0.0025
@export var stick_look_speed: float = 3.2
@export var camera_fov: float = 72.0
@export var aim_fov: float = 52.0

@export_group("Rifle")
@export var rifle_damage: float = 20.0
@export var fire_rate: float = 9.0
@export var mag_size: int = 30
@export var start_reserve: int = 180
@export var reload_time: float = 2.2
@export var rifle_range: float = 160.0
@export var spread_deg: float = 1.6
@export var aim_spread_deg: float = 0.4

@export_group("Abilities")
@export var grenade_count: int = 3
@export var grenade_cooldown: float = 4.0
@export var surge_cooldown: float = 12.0
@export var surge_radius: float = 6.0
@export var surge_damage: float = 35.0

@export_group("Fists")
@export var light_damage: Array[float] = [10.0, 11.0, 20.0]
@export var heavy_damage: float = 28.0
@export var punch_reach: float = 1.0
@export var punch_radius: float = 0.8

@export_group("Health")
@export var max_health: float = 150.0
@export var respawn_delay: float = 3.0

var health: HealthComponent
var rig: CharacterRig
var current_vehicle: DrivableCar
var nearby_vehicle: DrivableCar

## Missions/modes switch these.
var weapons_allowed := true:
	set(value):
		weapons_allowed = value
		_refresh_armed()
var respawn_enabled := true
var spawn_point := Vector3.ZERO
## Multiplayer: the peer that last hurt us (for kill credit).
var last_attacker_peer := 0

var ammo := 0
var reserve := 0
var grenades := 0
var aiming := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw := 0.0
var _pitch := -0.2
var _model_yaw := 0.0
var _camera_mode := 0
var _shake := 0.0
var _pivot: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _model: Node3D

var _wants_armed := true
var _fire_cooldown := 0.0
var _reload_timer := 0.0
var _grenade_timer := 0.0
var _surge_timer := 0.0
var _throw_timer := 0.0
var _action_lock := 0.0
var _heat_timer := 0.0
var _left_vehicle_frame := -1
var _net_timer := 0.0

var _attacking := false
var _attack_elapsed := 0.0
var _attack_active_at := 0.0
var _attack_duration := 0.0
var _attack_damage := 0.0
var _attack_heavy := false
var _attack_hit_done := false
var _combo_step := 0
var _combo_window := 0.0


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = PLAYER_LAYER
	collision_mask = WORLD_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60.0)
	spawn_point = global_position
	_yaw = rotation.y
	rotation = Vector3.ZERO
	_model_yaw = _yaw

	health = HealthComponent.new()
	health.name = "Health"
	health.max_health = max_health
	add_child(health)
	health.died.connect(_on_died)

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	rig = CharacterRig.new()
	rig.name = "Rig"
	_model.add_child(rig)
	rig.setup(GameSettings.character)

	_build_camera()
	ammo = mag_size
	reserve = start_reserve
	grenades = grenade_count
	_camera_mode = GameSettings.camera_mode
	GameSettings.camera_mode_changed.connect(_apply_camera_mode)
	_apply_camera_mode(_camera_mode, true)
	_refresh_armed()

	Net.damage_received.connect(_on_net_damage)
	Net.slow_received.connect(_on_net_slow)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ state

func is_alive() -> bool:
	return not health.is_dead


func is_targetable() -> bool:
	return is_alive() and current_vehicle == null


func is_armed() -> bool:
	return weapons_allowed and _wants_armed


func grenade_ready() -> float:
	return 1.0 - clampf(_grenade_timer / grenade_cooldown, 0.0, 1.0)


func surge_ready() -> float:
	return 1.0 - clampf(_surge_timer / surge_cooldown, 0.0, 1.0)


func is_reloading() -> bool:
	return _reload_timer > 0.0


func camera() -> Camera3D:
	return _camera


func view_yaw() -> float:
	return _yaw


func _refresh_armed() -> void:
	if rig:
		rig.armed = is_armed()
	if not is_armed():
		aiming = false
	loadout_changed.emit()
	ammo_changed.emit(ammo, reserve)


# ------------------------------------------------------------------ look

func add_look_input(delta_px: Vector2) -> void:
	if current_vehicle:
		current_vehicle.add_look_input(delta_px)
		return
	var s := LOOK_SCALE * GameSettings.look_sensitivity * (0.6 if aiming else 1.0)
	var invert := -1.0 if GameSettings.invert_look_y else 1.0
	_rotate_view(-delta_px.x * s, -delta_px.y * s * invert)


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


func _rotate_view(yaw_delta: float, pitch_delta: float) -> void:
	_yaw = wrapf(_yaw + yaw_delta, -PI, PI)
	_pitch = clampf(_pitch + pitch_delta, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	var stick := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if stick != Vector2.ZERO:
		_rotate_view(-stick.x * stick_look_speed * delta, -stick.y * stick_look_speed * delta)
	_pivot.position = Vector3(0.0, eye_height, 0.0)
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)

	var first_person := _camera_mode == GameSettings.FIRST_PERSON
	var target_fov := aim_fov if aiming else camera_fov
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(delta * 10.0, 0.0, 1.0))
	if not first_person:
		var target_len := aim_distance if aiming else third_person_distance
		_spring.spring_length = lerpf(_spring.spring_length, target_len, clampf(delta * 10.0, 0.0, 1.0))

	if _shake > 0.0:
		_shake = maxf(_shake - delta * 1.6, 0.0)
		var amount := _shake * _shake
		_camera.h_offset = randf_range(-1.0, 1.0) * amount
		_camera.v_offset = randf_range(-1.0, 1.0) * amount
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


# --------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	_send_network_state(delta)
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
	if Input.is_action_just_pressed(&"swap_weapon") and weapons_allowed:
		_wants_armed = not _wants_armed
		_reload_timer = 0.0
		_refresh_armed()

	_update_nearby_vehicle()
	if Input.is_action_just_pressed(&"interact") and nearby_vehicle and not _attacking \
			and Engine.get_physics_frames() != _left_vehicle_frame:
		nearby_vehicle.enter(self)
		return

	if is_armed():
		if Input.is_action_just_pressed(&"aim"):
			aiming = not aiming
		if Input.is_action_pressed(&"fire"):
			_try_fire()
		if Input.is_action_just_pressed(&"reload"):
			_start_reload()
		if Input.is_action_just_pressed(&"grenade"):
			_try_throw_grenade()
	else:
		_read_punch_input()
	if Input.is_action_just_pressed(&"surge"):
		_try_surge()

	var input_vec := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var move_dir := Basis(Vector3.UP, _yaw) * Vector3(input_vec.x, 0.0, input_vec.y)
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var target_speed := run_speed * input_vec.length()
	if Input.is_action_pressed(&"sprint") and input_vec.length() > 0.1 and not aiming:
		target_speed = sprint_speed
	if aiming:
		target_speed = minf(target_speed, aim_speed)
	if _attacking or _throw_timer > 0.0:
		target_speed *= 0.3
	var target_velocity := move_dir.normalized() * target_speed if move_dir.length() > 0.01 else Vector3.ZERO
	var accel := acceleration if is_on_floor() else acceleration * air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_velocity, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if Input.is_action_just_pressed(&"jump") and is_on_floor() and not _attacking:
		velocity.y = jump_velocity
		rig.play(&"jump", 1.0, 0.08)
		_action_lock = 0.45

	_update_punch(delta)
	move_and_slide()
	_update_facing_and_anim(move_dir, delta)
	if global_position.y < -40.0:
		_respawn()


func _tick_timers(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_grenade_timer = maxf(_grenade_timer - delta, 0.0)
	_surge_timer = maxf(_surge_timer - delta, 0.0)
	_action_lock = maxf(_action_lock - delta, 0.0)
	_heat_timer = maxf(_heat_timer - delta, 0.0)
	if _throw_timer > 0.0:
		_throw_timer -= delta
	if _reload_timer > 0.0:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			var take := mini(mag_size - ammo, reserve)
			ammo += take
			reserve -= take
			ammo_changed.emit(ammo, reserve)


func _update_facing_and_anim(move_dir: Vector3, delta: float) -> void:
	# Armed or first person: face where the camera looks (strafe).
	# Fists: face the way you move.
	if is_armed() or _camera_mode == GameSettings.FIRST_PERSON:
		_model_yaw = lerp_angle(_model_yaw, _yaw, clampf(turn_speed * 1.5 * delta, 0.0, 1.0))
	elif move_dir.length() > 0.1 and not _attacking:
		_model_yaw = lerp_angle(_model_yaw, atan2(-move_dir.x, -move_dir.z), clampf(turn_speed * delta, 0.0, 1.0))
	_model.rotation.y = _model_yaw

	if _action_lock > 0.0 or _attacking or _throw_timer > 0.0:
		return
	if _reload_timer > 0.0:
		rig.play(&"reload", 3.3 / reload_time, 0.1)
		return
	var facing := Basis(Vector3.UP, _model_yaw)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var local_forward := flat.dot(facing * Vector3.FORWARD)
	var local_right := flat.dot(facing * Vector3.RIGHT)
	if flat.length() < 0.3 and _fire_cooldown > 0.0:
		return   # standing and shooting: let the fire clip play
	rig.play_locomotion(local_right, local_forward)


# ------------------------------------------------------------------ rifle

func _try_fire() -> void:
	if _reload_timer > 0.0 or _fire_cooldown > 0.0 or _throw_timer > 0.0:
		return
	if ammo <= 0:
		_start_reload()
		return
	ammo -= 1
	_fire_cooldown = 1.0 / fire_rate
	ammo_changed.emit(ammo, reserve)

	var cam := _camera.global_transform
	var direction := -cam.basis.z
	var origin := cam.origin + direction * maxf((global_position - cam.origin).dot(direction), 0.0)
	direction = _aim_assist(origin, direction)
	var spread := deg_to_rad(aim_spread_deg if aiming else spread_deg)
	direction = direction.rotated(cam.basis.x, randf_range(-spread, spread)).rotated(cam.basis.y, randf_range(-spread, spread))

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * rifle_range)
	query.collision_mask = WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := origin + direction * rifle_range
	if not hit.is_empty():
		end = hit["position"]
		var target = hit["collider"]
		if target and target.has_method(&"take_hit"):
			target.take_hit(rifle_damage, direction * 1.5, self, false)
			GameSettings.vibrate(8)
		elif target is RigidBody3D:
			(target as RigidBody3D).apply_impulse(direction * 3.0, end - (target as Node3D).global_position)
		Effects.impact(get_tree(), end)
	var muzzle := rig.muzzle_position()
	Effects.muzzle_flash(get_tree(), muzzle)
	Effects.tracer(get_tree(), muzzle, end)
	if Vector3(velocity.x, 0.0, velocity.z).length() < 0.3:
		rig.replay(&"fire")
	_shake = maxf(_shake, 0.12)
	_pitch = clampf(_pitch + deg_to_rad(0.35), deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))   # recoil
	if Session.mode == Session.MODE_STORY and _heat_timer <= 0.0:
		WantedSystem.report_crime(WantedSystem.CRIME_GUNFIRE * 0.4, global_position, 3)
		_heat_timer = 2.0
	if Session.networked:
		Net.send_event("shot", {"a": muzzle, "b": end})


## Touch-friendly: nudge shots onto a target within a few degrees of the crosshair.
func _aim_assist(origin: Vector3, direction: Vector3) -> Vector3:
	var best_dir := direction
	var best_angle := deg_to_rad(3.5 if aiming else 5.0)
	var candidates: Array = get_tree().get_nodes_in_group(&"enemies") + get_tree().get_nodes_in_group(&"remote_players")
	for node in candidates:
		var target := node as Node3D
		if target == null or (target.has_method(&"is_alive") and not target.call(&"is_alive")):
			continue
		var to_target := target.global_position + Vector3.UP * 1.2 - origin
		if to_target.length() > rifle_range:
			continue
		var angle := direction.angle_to(to_target)
		if angle < best_angle:
			best_angle = angle
			best_dir = to_target.normalized()
	return best_dir


func _start_reload() -> void:
	if _reload_timer > 0.0 or ammo >= mag_size or reserve <= 0:
		return
	_reload_timer = reload_time


func add_ammo(amount: int) -> void:
	reserve += amount
	ammo_changed.emit(ammo, reserve)


# -------------------------------------------------------------- grenades

func _try_throw_grenade() -> void:
	if grenades <= 0 or _grenade_timer > 0.0 or _throw_timer > 0.0:
		return
	grenades -= 1
	_grenade_timer = grenade_cooldown
	_throw_timer = 0.8
	rig.play(&"throw_grenade", 2.2, 0.08)
	loadout_changed.emit()
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree() or health.is_dead:
		return
	var cam_basis := _camera.global_basis
	var velocity_out := (-cam_basis.z + Vector3.UP * 0.35).normalized() * 16.0 + velocity * 0.5
	throw_grenade_from(global_position + Vector3.UP * 1.6 - cam_basis.z * 0.6, velocity_out)


## Also used while driving (Street Race).
func throw_grenade_from(origin: Vector3, launch_velocity: Vector3) -> void:
	var grenade := Grenade.new()
	grenade.thrower = self
	get_tree().current_scene.add_child(grenade)
	grenade.global_position = origin
	grenade.linear_velocity = launch_velocity
	if Session.networked:
		Net.send_event("grenade", {"pos": origin, "vel": launch_velocity})


func use_vehicle_grenade() -> bool:
	if grenades <= 0 or _grenade_timer > 0.0 or current_vehicle == null:
		return false
	grenades -= 1
	_grenade_timer = grenade_cooldown
	loadout_changed.emit()
	var car := current_vehicle
	var back := -car.global_basis.z   # car body drives +Z: lob it behind at the chasers
	throw_grenade_from(car.global_position + Vector3.UP * 1.6 + back * 2.5, back * 9.0 + Vector3.UP * 5.0 + car.linear_velocity * 0.6)
	return true


func refill_grenades(count: int) -> void:
	grenades = maxi(grenades, count)
	loadout_changed.emit()


# ----------------------------------------------------------------- surge

func _try_surge() -> void:
	if _surge_timer > 0.0:
		return
	_surge_timer = surge_cooldown
	Effects.surge(get_tree(), global_position + Vector3.UP, surge_radius)
	_shake = 0.5
	GameSettings.vibrate(60)
	var sphere := SphereShape3D.new()
	sphere.radius = surge_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), global_position + Vector3.UP)
	params.collision_mask = PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	params.exclude = [get_rid()]
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 24):
		var target = hit.get("collider")
		if target == null or target == self:
			continue
		var offset: Vector3 = (target as Node3D).global_position - global_position
		var push := (Vector3(offset.x, 0.0, offset.z).normalized() + Vector3.UP * 0.4) * 9.0
		if target is DrivableCar:
			(target as DrivableCar).apply_central_impulse(push * (target as DrivableCar).mass * 0.3)
		elif target.has_method(&"take_hit"):
			target.take_hit(surge_damage, push, self, true)
	if Session.networked:
		Net.send_event("surge", {"pos": global_position + Vector3.UP, "r": surge_radius})


# ------------------------------------------------------------------ fists

func _read_punch_input() -> void:
	if _attacking:
		return
	if Input.is_action_just_pressed(&"punch_light"):
		_start_punch(false)
	elif Input.is_action_just_pressed(&"punch_heavy"):
		_start_punch(true)


func _start_punch(heavy: bool) -> void:
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
	var clip := &"punch_heavy" if heavy else StringName("punch_%d" % _combo_step)
	if not rig.play(clip, 1.0, 0.05):
		# No punch clips yet: a body lunge so hits still read.
		var lunge := Vector3(0.0, 0.0, -0.35 if heavy else -0.2).rotated(Vector3.UP, _model_yaw)
		var tween := create_tween()
		tween.tween_property(_model, "position", lunge, _attack_active_at)
		tween.tween_property(_model, "position", Vector3.ZERO, maxf(_attack_duration - _attack_active_at, 0.05))


func _update_punch(delta: float) -> void:
	if not _attacking:
		_combo_window = maxf(_combo_window - delta, 0.0)
		return
	_attack_elapsed += delta
	if not _attack_hit_done and _attack_elapsed >= _attack_active_at:
		_attack_hit_done = true
		_perform_punch()
	if _attack_elapsed >= _attack_duration:
		_attacking = false
		_combo_window = 0.45


func _is_finisher() -> bool:
	return _attack_heavy or _combo_step == light_damage.size()


func _perform_punch() -> void:
	var forward := Basis(Vector3.UP, _model_yaw) * Vector3.FORWARD
	var shape := SphereShape3D.new()
	shape.radius = punch_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), global_position + Vector3.UP * 1.1 + forward * punch_reach)
	params.collision_mask = PLAYER_LAYER | ENEMY_LAYER
	params.exclude = [get_rid()]
	var landed := false
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(params, 8):
		var target = hit.get("collider")
		if target == null or target == self or not target.has_method(&"take_hit"):
			continue
		target.take_hit(_attack_damage, forward * (7.0 if _is_finisher() else 2.5), self, _is_finisher())
		attack_landed.emit(target, _attack_damage, light_damage.size() if _is_finisher() else _combo_step)
		landed = true
	if landed:
		_hit_stop(0.08 if _is_finisher() else 0.045)
		_shake = 0.55 if _is_finisher() else 0.3
		GameSettings.vibrate(35 if _is_finisher() else 15)


func _hit_stop(duration: float) -> void:
	if Session.networked:
		return   # never slow time in multiplayer
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _face_nearest_enemy() -> void:
	var facing := Basis(Vector3.UP, _model_yaw) * Vector3.FORWARD
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(&"enemies") + get_tree().get_nodes_in_group(&"remote_players"):
		var enemy := node as Node3D
		if enemy == null or (enemy.has_method(&"is_alive") and not enemy.call(&"is_alive")):
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > 3.2 or dist < 0.01:
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


# ----------------------------------------------------------------- damage

func take_hit(damage: float, knockback: Vector3, attacker: Node3D, heavy: bool = false) -> void:
	if health.is_dead or current_vehicle:
		return
	health.take_damage(damage, attacker)
	velocity += knockback
	_shake = 0.4
	GameSettings.vibrate(40)
	if heavy:
		_attacking = false
	if not _attacking and _action_lock <= 0.0:
		rig.play(&"hit", 1.0, 0.05)
		_action_lock = 0.3


func _on_net_damage(amount: float, from_peer: int, knockback: Vector3) -> void:
	last_attacker_peer = from_peer
	if current_vehicle:
		current_vehicle.take_vehicle_damage(amount)
		return
	take_hit(amount, knockback, null, amount > 40.0)


func _on_net_slow(seconds: float) -> void:
	if current_vehicle:
		current_vehicle.apply_slow(seconds)


func _on_died() -> void:
	if current_vehicle:
		current_vehicle.exit()
	_attacking = false
	aiming = false
	create_tween().tween_property(_model, "rotation:x", -PI * 0.5, 0.4)
	knocked_out.emit()
	if Session.mode != Session.MODE_STORY:
		# Works offline too (solo practice): Net emits locally when not connected.
		Net.announce_eliminated(Session.my_id(), last_attacker_peer)
	if not respawn_enabled:
		return
	await get_tree().create_timer(respawn_delay).timeout
	if is_inside_tree():
		_respawn()


func _respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	_model.rotation.x = 0.0
	health.revive()
	ammo = mag_size
	reserve = maxi(reserve, start_reserve / 2)
	grenades = maxi(grenades, 1)
	ammo_changed.emit(ammo, reserve)
	loadout_changed.emit()
	if Session.mode == Session.MODE_STORY:
		WantedSystem.clear()
	respawned.emit()


func respawn_at(point: Vector3) -> void:
	spawn_point = point
	_respawn()


# --------------------------------------------------------------- vehicles

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


func start_driving(car: DrivableCar) -> void:
	current_vehicle = car
	nearby_vehicle = null
	nearby_vehicle_changed.emit(null)
	_attacking = false
	aiming = false
	_reload_timer = 0.0
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	set_process(false)
	vehicle_changed.emit(car)


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


## Cars call this every physics frame while we drive, so other players still see us.
func send_state_from_vehicle(delta: float) -> void:
	_send_network_state(delta)


# ----------------------------------------------------------------- network

func _send_network_state(delta: float) -> void:
	if not Session.networked:
		return
	_net_timer -= delta
	if _net_timer > 0.0:
		return
	_net_timer = 1.0 / 15.0
	var state := {
		"p": global_position, "y": _model_yaw, "c": rig.current_clip(),
		"s": rig.anim.speed_scale if rig.anim else 1.0, "a": is_armed(), "h": health.current,
		"ch": GameSettings.character, "alive": is_alive(),
	}
	if current_vehicle:
		state["v"] = current_vehicle.vehicle_id
		state["vp"] = current_vehicle.global_position
		state["vq"] = current_vehicle.global_basis.get_rotation_quaternion()
		state["vc"] = current_vehicle.paint
	Net.send_state(state)


# ----------------------------------------------------------------- camera

func _apply_camera_mode(mode: int, instant: bool = false) -> void:
	_camera_mode = mode
	var first_person := mode == GameSettings.FIRST_PERSON
	var target_length := 0.0 if first_person else third_person_distance
	var target_offset := 0.0 if first_person else shoulder_offset
	_set_shadow_only(_model, first_person)
	if instant:
		_spring.spring_length = target_length
		_spring.position.x = target_offset
		return
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_spring, "spring_length", target_length, 0.25)
	tween.tween_property(_spring, "position:x", target_offset, 0.25)


func _set_shadow_only(node: Node, shadow_only: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	for child in node.get_children():
		_set_shadow_only(child, shadow_only)


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
	_camera.far = maxf(GameSettings.view_distance * 1.6, 300.0)
	_spring.add_child(_camera)
	_camera.make_current()
