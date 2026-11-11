class_name TrafficManager
extends Node
## Civilian traffic: a few cars drive the city's main streets near the player,
## keep to their lane, turn at junctions and wait behind anything in front.
## A car you take over simply stops being traffic.

const LANE := 3.6            # metres right of the street's centre line
const CRUISE := 13.0         # m/s

var world: World
var max_cars := 6
var _cars: Array[Dictionary] = []   # {"car", "pilot", "from", "to"}
var _tick := 0.0
var _spawn_tick := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	max_cars = 4 if GameSettings.quality == GameSettings.QUALITY_LOW else 6


func _lane_point(from: Vector2, to: Vector2, at: Vector2, back: float) -> Vector3:
	var dir := (to - from).normalized()
	var right := Vector2(-dir.y, dir.x)
	var p := at + right * LANE - dir * back
	return Vector3(p.x, 0.4, p.y)


func _process(delta: float) -> void:
	var city := world.imported_city
	if city == null or city.traffic_nodes.size() < 2 or world.player == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	var focus := world.player.current_vehicle.global_position if world.player.current_vehicle else world.player.global_position
	var kept: Array[Dictionary] = []
	for entry in _cars:
		var car := entry["car"] as DrivableCar
		var pilot := entry["pilot"] as CarPilot
		if not is_instance_valid(car):
			continue
		if car.driver != null or car.wrecked:
			if is_instance_valid(pilot):
				pilot.queue_free()
			car.ai_enabled = false
			car.ai_top_speed_scale = 1.0
			continue
		if car.global_position.distance_to(focus) > 280.0:
			car.queue_free()
			continue
		# Next street at the junction ahead.
		var to: int = entry["to"]
		var goal := city.traffic_nodes[to]
		if Vector2(car.global_position.x, car.global_position.z).distance_to(goal) < 22.0:
			var options: Array = (city.traffic_links[to] as Array).duplicate()
			if options.size() > 1:
				options.erase(entry["from"])
			var next: int = options[_rng.randi() % options.size()]
			entry["from"] = to
			entry["to"] = next
			pilot.route = [_lane_point(goal, city.traffic_nodes[next], goal, -14.0), _lane_point(goal, city.traffic_nodes[next], city.traffic_nodes[next], 16.0)]
			pilot.route_index = 0
		# Wait behind whatever is in the lane ahead.
		var ahead := car.global_basis.z
		var blocked := false
		for node in get_tree().get_nodes_in_group(&"vehicles") + [world.player]:
			var other := node as Node3D
			if other == car or other == null:
				continue
			var offset := other.global_position - car.global_position
			var forward := offset.dot(ahead)
			if forward > 2.5 and forward < 13.0 and absf(offset.dot(car.global_basis.x)) < 2.4:
				blocked = true
				break
		pilot.hold = blocked
		kept.append(entry)
	_cars = kept
	_spawn_tick -= 0.2
	if _spawn_tick <= 0.0 and _cars.size() < max_cars:
		_spawn_tick = 1.5
		_spawn(focus)


func _spawn(focus: Vector3) -> void:
	var city := world.imported_city
	for attempt in 8:
		var from := _rng.randi() % city.traffic_nodes.size()
		var links: Array = city.traffic_links[from]
		if links.is_empty():
			continue
		var to: int = links[_rng.randi() % links.size()]
		var a := city.traffic_nodes[from]
		var b := city.traffic_nodes[to]
		var at := a.lerp(b, _rng.randf_range(0.2, 0.7))
		var pos := _lane_point(a, b, at, 0.0)
		var distance := pos.distance_to(focus)
		if distance < 70.0 or distance > 230.0:
			continue
		var camera := get_viewport().get_camera_3d()
		if camera and camera.is_position_in_frustum(pos) and distance < 120.0:
			continue
		var clear := true
		for node in get_tree().get_nodes_in_group(&"vehicles"):
			if (node as Node3D).global_position.distance_to(pos) < 12.0:
				clear = false
		if not clear:
			continue
		var dir := (b - a).normalized()
		var id := VehicleCatalog.pick_civilian(_rng)
		var car := world.spawn_car(id, pos, atan2(dir.x, dir.y), VehicleCatalog.random_paint(_rng))
		car.ai_top_speed_scale = CRUISE / maxf(float(car.data["top_speed"]), 1.0)
		var pilot := CarPilot.new()
		pilot.route = [_lane_point(a, b, b, 16.0)]
		pilot.skill = 0.7
		car.add_child(pilot)
		_cars.append({"car": car, "pilot": pilot, "from": from, "to": to})
		return
