class_name RemoteAvatar
extends CharacterBody3D
## Another player in a multiplayer match. Driven by the state packets their
## device sends (~15 Hz) and smoothed locally. Hitting it (bullets, punches,
## grenades, surge) forwards the damage to that player's device.

const PLAYER_LAYER := 2
const VEHICLE_LAYER := 32

var peer_id := 0
var display_name := "Player"
var team := ""

var _rig: CharacterRig
var _car_visual: Node3D
var _car_id := ""
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _car_target_pos := Vector3.ZERO
var _car_target_rot := Quaternion.IDENTITY
var _alive := true
var _in_vehicle := false
var _label: Label3D


func setup(id: int, info: Dictionary) -> void:
	peer_id = id
	display_name = str(info.get("name", "Player"))
	team = Session.team_of(id)
	name = "Remote_%d" % id


func _ready() -> void:
	add_to_group(&"remote_players")
	collision_layer = PLAYER_LAYER
	collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_rig = CharacterRig.new()
	add_child(_rig)
	var info: Dictionary = Net.players.get(peer_id, {})
	_rig.setup(str(info.get("character", "x_bot")))
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.2, 0)
	_label.font_size = 48
	_label.outline_size = 10
	_label.modulate = Color(0.55, 0.75, 1.0) if team == "police" else (Color(1.0, 0.55, 0.4) if team == "robbers" else Color(1, 1, 1))
	add_child(_label)
	_target_pos = global_position


func is_alive() -> bool:
	return _alive and not _in_vehicle


func is_in_vehicle() -> bool:
	return _in_vehicle


func apply_state(state: Dictionary) -> void:
	_target_pos = state.get("p", _target_pos)
	_target_yaw = state.get("y", _target_yaw)
	_alive = state.get("alive", true)
	_rig.armed = state.get("a", true)
	var clip: StringName = StringName(str(state.get("c", "idle")))
	_rig.play(clip, float(state.get("s", 1.0)))
	var car_id := str(state.get("v", ""))
	_in_vehicle = car_id != ""
	if car_id != _car_id:
		_set_car(car_id, state.get("vc", Color(0, 0, 0, 0)))
	if _in_vehicle:
		_car_target_pos = state.get("vp", _target_pos)
		_car_target_rot = state.get("vq", Quaternion.IDENTITY)
	_rig.visible = not _in_vehicle
	rotation.x = 0.0 if _alive else -PI * 0.5


func _physics_process(delta: float) -> void:
	var blend := clampf(delta * 12.0, 0.0, 1.0)
	global_position = global_position.lerp(_target_pos, blend)
	_rig.rotation.y = lerp_angle(_rig.rotation.y, _target_yaw, blend)
	if _car_visual:
		_car_visual.global_position = _car_visual.global_position.lerp(_car_target_pos, blend)
		_car_visual.quaternion = _car_visual.quaternion.slerp(_car_target_rot, blend)


func _set_car(car_id: String, paint: Color) -> void:
	_car_id = car_id
	if _car_visual:
		_car_visual.queue_free()
		_car_visual = null
	if car_id == "":
		return
	# A frozen car body: solid to bullets/grenades, not simulated locally.
	var car := preload("res://scenes/vehicles/car.tscn").instantiate() as DrivableCar
	car.vehicle_id = car_id
	car.paint = paint
	car.freeze = true
	car.remove_from_group(&"vehicles")
	car.set_meta(&"remote_peer", peer_id)
	car.top_level = true
	add_child(car)
	car.remove_from_group(&"vehicles")   # can't be entered
	_car_visual = car
	_car_visual.global_position = _target_pos


## Called by local bullets, punches, grenades, surge.
func take_hit(damage: float, knockback: Vector3, _attacker: Node3D, heavy: bool = false) -> void:
	if not _alive:
		return
	if Session.mode == Session.MODE_HEIST and team != "" and team == Session.team_of(multiplayer.get_unique_id()):
		return   # no friendly fire
	Net.send_damage(peer_id, damage, knockback)
	if heavy and _in_vehicle:
		Net.send_slow(peer_id, 2.5)
	Effects.impact(get_tree(), global_position + Vector3.UP * 1.2)
