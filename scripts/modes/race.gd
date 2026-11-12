class_name RaceMode
extends Node
## Street race for up to 8: the grand loop from downtown, through the
## harbour, over the mountain pass, down through the suburbs and the forest
## and back. Throw grenades (G / GRENADE) and fire power surges (Q / SURGE)
## at rivals. Wreck your car and it explodes; you're back on the road where
## you died three seconds later.

const PRIZES := [5000, 3000, 2000, 1200, 800, 600, 400, 300]
const CP_SPACING := 90.0

var world: Node3D
var player: Player
var route: Array[Vector3] = []
var checkpoints: Array[int] = []      # indices into route
var laps := 1
var racers: Array[Dictionary] = []    # {"id", "name", "car", "cp", "lap", "done", "time", "local", "bot"}
var my_car: Car
var running := false
var race_time := 0.0
var grenades := 3
var surge := 0.0
var sync: NetSync
var _finish_order: Array = []
var _gate: MeshInstance3D
var _net_tick := 0.0


func begin() -> void:
	player = world.get("player")
	laps = int(Game.match_config.get("laps", 1))
	var roads: Roads = world.get("roads")
	route = roads.route(Layout.RACE_LOOP)
	var acc := 0.0
	checkpoints.append(0)
	for i in range(1, route.size()):
		acc += route[i].distance_to(route[i - 1])
		if acc >= CP_SPACING:
			acc = 0.0
			checkpoints.append(i)
	var roster: Array = Game.match_config.get("roster", [1])
	var networked: bool = Game.match_config.get("networked", false)
	var bots := 0 if networked else int(Game.match_config.get("bots", 5))
	var slot := 0
	var my_car_id := str(Game.match_config.get("car", "sport"))
	# Our car.
	my_car = _spawn_on_grid(my_car_id, roster.find(Net.my_id()) if networked else 0, CarCatalog.PAINTS[0])
	player.enter_car(my_car)
	my_car.exit_locked = true
	racers.append({"id": Net.my_id(), "name": Game.player_name, "car": my_car, "cp": 0, "idx": 0, "lap": 0, "done": false, "time": 0.0, "local": true})
	slot = roster.size() if networked else 1
	var names := ["Rook", "Vega", "Dre", "Kaito", "Jax", "Mila", "Saint"]
	for i in mini(bots, 7):
		var id: String = CarCatalog.RACE_CARS[(i + 2) % CarCatalog.RACE_CARS.size()]
		var c := _spawn_on_grid(id, slot + i, CarCatalog.PAINTS[(i + 1) % CarCatalog.PAINTS.size()])
		var ai := RaceDriver.new()
		ai.route = route
		ai.skill = clampf(float(Game.match_config.get("difficulty", 0.6)) + randf_range(-0.12, 0.12), 0.3, 1.0)
		ai.race = self
		c.add_child(ai)
		racers.append({"id": 100 + i, "name": names[i], "car": c, "cp": 0, "idx": 0, "lap": 0, "done": false, "time": 0.0, "local": true, "bot": ai})
	if networked:
		sync = NetSync.new()
		sync.world = world
		sync.player = player
		add_child(sync)
		for id in roster:
			if int(id) != Net.my_id():
				racers.append({"id": int(id), "name": Net.name_of(int(id)), "car": null, "cp": 0, "idx": 0, "lap": 0, "done": false, "time": 0.0, "local": false})
	for r in racers:
		if r["car"]:
			(r["car"] as Car).exploded.connect(_on_exploded)
	_build_gate()
	Net.event_received.connect(_on_event)
	_countdown()


func _spawn_on_grid(id: String, slot: int, paint: Color) -> Car:
	var row := slot / 2
	var side := -3.5 if slot % 2 == 0 else 3.5
	var i := clampi(6 - row * 3, 0, route.size() - 2)   # rows go back from the line
	var a := route[i]
	var b := route[i + 1]
	var dir := (b - a).normalized()
	var lateral := Vector3(-dir.z, 0, dir.x) * side
	var pos := a - dir * (row * 7.0) + lateral + Vector3.UP * 0.7
	pos.y = Terrain.height_at(pos.x, pos.z) + 0.8
	pos.y = maxf(pos.y, a.y + 0.6)
	return world.call("spawn_car", id, pos, atan2(dir.x, dir.z), paint)


func _build_gate() -> void:
	var a := route[8]
	var dir := (route[9] - a).normalized()
	_gate = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(18.0, 0.8, 0.8)
	_gate.mesh = b
	_gate.material_override = Mats.glow(Color(1.0, 0.2, 0.15), 2.0)
	_gate.position = a + Vector3.UP * 7.0
	_gate.rotation.y = atan2(dir.x, dir.z)
	world.add_child(_gate)


func _countdown() -> void:
	var hud: Hud = world.get("hud")
	for r in racers:
		if r["car"]:
			(r["car"] as Car).freeze = true
	for n in [3, 2, 1]:
		hud.banner(str(n), "STREET RACE  •  %d lap%s" % [laps, "s" if laps > 1 else ""], 0.8)
		Sfx.play("beep")
		await get_tree().create_timer(1.0).timeout
	hud.banner("GO!", "", 0.8)
	Sfx.play("go")
	for r in racers:
		if r["car"] and not (r["car"] as Car).owner_peer:
			(r["car"] as Car).freeze = false
	running = true


func _physics_process(delta: float) -> void:
	if not running:
		return
	race_time += delta
	surge = minf(surge + delta * (12.0 if my_car.drifting else 4.0), 100.0)
	for r in racers:
		if not r["local"] or r["done"]:
			continue
		_track(r)
	_net_tick -= delta
	if _net_tick <= 0.0:
		_net_tick = 0.5
		Net.send_event("cp", {"id": racers[0]["id"], "lap": racers[0]["lap"], "idx": racers[0]["idx"]})
	# Our own controls in the car.
	if Input.is_action_just_pressed("grenade"):
		throw_grenade(my_car)
	if Input.is_action_just_pressed("surge"):
		car_surge(my_car)
	_update_hud()


## Where a racer is on the loop: the nearest route point in a window ahead
## of where they were (so a wide line or a shortcut never loses track), and
## a new lap when that wraps past the start line.
func _track(r: Dictionary) -> void:
	var car: Car = r["car"]
	if car == null or not is_instance_valid(car):
		return
	var start := int(r["idx"])
	var best := start
	var best_d := INF
	var span := range(-5, 60)
	if route[start].distance_to(car.global_position) > 60.0:
		span = range(0, route.size())     # lost (respawned, flung): search everything
		start = 0
	for k in span:
		var j := posmod(start + k, route.size())
		var d := route[j].distance_squared_to(car.global_position)
		if d < best_d:
			best_d = d
			best = j
	if best < route.size() / 4 and start > route.size() * 3 / 4 and race_time > 10.0:
		r["lap"] = int(r["lap"]) + 1
		if int(r["lap"]) >= laps:
			r["done"] = true
			r["time"] = race_time
			Net.send_event("finish", {"id": r["id"], "time": race_time})
	r["idx"] = best
	r["cp"] = best * checkpoints.size() / route.size()


func progress_of(r: Dictionary) -> float:
	return float(int(r["lap"]) * route.size() + int(r["idx"])) + (100000.0 if r["done"] else 0.0) - float(r["time"]) * 0.01


func standings() -> Array:
	var list := racers.duplicate()
	list.sort_custom(func(a, b) -> bool: return progress_of(a) > progress_of(b))
	return list


func _update_hud() -> void:
	var hud: Hud = world.get("hud")
	var list := standings()
	var me := 0
	for i in list.size():
		if list[i]["id"] == Net.my_id():
			me = i
	var mine: Dictionary = racers[0]
	var lap := mini(int(mine["lap"]) + 1, laps)
	hud.set_race(me + 1, list.size(), lap, laps, race_time, grenades, surge)
	if mine["done"] and running:
		running = false
		_finish()


# ----------------------------------------------------------------- weapons

func throw_grenade(car: Car) -> void:
	if car == my_car:
		if grenades <= 0 or car.wrecked:
			return
		grenades -= 1
	var from := car.global_position + Vector3.UP * 1.6 + car.global_basis.z * 2.5
	var vel := car.linear_velocity + car.global_basis.z * 18.0 + Vector3.UP * 5.0
	Net.send_event("grenade", {"p": from, "v": vel, "by": car.owner_peer if car.owner_peer else Net.my_id()})


func car_surge(car: Car) -> void:
	if car == my_car:
		if surge < 50.0 or car.wrecked:
			return
		surge -= 50.0
	Net.send_event("csurge", {"p": car.global_position, "by": Net.my_id(), "car": car.get_instance_id()})


func _on_event(from: int, kind: String, d: Dictionary) -> void:
	match kind:
		"grenade":
			var g := Grenade.new()
			g.position = d["p"]
			g.linear_velocity = d["v"]
			world.add_child(g)
			g.blew.connect(_on_grenade_blew)
		"csurge":
			var pos: Vector3 = d["p"]
			Fx.shockwave(world, pos + Vector3.UP, 14.0)
			Sfx.play("surge", pos, 4.0)
			for r in racers:
				var c: Car = r["car"]
				if c and is_instance_valid(c) and r["local"] and c.get_instance_id() != int(d.get("car", 0)) and c.global_position.distance_to(pos) < 14.0 and c.global_position.distance_to(pos) > 0.5:
					c.take_damage(140.0)
					c.stun(1.2)
					c.apply_central_impulse((c.global_position - pos).normalized() * c.mass * 7.0 + Vector3.UP * c.mass * 2.0)
		"cp":
			for r in racers:
				if r["id"] == int(d["id"]) and not r["local"]:
					r["idx"] = int(d["idx"])
					r["lap"] = int(d["lap"])
					if sync and sync.cars.has(int(d["id"])):
						r["car"] = sync.cars[int(d["id"])]
		"finish":
			for r in racers:
				if r["id"] == int(d["id"]):
					r["done"] = true
					r["time"] = float(d["time"])
					(world.get("hud") as Hud).feed("%s finished  %s" % [r["name"], _clock(float(d["time"]))])


func _on_grenade_blew(pos: Vector3) -> void:
	for r in racers:
		var c: Car = r["car"]
		if c and is_instance_valid(c) and r["local"] and c.global_position.distance_to(pos) < 9.0:
			var k := 1.0 - c.global_position.distance_to(pos) / 9.0
			c.take_damage(320.0 * k + 60.0)
			c.stun(1.5)
			c.apply_central_impulse((c.global_position - pos).normalized() * c.mass * 8.0 * k + Vector3.UP * c.mass * 5.0 * k)


## A car blew up: three seconds later it's back on the road where it died.
func _on_exploded(car: Car) -> void:
	var at := car.global_position
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(car):
		return
	var best := 0
	var best_d := INF
	for i in range(0, route.size(), 2):
		var d := route[i].distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	var a := route[best]
	var b := route[mini(best + 1, route.size() - 1)]
	var dir := (b - a).normalized()
	car.repair()
	car.reset_to(a + Vector3.UP * 1.0, atan2(dir.x, dir.z))
	if car == my_car and player.car == null:
		player.enter_car(car)


func _finish() -> void:
	await get_tree().create_timer(1.0).timeout
	var list := standings()
	var rows: Array = []
	var earned := 0
	for i in list.size():
		var r: Dictionary = list[i]
		rows.append(["%d. %s" % [i + 1, r["name"]], _clock(float(r["time"])) if r["done"] else "racing..."])
		if r["id"] == Net.my_id():
			earned = PRIZES[mini(i, PRIZES.size() - 1)]
	Game.add_money(earned)
	(world.get("hud") as Hud).results("STREET RACE", rows, "You earned $%d" % earned)


func _clock(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
