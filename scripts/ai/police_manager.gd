class_name PoliceManager
extends Node
## Most-Wanted-style pursuit. Heat (WantedSystem stars) decides how many
## Crown Vic interceptors hunt you:
##   1 star: one car, cops tackle you on foot
##   2-3: more cars, cops shoot; 3+: roadblocks ahead of you
##   4-5: up to six units incl. black SUVs, very aggressive ramming
## Units are stubborn: a little faster than you, lead your path, box you
## in, and if you outrun them out of sight they get re-dispatched onto a
## road behind you. Stop near a cruiser for 3 s and you're BUSTED.
## Losing line of sight lets your heat cool (WantedSystem).

signal busted

const MAX_UNITS := [0, 1, 2, 3, 4, 6]
const SPAWN_MIN := 110.0
const SPAWN_MAX := 175.0
const RUBBERBAND := 230.0
const SEEN_RANGE := 110.0
const BUST_TIME := 3.0

var world: World
## >= 0 forces a heat level (solo heist); -1 follows WantedSystem.
var forced_stars := -1

var _units: Array[DrivableCar] = []
var _officers: Array[BotSoldier] = []
var _parked: Array[DrivableCar] = []   # roadblocks
var _spawn_cd := 1.0
var _roadblock_cd := 25.0
var _bust_timer := 0.0
var _seen_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func stars() -> int:
	return forced_stars if forced_stars >= 0 else WantedSystem.stars


func _physics_process(delta: float) -> void:
	var player := world.player
	if player == null:
		return
	_prune()
	var heat := stars()
	var focus := player.current_vehicle.global_position if player.current_vehicle else player.global_position

	if heat == 0:
		_stand_down(focus)
		_bust_timer = 0.0
		return

	_spawn_cd -= delta
	if _units.size() < MAX_UNITS[heat] and _spawn_cd <= 0.0:
		_spawn_cd = 3.5
		_dispatch(focus, heat)

	var target: Node3D = player.current_vehicle if player.current_vehicle else player
	var any_close := false
	for i in _units.size():
		var unit := _units[i]
		var pilot := unit.get_node_or_null("Pilot") as CarPilot
		if pilot == null:
			continue
		var dist := unit.global_position.distance_to(focus)
		pilot.aggression = 1.0 + heat * 0.25
		pilot.slot_offset = [-1.0, 1.0, 0.0, -0.6, 0.6, 0.0][i % 6]
		unit.ai_top_speed_scale = 1.06 + heat * 0.03
		if player.current_vehicle == null and dist < 28.0:
			# Suspect on foot: pull up and send officers out.
			pilot.target = null
			pilot.hold = true
			if not unit.has_meta(&"deployed"):
				unit.set_meta(&"deployed", true)
				_deploy_officers(unit, heat)
		else:
			pilot.hold = false
			pilot.target = target
		if dist > RUBBERBAND and not _on_screen(unit.global_position):
			_reposition(unit, focus)
		if dist < 9.0:
			any_close = true

	# Busted: barely moving with a cruiser (or an officer) right on you.
	var my_speed := player.current_vehicle.linear_velocity.length() if player.current_vehicle else Vector3(player.velocity.x, 0, player.velocity.z).length()
	var officer_close := false
	for officer in _officers:
		if officer.global_position.distance_to(focus) < 2.5:
			officer_close = true
	if (any_close and my_speed < 2.5) or (officer_close and heat <= 2 and my_speed < 1.5):
		_bust_timer += delta
		if _bust_timer > BUST_TIME:
			_bust_timer = 0.0
			_do_bust()
			return
	else:
		_bust_timer = maxf(_bust_timer - delta * 2.0, 0.0)

	# Line of sight keeps the heat from cooling.
	_seen_timer -= delta
	if _seen_timer <= 0.0:
		_seen_timer = 0.5
		WantedSystem.set_seen_by_police(_anyone_sees(focus))

	if heat >= 3:
		_roadblock_cd -= delta
		if _roadblock_cd <= 0.0 and player.current_vehicle:
			_roadblock_cd = 40.0 - heat * 4.0
			_roadblock(player.current_vehicle)


## Drop units that were destroyed, stolen by the player, or officers that died.
func _prune() -> void:
	var units: Array[DrivableCar] = []
	for unit in _units:
		if is_instance_valid(unit) and unit.driver == null:
			units.append(unit)
	_units = units
	var officers: Array[BotSoldier] = []
	for officer in _officers:
		if is_instance_valid(officer) and officer.is_alive():
			officers.append(officer)
	_officers = officers


func busting_progress() -> float:
	return _bust_timer / BUST_TIME


# ---------------------------------------------------------------- spawning

func _dispatch(focus: Vector3, heat: int) -> void:
	var spot := _pick_spawn(focus)
	if spot == Vector3.INF:
		return
	var heavy := heat >= 4 and _rng.randf() < 0.35
	var to_player := focus - spot
	var car := world.spawn_car("police_suv" if heavy else "police_sedan", spot, atan2(to_player.x, to_player.z))
	car.has_been_stolen = true
	car.add_to_group(&"police")
	var pilot := CarPilot.new()
	pilot.name = "Pilot"
	car.add_child(pilot)
	_units.append(car)


func _pick_spawn(focus: Vector3) -> Vector3:
	var points := world.road_points()
	var player := world.player
	var heading := Vector3.ZERO
	if player.current_vehicle:
		heading = player.current_vehicle.linear_velocity
	heading.y = 0.0
	for attempt in 30:
		var p: Vector3 = points[_rng.randi() % points.size()]
		var d := p.distance_to(focus)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		if _on_screen(p):
			continue
		# Prefer behind the suspect (they come from where you've been).
		if heading.length() > 5.0 and heading.normalized().dot((p - focus).normalized()) > 0.4 and attempt < 20:
			continue
		return p + Vector3.UP * 0.6
	return Vector3.INF


func _reposition(unit: DrivableCar, focus: Vector3) -> void:
	var spot := _pick_spawn(focus)
	if spot == Vector3.INF:
		return
	var to_player := focus - spot
	unit.global_transform = Transform3D(Basis(Vector3.UP, atan2(to_player.x, to_player.z)), spot)
	unit.linear_velocity = (focus - spot).normalized() * 12.0
	unit.angular_velocity = Vector3.ZERO


func _deploy_officers(unit: DrivableCar, heat: int) -> void:
	for side: float in [-1.0, 1.0]:
		var officer := BotSoldier.new()
		officer.team = "police"
		officer.display_name = "Police"
		officer.melee_only = heat <= 1
		officer.weapon_id = "glock17" if heat <= 2 else "m4a1"
		officer.tint_colors = [Color(0.55, 0.42, 0.33), Color(0.07, 0.1, 0.22)]
		officer.accuracy = 0.55 + heat * 0.06
		officer.position = unit.global_position + unit.global_basis.x * side * 2.2 + Vector3.UP * 0.3
		world.add_child(officer)
		officer.add_to_group(&"police")
		_officers.append(officer)


func _roadblock(target_car: DrivableCar) -> void:
	var velocity := target_car.linear_velocity
	velocity.y = 0.0
	if velocity.length() < 8.0:
		return
	var ahead := target_car.global_position + velocity.normalized() * 150.0
	var best := Vector3.INF
	var best_d := 60.0
	for p: Vector3 in world.road_points():
		var d := p.distance_to(ahead)
		if d < best_d and not _on_screen(p):
			best_d = d
			best = p
	if best == Vector3.INF:
		return
	var across := Vector3(-velocity.z, 0.0, velocity.x).normalized()
	for side: float in [-1.0, 1.0]:
		var car := world.spawn_car("police_sedan", best + across * side * 4.0 + Vector3.UP * 0.5, atan2(across.x, across.z))
		car.has_been_stolen = true
		car.siren_on = true
		car.add_to_group(&"police")
		_parked.append(car)


# ---------------------------------------------------------------- outcomes

func _do_bust() -> void:
	var player := world.player
	if player.current_vehicle:
		player.current_vehicle.exit()
	var fine := mini(500, GameSettings.money / 10)
	GameSettings.add_money(-fine)
	busted.emit()
	world.hud.show_banner("BUSTED", 3.0)
	if fine > 0:
		world.hud.show_hint("Fined $%d" % fine)
	WantedSystem.clear()
	player.respawn_at(world.precinct_position + Vector3(0, 0.4, -6.0))
	_clear_all()


func _stand_down(focus: Vector3) -> void:
	for unit in _units:
		var pilot := unit.get_node_or_null("Pilot") as CarPilot
		if pilot:
			pilot.target = null
			pilot.hold = true
		unit.siren_on = false
		if unit.global_position.distance_to(focus) > 120.0 and not _on_screen(unit.global_position):
			unit.queue_free()
	for officer in _officers:
		if officer.global_position.distance_to(focus) > 60.0:
			officer.queue_free()
	for car in _parked:
		if is_instance_valid(car) and car.global_position.distance_to(focus) > 150.0:
			car.queue_free()


func _clear_all() -> void:
	for unit in _units:
		unit.queue_free()
	for officer in _officers:
		officer.queue_free()
	for car in _parked:
		if is_instance_valid(car):
			car.queue_free()
	_units.clear()
	_officers.clear()
	_parked.clear()


func _anyone_sees(focus: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var watchers: Array[Node3D] = []
	for unit in _units:
		watchers.append(unit)
	for officer in _officers:
		watchers.append(officer)
	for watcher in watchers:
		var from := watcher.global_position + Vector3.UP * 1.4
		if from.distance_to(focus) > SEEN_RANGE:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, focus + Vector3.UP * 1.0, 1)
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _on_screen(point: Vector3) -> bool:
	var camera := world.get_viewport().get_camera_3d()
	return camera != null and camera.is_position_in_frustum(point) and camera.global_position.distance_to(point) < 220.0
