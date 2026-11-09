class_name CarPilot
extends Node
## Drives its parent DrivableCar. Two jobs:
##  * chase: hunt a target (player on foot or their car), leading it, and
##    ram/box it when close (police)
##  * route: follow a list of points (race bots)
## Unsticks itself by reversing; the car's own stabiliser stops rollovers.

var car: DrivableCar
var target: Node3D                 # chase target (PlayerController or a car)
var route: Array[Vector3] = []
var route_index := 0
var aggression := 1.0              # 1 = normal, >1 = rams harder, brakes later
var slot_offset := 0.0             # lateral offset when boxing in (-1..1)
var skill := 1.0                   # race bots: corner speed / line quality
var hold := false                  # pull over and stop (police deploying / standing down)

var _stuck_time := 0.0
var _reverse_time := 0.0


func _ready() -> void:
	car = get_parent() as DrivableCar
	car.ai_enabled = true
	car.sleeping = false
	car.siren_on = car.is_police


func _physics_process(delta: float) -> void:
	if car == null or car.driver != null or car.freeze:
		return
	if hold:
		car.ai_throttle = 0.0
		car.ai_reverse = 0.6 if car.forward_speed() > 1.0 else 0.0
		car.ai_steer = 0.0
		car.ai_handbrake = false
		return
	var goal := _goal()
	var to_goal := goal - car.global_position
	to_goal.y = 0.0
	var local := car.global_basis.inverse() * to_goal
	# Car body drives +Z; +X is its left. Positive steer = left.
	var angle := atan2(local.x, local.z)
	var speed := car.forward_speed()
	var distance := to_goal.length()

	if _reverse_time > 0.0:
		_reverse_time -= delta
		car.ai_throttle = 0.0
		car.ai_reverse = 1.0
		car.ai_steer = -signf(angle)
		car.ai_handbrake = false
		return

	car.ai_steer = clampf(angle * 2.2, -1.0, 1.0)
	var sharp := absf(angle) > 0.9
	# Straights: full car top speed. Corners: slow down with the turn angle.
	var straight_cap: float = float(car.data["top_speed"]) * car.ai_top_speed_scale
	var corner_speed := straight_cap
	if absf(angle) > 0.35:
		corner_speed = minf(straight_cap, lerpf(32.0, 9.0, clampf(absf(angle) / 1.4, 0.0, 1.0)) * skill * (1.0 + (aggression - 1.0) * 0.3))
	if absf(angle) > 2.3 and distance < 30.0:
		# Target is behind and close: reverse-turn instead of a huge circle.
		car.ai_throttle = 0.0
		car.ai_reverse = 1.0
		car.ai_steer = -car.ai_steer
	elif speed > corner_speed:
		car.ai_throttle = 0.0
		car.ai_reverse = 0.6 if speed > corner_speed + 6.0 else 0.0
	else:
		car.ai_throttle = 1.0
		car.ai_reverse = 0.0
	car.ai_handbrake = sharp and speed > 14.0 and aggression > 1.2

	# Stuck against something: back out.
	if car.ai_throttle > 0.5 and absf(speed) < 1.2:
		_stuck_time += delta
		if _stuck_time > 1.6:
			_stuck_time = 0.0
			_reverse_time = 1.2
	else:
		_stuck_time = 0.0

	if not route.is_empty() and distance < 16.0:
		route_index = mini(route_index + 1, route.size() - 1)


func _goal() -> Vector3:
	if target and is_instance_valid(target):
		var pos := target.global_position
		var velocity := Vector3.ZERO
		if target is RigidBody3D:
			velocity = (target as RigidBody3D).linear_velocity
		elif target is CharacterBody3D:
			velocity = (target as CharacterBody3D).velocity
		var distance := pos.distance_to(car.global_position)
		# Lead the target; up close aim at a slot beside its rear (PIT / box-in).
		var lead := clampf(distance / 30.0, 0.0, 1.5)
		var goal := pos + velocity * lead
		if distance < 25.0 and velocity.length() > 4.0:
			var heading := velocity.normalized()
			var side := Vector3(-heading.z, 0.0, heading.x)
			goal = pos + heading * 2.0 * aggression + side * slot_offset * 2.2
		return goal
	if not route.is_empty():
		return route[route_index]
	return car.global_position + car.global_basis.z * 10.0
