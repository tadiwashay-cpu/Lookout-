class_name StoryMode
extends GameMode
## Story start: you wake up in the crew's HQ (THE LOOKOUT). First job is
## Clean Hands — take the streets back from the Low Tide crew with your
## fists. Finish it and the rifle, grenades and surge are unlocked.

const GOON_SQUADS := 6
const GOONS_PER_SQUAD := 3

var _challenge: CleanHandsChallenge
var _market := Vector3.ZERO


func begin() -> void:
	var p := player()
	p.spawn_point = world.hq_spawn + Vector3.UP * 0.3
	p.weapons_allowed = false
	_market = world.imported_city.market if world.imported_city else WorldCity.block_center(3, 2)
	_challenge = CleanHandsChallenge.new()
	_challenge.name = "CleanHands"
	add_child(_challenge)
	_challenge.track_player(p)
	var squad_rng := RandomNumberGenerator.new()
	squad_rng.seed = 77
	var placed := 0
	var tries := 0
	while placed < GOON_SQUADS and tries < 60:
		tries += 1
		var ix := squad_rng.randi_range(1, WorldCity.BLOCKS_X - 1)
		var iz := squad_rng.randi_range(0, WorldCity.BLOCKS_Z - 2)
		var spot := Vector3(WorldCity.street_x(ix), 0.3, WorldCity.street_z(iz) + 20.0)
		if world.imported_city:
			spot = world.imported_city.spot_away_from(world.hq_spawn, 60.0, squad_rng) + Vector3.UP * 0.3
		if spot.distance_to(world.hq_spawn) < 60.0:
			continue
		for i in GOONS_PER_SQUAD:
			var goon := world.spawn_goon(spot + Vector3(squad_rng.randf_range(-3, 3), 0, squad_rng.randf_range(-3, 3)))
			_challenge.track_goon(goon)
		placed += 1
	_challenge.goons_required = mini(_challenge.goons_required, placed * GOONS_PER_SQUAD)
	_challenge.objectives_changed.connect(set_status)
	_challenge.completed.connect(_on_clean_hands_done)
	_challenge.hint.connect(func(text: String) -> void: hud().show_hint(text))
	_challenge.failed.connect(func(reason: String) -> void: hud().show_banner(reason, 4.0, 36))
	hud().show_banner("THE LOOKOUT", 2.5)
	hud().show_hint("Head out. The Low Tide crew is running the market — fists only.")
	_challenge.start()


func _on_clean_hands_done(summary: String) -> void:
	hud().show_banner(summary, 4.0)
	player().weapons_allowed = true
	player().refill_grenades(3)
	GameSettings.add_money(500)
	hud().show_hint("Weapons unlocked: rifle, grenades and power surge. +$500")
	set_status("Free roam — explore the harbour, highway, forest and suburb.")


func minimap_markers() -> Array:
	# Bank (green) and pawn shop (orange) are always on the map.
	var out: Array = [
		{"pos": world.bank_position, "color": Color(0.35, 0.85, 0.45), "kind": "place"},
		{"pos": world.pawn_shop_position, "color": Color(1.0, 0.55, 0.15), "kind": "place"},
	]
	for place: Dictionary in world.map_places:
		if not ["FIRST HARBOR BANK", "PAWN SHOP"].has(place["text"]):
			out.append({"pos": place["pos"], "color": place["color"], "kind": "place"})
	if _challenge and not _challenge.is_complete:
		out.append({"pos": _market, "color": Color(1.0, 0.8, 0.3), "kind": "objective"})
	return out
