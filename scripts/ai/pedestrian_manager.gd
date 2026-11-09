class_name PedestrianManager
extends Node
## Keeps a small crowd of pedestrians around the player in the city and
## suburb (spawned out of view 30-80 m away, removed beyond 110 m).

const MAX_PEDS := 12

var world: World
var _peds: Array[Pedestrian] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or world.player == null:
		return
	_timer = 1.0
	var focus := world.player.global_position
	var alive: Array[Pedestrian] = []
	for ped in _peds:
		if not is_instance_valid(ped):
			continue
		if ped.global_position.distance_to(focus) > 110.0:
			ped.queue_free()
			continue
		alive.append(ped)
	_peds = alive
	var in_town := WorldCity.HALF_X > absf(focus.x) and WorldCity.HALF_Z > absf(focus.z) or WorldRegions.SUBURB_RECT.has_point(Vector2(focus.x, focus.z))
	if not in_town or _peds.size() >= MAX_PEDS:
		return
	for attempt in 6:
		var angle := _rng.randf() * TAU
		var p := focus + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(30.0, 80.0)
		if not _is_walkable(p):
			continue
		var camera := world.get_viewport().get_camera_3d()
		if camera and camera.is_position_in_frustum(p) and camera.global_position.distance_to(p) < 45.0:
			continue
		var ped := Pedestrian.new()
		ped.position = p + Vector3.UP * 0.3
		world.add_child(ped)
		_peds.append(ped)
		return


## On a sidewalk-ish spot: inside the town and not inside a building.
func _is_walkable(p: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.position = p + Vector3.UP * 1.0
	query.collision_mask = 1 | 32
	return space.intersect_point(query, 1).is_empty()
