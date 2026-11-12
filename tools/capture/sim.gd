extends Node
## Dev: plays a mode by itself and logs what happens.
##   godot --path . res://tools/capture/sim.tscn -- OUT_DIR MODE SECONDS

var world: Node3D
var player: Player
var out := ""
var t := 0.0
var _log_t := 0.0
var _punch_t := 0.0
var _shots := 0
var seconds := 40.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var mode := int(args[1])
	seconds = float(args[2])
	Game.match_config = {"mode": mode, "networked": false, "minutes": 3, "bots": 3 if mode == 1 else 5, "laps": 1, "difficulty": 0.6, "car": "sport", "seed": 5}
	world = (load(Game.WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	player = world.get("player")


func _physics_process(delta: float) -> void:
	t += delta
	_log_t -= delta
	var mode := Game.mode()
	if mode == Game.Mode.CLEAN_HANDS:
		var foe := player.call("_nearest_foe", 30.0) as Fighter
		if foe:
			var d := foe.global_position - player.global_position
			d.y = 0.0
			var cam_basis := Basis(Vector3.UP, player.cam.yaw)
			var local := cam_basis.inverse() * d.normalized()
			TouchControls.stick = Vector2(local.x, local.z) if d.length() > 1.5 else Vector2.ZERO
			_punch_t -= delta
			if d.length() < 2.0 and _punch_t <= 0.0:
				_punch_t = 0.35
				if player.finisher_target and randf() < 0.5:
					player.finisher(player.finisher_target)
				elif randf() < 0.2:
					player.heavy()
				else:
					player.punch()
	elif mode == Game.Mode.RACE:
		var race := world.get("mode") as RaceMode
		if race and player.car:
			var car := player.car
			var best := 0
			var bd := INF
			for i in range(0, race.route.size()):
				var dd := race.route[i].distance_to(car.global_position)
				if dd < bd:
					bd = dd
					best = i
			var target := race.route[(best + 8) % race.route.size()]
			var local := car.global_basis.inverse() * (target - car.global_position)
			TouchControls.stick = Vector2(-clampf(atan2(local.x, local.z) * 2.0, -1, 1), 0)
			TouchControls.gas = car.forward_speed() < 40.0
	if _log_t <= 0.0:
		_log_t = 3.0
		var line := "T=%.0f " % t
		if mode == Game.Mode.CLEAN_HANDS:
			var m := world.get("mode") as CleanHandsMode
			for node in get_tree().get_nodes_in_group(&"fighters"):
				var f := node as Fighter
				if not f.is_in_group(&"civilians"):
					line += "%s:%d(%s) " % [f.display_name, int(f.health), Fighter.State.keys()[f.state]]
			line += " KOs=" + str(m.kos)
		elif mode == Game.Mode.RACE:
			var race := world.get("mode") as RaceMode
			for r in race.standings():
				var c: Car = r["car"]
				line += "%s cp%d %.0fkmh hp%d %s | " % [r["name"], r["cp"], c.speed_kmh() if c else 0.0, int(c.health) if c else 0, str(c.global_position.snapped(Vector3.ONE)) if c else ""]
		print(line)
		if _shots < 4 and t > 6.0 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("%s/sim%d_%d.png" % [out, mode, _shots])
			_shots += 1
	if t > seconds:
		get_tree().quit()
