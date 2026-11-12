class_name Car
extends VehicleBody3D
## A drivable car from the car pack. Handling is arcade-planted: strong
## lateral grip assist, speed-sensitive steering, downforce, a low centre of
## mass and a handbrake that lets the rear step out for a controlled drift.
## Nitro, collision damage, smoke at 35%, fire at 12%, then it explodes.

signal exploded(car: Car)
signal fell_off(car: Car)

var car_id := "sedan"
var data: Dictionary
var paint := Color(0, 0, 0, 0)
var driver: Node                  # Player when someone local drives
var health := 800.0
var wrecked := false
var nitro := 0.5
var nitro_on := false
var owner_peer := 0               # network owner (0 = local)
var exit_locked := false          # races: no getting out

# AI / remote inputs (-1..1)
var ai_enabled := false
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var in_nitro := false

var _wheels: Array[VehicleWheel3D] = []
var _rear: Array[VehicleWheel3D] = []
var _front: Array[VehicleWheel3D] = []
var _steer := 0.0
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _last_v := Vector3.ZERO
var _body_mesh: MeshInstance3D
var _lights: Array[SpotLight3D] = []
var gear := 1
var rpm := 0.0
var drifting := false


func _ready() -> void:
	data = CarCatalog.data(car_id)
	health = data["health"]
	mass = data["mass"]
	add_to_group(&"cars")
	collision_layer = Game.L_CARS
	collision_mask = Game.L_WORLD | Game.L_CARS | Game.L_CHARS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0)   # below the floor: arcade cars never roll
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_hit)
	can_sleep = false
	_build()
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Sfx.streams.get("engine")
	_engine.unit_size = 8.0
	_engine.volume_db = -6.0
	add_child(_engine)
	_skid = AudioStreamPlayer3D.new()
	_skid.stream = Sfx.streams.get("skid")
	_skid.volume_db = -60.0
	add_child(_skid)


func _build() -> void:
	var holder := Node3D.new()
	holder.name = "Model"
	holder.rotation.y = PI      # the pack faces -Z; VehicleBody3D drives +Z
	add_child(holder)
	var model := (load(data["model"]) as PackedScene).instantiate() as Node3D
	holder.add_child(model)
	var radius := 0.34
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name.begins_with("Wheel_") and owner_peer != 0:
			continue   # another player's car: wheels stay plain meshes (no raycast physics)
		if mi.name.begins_with("Wheel_"):
			var aabb := mi.get_aabb()
			var rel := _rel(mi)
			radius = maxf(aabb.size.y, aabb.size.z) * 0.5 * rel.basis.get_scale().y
			var wheel := VehicleWheel3D.new()
			wheel.name = mi.name
			wheel.position = rel.origin + Vector3.UP * 0.2   # suspension rest: the wheel hangs 0.22 below
			add_child(wheel)
			var front := mi.name.contains("F")
			wheel.use_as_steering = front
			var drive: String = data["drive"]
			wheel.use_as_traction = drive == "awd" or (drive == "fwd") == front
			wheel.wheel_radius = radius
			wheel.wheel_rest_length = 0.22
			wheel.suspension_travel = 0.22
			wheel.suspension_stiffness = 85.0
			wheel.suspension_max_force = mass * 12.0 * 4.0
			wheel.damping_compression = 0.9
			wheel.damping_relaxation = 1.1
			wheel.wheel_friction_slip = 3.2 * float(data["grip"])
			wheel.wheel_roll_influence = 0.02
			# Move the visual wheel under the physics wheel so it spins/steers.
			mi.get_parent().remove_child(mi)
			wheel.add_child(mi)
			mi.transform = Transform3D(rel.basis, Vector3.ZERO)
			_wheels.append(wheel)
			(_front if front else _rear).append(wheel)
		elif _body_mesh == null or mi.name == "Body":
			_body_mesh = mi
	# Body collider from the body mesh bounds (slightly inset).
	if _body_mesh:
		var box := _body_mesh.get_aabb()
		var xf := _rel(_body_mesh)
		var shape := BoxShape3D.new()
		var size := (xf.basis.get_scale() * box.size).abs()
		shape.size = Vector3(size.x * 0.92, size.y * 0.55, size.z * 0.95)
		var col := CollisionShape3D.new()
		col.shape = shape
		add_child(col)
		col.position = xf * box.get_center() + Vector3.UP * size.y * 0.12
		if paint.a > 0.0:
			_repaint(paint)
	# Headlights.
	for side in [-0.6, 0.6]:
		var l := SpotLight3D.new()
		l.position = Vector3(side, 0.7, 2.1)
		l.rotation = Vector3(-0.08, PI, 0)
		l.spot_range = 45.0
		l.spot_angle = 32.0
		l.light_energy = 0.0
		l.light_color = Color(1.0, 0.95, 0.85)
		add_child(l)
		_lights.append(l)


## Transform of a model node relative to the car body (no globals: they
## aren't up to date while the car is being built).
func _rel(node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p and p != self:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _repaint(color: Color) -> void:
	var shader := load("res://assets/shaders/car_paint.gdshader") as Shader
	for s in _body_mesh.mesh.get_surface_count():
		var mat := _body_mesh.get_active_material(s) as StandardMaterial3D
		if mat == null or not (mat.resource_name.to_lower().contains("body") or mat.resource_name.to_lower().contains("paint")):
			continue
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
		sm.set_shader_parameter("paint_color", color)
		_body_mesh.set_surface_override_material(s, sm)


func set_driver(d: Node) -> void:
	driver = d
	sleeping = false
	if d == null:
		in_throttle = 0.0
		in_brake = 0.0


func lights(on: bool) -> void:
	for l in _lights:
		l.light_energy = 3.0 if on else 0.0


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


func _physics_process(delta: float) -> void:
	if owner_peer != 0:
		return   # another player's car: positioned by the network
	if global_position.y < -30.0 or absf(global_position.x) > Layout.HALF + 400.0 or absf(global_position.z) > Layout.HALF + 400.0:
		fell_off.emit(self)
	if wrecked:
		engine_force = 0.0
		brake = 2.0
		return
	if driver and driver is Player:
		_read_player()
	elif not ai_enabled and owner_peer == 0:
		in_throttle = 0.0
		in_steer = 0.0
		in_handbrake = false
		brake = 1.0
	var speed := forward_speed()
	var top: float = data["top"] * (1.25 if nitro_on else 1.0)
	# Throttle / brake / reverse.
	var force := 0.0
	brake = 0.0
	if in_throttle > 0.05:
		if speed > -1.0:
			force = in_throttle * float(data["accel"]) * mass * clampf(1.15 - speed / top, 0.0, 1.0) * 0.85
		else:
			brake = 30.0
	if in_brake > 0.05:
		if speed > 1.5:
			brake = in_brake * 40.0
		else:
			force = -in_brake * float(data["accel"]) * mass * 0.6 * clampf(1.0 + speed / 14.0, 0.0, 1.0)
	nitro_on = in_nitro and nitro > 0.02 and in_throttle > 0.5
	if nitro_on:
		nitro = maxf(nitro - delta / 4.0, 0.0)
		force *= 1.8
	else:
		nitro = minf(nitro + delta * (0.06 if drifting else 0.012), 1.0)
	var drive_wheels := 0
	for w in _wheels:
		if w.use_as_traction:
			drive_wheels += 1
	for w in _wheels:
		w.engine_force = force / maxi(drive_wheels, 1) if w.use_as_traction else 0.0
		w.brake = brake
	# Steering: quicker at low speed, gentler at high speed.
	var max_steer: float = data["steer"] * lerpf(1.0, 0.2, clampf(absf(speed) / 45.0, 0.0, 1.0))
	_steer = move_toward(_steer, in_steer * max_steer, delta * 2.6)
	steering = _steer
	# Handbrake: lock the rear, ease their grip for a drift.
	for w in _rear:
		w.wheel_friction_slip = 3.2 * float(data["grip"]) * (0.45 if in_handbrake else 1.0)
		if in_handbrake:
			w.brake = 18.0
	_assist(delta, speed)
	_gearbox(speed, top)
	_sound(speed)
	_last_v = linear_velocity


## Planted feel: cancel most sideways slide, add downforce, limit spin.
## (Impulses only: writing the velocity directly would fight the suspension.)
func _assist(delta: float, speed: float) -> void:
	var on_ground := 0
	for w in _wheels:
		if w.is_in_contact():
			on_ground += 1
	if on_ground == 0:
		apply_torque_impulse(-Vector3(angular_velocity.x, 0, angular_velocity.z) * mass * 0.02)
		return
	var right := global_basis.x
	var lateral := linear_velocity.dot(right)
	drifting = (in_handbrake and absf(speed) > 12.0) or (absf(lateral) > 4.0 and absf(speed) > 15.0)
	var hold: float = float(data["grip"]) * (1.2 if drifting else 4.0)
	apply_central_impulse(-right * lateral * mass * clampf(hold * delta, 0.0, 1.0) * float(on_ground) / 4.0)
	apply_central_force(-global_basis.y * linear_velocity.length_squared() * mass * 0.004)
	# Roll / pitch: damp it and pull the car upright.
	var up := global_basis.y
	var fwd := global_basis.z
	var roll_rate := angular_velocity.dot(fwd)
	var pitch_rate := angular_velocity.dot(right)
	apply_torque_impulse((-fwd * roll_rate * 0.9 - right * pitch_rate * 0.5) * mass * delta * 8.0)
	var tilt := up.cross(Vector3.UP)
	apply_torque_impulse(tilt * mass * delta * 14.0)
	# Yaw: steady the car; allow controlled rotation while drifting.
	var yaw_rate := angular_velocity.dot(up)
	# ~1.4 g of cornering grip (more while drifting, it is a slide).
	var max_yaw := clampf((22.0 if drifting else 14.0) / maxf(absf(speed), 1.0), 0.6, 2.4)
	if absf(yaw_rate) > max_yaw:
		apply_torque_impulse(-up * (yaw_rate - signf(yaw_rate) * max_yaw) * mass * 0.6)
	_skid.volume_db = lerpf(_skid.volume_db, -6.0 if drifting else -60.0, delta * 8.0)
	if drifting and not _skid.playing:
		_skid.play()


func _gearbox(speed: float, top: float) -> void:
	var ratio := clampf(absf(speed) / top, 0.0, 1.0)
	gear = clampi(int(ratio * 6.0) + 1, 1, 6)
	var band := ratio * 6.0 - (gear - 1)
	rpm = clampf(0.25 + band * 0.75, 0.0, 1.0) if in_throttle > 0.05 or absf(speed) > 2.0 else 0.12


func _sound(_speed: float) -> void:
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = lerpf(0.55, 2.1, rpm)
	_engine.volume_db = -14.0 + in_throttle * 6.0


func _read_player() -> void:
	var stick := TouchControls.stick
	in_steer = -stick.x if stick.length() > 0.05 else Input.get_axis("move_right", "move_left")
	in_throttle = maxf(Input.get_action_strength("gas"), 1.0 if TouchControls.gas else 0.0)
	in_brake = maxf(Input.get_action_strength("brake"), 1.0 if TouchControls.brake else 0.0)
	in_handbrake = Input.is_action_pressed("handbrake") or TouchControls.handbrake
	in_nitro = Input.is_action_pressed("nitro") or TouchControls.nitro_held
	if Input.is_action_just_pressed("interact") and not exit_locked:
		(driver as Player).exit_car()


func _on_hit(other: Node) -> void:
	var dv := (_last_v - linear_velocity).length()
	if dv > 6.0:
		take_damage((dv - 6.0) * 22.0)
		Sfx.play("crash", global_position, clampf(dv - 12.0, -12.0, 6.0))
		if driver:
			CameraRig.shake_all(clampf(dv / 25.0, 0.1, 0.9))
	if other is Car and dv > 4.0:
		(other as Car).take_damage((dv - 4.0) * 10.0)


func take_damage(amount: float) -> void:
	if wrecked:
		return
	health = maxf(health - amount, 0.0)
	var full: float = data["health"]
	if health < full * 0.35 and _smoke == null:
		_smoke = Fx.plume(self, Vector3(0, 0.9, 1.6), false)
	if health < full * 0.12 and _fire == null:
		_fire = Fx.plume(self, Vector3(0, 0.8, 1.7), true)
	if health <= 0.0:
		explode()


func explode() -> void:
	if wrecked:
		return
	wrecked = true
	Fx.explosion(get_parent(), global_position + Vector3.UP * 0.8, true)
	apply_central_impulse(Vector3.UP * mass * 6.0)
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 2.0)
	if _body_mesh:
		var burnt := Mats.flat(Color(0.05, 0.045, 0.04), 0.95)
		for s in _body_mesh.mesh.get_surface_count():
			_body_mesh.set_surface_override_material(s, burnt)
	if _fire == null:
		_fire = Fx.plume(self, Vector3(0, 0.8, 0.0), true)
	for l in _lights:
		l.light_energy = 0.0
	# Anyone around is blown off their feet.
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		if f.alive and not f.in_car and f.global_position.distance_to(global_position) < 7.0:
			f.receive_hit(45.0, (f.global_position - global_position).normalized() * 12.0 + Vector3.UP * 4.0, null, true)
	for node in get_tree().get_nodes_in_group(&"cars"):
		var c := node as Car
		if c != self and c.global_position.distance_to(global_position) < 9.0:
			c.take_damage(160.0)
			c.apply_central_impulse((c.global_position - global_position).normalized() * c.mass * 5.0 + Vector3.UP * c.mass * 3.0)
	exploded.emit(self)
	if driver and driver is Player:
		var p := driver as Player
		p.exit_car()
		p.receive_hit(60.0, Vector3.UP * 4.0, null, true)


## Workshop: like new.
func repair() -> void:
	wrecked = false
	health = data["health"]
	for fx in [_smoke, _fire]:
		if fx and is_instance_valid(fx):
			fx.queue_free()
	_smoke = null
	_fire = null
	if _body_mesh:
		for s in _body_mesh.mesh.get_surface_count():
			_body_mesh.set_surface_override_material(s, null)
	if paint.a > 0.0:
		_repaint(paint)


## Place upright at `pos` facing `yaw` (respawns, race grid).
func reset_to(pos: Vector3, yaw: float) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_last_v = Vector3.ZERO


## Slowed by a surge blast or grenade.
func stun(seconds: float) -> void:
	linear_velocity *= 0.4
	angular_velocity += Vector3.UP * randf_range(-2.0, 2.0)
	in_nitro = false
	set_meta(&"stun_until", Time.get_ticks_msec() + int(seconds * 1000.0))
