class_name FreeRoamMode
extends Node
## Free roam: parked cars to take, people on the sidewalks, a few street
## hustlers who'll square up if you get close, every service open.

var world: Node3D
var _peds: Array[Pedestrian] = []
var _ped_timer := 0.0
var _rng := RandomNumberGenerator.new()


func begin() -> void:
	_rng.seed = 77
	var city: City = world.get("city")
	# Parked cars along the curbs.
	var n := 0
	for b in city.buildings:
		if _rng.randf() > 0.35:
			continue
		var door: Vector3 = b["door"]
		var face: Vector3 = b["face"]
		var along := face.cross(Vector3.UP)
		var pos := door + face * 4.0 + along * _rng.randf_range(-8, 8) + Vector3.UP * 0.6
		var id: String = CarCatalog.STREET_CARS[_rng.randi() % CarCatalog.STREET_CARS.size()]
		if _rng.randf() < 0.08:
			id = CarCatalog.RACE_CARS[_rng.randi() % CarCatalog.RACE_CARS.size()]
		world.call("spawn_car", id, pos, atan2(along.x, along.z), CarCatalog.PAINTS[_rng.randi() % CarCatalog.PAINTS.size()])
		n += 1
		if n > 40:
			break
	var regions: Regions = world.get("regions")
	for i in range(0, regions.house_doors.size(), 3):
		var d := regions.house_doors[i]
		world.call("spawn_car", CarCatalog.STREET_CARS[_rng.randi() % CarCatalog.STREET_CARS.size()], d + Vector3(4, 0.6, 0), _rng.randf() * TAU, CarCatalog.PAINTS[_rng.randi() % CarCatalog.PAINTS.size()])
	# Nash's own ride next to him.
	world.call("spawn_car", "sport", Layout.PLAYER_START + Vector3(4, 0.4, 3), PI * 0.5, Color(0.08, 0.08, 0.09))
	# Hustlers on street corners.
	for spot in [Vector3(-80 + 12, Layout.CITY_Y, 120 + 12), Vector3(280 - 12, Layout.CITY_Y, -120 + 12), Vector3(160 + 12, Layout.CITY_Y, 0 - 12)]:
		for k in 2:
			var b := BotFighter.new()
			b.model_path = Humanoid.random_npc(_rng)
			b.max_health = 70.0
			b.skill = 0.4
			b.position = spot + Vector3(k * 1.5, 0.3, 0)
			b.set_meta(&"hustler", true)
			world.add_child(b)
			b.add_to_group(&"hustlers")
	(world.get("hud") as Hud).banner("LOOKOUT", "Free roam  •  ENTER near a car to drive  •  find the services", 4.0)


func _process(delta: float) -> void:
	_ped_timer -= delta
	if _ped_timer > 0.0:
		return
	_ped_timer = 1.0
	var player: Player = world.get("player")
	var focus := player.global_position
	var alive: Array[Pedestrian] = []
	for p in _peds:
		if is_instance_valid(p) and p.global_position.distance_to(focus) < 120.0:
			alive.append(p)
		elif is_instance_valid(p):
			p.queue_free()
	_peds = alive
	# Hustlers only wake up when you're close (no fights across the map).
	for node in get_tree().get_nodes_in_group(&"hustlers"):
		var b := node as BotFighter
		var near := b.global_position.distance_to(focus) < 9.0
		b.target = player if near else null
	if not Layout.CITY_RECT.has_point(Vector2(focus.x, focus.z)) or _peds.size() >= 14:
		return
	var city: City = world.get("city")
	for attempt in 5:
		var p: Vector3 = city.sidewalk_points[_rng.randi() % city.sidewalk_points.size()]
		var d := p.distance_to(focus)
		if d < 25.0 or d > 90.0:
			continue
		var ped := Pedestrian.new()
		ped.position = p
		for k in 4:
			ped.waypoints.append(city.sidewalk_points[_rng.randi() % city.sidewalk_points.size()])
		world.add_child(ped)
		_peds.append(ped)
		break
