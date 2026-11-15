extends Control
## Title screen: Free Roam, Clean Hands, Street Race, Settings.
## Each mode: play solo against bots, host a game, or join one (games on
## the same Wi-Fi show up by themselves; anyone else joins by IP).

var _panel: VBoxContainer
var _status: Label
var _config := {"mode": Game.Mode.FREE_ROAM, "minutes": 3, "bots": 3, "laps": 1, "difficulty": 0.6, "car": "sport"}


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Key art on the right, fading into the dark panel on the left.
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/menu_bg.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.025, 0.03, 0.97), Color(0.02, 0.025, 0.03, 0.82), Color(0.02, 0.025, 0.03, 0.15)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var ver := Label.new()
	ver.text = "v%s  %s build" % [Game.version(), Game.BUILD_NAME]
	ver.add_theme_font_size_override("font_size", 22)
	ver.modulate = Color(1, 1, 1, 0.7)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Hud.pin(ver, Vector2(1.0, 1.0), Vector2(-420, -44), Vector2(400, 30))
	add_child(ver)
	var stripe := ColorRect.new()
	stripe.color = Color(1.0, 0.5, 0.08)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.size.x = 14
	add_child(stripe)
	var title := Label.new()
	title.text = "LOOKOUT"
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.12))
	title.position = Vector2(80, 40)
	add_child(title)
	var tag := Label.new()
	tag.text = "Nash doesn't believe in good or bad. Project Axiom changed what he can do about it."
	tag.add_theme_font_size_override("font_size", 24)
	tag.modulate = Color(1, 1, 1, 0.7)
	tag.position = Vector2(86, 190)
	add_child(tag)
	_panel = VBoxContainer.new()
	_panel.position = Vector2(86, 260)
	_panel.size = Vector2(760, 600)
	_panel.add_theme_constant_override("separation", 14)
	add_child(_panel)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status.add_theme_constant_override("outline_size", 8)
	_status.position = Vector2(900, 270)
	_status.size = Vector2(660, 560)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)
	Net.players_changed.connect(_refresh_lobby)
	Net.servers_changed.connect(_refresh_servers)
	Net.connection_failed.connect(func() -> void: _status.text = "Couldn't connect.")
	_home()


func _clear() -> void:
	for c in _panel.get_children():
		c.queue_free()
	_status.text = ""


func _button(text: String, action: Callable, size: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 74)
	b.add_theme_font_size_override("font_size", size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		Sfx.play("click")
		action.call())
	_panel.add_child(b)
	return b


func _home() -> void:
	_clear()
	Net.listen_for_games(false)
	_status.text = "Cash: $%d" % Game.money
	_button("FREE ROAM", func() -> void: _config["mode"] = Game.Mode.FREE_ROAM; Game.start_match(_config.duplicate()))
	_button("CLEAN HANDS  —  ring brawl", func() -> void: _mode_menu(Game.Mode.CLEAN_HANDS))
	_button("STREET RACE  —  up to 8", func() -> void: _mode_menu(Game.Mode.RACE))
	_button("SETTINGS", _settings)
	_button("HOW TO PLAY", _how_to, 28)
	_button("PLAYTEST REPORT", _report, 28)


func _how_to() -> void:
	_clear()
	_status.text = ""
	var text := Label.new()
	text.text = "\n".join([
		"ON FOOT   left side of the screen: move (push all the way to sprint)   •   drag the right side: look",
		"PUNCH  tap again and again for a 5-hit combo",
		"HEAVY  big moves up close, a charge from range, a stomp on a downed fighter, a FINISHER on a dazed one",
		"BLOCK  hold it and face them   •   DODGE  roll through a hit   •   SURGE  blast everyone around you (needs half a bar)",
		"ENTER  get in the nearest car, use doors and counters",
		"",
		"DRIVING   left side: steer   •   GAS / BRAKE (brake also reverses)   •   DRIFT for bends   •   NITRO on straights",
		"RACES   GRENADE lobs one ahead, SURGE stuns cars next to you. A wrecked car respawns where it died.",
		"",
		"MAP   tap the round radar.     MULTIPLAYER   everyone on the same Wi-Fi: one player HOSTS, the rest JOIN.",
		"Gamepad and keyboard work too (WASD, J punch, K heavy, L block, Space jump, E enter).",
	])
	text.add_theme_font_size_override("font_size", 23)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.custom_minimum_size = Vector2(1300, 0)
	_panel.add_child(text)
	_button("BACK", _home, 28)


## What testers send back: device, frame rates per session, version.
func _report() -> void:
	_clear()
	_status.add_theme_font_size_override("font_size", 19)
	_status.text = Game.report_text()
	var note := Label.new()
	note.text = "Play each mode for a minute, then come back here.\nCOPY puts this report on the clipboard: paste it into a chat or notes, and add what felt good, what felt bad and what broke."
	note.add_theme_font_size_override("font_size", 22)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size = Vector2(740, 0)
	_panel.add_child(note)
	_button("COPY REPORT", func() -> void:
		DisplayServer.clipboard_set(Game.report_text())
		note.text = "Copied. Paste it wherever you're collecting feedback.")
	_button("CLEAR SESSIONS", func() -> void:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.REPORT_PATH))
		_status.text = Game.report_text(), 28)
	_button("BACK", func() -> void:
		_status.add_theme_font_size_override("font_size", 24)
		_home(), 28)


func _mode_menu(mode: int) -> void:
	_clear()
	_config["mode"] = mode
	var race := mode == Game.Mode.RACE
	_status.text = ("STREET RACE\nThe grand loop: downtown, the harbour, over the mountain pass, through the suburbs and the forest. Grenades and power surges are allowed. Wreck your car and it explodes; you respawn where you died." if race
		else "CLEAN HANDS\nBare hands in the harbour ring. Every KO scores. When the clock runs out, the most KOs takes the biggest purse.")
	_option_row("BOTS (solo)", [1, 2, 3, 5, 7] if race else [1, 2, 3, 5], "bots")
	if race:
		_option_row("LAPS", [1, 2, 3], "laps")
		_option_row("CAR", ["sport", "spyder_rs", "aurora_gt", "strix_v12", "vortex_rs", "redline_gt"], "car")
	else:
		_option_row("MINUTES", [2, 3, 5, 8], "minutes")
	_option_row("DIFFICULTY", [0.35, 0.6, 0.85], "difficulty")
	_button("PLAY SOLO (vs bots)", func() -> void:
		var c := _config.duplicate()
		c["networked"] = false
		Game.start_match(c))
	_button("HOST A GAME", _host)
	_button("JOIN A GAME", _join)
	_button("BACK", _home, 28)


func _option_row(label: String, values: Array, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(210, 0)
	l.add_theme_font_size_override("font_size", 26)
	row.add_child(l)
	var group := ButtonGroup.new()
	for v in values:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = {0.35: "EASY", 0.6: "MEDIUM", 0.85: "HARD"}.get(v, str(v).replace("_", " ").to_upper())
		b.custom_minimum_size = Vector2(80, 58)
		b.add_theme_font_size_override("font_size", 20)
		b.button_pressed = _config.get(key) == v
		b.pressed.connect(func() -> void: _config[key] = v)
		row.add_child(b)
	_panel.add_child(row)


func _host() -> void:
	var err := Net.host()
	if err != OK:
		_status.text = "Couldn't host (port %d busy?)" % Net.PORT
		return
	Game.match_config = _config.duplicate()
	_lobby()


func _lobby() -> void:
	_clear()
	_refresh_lobby()
	if Net.is_host():
		_button("START", func() -> void: Net.start_match(_config.duplicate()))
	_button("LEAVE", func() -> void: Net.leave(); _home(), 28)


func _refresh_lobby() -> void:
	if not Net.is_online():
		return
	var lines := ["LOBBY  (%d/%d)" % [Net.players.size(), Net.MAX_PLAYERS], ""]
	for id in Net.players:
		lines.append("• %s%s" % [Net.name_of(int(id)), "  (host)" if int(id) == 1 else ""])
	lines.append("")
	lines.append("Others on this Wi-Fi will see this game under JOIN." if Net.is_host() else "Waiting for the host to start...")
	if Net.is_host():
		lines.append("Your address: " + ", ".join(Array(IP.get_local_addresses()).filter(func(a: String) -> bool: return a.begins_with("192.") or a.begins_with("10.") or a.begins_with("172."))))
	_status.text = "\n".join(lines)


func _join() -> void:
	_clear()
	Net.listen_for_games(true)
	_status.text = "Looking for games on this Wi-Fi..."
	var ip := LineEdit.new()
	ip.placeholder_text = "or type the host's IP address"
	ip.custom_minimum_size = Vector2(0, 64)
	ip.add_theme_font_size_override("font_size", 28)
	_panel.add_child(ip)
	_button("JOIN THIS IP", func() -> void: _connect(ip.text.strip_edges()), 28)
	var list := VBoxContainer.new()
	list.name = "Servers"
	_panel.add_child(list)
	_button("BACK", func() -> void: _mode_menu(int(_config["mode"])), 28)


func _refresh_servers() -> void:
	var list := _panel.get_node_or_null("Servers")
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	for ip: String in Net.servers:
		var s: Dictionary = Net.servers[ip]
		var b := Button.new()
		b.text = "%s's game  (%d players)" % [s["name"], s["players"]]
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(func() -> void: _connect(ip))
		list.add_child(b)
	_status.text = "%d game(s) found." % Net.servers.size()


func _connect(ip: String) -> void:
	if ip == "":
		return
	if Net.join(ip) != OK:
		_status.text = "Couldn't connect to %s" % ip
		return
	Net.listen_for_games(false)
	_lobby()
	_status.text = "Connecting to %s..." % ip


func _settings() -> void:
	_clear()
	var name_edit := LineEdit.new()
	name_edit.text = Game.player_name
	name_edit.custom_minimum_size = Vector2(0, 64)
	name_edit.add_theme_font_size_override("font_size", 28)
	name_edit.text_changed.connect(func(t: String) -> void: Game.player_name = t.left(16))
	_panel.add_child(name_edit)
	_option_row_settings("GRAPHICS", ["LOW", "MEDIUM", "HIGH", "ULTRA"], Game.quality, func(i: int) -> void: Game.set_quality(i))
	_option_row_settings("FPS COUNTER", ["OFF", "ON"], 1 if Game.show_fps else 0, func(i: int) -> void: Game.show_fps = i == 1)
	var note := Label.new()
	note.text = "The game holds 60 fps by itself: resolution adapts while a scene is heavy, and if that isn't enough it switches off one effect at a time and remembers it for this device. Picking a GRAPHICS level resets that."
	note.add_theme_font_size_override("font_size", 20)
	note.modulate = Color(1, 1, 1, 0.6)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size = Vector2(740, 0)
	_panel.add_child(note)
	_button("SAVE", func() -> void: Game.save(); _home())


func _option_row_settings(label: String, names: Array, current: int, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(210, 0)
	l.add_theme_font_size_override("font_size", 26)
	row.add_child(l)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = names[i]
		b.custom_minimum_size = Vector2(130, 58)
		b.button_pressed = i == current
		b.pressed.connect(func() -> void: on_pick.call(i))
		row.add_child(b)
	_panel.add_child(row)
