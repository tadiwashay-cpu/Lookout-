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
	_status.position = Vector2(900, 270)
	_status.size = Vector2(640, 560)
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
	b.pressed.connect(action)
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
		b.custom_minimum_size = Vector2(90, 58)
		b.add_theme_font_size_override("font_size", 22)
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
	var q := {"quality": Game.quality}
	_option_row_settings("GRAPHICS", ["LOW", "MEDIUM", "HIGH"], Game.quality, func(i: int) -> void:
		Game.quality = i
		Game.view_distance = [550.0, 900.0, 1400.0][i])
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
