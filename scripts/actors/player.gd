class_name Player
extends Fighter
## Nash: superhuman speed and strength after Project Axiom. Third-person
## movement, Def Jam style brawling (camera swings side-on when a fight
## starts), cinematic finishers, power surge, and driving any car.

signal interact_changed(prompt: String)

var cam: CameraRig
var car: Car                      # the car we're driving
var interactable: Node            # nearest usable thing (door, counter...)
var finisher_target: Fighter
var _fight_target: Fighter
var _was_blocking := false
var _finisher_time := 0.0
var controls_enabled := true


func _ready() -> void:
	model_path = Humanoid.NASH
	max_health = 160.0
	super._ready()
	display_name = Game.player_name
	add_to_group(&"player")


func setup_camera(c: CameraRig) -> void:
	cam = c
	cam.target = self
	cam.yaw = rotation.y + PI


func _wants_move() -> Vector3:
	if not controls_enabled:
		return Vector3.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if TouchControls.stick.length() > 0.05:
		v = TouchControls.stick
	if v.length() < 0.05:
		return Vector3.ZERO
	var basis := Basis(Vector3.UP, cam.yaw if cam else 0.0)
	var dir := basis * Vector3(v.x, 0, v.y)
	dir.y = 0.0
	return dir.limit_length(1.0)


func _wants_sprint() -> bool:
	return Input.is_action_pressed("sprint") or TouchControls.stick.length() > 0.92


func _face_target() -> Fighter:
	return _fight_target


func strength_scale() -> float:
	return 1.35   # Axiom strength


func _physics_process(delta: float) -> void:
	if car:
		global_position = car.global_position + Vector3.UP * 0.6
		return
	_fight_target = _nearest_foe(7.0)
	_update_camera_mode()
	if controls_enabled:
		_read_actions()
	super._physics_process(delta)
	if _finisher_time > 0.0:
		_finisher_time -= delta / maxf(Engine.time_scale, 0.05)
	if global_position.y < -40.0:
		respawn(Layout.PLAYER_START)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and cam:
		cam.add_look((event as InputEventMouseMotion).relative)


func _read_actions() -> void:
	if Input.is_action_just_pressed("punch"):
		punch()
	if Input.is_action_just_pressed("heavy"):
		if finisher_target and finisher_target.finishable() and finisher_target.global_position.distance_to(global_position) < 2.6:
			finisher(finisher_target)
		else:
			heavy()
	var blocking := Input.is_action_pressed("block")
	if blocking != _was_blocking:
		block(blocking)
		_was_blocking = blocking
	if Input.is_action_just_pressed("dodge"):
		dodge(_wants_move())
	if Input.is_action_just_pressed("jump"):
		jump()
	if Input.is_action_just_pressed("surge"):
		power_surge()
	if Input.is_action_just_pressed("interact"):
		_interact()
	if cam and TouchControls.look_delta != Vector2.ZERO:
		cam.add_look(TouchControls.look_delta)
		TouchControls.look_delta = Vector2.ZERO


func _nearest_foe(radius: float) -> Fighter:
	var best: Fighter = null
	var best_d := radius
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		if f == self or not f.alive or f.in_car or f.is_in_group(&"civilians"):
			continue
		var d := f.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = f
	finisher_target = best if best and best.finishable() else null
	return best


func _update_camera_mode() -> void:
	if cam == null or cam.mode == CameraRig.Mode.CINEMA or cam.mode == CameraRig.Mode.CAR:
		return
	if _fight_target and _fight_target.global_position.distance_to(global_position) < 5.5:
		cam.mode = CameraRig.Mode.FIGHT
		cam.opponent = _fight_target
	else:
		cam.mode = CameraRig.Mode.FOOT


func _land_hit(target: Fighter, attack: Dictionary) -> void:
	super._land_hit(target, attack)
	var heavy := bool(attack.get("heavy", false))
	CameraRig.shake_all(0.45 if heavy else 0.18)
	if heavy:
		Game.hitstop(0.07)


func receive_hit(damage: float, push: Vector3, attacker: Fighter, heavy: bool) -> void:
	var before := health
	super.receive_hit(damage, push, attacker, heavy)
	if health < before:
		CameraRig.shake_all(0.35 if heavy else 0.15)
		var hud := get_tree().get_first_node_in_group(&"hud")
		if hud:
			hud.call("damage_flash", clampf((before - health) / 30.0, 0.2, 1.0))


## Def Jam finisher: slow motion, orbiting camera, three hits, launch.
func finisher(target: Fighter) -> void:
	if not can_act():
		return
	_set_state(State.FINISHER)
	_finisher_time = 1.6
	var d := target.global_position - global_position
	rotation.y = atan2(d.x, d.z)
	if cam:
		cam.cinema((global_position + target.global_position) * 0.5, 1.6)
	Game.slowmo(0.35, 0.55)
	Sfx.play("surge", global_position, -2.0, 1.4)
	var seq := [[&"Punch_Jab", 0.0], [&"Punch_Cross", 0.18], [&"Melee_Hook", 0.36]]
	for step in seq:
		var t := get_tree().create_timer(float(step[1]), true, false, false)
		t.timeout.connect(func() -> void:
			if not is_instance_valid(target):
				return
			body.one_shot(step[0], 1.6, 0.03)
			var last: bool = step[0] == &"Melee_Hook"
			var dmg := target.health + 5.0 if last and target.health < target.max_health * 0.35 else (8.0 if not last else 40.0)
			target.receive_hit(dmg, global_basis.z * (16.0 if last else 1.0) + (Vector3.UP * 6.0 if last else Vector3.ZERO), self, last)
			CameraRig.shake_all(1.2 if last else 0.4)
			if last:
				Game.hitstop(0.12)
				Fx.shockwave(get_parent(), target.global_position + Vector3.UP, 3.0)
				surge = minf(surge + 25.0, 100.0))
	var done := get_tree().create_timer(0.9, true, false, false)
	done.timeout.connect(func() -> void:
		if state == State.FINISHER:
			_set_state(State.FREE)
			body.cancel_one_shot())


# --------------------------------------------------------------- vehicles

func _interact() -> void:
	if interactable and is_instance_valid(interactable):
		interactable.call("use", self)
		return
	var best: Car = null
	var best_d := 4.0
	for node in get_tree().get_nodes_in_group(&"cars"):
		var c := node as Car
		if c.driver != null or c.wrecked:
			continue
		var d := c.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = c
	if best:
		enter_car(best)


func enter_car(c: Car) -> void:
	car = c
	in_car = true
	c.set_driver(self)
	visible = false
	collision_layer = 0
	collision_mask = 0
	if cam:
		cam.target = c
		cam.mode = CameraRig.Mode.CAR
		cam.yaw = 0.0


func exit_car() -> void:
	if car == null:
		return
	var c := car
	car = null
	in_car = false
	c.set_driver(null)
	var side := c.global_basis.x * 2.2
	global_position = c.global_position + side + Vector3.UP * 0.5
	velocity = Vector3.ZERO
	visible = true
	collision_layer = Game.L_CHARS
	collision_mask = Game.L_WORLD | Game.L_CARS | Game.L_CHARS | Game.L_BARRIER
	if cam:
		cam.target = self
		cam.mode = CameraRig.Mode.FOOT
		cam.yaw = c.rotation.y + PI


func set_interactable(node: Node, prompt: String) -> void:
	interactable = node
	interact_changed.emit(prompt)


func clear_interactable(node: Node) -> void:
	if interactable == node:
		interactable = null
		interact_changed.emit("")
