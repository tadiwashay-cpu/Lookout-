class_name CameraRig
extends Camera3D
## The one gameplay camera.
##  FOOT    third person behind Nash (drag to look)
##  FIGHT   Def Jam framing: side-on to the line between Nash and his
##          opponent, low, both in shot
##  CAR     NFS chase cam (lags in turns, FOV rises with speed)
##  CINEMA  finisher orbit
## Shakes add up and decay; `shake_at` scales by distance.

enum Mode { FOOT, FIGHT, CAR, CINEMA }

static var _all: Array[CameraRig] = []

var mode := Mode.FOOT
var target: Node3D                # what we follow (Fighter or Car)
var opponent: Node3D              # FIGHT framing
var yaw := 0.0
var pitch := -0.22
var distance := 4.8
var _shake := 0.0
var _cinema_time := 0.0
var _cinema_center := Vector3.ZERO
var _smooth_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _car_yaw := 0.0
var base_fov := 70.0


func _ready() -> void:
	_all.append(self)
	fov = base_fov
	far = Game.view_distance + 300.0
	near = 0.08


func _exit_tree() -> void:
	_all.erase(self)


static func shake_all(amount: float) -> void:
	for c in _all:
		c._shake = minf(c._shake + amount, 2.0)


static func shake_at(pos: Vector3, amount: float) -> void:
	for c in _all:
		var d := c.global_position.distance_to(pos)
		c._shake = minf(c._shake + amount * clampf(1.0 - d / 60.0, 0.0, 1.0), 2.0)


func add_look(delta_px: Vector2) -> void:
	var s := 0.0045 * Game.look_sensitivity
	yaw -= delta_px.x * s
	pitch = clampf(pitch - delta_px.y * s, -1.1, 0.5)


func cinema(center: Vector3, seconds: float) -> void:
	mode = Mode.CINEMA
	_cinema_center = center
	_cinema_time = seconds


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	var want_pos: Vector3
	var look_at_pos: Vector3
	match mode:
		Mode.FOOT:
			var pivot := target.global_position + Vector3.UP * 1.6
			var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
			want_pos = pivot + dir * distance + global_basis.x * 0.0
			want_pos = _avoid_walls(pivot, want_pos)
			look_at_pos = pivot + Vector3.UP * 0.1
			fov = lerpf(fov, base_fov + (8.0 if target is Fighter and (target as Fighter)._foot_speed > 9.0 else 0.0), real_dt * 4.0)
		Mode.FIGHT:
			var a := target.global_position
			var b := opponent.global_position if opponent and is_instance_valid(opponent) else a + target.global_basis.z * 2.0
			var mid := (a + b) * 0.5
			var line := b - a
			line.y = 0.0
			var side := Vector3(-line.z, 0, line.x).normalized()
			# Stay on the side the camera is already on (no flips).
			var cam_flat := global_position - mid
			cam_flat.y = 0.0
			if side.dot(cam_flat) < 0.0:
				side = -side
			var spread := clampf(line.length(), 1.5, 8.0)
			want_pos = mid + side * (4.2 + spread * 0.7) + Vector3.UP * 1.6 - line.normalized() * 0.8
			look_at_pos = mid + Vector3.UP * 1.1
			yaw = atan2(want_pos.x - mid.x, want_pos.z - mid.z)
			fov = lerpf(fov, 62.0, real_dt * 3.0)
		Mode.CAR:
			var car := target as RigidBody3D
			var vel := car.linear_velocity
			var speed := vel.length()
			var heading := atan2(car.global_basis.z.x, car.global_basis.z.z)
			_car_yaw = lerp_angle(_car_yaw, heading, clampf(real_dt * 5.0, 0.0, 1.0))
			var behind := -Vector3(sin(_car_yaw + yaw), 0, cos(_car_yaw + yaw))
			want_pos = car.global_position + behind * (6.2 + speed * 0.02) + Vector3.UP * (2.1 + pitch * -2.0)
			look_at_pos = car.global_position + Vector3.UP * 1.0 + car.global_basis.z * 3.0
			fov = lerpf(fov, base_fov + clampf(speed * 0.35, 0.0, 22.0) + (8.0 if car.get("nitro_on") else 0.0), real_dt * 3.0)
			yaw = lerpf(yaw, 0.0, real_dt * 1.5)
		Mode.CINEMA:
			_cinema_time -= real_dt
			var ang := Time.get_ticks_msec() * 0.0008
			want_pos = _cinema_center + Vector3(cos(ang) * 3.4, 1.2, sin(ang) * 3.4)
			look_at_pos = _cinema_center + Vector3.UP * 1.0
			fov = lerpf(fov, 48.0, real_dt * 4.0)
			if _cinema_time <= 0.0:
				mode = Mode.FOOT
	_smooth_pos = _smooth_pos.lerp(want_pos, clampf(real_dt * (14.0 if mode == Mode.CAR else 10.0), 0.0, 1.0))
	if _smooth_pos.distance_to(want_pos) > 30.0:
		_smooth_pos = want_pos
	var shake_offset := Vector3.ZERO
	if _shake > 0.0:
		var s := _shake * _shake * 0.25
		shake_offset = Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), _rng.randf_range(-s, s))
		_shake = maxf(_shake - real_dt * 2.5, 0.0)
	global_position = _smooth_pos + shake_offset
	if global_position.distance_to(look_at_pos) > 0.1:
		look_at(look_at_pos + shake_offset * 0.5, Vector3.UP)


func _avoid_walls(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return to
	return (hit["position"] as Vector3) + (from - to).normalized() * 0.3
