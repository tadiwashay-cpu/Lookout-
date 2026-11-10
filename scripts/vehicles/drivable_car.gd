class_name DrivableCar
extends VehicleBody3D
## Any car in the world: parked until the player gets in, then driven with
## the same input actions as walking (joystick X steers; GAS / REV buttons
## or W/S drive; JUMP is the handbrake; INTERACT gets out).
##
## Built at runtime from a split .glb (Body + Wheel_FL/FR/RL/RR) so one
## script serves every model. Stats come from VehicleCatalog (hidden rank).
##
## Note: Godot's VehicleBody3D drives along its local +Z, so the model
## (which faces -Z like everything else in the project) is turned 180°.

signal driver_entered(driver: PlayerController)
signal driver_exited(driver: PlayerController)

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const VEHICLE_LAYER := 32
const CAR_SCENE_DISTANCE := 140.0   # meshes fade out beyond this (mobile draw calls)

@export var vehicle_id: String = "sedan"
## Leave transparent to keep the factory paint.
@export var paint: Color = Color(0, 0, 0, 0)
## Street Race: the driver can't get out.
@export var locked := false

## AI drivers (police pursuit, race bots) set these instead of the player's input.
var ai_enabled := false
var ai_throttle := 0.0
var ai_reverse := 0.0
var ai_steer := 0.0          # -1 right .. +1 left (same as the player's axis)
var ai_handbrake := false
var ai_top_speed_scale := 1.0
var _upside_down_time := 0.0

var data: Dictionary
var driver: PlayerController
var has_been_stolen := false
var is_police := false
var health := 800.0
var _slow_timer := 0.0

var _wheels: Array[VehicleWheel3D] = []
var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _traction_count := 0
var _steer := 0.0
var _camera: Camera3D
var _cam_yaw_offset := 0.0
var _cam_pitch := 0.28
var _light_bar: Array[MeshInstance3D] = []
var _siren_time := 0.0
var _roof_height := 1.4
var _entered_frame := -1
var _own_lights: MeshInstance3D
var _lights_material: StandardMaterial3D
var siren_on := false
var _skid_last: Dictionary = {}   # rear wheel -> last contact point while skidding
var _skids: SkidMarks
## Arcade handling: grip assist when driving straight, a held drift state
## after a handbrake flick (rear steps out, momentum is kept).
var drifting := false
const GRIP_ASSIST := 3.2      # how hard sideways sliding is cancelled (1/s)
const DRIFT_GRIP := 0.55      # assist left while drifting
const DRIFT_YAW_MAX := 2.3    # rad/s spin cap so you don't loop
enum CamView { CLOSE, FAR, FREE, HOOD, INTERIOR }
## Remembered between cars. INTERIOR only for cars whose catalog entry has "interior".
static var cam_view: CamView = CamView.CLOSE
## 0 = day, 1 = night. Set by DayNight; cars switch their lights from it.
static var night := 0.0
const BLUR_FROM := 41.7   # m/s = 150 km/h
var _lamp_materials: Array[StandardMaterial3D] = []
var _lamps_on := -1.0
var _headlights: Array[SpotLight3D] = []
var _engine_sound: AudioStreamPlayer3D
var _skid_sound: AudioStreamPlayer3D
var _siren_sound: AudioStreamPlayer3D
var _blur_layer: CanvasLayer
var _blur_material: ShaderMaterial
var _body_aabb := AABB()
## Red light streaks behind the car you drive (GPUTrail add-on), shown at speed.
var _light_trails: Array[GPUTrail3D] = []
const TRAIL_SPEED := 22.0   # m/s (~80 km/h)

const _PAINT_SHADER := preload("res://assets/materials/shaders/car_paint.gdshader")


func _ready() -> void:
	add_to_group(&"vehicles")
	data = VehicleCatalog.get_data(vehicle_id)
	is_police = data["police"]
	mass = data["mass"]
	health = data["health"]
	collision_layer = VEHICLE_LAYER
	collision_mask = WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER | VEHICLE_LAYER | 16   # 16 = pedestrians
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.12, 0.0)   # very low: planted, resists rolling
	contact_monitor = false   # only while driven (mobile perf)
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	can_sleep = true
	set_process(false)
	_build_from_model()
	if is_police and paint.a == 0.0 and not data.has("colors"):
		paint = VehicleCatalog.POLICE_PAINT.get(vehicle_id, Color(0.05, 0.05, 0.06))
	if paint.a > 0.0:
		_apply_paint(paint)
	if is_police and _own_lights == null:
		_build_light_bar()
	elif _own_lights and not is_police:
		_setup_head_tail_lights()
	if _lamp_materials.is_empty() and not is_police:
		_setup_optics_lamps()   # lamps painted on the body ("Optics" materials)
	elif _own_lights:
		_lights_material = StandardMaterial3D.new()
		_lights_material.emission_enabled = true
		_own_lights.material_override = _lights_material
		_set_light_bar(0.0)


# ------------------------------------------------------------------ building

func _build_from_model() -> void:
	var scene := load(data["model_path"]) as PackedScene
	if scene == null:
		push_error("DrivableCar: missing model %s" % data["model_path"])
		return
	var holder := Node3D.new()
	holder.name = "Model"
	holder.rotation.y = PI   # model faces -Z, VehicleBody3D drives +Z
	add_child(holder)
	var model := scene.instantiate() as Node3D
	holder.add_child(model)

	var colors: Dictionary = data.get("colors", {})
	if not colors.is_empty():
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for s in mesh_instance.mesh.get_surface_count():
				var original := mesh_instance.mesh.surface_get_material(s) as StandardMaterial3D
				if original and colors.has(original.resource_name):
					var tinted := original.duplicate() as StandardMaterial3D
					tinted.albedo_color = colors[original.resource_name]
					mesh_instance.set_surface_override_material(s, tinted)
	_own_lights = model.find_child("Lights", true, false) as MeshInstance3D
	var body_mesh := model.find_child("Body", true, false) as MeshInstance3D
	if body_mesh:
		_add_body_collision(body_mesh)
		_fade_distance(body_mesh)

	for wheel_name: String in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel_mesh := model.find_child(wheel_name, true, false) as MeshInstance3D
		if wheel_mesh == null:
			continue
		var is_front := wheel_name.begins_with("Wheel_F")
		var wheel := VehicleWheel3D.new()
		wheel.name = wheel_name
		var mesh_size := wheel_mesh.get_aabb().size
		wheel.wheel_radius = maxf(mesh_size.y, mesh_size.z) * 0.5
		wheel.wheel_rest_length = 0.16
		# Attach the suspension above the hub so the resting wheel sits where
		# the model drew it (otherwise the car squats and wheels look sunken).
		wheel.position = to_local(wheel_mesh.global_position) + Vector3.UP * 0.13
		wheel.suspension_travel = 0.26
		wheel.suspension_stiffness = 90.0   # ~2.7 cm sag at rest, stays off the bump stops
		wheel.suspension_max_force = float(data["mass"]) * 14.0
		wheel.damping_compression = 2.4
		wheel.damping_relaxation = 3.0
		wheel.wheel_friction_slip = data["grip"]
		wheel.wheel_roll_influence = 0.05   # low = the chassis won't be levered over
		wheel.use_as_steering = is_front
		var drive: String = data["drive"]
		wheel.use_as_traction = drive == "awd" or (drive == "fwd") == is_front
		add_child(wheel)
		# Move the visual wheel under the physics wheel so it spins and steers.
		var visual_basis := wheel_mesh.global_basis
		wheel_mesh.get_parent().remove_child(wheel_mesh)
		wheel.add_child(wheel_mesh)
		wheel_mesh.position = Vector3.ZERO
		wheel_mesh.global_basis = visual_basis
		_fade_distance(wheel_mesh)
		_wheels.append(wheel)
		(_front_wheels if is_front else _rear_wheels).append(wheel)
		if wheel.use_as_traction:
			_traction_count += 1
		wheel.brake = float(data["brake"]) * 0.5   # parked: handbrake on


func _add_body_collision(body_mesh: MeshInstance3D) -> void:
	var aabb := body_mesh.get_aabb()
	_body_aabb = aabb
	_roof_height = aabb.end.y
	# Keep the box above the wheels' lower half so the suspension does the work.
	var bottom := aabb.position.y + aabb.size.y * 0.22
	var size := Vector3(aabb.size.x * 0.96, aabb.end.y - bottom, aabb.size.z * 0.97)
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	var centre := Vector3(aabb.get_center().x, bottom + size.y * 0.5, aabb.get_center().z)
	shape.position = Vector3(-centre.x, centre.y, -centre.z)   # model is rotated 180°
	add_child(shape)


func _fade_distance(geometry: GeometryInstance3D) -> void:
	geometry.visibility_range_end = CAR_SCENE_DISTANCE
	geometry.visibility_range_end_margin = 10.0
	geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _apply_paint(color: Color) -> void:
	var body_mesh := find_child("Body", true, false) as MeshInstance3D
	if body_mesh == null or body_mesh.mesh == null:
		return
	for i in body_mesh.mesh.get_surface_count():
		var original := body_mesh.mesh.surface_get_material(i) as BaseMaterial3D
		if original == null or not original.resource_name.begins_with("Body"):
			continue
		var paint_material := ShaderMaterial.new()
		paint_material.shader = _PAINT_SHADER
		paint_material.set_shader_parameter("albedo_tex", original.albedo_texture)
		var orm := original.roughness_texture
		paint_material.set_shader_parameter("has_orm", orm != null)
		if orm:
			paint_material.set_shader_parameter("orm_tex", orm)
		paint_material.set_shader_parameter("paint_color", color)
		body_mesh.set_surface_override_material(i, paint_material)


func _build_light_bar() -> void:
	var bar_base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.1, 0.08, 0.28)
	bar_base.mesh = base_mesh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	bar_base.material_override = dark
	bar_base.position = Vector3(0, _roof_height + 0.04, 0.1)
	add_child(bar_base)
	for i in 2:
		var lamp := MeshInstance3D.new()
		var lamp_mesh := BoxMesh.new()
		lamp_mesh.size = Vector3(0.5, 0.1, 0.24)
		lamp.mesh = lamp_mesh
		var lamp_material := StandardMaterial3D.new()
		lamp_material.albedo_color = Color(0.7, 0.08, 0.06) if i == 0 else Color(0.08, 0.2, 0.8)
		lamp_material.emission_enabled = true
		lamp_material.emission = lamp_material.albedo_color
		lamp_material.emission_energy_multiplier = 0.0
		lamp.material_override = lamp_material
		lamp.position = Vector3(-0.27 if i == 0 else 0.27, _roof_height + 0.13, 0.1)
		add_child(lamp)
		_light_bar.append(lamp)


# ------------------------------------------------------------------- driving

func can_enter() -> bool:
	return driver == null


func enter(player: PlayerController) -> void:
	if driver:
		return
	driver = player
	_entered_frame = Engine.get_physics_frames()
	# Taking an AI car (e.g. a pursuit unit): the AI lets go for good.
	ai_enabled = false
	ai_throttle = 0.0
	ai_reverse = 0.0
	ai_steer = 0.0
	siren_on = false
	var pilot := get_node_or_null("Pilot")
	if pilot:
		pilot.queue_free()
	sleeping = false
	contact_monitor = true
	set_process(true)
	if not has_been_stolen and Session.mode == Session.MODE_STORY:
		has_been_stolen = true
		var severity := WantedSystem.CRIME_POLICE_VEHICLE_THEFT if is_police else WantedSystem.CRIME_VEHICLE_THEFT
		WantedSystem.report_crime(severity, global_position)
	_cam_yaw_offset = 0.0
	_camera = Camera3D.new()
	_camera.fov = 74.0
	_camera.far = 800.0
	_camera.top_level = true
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # we place it from the interpolated car
	add_child(_camera)
	_camera.global_position = global_position - global_basis.z * 6.0 + Vector3.UP * 2.5
	_camera.make_current()
	if cam_view == CamView.INTERIOR and not bool(data.get("interior", false)):
		cam_view = CamView.HOOD
	_add_light_trails()
	_add_headlights()
	if _engine_sound == null:
		_engine_sound = Audio.loop(self, "engine_loop", -4.0)
	if _skid_sound == null:
		_skid_sound = Audio.loop(self, "skid", -6.0)
		if _skid_sound:
			_skid_sound.stream_paused = true
	player.start_driving(self)
	driver_entered.emit(player)


func exit() -> void:
	if driver == null:
		return
	var player := driver
	driver = null
	for wheel in _wheels:
		wheel.engine_force = 0.0
		wheel.brake = float(data["brake"]) * 0.5
	if _camera:
		_camera.queue_free()
		_camera = null
	for trail in _light_trails:
		if is_instance_valid(trail):
			trail.queue_free()
	_light_trails.clear()
	for lamp in _headlights:
		lamp.queue_free()
	_headlights.clear()
	if _blur_layer:
		_blur_layer.queue_free()
		_blur_layer = null
	for sound in [_engine_sound, _skid_sound]:
		if sound:
			sound.queue_free()
	_engine_sound = null
	_skid_sound = null
	contact_monitor = false
	set_process(false)
	player.stop_driving(_find_exit_spot(), atan2(global_basis.z.x, global_basis.z.z) + PI)
	driver_exited.emit(player)
	_set_light_bar(0.0)


## Driver's door first (the car's left = +X, since the body faces +Z), then
## passenger side, behind, in front, and finally the roof.
func _find_exit_spot() -> Vector3:
	var flat_x := Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()
	var flat_z := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	var candidates: Array[Vector3] = [
		global_position + flat_x * 1.9,
		global_position - flat_x * 1.9,
		global_position - flat_z * 3.4,
		global_position + flat_z * 3.4,
	]
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.85
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.collision_mask = WORLD_LAYER | VEHICLE_LAYER
	params.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	for spot in candidates:
		var feet := Vector3(spot.x, global_position.y + 0.2, spot.z)
		params.transform = Transform3D(Basis(), feet + Vector3.UP * 0.95)
		if space.intersect_shape(params, 1).is_empty():
			return feet
	return global_position + Vector3.UP * (_roof_height + 0.6)


## Orbit the chase camera (drag on the right side of the screen).
func add_look_input(delta_px: Vector2) -> void:
	_cam_yaw_offset = clampf(_cam_yaw_offset - delta_px.x * 0.006, -PI, PI)
	_cam_pitch = clampf(_cam_pitch + delta_px.y * 0.004, 0.05, 0.9)


func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


## Grenade hits in Street Race: brief loss of power and top speed.
func apply_slow(seconds: float) -> void:
	_slow_timer = maxf(_slow_timer, seconds)


func is_slowed() -> bool:
	return _slow_timer > 0.0


func take_vehicle_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	if health <= 0.0 and driver and not locked:
		exit()


func take_hit(damage: float, knockback: Vector3, _attacker: Node3D, _heavy: bool = false) -> void:
	if has_meta(&"remote_peer"):
		Net.send_damage(int(get_meta(&"remote_peer")), damage)
		return
	take_vehicle_damage(damage)
	apply_central_impulse(knockback * mass * 0.05)


func _physics_process(delta: float) -> void:
	_slow_timer = maxf(_slow_timer - delta, 0.0)
	if not _lamp_materials.is_empty() or not _headlights.is_empty():
		_update_lamps()
	_stabilize(delta)
	if driver == null and not ai_enabled:
		return
	if driver == null:
		_drive(delta, ai_throttle, ai_reverse, ai_steer, ai_handbrake)
		return
	driver.global_position = global_position + Vector3.UP * 0.5

	if Input.is_action_just_pressed(&"toggle_camera"):
		_next_cam_view()

	# Same press that got us in must not also get us out.
	if Input.is_action_just_pressed(&"interact") and Engine.get_physics_frames() != _entered_frame and not locked:
		exit()
		return
	if Input.is_action_just_pressed(&"grenade"):
		driver.use_vehicle_grenade()
	driver.send_state_from_vehicle(delta)

	_drive(delta, Input.get_action_strength(&"move_forward"), Input.get_action_strength(&"move_back"),
		Input.get_axis(&"move_right", &"move_left"), Input.is_action_pressed(&"jump"))
	if is_police:
		_siren_time += delta


## Civilian cars: keep each light's own colour (white heads, red tails) and
## make it glow at night while the car is driven or AI-driven.
func _setup_head_tail_lights() -> void:
	for s in _own_lights.mesh.get_surface_count():
		var base := _own_lights.mesh.surface_get_material(s) as StandardMaterial3D
		var lamp := (base.duplicate() if base else StandardMaterial3D.new()) as StandardMaterial3D
		lamp.emission_enabled = true
		lamp.emission = lamp.albedo_color
		lamp.emission_energy_multiplier = 0.0
		_own_lights.set_surface_override_material(s, lamp)
		_lamp_materials.append(lamp)


func _setup_optics_lamps() -> void:
	var body_mesh := find_child("Body", true, false) as MeshInstance3D
	if body_mesh == null or body_mesh.mesh == null:
		return
	for s in body_mesh.mesh.get_surface_count():
		var base := body_mesh.mesh.surface_get_material(s) as StandardMaterial3D
		if base == null or not base.resource_name.begins_with("Optics"):
			continue
		var lamp := base.duplicate() as StandardMaterial3D
		lamp.emission_enabled = true
		# Front lamps glow white, rear lamps red (models that don't say: white).
		lamp.emission = Color(1.0, 0.1, 0.06) if base.resource_name.contains("Rear") else Color(1.0, 0.95, 0.85)
		lamp.emission_energy_multiplier = 0.0
		body_mesh.set_surface_override_material(s, lamp)
		_lamp_materials.append(lamp)


func _update_lamps() -> void:
	var on := night if (driver or ai_enabled) else 0.0
	if absf(on - _lamps_on) < 0.05:
		return
	_lamps_on = on
	for lamp in _lamp_materials:
		lamp.emission_energy_multiplier = on * 4.0
	for spot in _headlights:
		spot.visible = on > 0.3


func _add_headlights() -> void:
	if not _headlights.is_empty() or _body_aabb.size == Vector3.ZERO:
		return
	var front_z := -_body_aabb.position.z   # model is rotated 180°: its -Z end is our +Z front
	for side in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(side * _body_aabb.size.x * 0.32, _body_aabb.position.y + _body_aabb.size.y * 0.4, front_z)
		spot.rotation = Vector3(deg_to_rad(-6.0), PI, 0.0)   # SpotLight shines along -Z; flip to face +Z
		spot.spot_range = 38.0
		spot.spot_angle = 32.0
		spot.light_energy = 3.0
		spot.light_color = Color(1.0, 0.94, 0.82)
		spot.shadow_enabled = false
		spot.visible = false
		add_child(spot)
		_headlights.append(spot)
	_lamps_on = -1.0


## Motion blur round the screen edges above 150 km/h (driven car only).
func _update_speed_fx(speed: float) -> void:
	var amount := clampf((speed - BLUR_FROM) / 14.0, 0.0, 1.0)
	if GameSettings.quality == GameSettings.QUALITY_LOW:
		amount = 0.0
	if amount <= 0.0:
		if _blur_layer:
			_blur_layer.visible = false
		return
	if _blur_layer == null:
		_blur_layer = CanvasLayer.new()
		_blur_layer.layer = 5   # under the HUD
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_blur_material = ShaderMaterial.new()
		_blur_material.shader = preload("res://assets/materials/shaders/speed_blur.gdshader")
		rect.material = _blur_material
		_blur_layer.add_child(rect)
		add_child(_blur_layer)
	_blur_layer.visible = true
	_blur_material.set_shader_parameter(&"amount", amount)


func _next_cam_view() -> void:
	var count: int = CamView.size() if bool(data.get("interior", false)) else int(CamView.INTERIOR)
	cam_view = ((int(cam_view) + 1) % count) as CamView
	_cam_yaw_offset = 0.0


## Anti-roll: keeps cars planted in hard corners (and rights them if they flip).
func _stabilize(delta: float) -> void:
	if freeze or sleeping:
		return
	var up := global_basis.y
	var forward := global_basis.z
	var speed := linear_velocity.length()
	# Counter roll angle and roll rate around the car's long axis.
	var roll := asin(clampf(global_basis.x.dot(Vector3.UP), -1.0, 1.0))
	var roll_rate := angular_velocity.dot(forward)
	# Positive roll = rotated +angle about forward, so push back the other way.
	apply_torque(-forward * (roll * 9.0 + roll_rate * 2.5) * mass)
	# Pitch damping (no wheelies / nose-dives)
	var pitch_rate := angular_velocity.dot(global_basis.x)
	apply_torque(-global_basis.x * pitch_rate * 1.5 * mass)
	# Downforce grows with speed
	# Capped so the springs never bottom out (that's what sank the cars).
	apply_central_force(-up * minf(speed * speed * 0.005, 7.0) * mass)
	# Upside down and stopped: flip back onto the wheels after a moment.
	if up.dot(Vector3.UP) < 0.35 and speed < 3.0:
		_upside_down_time += delta
		if _upside_down_time > 1.5:
			_upside_down_time = 0.0
			var heading := Vector3(forward.x, 0.0, forward.z).normalized()
			if heading.length() < 0.1:
				heading = Vector3.FORWARD
			global_transform = Transform3D(Basis.looking_at(-heading, Vector3.UP), global_position + Vector3.UP * 1.2)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			reset_physics_interpolation()
	else:
		_upside_down_time = 0.0


func _drive(delta: float, throttle: float, reverse: float, steer_input: float, handbrake: bool) -> void:
	if freeze:
		return
	var speed := forward_speed()
	var top_speed: float = data["top_speed"] * (0.55 if _slow_timer > 0.0 else 1.0) * ai_top_speed_scale
	var accel: float = data["accel"] * (0.4 if _slow_timer > 0.0 else 1.0)
	var decel: float = data["decel"]
	var forward := global_basis.z
	var grounded := 0
	for wheel in _wheels:
		if wheel.is_in_contact():
			grounded += 1

	# Drive by applying the acceleration directly as a force on the body:
	# predictable on every device, independent of Godot's wheel force units.
	var drive := 0.0     # m/s^2 along the car's forward axis
	var holding := false
	if throttle > 0.05:
		if speed < -0.5:
			drive = decel * throttle
		elif speed < top_speed:
			drive = accel * throttle * clampf(1.15 - speed / top_speed, 0.25, 1.0)
	elif reverse > 0.05:
		if speed > 0.5:
			drive = -decel * reverse
		elif speed > -top_speed * 0.3:
			drive = -accel * 0.55 * reverse
	else:
		drive = -signf(speed) * minf(1.2, absf(speed) * 2.0)   # coasting drag
		holding = absf(speed) < 0.4
	if grounded >= 2:
		apply_central_force(forward * drive * mass)
	# Air drag so cars settle at their top speed instead of creeping past it.
	apply_central_force(-linear_velocity * mass * 0.015)

	var hold_brake: float = data["brake"]
	for wheel in _wheels:
		wheel.engine_force = 0.0
		wheel.brake = hold_brake if holding else 0.0
		wheel.wheel_friction_slip = data["grip"]
	var side := global_basis.x
	var lateral := linear_velocity.dot(side)
	# Enter a drift: handbrake flick at speed. Stay in it while sliding.
	if handbrake and speed > 12.0:
		drifting = true
	elif drifting and (absf(lateral) < 1.2 or speed < 6.0):
		drifting = false
	if handbrake:
		for wheel in _rear_wheels:
			wheel.brake = hold_brake * (0.6 if drifting else 1.5)
			wheel.wheel_friction_slip = float(data["grip"]) * 0.45   # let the rear step out
	elif drifting:
		for wheel in _rear_wheels:
			wheel.wheel_friction_slip = float(data["grip"]) * 0.6
	if grounded >= 2:
		# Grip assist: bleed off sideways speed. While drifting, turn part of
		# it back into forward speed so a slide doesn't kill your momentum.
		var assist := DRIFT_GRIP if drifting else GRIP_ASSIST
		apply_central_force(-side * lateral * assist * mass)
		if drifting:
			apply_central_force(forward * absf(lateral) * 0.9 * mass * signf(speed))
			# Steering holds the angle; gas pushes it wider.
			apply_torque(Vector3.UP * steer_input * (1.6 + throttle * 1.2) * mass)
		var yaw_rate := angular_velocity.y
		var cap := DRIFT_YAW_MAX if drifting else 1.6
		if absf(yaw_rate) > cap:
			angular_velocity.y = signf(yaw_rate) * cap

	# Less steering lock at speed keeps the car controllable on a touchscreen.
	var speed_factor := clampf(absf(speed) / top_speed, 0.0, 1.0)
	var max_steer: float = float(data["steer"]) * lerpf(1.0, 0.35, speed_factor)
	_steer = move_toward(_steer, steer_input * max_steer, 3.6 * delta)
	for wheel in _front_wheels:
		wheel.steering = _steer
	_lay_skid_marks(speed, handbrake)
	if is_police and (siren_on and ai_enabled) != (_siren_sound != null):
		if _siren_sound:
			_siren_sound.queue_free()
			_siren_sound = null
		else:
			_siren_sound = Audio.loop(self, "siren_loop", -2.0)
	if ai_enabled and is_police and siren_on:
		_siren_time += delta
		_flash_lights()


## Rubber on the road when the rear steps out, the handbrake locks, or the
## tyres lose grip (Godot's skid info drops towards 0 as a wheel slides).
func _lay_skid_marks(speed: float, handbrake: bool) -> void:
	var lateral := absf(linear_velocity.dot(global_basis.x))
	var car_skidding := absf(speed) > 4.0 and (handbrake or drifting or lateral > 2.6)
	for wheel in _rear_wheels:
		var skidding := car_skidding or (absf(speed) > 6.0 and wheel.get_skidinfo() < 0.35)
		if not skidding or not wheel.is_in_contact():
			_skid_last.erase(wheel)
			continue
		# VehicleWheel3D's node follows the suspension, so the tyre touches
		# the road one radius below its centre.
		var point := wheel.global_position - global_basis.y * wheel.wheel_radius
		if not _skid_last.has(wheel):
			_skid_last[wheel] = point
			continue
		var last: Vector3 = _skid_last[wheel]
		if last.distance_squared_to(point) < 0.16:
			continue   # ~40 cm segments keep the buffer long-lived
		if _skids == null or not is_instance_valid(_skids):
			_skids = SkidMarks.instance(get_tree())
		if _skids:
			_skids.add_segment(last, point, global_basis.y, clampf(lateral / 6.0 + (0.5 if handbrake else 0.3), 0.3, 1.0))
		_skid_last[wheel] = point


func _add_light_trails() -> void:
	if not _light_trails.is_empty() or _body_aabb.size == Vector3.ZERO:
		return
	if GameSettings.quality == GameSettings.QUALITY_LOW:
		return   # save the GPU on low settings
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.12, 0.08, 0.85))
	ramp.set_color(1, Color(1.0, 0.05, 0.02, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	# The model is rotated 180°, so its +Z end (the rear) sits at car-space -Z.
	var rear_z := -_body_aabb.end.z + 0.05
	var height := _body_aabb.position.y + _body_aabb.size.y * 0.45
	for side in [-1.0, 1.0]:
		var trail := GPUTrail3D.new()
		trail.position = Vector3(side * _body_aabb.size.x * 0.36 - _body_aabb.get_center().x, height, rear_z)
		trail.scale = Vector3(1.0, 0.05, 1.0)   # the ribbon spans local ±Y: ~10 cm tall
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(trail)
		trail.length = 24
		trail.color_ramp = ramp_texture
		trail.visible = false
		trail.set_process(false)
		_light_trails.append(trail)


func _update_light_trails() -> void:
	var fast := absf(forward_speed()) > TRAIL_SPEED
	for trail in _light_trails:
		if trail.visible != fast:
			trail.visible = fast
			trail.set_process(fast)   # idle trails cost nothing
			if fast:
				trail.restart()   # don't draw a streak from where it last stopped


func _process(delta: float) -> void:
	_update_light_trails()
	if _engine_sound:
		# Rev with speed inside each "gear" so it climbs and drops like shifts.
		var v := absf(forward_speed())
		var in_gear := fmod(v, 14.0) / 14.0
		_engine_sound.pitch_scale = lerpf(_engine_sound.pitch_scale, 0.7 + in_gear * 0.9 + minf(v / 60.0, 0.5), clampf(delta * 6.0, 0.0, 1.0))
	if _skid_sound:
		var sliding := drifting or absf(linear_velocity.dot(global_basis.x)) > 3.0
		_skid_sound.stream_paused = not (sliding and linear_velocity.length() > 5.0)
	if _camera == null:
		return
	if is_police and driver:
		_flash_lights()

	var xf := get_global_transform_interpolated()   # smooth: no physics-tick stutter
	var speed := linear_velocity.length()
	_update_speed_fx(speed)
	match cam_view:
		CamView.HOOD, CamView.INTERIOR:
			var seat := Vector3(0.36, 1.12, 0.1) if cam_view == CamView.INTERIOR else Vector3(0.0, _roof_height * 0.82, _body_aabb.end.z * 0.2)
			_camera.global_position = xf * seat
			_camera.global_basis = xf.basis.rotated(xf.basis.y, PI + _cam_yaw_offset)
			_cam_yaw_offset = move_toward(_cam_yaw_offset, 0.0, delta * 0.8)
			_camera.fov = lerpf(_camera.fov, 78.0 + clampf(speed - 20.0, 0.0, 40.0) * 0.3, clampf(delta * 3.0, 0.0, 1.0))
			return
	var free := cam_view == CamView.FREE
	if not free and absf(_cam_yaw_offset) > 0.0:
		_cam_yaw_offset = move_toward(_cam_yaw_offset, 0.0, delta * 0.5)
	var car_yaw := atan2(xf.basis.z.x, xf.basis.z.z)
	var yaw := car_yaw + _cam_yaw_offset
	var base := 4.6 if cam_view == CamView.CLOSE else 7.5
	var distance := base + clampf(speed * 0.05, 0.0, 2.2)
	var pitch := _cam_pitch if free else (0.2 if cam_view == CamView.CLOSE else 0.3)
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var target := xf.origin - back * distance * cos(pitch) + Vector3.UP * (1.1 + distance * sin(pitch))
	_camera.global_position = _camera.global_position.lerp(target, clampf(delta * (12.0 if free else 7.0), 0.0, 1.0))
	_camera.look_at(xf.origin + Vector3.UP * 1.0, Vector3.UP)
	# Faster feel: widen the view with speed.
	_camera.fov = lerpf(_camera.fov, 72.0 + clampf(speed - 15.0, 0.0, 45.0) * 0.35, clampf(delta * 3.0, 0.0, 1.0))


func _set_light_bar(energy: float) -> void:
	for lamp in _light_bar:
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = energy
	if _lights_material:
		_lights_material.albedo_color = Color(0.3, 0.3, 0.35)
		_lights_material.emission = Color(0.3, 0.3, 0.35)
		_lights_material.emission_energy_multiplier = energy


func _flash_lights() -> void:
	var phase := fmod(_siren_time * 3.0, 1.0)
	for i in _light_bar.size():
		var on := (phase < 0.5) == (i == 0)
		(_light_bar[i].material_override as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.2
	if _lights_material:
		var red := phase < 0.5
		var color := Color(1.0, 0.1, 0.08) if red else Color(0.1, 0.25, 1.0)
		_lights_material.albedo_color = color
		_lights_material.emission = color
		_lights_material.emission_energy_multiplier = 5.0


func _on_body_entered(body: Node) -> void:
	var impact := linear_velocity.length()
	if impact > 7.0:
		Audio.play("crash", global_position, minf(impact * 0.3 - 6.0, 4.0))
	if impact < 6.0 or not body.has_method(&"take_hit"):
		return
	if body is PlayerController:
		return
	var push := linear_velocity.normalized() * minf(impact * 0.8, 14.0)
	body.call(&"take_hit", impact * 5.0, push, self, true)
