class_name StreetRaceMode
extends GameMode
## Point-to-point race over the big map (city edge -> highway -> forest ->
## suburb, or the reverse — picked by the match seed). Everyone is locked
## into a race car; GRENADE lobs one behind you to slow the chasers.
## Race-only cars can be added to VehicleCatalog later; for now everyone
## gets the same S-class car so it's fair.

const CHECKPOINT_SPACING := 140.0
const CHECKPOINT_RADIUS := 15.0
const RACE_CAR := "sport"

var _checkpoints: Array[Vector3] = []
var _next := 0
var _time := 0.0
var _started := false
var _car: DrivableCar
var _rings: Array[MeshInstance3D] = []
var _results: Array = []          # [{"name", "time"}]
var _finish_deadline := -1.0
var _bots: Array[DrivableCar] = []
var _bot_done: Dictionary = {}
const BOT_RACERS := 3


func begin() -> void:
	_build_route()
	var grid_index := 0
	if Session.networked:
		var ids: Array = Net.players.keys()
		ids.sort()
		grid_index = ids.find(Session.my_id())
	var start := _checkpoints[0]
	var forward := (_checkpoints[1] - start).normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var pos := start - forward * (8.0 + (grid_index / 2) * 9.0) + right * (3.5 if grid_index % 2 == 0 else -3.5)
	pos.y = world.ground_height(pos.x, pos.z) + 0.6
	_car = world.spawn_car(RACE_CAR, pos, atan2(forward.x, forward.z), Color.from_hsv(fmod(grid_index * 0.17, 1.0), 0.55, 0.55))
	_car.locked = true
	_car.has_been_stolen = true
	_car.freeze = true
	player().refill_grenades(6)
	player().grenade_cooldown = 3.0
	_build_rings()
	Net.match_event.connect(_on_event)
	if not Session.networked:
		_spawn_bot_racers(start, forward, right)
	_countdown()


func _build_route() -> void:
	var path: Array[Vector3] = []
	for p in world.regions.highway_samples:
		path.append(p)
	for p in world.regions.forest_road_samples:
		path.append(p)
	var suburb_end := Vector3(WorldRegions.SUBURB_RECT.position.x + 30.0, 0.3, WorldRegions.SUBURB_MAIN_Z)
	path.append(suburb_end)
	if Session.match_rng(5).randf() < 0.5:
		path.reverse()
	_checkpoints.append(path[0])
	var travelled := 0.0
	for i in range(1, path.size()):
		travelled += path[i].distance_to(path[i - 1])
		if travelled >= CHECKPOINT_SPACING:
			_checkpoints.append(path[i])
			travelled = 0.0
	if _checkpoints[_checkpoints.size() - 1] != path[path.size() - 1]:
		_checkpoints.append(path[path.size() - 1])
	for i in _checkpoints.size():
		_checkpoints[i].y = world.ground_height(_checkpoints[i].x, _checkpoints[i].z) + 0.4


func _spawn_bot_racers(start: Vector3, forward: Vector3, right: Vector3) -> void:
	var rng := Session.match_rng(21)
	var route: Array[Vector3] = []
	for i in range(1, _checkpoints.size()):
		route.append(_checkpoints[i])
	for i in BOT_RACERS:
		var slot := i + 1
		var pos := start - forward * (8.0 + (slot / 2) * 9.0) + right * (3.5 if slot % 2 == 0 else -3.5)
		pos.y = world.ground_height(pos.x, pos.z) + 0.6
		var car := world.spawn_car(RACE_CAR, pos, atan2(forward.x, forward.z), Color.from_hsv(fmod(slot * 0.17, 1.0), 0.55, 0.55))
		car.has_been_stolen = true
		car.freeze = true
		car.set_meta(&"racer_name", ["Ace", "Blaze", "Cruz"][i])
		var pilot := CarPilot.new()
		pilot.name = "Pilot"
		pilot.route = route
		pilot.skill = rng.randf_range(0.85, 1.05)
		pilot.aggression = 1.3
		car.add_child(pilot)
		_bots.append(car)


func _build_rings() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = CHECKPOINT_RADIUS - 1.2
	torus.outer_radius = CHECKPOINT_RADIUS
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.75, 0.25, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(1, _checkpoints.size()):
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = material
		var dir := (_checkpoints[i] - _checkpoints[i - 1]).normalized()
		ring.basis = Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, 0.0) * Basis(Vector3.RIGHT, PI * 0.5)
		ring.position = _checkpoints[i] + Vector3.UP * 4.0
		ring.visible = false
		world.add_child(ring)
		_rings.append(ring)
	_show_rings()


func _show_rings() -> void:
	for i in _rings.size():
		_rings[i].visible = i == _next or i == _next + 1


func _countdown() -> void:
	await get_tree().process_frame
	_car.enter(player())
	for n in [3, 2, 1]:
		hud().show_banner(str(n), 0.6, 120)
		await get_tree().create_timer(1.0).timeout
	hud().show_banner("GO!", 0.8, 120)
	_car.freeze = false
	for bot in _bots:
		bot.freeze = false
	_started = true


func _process(delta: float) -> void:
	if not _started or finished:
		return
	_time += delta
	for i in _bots.size():
		var bot := _bots[i]
		if _bot_done.has(i) or not is_instance_valid(bot):
			continue
		var pilot := bot.get_node_or_null("Pilot") as CarPilot
		if pilot and pilot.route_index >= pilot.route.size() - 1 and bot.global_position.distance_to(pilot.route[pilot.route.size() - 1]) < CHECKPOINT_RADIUS + 4.0:
			_bot_done[i] = true
			_on_event("race_finish", {"name": str(bot.get_meta(&"racer_name")), "time": _time, "sender": -(i + 1)})
	if _next < _rings.size():
		var target := _checkpoints[_next + 1]
		if _car.global_position.distance_to(target) < CHECKPOINT_RADIUS + 3.0:
			_next += 1
			GameSettings.vibrate(20)
			_show_rings()
			if _next >= _rings.size():
				Net.send_event("race_finish", {"name": GameSettings.player_name, "time": _time})
	set_status("Checkpoint %d/%d   •   %s   •   Grenades %d" % [mini(_next + 1, _rings.size()), _rings.size(), _fmt(_time), player().grenades])
	if _finish_deadline > 0.0 and _time > _finish_deadline:
		_finish()


func _on_event(kind: String, data: Dictionary) -> void:
	if kind != "race_finish":
		return
	_results.append({"name": str(data.get("name", "?")), "time": float(data.get("time", 0.0)), "peer": int(data.get("sender", 0))})
	_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	if _finish_deadline < 0.0:
		_finish_deadline = _time + 45.0
	var expected := Net.players.size() if Session.networked else 1 + _bots.size()
	if _results.size() >= expected:
		_finish()


func _finish() -> void:
	var lines := PackedStringArray()
	var my_place := 0
	for i in _results.size():
		var r: Dictionary = _results[i]
		lines.append("%d. %s  %s" % [i + 1, r["name"], _fmt(r["time"])])
		if int(r["peer"]) == Session.my_id() and my_place == 0:
			my_place = i + 1
	var won := my_place == 1
	hud().show_hint("\n".join(lines))
	end_match("YOU WIN" if won else ("FINISHED #%d" % my_place if my_place > 0 else "DID NOT FINISH"), won, 700 if won else (200 if my_place > 0 else 0))


func minimap_markers() -> Array:
	if _next + 1 < _checkpoints.size():
		return [{"pos": _checkpoints[_next + 1], "color": Color(1.0, 0.8, 0.3), "kind": "objective"}]
	return []


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
