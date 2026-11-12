class_name Fighter
extends CharacterBody3D
## Anyone who can fight: Nash, bots and other players' avatars.
## Combat model (Def Jam style): light combo (jab, cross, hook), heavy
## (shoulder charge), block, dodge roll, power surge (area blast) and a
## cinematic finisher on a staggered opponent. Hits push, stagger, knock
## down; health 0 = KO.

signal knocked_out(victim: Fighter, attacker: Fighter)
signal hit_landed(target: Fighter, damage: float, heavy: bool)

const ATTACKS := {
	"jab": {"clip": &"Punch_Jab", "damage": 7.0, "start": 0.14, "end": 0.3, "range": 1.7, "push": 2.0, "speed": 1.35},
	"cross": {"clip": &"Punch_Cross", "damage": 10.0, "start": 0.18, "end": 0.34, "range": 1.8, "push": 3.0, "speed": 1.3},
	"hook": {"clip": &"Melee_Hook", "damage": 15.0, "start": 0.26, "end": 0.44, "range": 1.9, "push": 6.0, "speed": 1.25, "heavy": true},
	"charge": {"clip": &"Shield_Dash_RM", "damage": 18.0, "start": 0.12, "end": 0.45, "range": 2.0, "push": 11.0, "speed": 1.2, "heavy": true, "lunge": 9.0},
}
const COMBO := ["jab", "cross", "hook"]

@export var max_health := 100.0
var health := 100.0
var surge := 0.0                # 0..100, fills by landing and taking hits
var display_name := "Fighter"
var peer_id := 0                # network owner (0 = local / bot)
var fighter_id := 0             # unique in the match
var team := 0
var body: Humanoid
var model_path := Humanoid.NASH
var model_height := 1.8

var walk_speed := 3.2
var run_speed := 6.5
var sprint_speed := 12.0        # Nash is superhuman
var gravity := 24.0
var jump_velocity := 9.5

enum State { FREE, ATTACK, STAGGER, DOWN, DODGE, BLOCK, FINISHER, KO }
var state := State.FREE
var _state_time := 0.0
var _attack: Dictionary = {}
var _attack_hit: Array = []
var _combo_step := 0
var _combo_window := 0.0
var _queued := ""
var _down_time := 0.0
var _knock := Vector3.ZERO
var _invuln := 0.0
var _stagger_meter := 0.0
var alive := true
var in_car := false
var _foot_speed := 0.0


func _ready() -> void:
	add_to_group(&"fighters")
	collision_layer = Game.L_CHARS
	collision_mask = Game.L_WORLD | Game.L_CARS | Game.L_CHARS | Game.L_BARRIER
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50)
	body = Humanoid.new()
	body.name = "Body"
	add_child(body)
	body.setup(model_path, model_height)
	health = max_health


# ------------------------------------------------------------ to override

## World-space desired movement (length 0..1) and whether to sprint.
func _wants_move() -> Vector3:
	return Vector3.ZERO


func _wants_sprint() -> bool:
	return false


func _face_target() -> Fighter:
	return null


# --------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	if in_car:
		return
	_state_time += delta
	_invuln = maxf(_invuln - delta, 0.0)
	_combo_window = maxf(_combo_window - delta, 0.0)
	_stagger_meter = maxf(_stagger_meter - delta * 12.0, 0.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	var move := Vector3.ZERO
	match state:
		State.FREE, State.BLOCK:
			move = _wants_move()
			var speed := walk_speed if state == State.BLOCK else (sprint_speed if _wants_sprint() else run_speed)
			var target_v := move * speed
			velocity.x = move_toward(velocity.x, target_v.x, delta * 45.0)
			velocity.z = move_toward(velocity.z, target_v.z, delta * 45.0)
			var foe := _face_target()
			var look := move
			if foe and foe.global_position.distance_to(global_position) < 6.0:
				look = foe.global_position - global_position
			look.y = 0.0
			if look.length() > 0.05:
				rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z), clampf(delta * 14.0, 0.0, 1.0))
		State.ATTACK:
			_tick_attack(delta)
		State.DODGE:
			if _state_time > 0.45:
				_set_state(State.FREE)
		State.STAGGER:
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, delta * 22.0)
			if _state_time > 0.42:
				_set_state(State.FREE)
		State.DOWN:
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, delta * 14.0)
			if alive and _state_time > _down_time:
				body.one_shot(&"LayToIdle", 1.6)
				_invuln = 1.2
				_set_state(State.STAGGER)
				_state_time = -0.6
		State.FINISHER, State.KO:
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, delta * 10.0)
	move_and_slide()
	_foot_speed = Vector2(velocity.x, velocity.z).length()
	_animate()


func _animate() -> void:
	if state == State.FREE and not body.busy():
		if not is_on_floor() and velocity.y > 1.0:
			body.play(&"Jump")
		elif _foot_speed < 0.4:
			body.play(&"Punch_Enter" if _face_target() != null and _face_target().global_position.distance_to(global_position) < 5.0 else &"Idle")
		elif _foot_speed < 4.5:
			body.play(&"Jog_Fwd" if _foot_speed > 2.5 else &"Walk", -1.0, clampf(_foot_speed / 3.0, 0.7, 1.4))
		else:
			body.play(&"Sprint", -1.0, clampf(_foot_speed / 8.0, 0.9, 1.6))
	elif state == State.BLOCK:
		body.play(&"Sword_Block", 0.1)


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0


# ---------------------------------------------------------------- attacks

func can_act() -> bool:
	return alive and not in_car and state in [State.FREE, State.BLOCK]


func punch() -> void:
	if state == State.ATTACK and _state_time > float(_attack["start"]):
		_queued = "punch"
		return
	if not can_act():
		return
	if _combo_window <= 0.0:
		_combo_step = 0
	_start_attack(COMBO[_combo_step % COMBO.size()])
	_combo_step += 1


func heavy() -> void:
	if not can_act():
		return
	_combo_step = 0
	_start_attack("charge")


func _start_attack(kind: String) -> void:
	_attack = ATTACKS[kind].duplicate()
	_attack["kind"] = kind
	_attack_hit = []
	_set_state(State.ATTACK)
	var foe := _face_target()
	if foe and foe.global_position.distance_to(global_position) < 4.0:
		var d := foe.global_position - global_position
		rotation.y = atan2(d.x, d.z)
	var length := body.one_shot(_attack["clip"], float(_attack["speed"]))
	_attack["length"] = minf(length, 0.75)
	Sfx.play("whoosh", global_position + Vector3.UP, -8.0, 1.2 if kind == "jab" else 0.9)


func _tick_attack(delta: float) -> void:
	var fwd := global_basis.z
	var lunge: float = _attack.get("lunge", 1.6)
	if _state_time < float(_attack["end"]):
		velocity.x = fwd.x * lunge
		velocity.z = fwd.z * lunge
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 30.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 30.0)
	if _state_time >= float(_attack["start"]) and _state_time <= float(_attack["end"]):
		for node in get_tree().get_nodes_in_group(&"fighters"):
			var f := node as Fighter
			if f == self or not f.alive or f.in_car or _attack_hit.has(f) or f.team != 0 and f.team == team:
				continue
			var d := f.global_position - global_position
			d.y = 0.0
			if d.length() < float(_attack["range"]) and fwd.dot(d.normalized()) > 0.35:
				_attack_hit.append(f)
				_land_hit(f, _attack)
	if _state_time >= float(_attack["length"]) * 0.8:
		_combo_window = 0.45
		_set_state(State.FREE)
		body.cancel_one_shot()
		if _queued == "punch":
			_queued = ""
			punch()


## Our hit connects: the victim's owner applies it (networked fights).
func _land_hit(target: Fighter, attack: Dictionary) -> void:
	var dmg: float = attack["damage"] * strength_scale()
	var push: Vector3 = global_basis.z * float(attack["push"])
	var heavy := bool(attack.get("heavy", false))
	surge = minf(surge + (9.0 if heavy else 5.0), 100.0)
	hit_landed.emit(target, dmg, heavy)
	target.receive_hit(dmg, push, self, heavy)


func strength_scale() -> float:
	return 1.0


## Apply a hit (call on whoever owns the victim).
func receive_hit(damage: float, push: Vector3, attacker: Fighter, heavy: bool) -> void:
	if not alive or _invuln > 0.0 or in_car:
		return
	if state == State.BLOCK and attacker and global_basis.z.dot((attacker.global_position - global_position).normalized()) > 0.2:
		damage *= 0.15
		push *= 0.3
		Sfx.play("block", global_position + Vector3.UP, -4.0)
		Fx.sparks(get_parent(), global_position + Vector3.UP * 1.3 + global_basis.z * 0.4, Color(0.8, 0.9, 1.0))
		_stagger_meter += damage * 2.0
		if _stagger_meter > 40.0:   # guard break
			_set_state(State.STAGGER)
			body.one_shot(&"Idle_Shield_Break", 1.3)
		return
	health -= damage
	surge = minf(surge + damage * 0.4, 100.0)
	_knock = push
	if attacker:
		var d := attacker.global_position - global_position
		rotation.y = atan2(d.x, d.z)
	Sfx.play("heavy" if heavy else "punch", global_position + Vector3.UP * 1.4, 0.0)
	Fx.sparks(get_parent(), global_position + Vector3.UP * 1.4 + global_basis.z * 0.3, Color(1.0, 0.8, 0.5))
	if health <= 0.0:
		health = 0.0
		_ko(attacker)
		return
	_stagger_meter += damage
	if heavy or _stagger_meter > 45.0 or push.length() > 8.0:
		_stagger_meter = 0.0
		_set_state(State.DOWN)
		_down_time = 1.4
		_knock = push * 1.4 + Vector3.UP * 3.0
		velocity.y = 4.0
		body.one_shot(&"Hit_Knockback", 1.0, 0.05)
	else:
		_set_state(State.STAGGER)
		body.one_shot(&"Hit_Head" if randf() < 0.5 else &"Hit_Chest", 1.3, 0.05)


func _ko(attacker: Fighter) -> void:
	alive = false
	_set_state(State.KO)
	body.one_shot(&"Death01", 1.0, 0.05)
	knocked_out.emit(self, attacker)


## Staggered / low health: open to a finisher.
func finishable() -> bool:
	return alive and (health < max_health * 0.3 or state == State.DOWN or state == State.STAGGER and _stagger_meter > 25.0)


func block(on: bool) -> void:
	if on and can_act():
		_set_state(State.BLOCK)
	elif not on and state == State.BLOCK:
		_set_state(State.FREE)


func dodge(dir: Vector3) -> void:
	if not can_act():
		return
	if dir.length() < 0.1:
		dir = -global_basis.z
	dir = dir.normalized()
	rotation.y = atan2(dir.x, dir.z)
	velocity.x = dir.x * 11.0
	velocity.z = dir.z * 11.0
	_invuln = 0.35
	_set_state(State.DODGE)
	body.one_shot(&"Roll", 1.5)
	Sfx.play("whoosh", global_position, -6.0, 0.8)


func jump() -> void:
	if can_act() and is_on_floor():
		velocity.y = jump_velocity
		body.one_shot(&"Jump_Start", 1.2)


## Power surge: everyone around is blasted away.
func power_surge() -> bool:
	if not can_act() or surge < 50.0:
		return false
	surge -= 50.0
	_set_state(State.ATTACK)
	_attack = {"clip": &"Spell_Simple_Shoot", "start": 99.0, "end": 99.0, "length": 0.6, "kind": "surge"}
	body.one_shot(&"Spell_Simple_Shoot", 1.6)
	Sfx.play("surge", global_position, 4.0)
	Fx.shockwave(get_parent(), global_position + Vector3.UP * 0.8, 7.0)
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		if f == self or not f.alive or f.in_car:
			continue
		var d := f.global_position - global_position
		if d.length() < 7.0:
			var push := (Vector3(d.x, 0, d.z).normalized() * (14.0 - d.length())) + Vector3.UP * 2.0
			_land_hit(f, {"damage": 22.0, "push": 0.0, "heavy": true})
			f._knock = push
	return true


func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	health = max_health
	alive = true
	_invuln = 2.0
	_set_state(State.FREE)
	body.cancel_one_shot()
	body.play(&"Idle", 0.0, 1.0, true)


func is_down() -> bool:
	return state in [State.DOWN, State.KO]
