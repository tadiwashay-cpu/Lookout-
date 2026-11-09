class_name Goon
extends CharacterBody3D
## Street thug from the Low Tide crew. Melee only.
## Brawler rules that keep fights readable on a phone screen:
##  * only MAX_ACTIVE_ATTACKERS goons may swing at once; the rest circle you
##  * every attack has a visible wind-up (body flashes) so you can dodge
##  * light hits stagger, finishers knock down

signal defeated(goon: Goon)

enum State { IDLE, CHASE, WINDUP, RECOVER, STAGGER, KNOCKDOWN, DEAD }

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const VEHICLE_LAYER := 32
const MAX_ACTIVE_ATTACKERS := 2

static var _active_attackers: int = 0

@export var max_health: float = 45.0
@export var move_speed: float = 3.8
@export var aggro_range: float = 16.0
@export var attack_range: float = 1.5
@export var attack_damage: float = 9.0
@export var windup_time: float = 0.55
@export var recover_time: float = 0.7
@export var attack_cooldown: float = 1.4
@export var circle_distance: float = 3.2
@export var wander_radius: float = 5.0

var health: HealthComponent
## True when the final blow came from a car (doesn't count for Clean Hands).
var defeated_by_vehicle := false

var _state: State = State.IDLE
var _state_time := 0.0
var _cooldown := 0.0
var _has_token := false
var _player: PlayerController
var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _strafe_sign := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _body_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"enemies")
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	floor_max_angle = deg_to_rad(60.0)
	_rng.randomize()
	_home = global_position
	_wander_target = _home
	_strafe_sign = 1.0 if _rng.randf() > 0.5 else -1.0

	health = HealthComponent.new()
	health.max_health = max_health
	add_child(health)
	health.died.connect(_on_died)

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_build_placeholder_body()


func _exit_tree() -> void:
	_release_token()


func is_alive() -> bool:
	return _state != State.DEAD


func _physics_process(delta: float) -> void:
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as PlayerController

	match _state:
		State.IDLE:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.RECOVER, State.STAGGER:
			_brake(delta, 10.0)
			var limit := recover_time if _state == State.RECOVER else 0.4
			if _state_time >= limit:
				_set_state(State.CHASE)
		State.KNOCKDOWN:
			_brake(delta, 6.0)
			if _state_time >= 1.3:
				create_tween().tween_property(_model, "rotation:x", 0.0, 0.25)
				_set_state(State.CHASE)
		State.DEAD:
			_brake(delta, 6.0)

	move_and_slide()


# ---------------------------------------------------------------------- states

func _tick_idle(delta: float) -> void:
	if _player_in_range(aggro_range):
		_set_state(State.CHASE)
		return
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.6 or _state_time > 6.0:
		var angle := _rng.randf() * TAU
		_wander_target = _home + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(1.0, wander_radius)
		_state_time = 0.0
	_steer(to_target.normalized(), move_speed * 0.35, delta)
	_face(to_target, delta)


func _tick_chase(delta: float) -> void:
	if not _player_in_range(aggro_range * 1.6):
		_release_token()
		_set_state(State.IDLE)
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player / maxf(dist, 0.001)
	_face(to_player, delta)

	if dist <= attack_range and _cooldown <= 0.0 and _try_take_token():
		_set_state(State.WINDUP)
		return

	if _has_token or _active_attackers < MAX_ACTIVE_ATTACKERS:
		_steer(dir if dist > attack_range * 0.8 else Vector3.ZERO, move_speed, delta)
	else:
		# Wait your turn: hold a ring around the player and strafe.
		var strafe := dir.cross(Vector3.UP) * _strafe_sign
		var radial := dir * clampf(dist - circle_distance, -1.0, 1.0)
		_steer((radial + strafe * 0.6).normalized(), move_speed * 0.55, delta)


func _tick_windup(delta: float) -> void:
	_brake(delta, 12.0)
	if _player:
		_face(_player.global_position - global_position, delta)
	var pulse := 0.5 + 0.5 * sin(_state_time * 30.0)
	_body_material.emission = Color(0.9, 0.25, 0.1) * pulse
	if _state_time < windup_time:
		return
	_body_material.emission = Color.BLACK
	if _player and _player.is_targetable():
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		var forward := -_model.global_basis.z
		if to_player.length() <= attack_range + 0.4 and forward.dot(to_player.normalized()) > 0.4:
			_player.take_hit(attack_damage, to_player.normalized() * 4.0, self, false)
	_cooldown = attack_cooldown + _rng.randf_range(0.0, 0.6)
	_set_state(State.RECOVER)


# ---------------------------------------------------------------------- damage

func take_hit(damage: float, knockback: Vector3, attacker: Node3D, heavy: bool = false) -> void:
	if _state == State.DEAD:
		return
	_release_token()
	_body_material.emission = Color.BLACK
	defeated_by_vehicle = attacker is DrivableCar
	health.take_damage(damage, attacker)
	velocity.x = knockback.x
	velocity.z = knockback.z
	if heavy:
		velocity.y = 3.0
	_flash_hit()
	WantedSystem.report_crime(WantedSystem.CRIME_VIGILANTE, global_position, WantedSystem.CRIME_VIGILANTE_CAP)
	if health.is_dead:
		return
	if heavy:
		_set_state(State.KNOCKDOWN)
		create_tween().tween_property(_model, "rotation:x", -PI * 0.45, 0.2)
	else:
		_set_state(State.STAGGER)


func _on_died() -> void:
	_set_state(State.DEAD)
	_release_token()
	remove_from_group(&"enemies")
	collision_layer = 0
	collision_mask = WORLD_LAYER
	create_tween().tween_property(_model, "rotation:x", -PI * 0.5, 0.35) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	defeated.emit(self)
	await get_tree().create_timer(8.0).timeout
	queue_free()


# --------------------------------------------------------------------- helpers

func _set_state(new_state: State) -> void:
	_state = new_state
	_state_time = 0.0


func _player_in_range(range_m: float) -> bool:
	if _player == null or not _player.is_targetable():
		return false
	return global_position.distance_to(_player.global_position) <= range_m


func _try_take_token() -> bool:
	if _has_token:
		return true
	if _active_attackers >= MAX_ACTIVE_ATTACKERS:
		return false
	_active_attackers += 1
	_has_token = true
	return true


func _release_token() -> void:
	if _has_token:
		_has_token = false
		_active_attackers = maxi(_active_attackers - 1, 0)


func _steer(desired: Vector3, speed: float, delta: float) -> void:
	var separation := Vector3.ZERO
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node == self:
			continue
		var offset := global_position - (node as Node3D).global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > 0.01 and dist < 1.4:
			separation += offset / dist * (1.4 - dist)
	var wish := desired + separation * 1.5
	if wish.length() > 1.0:
		wish = wish.normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * speed, 14.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _brake(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func _face(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.05:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(10.0 * delta, 0.0, 1.0))


func _flash_hit() -> void:
	_body_material.emission_energy_multiplier = 1.0
	_body_material.emission = Color(1.0, 1.0, 1.0) * 0.6
	var tween := create_tween()
	tween.tween_property(_body_material, "emission", Color.BLACK, 0.12)


func _build_placeholder_body() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	var jackets := [Color(0.16, 0.18, 0.14), Color(0.13, 0.13, 0.14), Color(0.27, 0.12, 0.1), Color(0.12, 0.15, 0.22)]
	var skins := [Color(0.42, 0.26, 0.17), Color(0.62, 0.45, 0.33), Color(0.28, 0.17, 0.11), Color(0.75, 0.58, 0.46)]

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = jackets[_rng.randi() % jackets.size()]
	_body_material.roughness = 0.85
	_body_material.emission_enabled = true
	_body_material.emission = Color.BLACK
	var jeans := StandardMaterial3D.new()
	jeans.albedo_color = Color(0.2, 0.24, 0.3)
	jeans.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = skins[_rng.randi() % skins.size()]
	skin.roughness = 0.7
	var bandana := StandardMaterial3D.new()
	bandana.albedo_color = Color(0.55, 0.12, 0.08)   # Low Tide crew colour
	bandana.roughness = 0.8

	_add_box(Vector3(0.5, 0.6, 0.3), Vector3(0, 1.28, 0), _body_material)
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(0.17, 0.85, 0.2), Vector3(0.12 * side, 0.45, 0), jeans)
		_add_box(Vector3(0.14, 0.55, 0.14), Vector3(0.34 * side, 1.25, 0), _body_material)
		_add_box(Vector3(0.12, 0.12, 0.12), Vector3(0.34 * side, 0.95, 0), skin)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.34
	head.mesh = head_mesh
	head.material_override = skin
	head.position = Vector3(0, 1.76, 0)
	_model.add_child(head)
	_add_box(Vector3(0.34, 0.08, 0.34), Vector3(0, 1.64, 0), bandana)


func _add_box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	_model.add_child(instance)
	return instance
