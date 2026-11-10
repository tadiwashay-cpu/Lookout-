class_name HeistMode
extends GameMode
## Robbers vs Police. Teams are split at random by the host. Robbers start
## at the bank and must get any one robber into the extraction zone
## (random: harbour, suburb, forest or highway). Police start at the
## precinct and win by taking every robber down or running out the clock.
## Robbers don't respawn; police respawn at the precinct. Winners earn
## money for better gear (shop coming next).

const TIME_LIMIT := 420.0
const EXTRACT_RADIUS := 12.0

var _team := "robbers"
var _extract := Vector3.ZERO
var _extract_region := ""
var _time := 0.0
var _robbers_alive: Dictionary = {}
var _zone_ring: MeshInstance3D
var _sent_escape := false
## Phase 1: robbers crack the vault at the bank (stand by it). Phase 2: run.
const CRACK_TIME := 14.0
const CRACK_RADIUS := 7.0
var _crack := 0.0
var _loot := false
var _crack_sync := 0.0


func begin() -> void:
	_team = Session.team_of(Session.my_id()) if Session.networked else "robbers"
	var regions: Array = world.extraction_points.keys()
	_extract_region = regions[Session.match_rng(11).randi() % regions.size()]
	_extract = world.extraction_points[_extract_region]
	var p := player()
	p.refill_grenades(3)
	if _team == "police":
		p.respawn_enabled = true
		p.spawn_point = world.precinct_position + Vector3(0, 0.3, -2.0)
		p.respawn_delay = 6.0
	else:
		p.respawn_enabled = false
	if Session.networked:
		for id: int in Session.teams:
			if Session.teams[id] == "robbers":
				_robbers_alive[id] = true
	else:
		_robbers_alive[1] = true
	Net.player_eliminated.connect(_on_eliminated)
	Net.match_event.connect(_on_event)
	_build_zone()
	if not Session.networked:
		_spawn_solo_police()
	hud().show_banner("ROBBERS VS POLICE", 2.5)
	if _team == "robbers":
		hud().show_hint("You're a ROBBER. Crack the vault at the bank, then escape to the %s!" % _extract_region)
	else:
		hud().show_hint("You're POLICE. Stop the robbers at the bank, or before they reach the %s." % _extract_region)
	_zone_ring.visible = false   # extraction opens once the cash is out
	world.add_label("VAULT", world.bank_position + Vector3.UP * 3.0, 64, Color(1.0, 0.85, 0.4))
	player().draw_weapon()


## Solo practice: officers on foot from the precinct plus Crown Vic pursuit.
func _spawn_solo_police() -> void:
	for i in 4:
		var officer := GameMode.make_bot(world, i, "police", "glock17" if i < 2 else "m4a1",
			world.precinct_position + Vector3(-6.0 + i * 4.0, 0.0, -3.0))
		officer.display_name = "Police"
		officer.tint_colors = [Color(0.55, 0.42, 0.33), Color(0.07, 0.1, 0.22)]
		officer.rig.tint(officer.tint_colors)
		officer.accuracy = 0.55
		officer.sight_range = 90.0
		officer.has_objective = true
		officer.objective = world.bank_position
		officer.add_to_group(&"police")
	var pursuit := PoliceManager.new()
	pursuit.name = "Pursuit"
	pursuit.world = world
	pursuit.forced_stars = 3
	add_child(pursuit)
	world.police = pursuit
	pursuit.busted.connect(func() -> void: _resolve(false))


func _build_zone() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = EXTRACT_RADIUS
	cylinder.bottom_radius = EXTRACT_RADIUS
	cylinder.height = 30.0
	cylinder.radial_segments = 24
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.3, 1.0, 0.45, 0.18) if _team == "robbers" else Color(1.0, 0.3, 0.25, 0.18)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone_ring = MeshInstance3D.new()
	_zone_ring.mesh = cylinder
	_zone_ring.material_override = material
	_zone_ring.position = _extract + Vector3.UP * 15.0
	world.add_child(_zone_ring)


func _process(delta: float) -> void:
	if finished:
		return
	_time += delta
	var left := maxf(TIME_LIMIT - _time, 0.0)
	var phase := "ESCAPE" if _loot else "VAULT %d%%" % int(_crack / CRACK_TIME * 100.0)
	set_status("%s   •   %s   •   Robbers left %d   •   %d:%02d" % [_team.to_upper(), phase, _robbers_alive.size(), int(left) / 60, int(left) % 60])
	var p := player()
	var where := p.current_vehicle.global_position if p.current_vehicle else p.global_position
	if _team == "robbers" and not _loot and p.is_alive() and p.current_vehicle == null and where.distance_to(world.bank_position) < CRACK_RADIUS:
		_crack += delta
		_crack_sync -= delta
		if _crack_sync <= 0.0:   # teammates and police see the progress
			_crack_sync = 1.0
			Net.send_event("heist_crack", {"t": _crack})
		if _crack >= CRACK_TIME:
			Net.send_event("heist_loot", {"name": GameSettings.player_name})
	if _team == "robbers" and _loot and p.is_alive() and not _sent_escape and where.distance_to(_extract) < EXTRACT_RADIUS:
		_sent_escape = true
		Net.send_event("heist_escaped", {"name": GameSettings.player_name})
	if left <= 0.0:
		_resolve(false)


func _on_event(kind: String, data: Dictionary) -> void:
	if kind == "heist_crack":
		_crack = maxf(_crack, float(data.get("t", 0.0)))   # robbers crack it together
	elif kind == "heist_loot" and not _loot:
		_loot = true
		_crack = CRACK_TIME
		_zone_ring.visible = true
		Audio.play("explosion", world.bank_position + Vector3.UP, 0.0)
		hud().show_banner("VAULT OPEN", 2.0)
		hud().show_hint("%s has the cash! %s" % [str(data.get("name", "A robber")),
			"Get to the %s!" % _extract_region if _team == "robbers" else "Cut them off before the %s!" % _extract_region])
	if kind == "heist_escaped":
		hud().show_hint("%s escaped with the cash!" % str(data.get("name", "A robber")))
		_resolve(true)


func _on_eliminated(peer_id: int, _by_peer: int) -> void:
	if _robbers_alive.has(peer_id):
		_robbers_alive.erase(peer_id)
		if _robbers_alive.is_empty():
			_resolve(false)


func _resolve(robbers_won: bool) -> void:
	if finished:
		return
	var i_won := (robbers_won and _team == "robbers") or (not robbers_won and _team == "police")
	var title := "ROBBERS ESCAPED" if robbers_won else "POLICE WIN"
	end_match(title, i_won, 1000 if i_won else 250)


func minimap_markers() -> Array:
	var color := Color(0.35, 1.0, 0.5) if _team == "robbers" else Color(1.0, 0.35, 0.3)
	if not _loot:
		return [{"pos": world.bank_position, "color": Color(1.0, 0.85, 0.4), "kind": "objective"}]
	return [{"pos": _extract, "color": color, "kind": "objective"}, {"pos": world.bank_position, "color": Color(0.9, 0.85, 0.5), "kind": "poi"}]
