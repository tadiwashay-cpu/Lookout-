class_name BotSoldier
extends CharacterBody3D
## Armed AI: cops on foot, battle-royale bots, heist police. Uses the
## low-poly NPC model (tinted per team) with the same clips and guns as
## players.
##   move: walk/run toward `objective` (zone centre, the player...)
##   fight: nearest visible enemy within sight range -> strafe + shoot
##          (reaction delay, accuracy drops with distance and movement)
## `team` decides friends: bots never shoot their own team.

signal died(bot: BotSoldier, killer: Node)

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const VEHICLE_LAYER := 32

var team := "bots"
var bot_id := -1
var display_name := "Bot"
var weapon_id := "m4a1"
var tint_colors: Array = [Color(0.6, 0.45, 0.35), Color(0.25, 0.27, 0.3)]
var objective := Vector3.ZERO
var has_objective := false
var sight_range := 70.0
var accuracy := 0.7               # 0..1
var damage_scale := 0.7           # bots hit softer than players
var max_health := 100.0
var melee_only := false           # cops at 1 star try to tackle, not shoot
var melee_damage := 12.0
var _swing_id := 0

var health: HealthComponent
var rig: CharacterRig
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _target: Node3D
var _think := 0.0
var _fire_cd := 0.0
var _reaction := 0.0
var _strafe := 1.0
var _strafe_timer := 0.0
var _weapon: Dictionary
var _ammo := 0
var _reload := 0.0
var _rng := RandomNumberGenerator.new()
var _last_attacker: Node
var _action_lock := 0.0


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"enemies")
	add_to_group(&"bots")
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER
	floor_max_angle = deg_to_rad(55.0)
	health = HealthComponent.new()
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
	rig = CharacterRig.new()
	add_child(rig)
	rig.armed = not melee_only
	rig.setup("npc")
	rig.tint(tint_colors)
	_weapon = WeaponCatalog.get_data(weapon_id)
	_ammo = int(_weapon["mag"])
	if not melee_only:
		rig.set_weapon(weapon_id)
	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.15, 0)
	label.font_size = 40
	label.outline_size = 8
	label.visibility_range_end = 45.0
	label.modulate = Color(0.6, 0.75, 1.0) if team == "police" else Color(1.0, 0.85, 0.75)
	add_child(label)


func is_alive() -> bool:
	return not health.is_dead


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if melee_only:
		rig.fight_ready = _target != null and is_instance_valid(_target) and global_position.distance_to(_target.global_position) < 8.0
	if health.is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		move_and_slide()
		return
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_action_lock = maxf(_action_lock - delta, 0.0)
	_think -= delta
	if _think <= 0.0:
		_think = 0.35 + _rng.randf() * 0.2
		_pick_target()
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_ammo = int(_weapon["mag"])

	var move := Vector3.ZERO
	var face := -rig.global_basis.z
	if _target and is_instance_valid(_target):
		var to_target := _target.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		face = to_target.normalized()
		var ideal := 2.0 if melee_only else 16.0
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(1.0, 2.5)
			_strafe = -_strafe if _rng.randf() < 0.6 else _strafe
		var side := Vector3(-face.z, 0.0, face.x) * _strafe
		if dist > ideal + 6.0:
			move = face
		elif dist < ideal - 4.0 and not melee_only:
			move = -face * 0.6 + side * 0.5
		else:
			move = side * (0.0 if melee_only else 0.8)
		_reaction -= delta
		if _reaction <= 0.0:
			if melee_only:
				if dist < 2.2 and _fire_cd <= 0.0:
					_melee()
			elif dist < sight_range:
				_shoot()
	elif has_objective:
		var to_obj := objective - global_position
		to_obj.y = 0.0
		if to_obj.length() > 6.0:
			move = to_obj.normalized()
			face = move
	move = _avoid(move)
	var speed := 4.2 if (_target == null or melee_only) else 2.6
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(move * speed, 14.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	if face.length() > 0.1:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-face.x, -face.z), clampf(8.0 * delta, 0.0, 1.0))
	var facing := Basis(Vector3.UP, rig.rotation.y)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if _action_lock > 0.0:
		pass   # let a one-shot (punch, flinch) finish
	elif _reload > 0.0:
		var reload := rig.reload_clip()
		rig.play(reload, rig.clip_length(reload) / float(_weapon["reload"]))
	elif flat.length() < 0.3 and _fire_cd > 0.0 and not melee_only:
		rig.play(rig.fire_clip())
	else:
		rig.play_locomotion(flat.dot(facing * Vector3.RIGHT), flat.dot(facing * Vector3.FORWARD))


func _pick_target() -> void:
	var best: Node3D = null
	var best_d := sight_range
	for node in get_tree().get_nodes_in_group(&"player") + get_tree().get_nodes_in_group(&"bots"):
		if node == self:
			continue
		var other := node as Node3D
		if other == null or not other.call(&"is_alive"):
			continue
		if other is BotSoldier and (other as BotSoldier).team == team:
			continue
		if other is PlayerController:
			var p := other as PlayerController
			if team == "police" and WantedSystem.stars == 0 and Session.mode == Session.MODE_STORY:
				continue
			if p.current_vehicle:
				continue   # the pursuit cars handle drivers
		var d := global_position.distance_to(other.global_position)
		if d < best_d and _can_see(other):
			best_d = d
			best = other
	if best != _target:
		_reaction = _rng.randf_range(0.35, 0.8)
	_target = best


func _can_see(other: Node3D) -> bool:
	var from := global_position + Vector3.UP * 1.5
	var to := other.global_position + Vector3.UP * 1.3
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER | VEHICLE_LAYER)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _shoot() -> void:
	if _fire_cd > 0.0 or _reload > 0.0:
		return
	if _ammo <= 0:
		_reload = float(_weapon["reload"])
		return
	_ammo -= 1
	_fire_cd = 1.0 / float(_weapon["rate"]) * _rng.randf_range(1.0, 1.6)
	var from := rig.muzzle_position()
	var aim := _target.global_position + Vector3.UP * 1.25
	var dist := from.distance_to(aim)
	var moving := Vector3(velocity.x, 0, velocity.z).length() > 1.0
	var miss_chance := clampf((1.0 - accuracy) + dist / 140.0 + (0.15 if moving else 0.0), 0.05, 0.92)
	var hit_target := _rng.randf() > miss_chance
	var end := aim
	if not hit_target:
		end = aim + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-0.6, 1.2), _rng.randf_range(-1.5, 1.5))
	var query := PhysicsRayQueryParameters3D.create(from, from + (end - from).normalized() * (dist + 2.0), WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit["position"]
		var victim = hit["collider"]
		if victim and victim.has_method(&"take_hit") and victim != self:
			if victim is PlayerController:
				(victim as PlayerController).last_attacker_peer = bot_id
			victim.take_hit(float(_weapon["damage"]) * damage_scale, (end - from).normalized() * 1.2, self, false)
		Effects.impact(get_tree(), end)
	Effects.muzzle_flash(get_tree(), from)
	Effects.tracer(get_tree(), from, end)
	rig.kick()


func _melee() -> void:
	_fire_cd = _rng.randf_range(1.1, 1.7)
	var clips := [&"punch_1", &"punch_2", &"punch_3", &"kick_front", &"punch_heavy"]
	var clip: StringName = clips[_rng.randi() % clips.size()]
	if not rig.has_clip(clip):
		clip = &"punch_1"
	var heavy := clip == &"kick_front" or clip == &"punch_heavy"
	rig.replay(clip, 1.5)
	_action_lock = rig.clip_length(clip) / 1.5
	var target := _target
	var swing := Time.get_ticks_msec()
	_swing_id = swing
	# The hit lands on the swing, not the instant the bot decides to attack.
	await get_tree().create_timer(0.3).timeout
	if _swing_id != swing:
		return   # interrupted (got hit) before the blow connected
	if not is_inside_tree() or health.is_dead or target == null or not is_instance_valid(target):
		return
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length() > 2.4 or not target.has_method(&"take_hit"):
		return
	if target.has_method(&"is_alive") and not target.call(&"is_alive"):
		return
	if target is PlayerController:
		(target as PlayerController).last_attacker_peer = bot_id   # KO credit
	target.take_hit(melee_damage * (1.6 if heavy else 1.0), offset.normalized() * (6.0 if heavy else 3.0), self, heavy)


## Simple obstacle feeler: turn away from walls straight ahead.
func _avoid(move: Vector3) -> Vector3:
	if move.length() < 0.1:
		return move
	var from := global_position + Vector3.UP * 0.6
	var query := PhysicsRayQueryParameters3D.create(from, from + move.normalized() * 2.5, WORLD_LAYER | VEHICLE_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return move
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	return (move + normal * 1.4 + Vector3(-move.z, 0, move.x) * _strafe).normalized()


func take_hit(damage: float, knockback: Vector3, attacker: Node3D, _heavy: bool = false) -> void:
	if health.is_dead:
		return
	if attacker is BotSoldier and (attacker as BotSoldier).team == team:
		return
	_last_attacker = attacker
	health.take_damage(damage, attacker)
	velocity += knockback
	if attacker and attacker != self and (_target == null or _rng.randf() < 0.5):
		_target = attacker
		_reaction = 0.2
	if not health.is_dead:
		rig.replay(rig.hit_clip(), 1.8, 0.05)
		_action_lock = maxf(_action_lock, 0.3)
		_swing_id = 0


func _on_died() -> void:
	remove_from_group(&"enemies")
	remove_from_group(&"bots")
	collision_layer = 0
	collision_mask = WORLD_LAYER
	var death: StringName = &"ko_loser" if melee_only else [&"death_back", &"death_front"][_rng.randi() % 2]
	if not rig.has_clip(death):
		death = &"death"
	rig.replay(death, 1.3, 0.1)
	rig.armed = false
	died.emit(self, _last_attacker)
	await get_tree().create_timer(10.0).timeout
	if is_inside_tree():
		queue_free()
