class_name RaceDriver
extends Node
## AI racer: follows the route with a look-ahead point, brakes for bends it
## can see coming, uses nitro on straights and its weapons on rivals.

var route: Array[Vector3] = []
var skill := 0.7
var race: RaceMode
var car: Car
var _i := 0
var _lane := 0.0
var _weapon_cd := 4.0
var _stuck := 0.0
var _reverse := 0.0


func _ready() -> void:
	car = get_parent() as Car
	car.ai_enabled = true
	_lane = randf_range(-3.0, 3.0)
	var best := INF
	for k in route.size():
		var d := route[k].distance_to(car.global_position)
		if d < best:
			best = d
			_i = k


func _physics_process(delta: float) -> void:
	if car.wrecked or car.freeze or race == null or not race.running:
		car.in_throttle = 0.0
		return
	# Track the nearest route point in a window ahead (a wide line never
	# leaves us chasing a point behind the car).
	var best := _i
	var best_d := INF
	for k in 40:
		var j := (_i + k) % route.size()
		var d := route[j].distance_squared_to(car.global_position)
		if d < best_d:
			best_d = d
			best = j
	_i = best
	var speed := car.forward_speed()
	var look := clampi(int(speed * 0.35) + 3, 3, 22)
	var target := route[(_i + look) % route.size()]
	var dir := (route[(_i + look + 1) % route.size()] - target).normalized()
	target += Vector3(-dir.z, 0, dir.x) * _lane
	var local := car.global_basis.inverse() * (target - car.global_position)
	var angle := atan2(local.x, local.z)
	# Bend ahead: angle between now and far ahead.
	var far := route[(_i + look * 2) % route.size()]
	var here_dir := car.global_basis.z
	var far_dir := (far - car.global_position).normalized()
	var bend := here_dir.angle_to(far_dir)
	var corner_speed: float = lerpf(float(car.data["top"]), 16.0, clampf(bend / 1.2, 0.0, 1.0)) * lerpf(0.75, 1.0, skill)
	if Time.get_ticks_msec() < int(car.get_meta(&"stun_until", 0)):
		car.in_throttle = 0.0
		car.in_brake = 0.0
		return
	if _reverse > 0.0:
		_reverse -= delta
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.in_steer = -signf(angle)
		return
	car.in_steer = clampf(angle * 2.0, -1.0, 1.0)
	car.in_throttle = 1.0 if speed < corner_speed else 0.0
	car.in_brake = 0.6 if speed > corner_speed + 6.0 else 0.0
	car.in_handbrake = bend > 1.1 and speed > 25.0
	car.in_nitro = bend < 0.15 and speed > 20.0 and car.nitro > 0.3 and skill > 0.5
	if car.in_throttle > 0.5 and absf(speed) < 1.5:
		_stuck += delta
		if _stuck > 1.5:
			_stuck = 0.0
			_reverse = 1.0
	else:
		_stuck = 0.0
	_weapon_cd -= delta
	if _weapon_cd <= 0.0:
		_weapon_cd = randf_range(5.0, 10.0) / maxf(skill, 0.3)
		for r in race.racers:
			var other: Car = r["car"]
			if other == null or other == car or not is_instance_valid(other):
				continue
			var off := other.global_position - car.global_position
			if off.length() < 12.0:
				race.car_surge(car)
				break
			if off.length() < 45.0 and car.global_basis.z.dot(off.normalized()) > 0.85:
				race.throw_grenade(car)
				break
