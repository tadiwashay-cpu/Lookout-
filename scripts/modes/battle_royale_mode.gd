class_name BattleRoyaleMode
extends GameMode
## Everyone drops into a random region (harbour, suburb, forest, highway).
## A safe zone shrinks in phases; outside it you take damage. Last one
## standing wins. Solo practice: survive until the zone closes.

## [time (s), radius (m)] — radius is interpolated between entries.
const PHASES := [[0.0, 1100.0], [45.0, 1100.0], [105.0, 560.0], [150.0, 560.0],
	[210.0, 260.0], [250.0, 260.0], [330.0, 90.0], [370.0, 90.0], [450.0, 12.0]]

const BOT_COUNT := 9
const BOT_WEAPONS := ["m4a1", "ak47", "mp5k", "uzi", "g36", "spas12", "m16a4"]

var _center := Vector2.ZERO
var _time := 0.0
var _alive: Dictionary = {}
var _tick := 0.0
var _dome: MeshInstance3D
var _bots: Array[BotSoldier] = []


func begin() -> void:
	var rng := Session.match_rng(99)
	var regions: Array = world.region_points.keys()
	var region: String = regions[rng.randi() % regions.size()]
	var p := world.random_point_in(region, rng)
	_center = Vector2(p.x, p.z)
	player().respawn_enabled = false
	player().refill_grenades(3)
	var everyone: Array = Net.players.keys() if Session.networked else [1]
	for id in everyone:
		_alive[id] = true
	_build_dome()
	if not Session.networked:
		_spawn_bots(rng)
	Net.player_eliminated.connect(_on_eliminated)
	hud().show_banner("BATTLE ROYALE", 2.5)
	hud().show_hint("Dropped at the %s. Stay inside the circle." % Session.spawn_region_for(Session.my_id()))


## The safe zone as a glowing wall you can see from anywhere.
func _build_dome() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 64
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.35, 0.65, 1.0, 0.22)
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_dome = MeshInstance3D.new()
	_dome.mesh = cylinder
	_dome.material_override = material
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_dome)


func _spawn_bots(rng: RandomNumberGenerator) -> void:
	var regions: Array = world.region_points.keys()
	for i in BOT_COUNT:
		var region: String = regions[rng.randi() % regions.size()]
		var bot := GameMode.make_bot(world, i, "bot_%d" % i, BOT_WEAPONS[i % BOT_WEAPONS.size()], world.random_point_in(region, rng))
		bot.accuracy = rng.randf_range(0.45, 0.75)
		bot.has_objective = true
		bot.died.connect(_on_bot_died)
		_alive[bot.bot_id] = true
		_bots.append(bot)


func _on_bot_died(bot: BotSoldier, killer: Node) -> void:
	var by := 0
	if killer is PlayerController:
		by = Session.my_id()
	elif killer is BotSoldier:
		by = (killer as BotSoldier).bot_id
	Net.announce_eliminated(bot.bot_id, by)


func _radius_at(t: float) -> float:
	for i in PHASES.size() - 1:
		var a: Array = PHASES[i]
		var b: Array = PHASES[i + 1]
		if t <= b[0]:
			return lerpf(a[1], b[1], clampf((t - a[0]) / maxf(b[0] - a[0], 0.01), 0.0, 1.0))
	return PHASES[PHASES.size() - 1][1]


func safe_zone() -> Dictionary:
	return {"center": _center, "radius": _radius_at(_time)}


func _process(delta: float) -> void:
	if finished:
		return
	_time += delta
	_tick -= delta
	var p := player()
	var pos := Vector2(p.global_position.x, p.global_position.z)
	var radius := _radius_at(_time)
	_dome.position = Vector3(_center.x, 200.0, _center.y)
	_dome.scale = Vector3(radius, 500.0, radius)
	if _tick <= 0.0:
		_tick = 1.0
		var dps := 4.0 + _time / 60.0 * 2.0
		if p.is_alive() and pos.distance_to(_center) > radius:
			p.take_hit(dps, Vector3.ZERO, null, false)
			hud().show_hint("Outside the zone! Get inside the blue wall.")
		for bot in _bots:
			if is_instance_valid(bot) and bot.is_alive():
				bot.objective = Vector3(_center.x, 0.0, _center.y) + (bot.global_position - Vector3(_center.x, 0, _center.y)).normalized() * radius * 0.4
				if Vector2(bot.global_position.x, bot.global_position.z).distance_to(_center) > radius:
					bot.take_hit(dps, Vector3.ZERO, null, false)
	set_status("Alive %d   •   Zone %dm" % [_alive.size(), int(radius)])
	if not Session.networked and _time > PHASES[PHASES.size() - 1][0] + 60.0 and p.is_alive():
		end_match("YOU SURVIVED", true, 400)


func _on_eliminated(peer_id: int, by_peer: int) -> void:
	_alive.erase(peer_id)
	if by_peer == Session.my_id() and peer_id != by_peer:
		hud().show_hint("Eliminated %s" % names_for([peer_id]))
	if peer_id == Session.my_id():
		hud().show_banner("ELIMINATED", 3.0)
	if Session.networked and _alive.size() <= 1:
		var winners: Array = _alive.keys()
		var i_won := winners.has(Session.my_id())
		end_match(("YOU WIN" if i_won else "%s WINS" % names_for(winners).to_upper()) if not winners.is_empty() else "DRAW", i_won, 800 if i_won else 150)
	elif not Session.networked and peer_id == Session.my_id():
		end_match("ELIMINATED — #%d" % (_alive.size() + 1), false, 50)
	elif not Session.networked and _alive.size() == 1 and _alive.has(Session.my_id()):
		end_match("YOU WIN", true, 800)
