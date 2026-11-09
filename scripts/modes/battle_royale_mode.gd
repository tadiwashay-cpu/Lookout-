class_name BattleRoyaleMode
extends GameMode
## Everyone drops into a random region (harbour, suburb, forest, highway).
## A safe zone shrinks in phases; outside it you take damage. Last one
## standing wins. Solo practice: survive until the zone closes.

## [time (s), radius (m)] — radius is interpolated between entries.
const PHASES := [[0.0, 1100.0], [45.0, 1100.0], [105.0, 560.0], [150.0, 560.0],
	[210.0, 260.0], [250.0, 260.0], [330.0, 90.0], [370.0, 90.0], [450.0, 12.0]]

var _center := Vector2.ZERO
var _time := 0.0
var _alive: Dictionary = {}
var _tick := 0.0


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
	Net.player_eliminated.connect(_on_eliminated)
	hud().show_banner("BATTLE ROYALE", 2.5)
	hud().show_hint("Dropped at the %s. Stay inside the circle." % Session.spawn_region_for(Session.my_id()))


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
	if p.is_alive() and pos.distance_to(_center) > _radius_at(_time) and _tick <= 0.0:
		_tick = 1.0
		var dps := 4.0 + _time / 60.0 * 2.0
		p.take_hit(dps, Vector3.ZERO, null, false)
	set_status("Alive %d   •   Zone %dm" % [_alive.size(), int(_radius_at(_time))])
	if not Session.networked and _time > PHASES[PHASES.size() - 1][0] and p.is_alive():
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
		end_match("ELIMINATED", false, 50)
