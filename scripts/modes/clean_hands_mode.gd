class_name CleanHandsMode
extends GameMode
## CLEAN HANDS — fists only. Everyone drops into a ring somewhere in the
## world (harbour, suburb, forest or highway, picked from the match seed so
## every device agrees). Landing punches fills your surge meter; when it is
## full, SURGE blasts everyone around you. Knock-outs score; you get back up
## a few seconds later somewhere else in the ring.
## First to KO_TARGET knock-outs, or most after MATCH_TIME, wins.
## Local Wi-Fi multiplayer, or solo practice against brawler bots.

const ARENA_RADIUS := 24.0
const KO_TARGET := 10
const MATCH_TIME := 300.0
const BOT_COUNT := 5
const BOT_RESPAWN := 4.0

var _center := Vector3.ZERO
var _time := 0.0
var _tick := 0.0
var _kos: Dictionary = {}          # id -> knock-outs (peers > 0, bots < 0)
var _names: Dictionary = {}        # bot id -> name
var _ring: MeshInstance3D
var _bots: Array[BotSoldier] = []
var _rng := RandomNumberGenerator.new()


## Same answer on every device: the arena comes from the match seed.
static func arena_center(world: World) -> Vector3:
	var rng := Session.match_rng(4242)
	var regions: Array = world.region_points.keys()
	regions.sort()
	if regions.is_empty():
		return world.hq_spawn
	return world.random_point_in(regions[rng.randi() % regions.size()], rng)


static func spawn_point_for(world: World, peer_id: int, salt: int = 0) -> Vector3:
	var center := arena_center(world)
	var rng := Session.match_rng(peer_id * 31 + salt)
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(ARENA_RADIUS * 0.3, ARENA_RADIUS * 0.75)
	var p := center + Vector3(cos(angle), 0.0, sin(angle)) * dist
	p.y = world.ground_height(p.x, p.z) + 0.5
	return p


func begin() -> void:
	_rng.randomize()
	_center = arena_center(world)
	var p := player()
	p.weapons_allowed = false
	p.surge_needs_meter = true
	p.surge_meter = 0.0
	p.respawn_enabled = true
	p.respawn_delay = 3.0
	p.knocked_out.connect(_on_player_down)
	var everyone: Array = Net.players.keys() if Session.networked else [Session.my_id()]
	for id in everyone:
		_kos[id] = 0
	_build_ring()
	if not Session.networked:
		for i in BOT_COUNT:
			_spawn_bot(i)
	Net.player_eliminated.connect(_on_eliminated)
	hud().show_banner("CLEAN HANDS", 2.5)
	hud().show_hint("Fists only. Land hits to fill your surge meter, then hit SURGE.")


func minimap_markers() -> Array:
	var out := [{"pos": _center, "color": Color(1.0, 0.62, 0.2), "kind": "objective"}]
	for bot in _bots:
		if is_instance_valid(bot) and bot.is_alive():
			out.append({"pos": bot.global_position, "color": Color(0.9, 0.3, 0.25), "kind": "danger"})
	return out


func safe_zone() -> Dictionary:
	return {"center": Vector2(_center.x, _center.z), "radius": ARENA_RADIUS}


## A low glowing ring on the ground so the fight has a clear edge.
func _build_ring() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = ARENA_RADIUS
	cylinder.bottom_radius = ARENA_RADIUS
	cylinder.height = 2.5
	cylinder.radial_segments = 64
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_color = Color(1.0, 0.6, 0.2, 0.28)
	_ring = MeshInstance3D.new()
	_ring.mesh = cylinder
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_ring)
	_ring.global_position = _center + Vector3.UP * 1.0


func _spawn_bot(index: int) -> void:
	var names := ["Brick", "Knuckles", "Tank", "Rook", "Mace", "Ox"]
	var palette := [Color(0.5, 0.12, 0.1), Color(0.2, 0.25, 0.35), Color(0.3, 0.32, 0.22), Color(0.4, 0.38, 0.33), Color(0.15, 0.15, 0.17)]
	var bot := BotSoldier.new()
	bot.bot_id = -(index + 1)
	bot.team = "brawler_%d" % index        # everyone for themselves
	bot.display_name = names[index % names.size()]
	bot.melee_only = true                  # must be set before _ready
	bot.melee_damage = _rng.randf_range(9.0, 13.0)
	bot.sight_range = ARENA_RADIUS * 2.5
	bot.tint_colors = [Color(0.55, 0.4, 0.3), palette[index % palette.size()]]
	bot.position = _random_arena_point()
	bot.objective = _center
	bot.has_objective = true
	world.add_child(bot)
	bot.died.connect(_on_bot_died.bind(index))
	_names[bot.bot_id] = bot.display_name
	_kos[bot.bot_id] = _kos.get(bot.bot_id, 0)
	if index < _bots.size():
		_bots[index] = bot
	else:
		_bots.append(bot)


func _random_arena_point() -> Vector3:
	var angle := _rng.randf() * TAU
	var p := _center + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(3.0, ARENA_RADIUS * 0.8)
	p.y = world.ground_height(p.x, p.z) + 0.5
	return p


func _on_bot_died(bot: BotSoldier, killer: Node, index: int) -> void:
	var by := 0
	if killer is PlayerController:
		by = Session.my_id()
	elif killer is BotSoldier:
		by = (killer as BotSoldier).bot_id
	Net.announce_eliminated(bot.bot_id, by)
	await get_tree().create_timer(BOT_RESPAWN).timeout
	if not finished and is_inside_tree():
		_spawn_bot(index)


## Pick a fresh spot in the ring before the player gets back up.
func _on_player_down() -> void:
	player().spawn_point = spawn_point_for(world, Session.my_id(), int(_time * 10.0))


func _on_eliminated(peer_id: int, by_peer: int) -> void:
	if finished:
		return
	if by_peer != 0 and by_peer != peer_id:
		_kos[by_peer] = int(_kos.get(by_peer, 0)) + 1
		if by_peer == Session.my_id():
			hud().show_hint("KO! %s is down." % _name_of(peer_id))
			# A knock-out tops your meter up a little.
			player().surge_meter = minf(player().surge_meter + 20.0, 100.0)
		if int(_kos[by_peer]) >= KO_TARGET:
			_finish()
			return
	if peer_id == Session.my_id():
		hud().show_banner("KNOCKED OUT", 2.0)


func _name_of(id: int) -> String:
	if _names.has(id):
		return str(_names[id])
	return names_for([id])


func _leader() -> Array:
	var best := -1
	var leaders: Array = []
	for id in _kos:
		var k := int(_kos[id])
		if k > best:
			best = k
			leaders = [id]
		elif k == best:
			leaders.append(id)
	return leaders


func _finish() -> void:
	var leaders := _leader()
	var me := Session.my_id()
	if leaders.size() == 1 and leaders[0] == me:
		end_match("YOU WIN — %d KOs" % int(_kos[me]), true, 600)
	elif leaders.has(me):
		end_match("DRAW — %d KOs" % int(_kos[me]), false, 250)
	else:
		var winner_names := PackedStringArray()
		for id in leaders:
			winner_names.append(_name_of(id))
		end_match("%s WINS" % ", ".join(winner_names).to_upper(), false, 100 + int(_kos.get(me, 0)) * 20)


func _process(delta: float) -> void:
	if finished:
		return
	_time += delta
	_tick -= delta
	var p := player()
	if _tick <= 0.0:
		_tick = 0.5
		# Leaving the ring: shoved back in, and it stings.
		var offset := p.global_position - _center
		offset.y = 0.0
		if p.is_alive() and p.current_vehicle == null and offset.length() > ARENA_RADIUS:
			p.take_hit(4.0, -offset.normalized() * 6.0, null, false)
			hud().show_hint("Stay inside the ring!")
		for bot in _bots:
			if is_instance_valid(bot) and bot.is_alive():
				var bot_offset := bot.global_position - _center
				bot_offset.y = 0.0
				if bot_offset.length() > ARENA_RADIUS:
					bot.take_hit(4.0, -bot_offset.normalized() * 6.0, null, false)
	var left := maxf(MATCH_TIME - _time, 0.0)
	set_status("KOs %d / %d   •   Leader %s   •   %d:%02d" % [int(_kos.get(Session.my_id(), 0)), KO_TARGET,
		_name_of(_leader()[0]) if not _kos.is_empty() else "-", floori(left / 60.0), int(left) % 60])
	if left <= 0.0:
		_finish()
