extends Control
## First screen: pick X or Y, then Story / Multiplayer / Settings.
## Multiplayer: choose a mode, then HOST on Wi-Fi (others JOIN with the IP
## shown), or PRACTICE SOLO offline.

var _cards: Dictionary = {}
var _main: VBoxContainer
var _mp_panel: PanelContainer
var _mode_select: OptionButton
var _ip_edit: LineEdit
var _lobby_list: Label
var _lobby_info: Label
var _start_button: Button
var _status: Label
var _money: Label

## Battle Royale, Street Race, Robbers vs Police (see Session.MODE_*).
const MP_MODES := [1, 2, 3]


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.055, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 60
	layout.offset_right = -60
	layout.offset_top = 40
	layout.offset_bottom = -40
	layout.add_theme_constant_override("separation", 60)
	add_child(layout)

	# Left: title + character select
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(left)
	var title := Label.new()
	title.text = "LOOKOUT"
	title.add_theme_font_size_override("font_size", 110)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.42))
	left.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose your character"
	left.add_child(subtitle)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 30)
	left.add_child(cards)
	for id: String in GameSettings.CHARACTERS:
		cards.add_child(_character_card(id))
	_refresh_cards()

	# Right: main buttons
	_main = VBoxContainer.new()
	_main.custom_minimum_size.x = 520
	_main.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(_main)
	for entry: Array in [["STORY", _on_story], ["MULTIPLAYER", _on_multiplayer], ["SETTINGS", _on_settings], ["QUIT", _on_quit]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 96
		button.add_theme_font_size_override("font_size", 40)
		button.pressed.connect(entry[1])
		_main.add_child(button)
	_money = Label.new()
	_money.text = "$%d" % GameSettings.money
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_main.add_child(_money)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main.add_child(_status)

	_build_multiplayer_panel()
	Net.players_changed.connect(_refresh_lobby)
	Net.connected_ok.connect(func() -> void: _status.text = "Connected. Waiting for the host to start…")
	Net.connection_failed.connect(func() -> void: _status.text = "Couldn't connect. Check the IP and that you're on the same Wi-Fi.")
	Net.session_ended.connect(func(reason: String) -> void: _status.text = reason)


# ------------------------------------------------------------ characters

func _character_card(id: String) -> Control:
	var info: Dictionary = GameSettings.CHARACTERS[id]
	var card := Button.new()
	card.custom_minimum_size = Vector2(380, 560)
	card.toggle_mode = true
	card.pressed.connect(func() -> void: _select(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 14
	box.offset_bottom = -14
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var portrait := TextureRect.new()
	portrait.texture = load(info["portrait"]) as Texture2D
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)
	var name_label := Label.new()
	name_label.text = "%s BOT" % info["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	_cards[id] = card
	return card


func _select(id: String) -> void:
	GameSettings.character = id
	GameSettings.save()
	_refresh_cards()


func _refresh_cards() -> void:
	for id: String in _cards:
		(_cards[id] as Button).button_pressed = id == GameSettings.character


# ------------------------------------------------------------ main buttons

func _on_story() -> void:
	Session.start_story()


func _on_multiplayer() -> void:
	_mp_panel.visible = true


func _on_settings() -> void:
	var panel := SettingsPanel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -380
	panel.offset_bottom = 380
	panel.closed.connect(panel.queue_free)
	add_child(panel)


func _on_quit() -> void:
	get_tree().quit()


# ------------------------------------------------------------ multiplayer

func _build_multiplayer_panel() -> void:
	_mp_panel = PanelContainer.new()
	_mp_panel.set_anchors_preset(Control.PRESET_CENTER)
	_mp_panel.offset_left = -620
	_mp_panel.offset_right = 620
	_mp_panel.offset_top = -420
	_mp_panel.offset_bottom = 420
	_mp_panel.visible = false
	add_child(_mp_panel)
	var box := VBoxContainer.new()
	_mp_panel.add_child(box)
	var title := Label.new()
	title.text = "MULTIPLAYER"
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var mode_row := HBoxContainer.new()
	var mode_label := Label.new()
	mode_label.text = "Mode"
	mode_label.custom_minimum_size.x = 160
	mode_row.add_child(mode_label)
	_mode_select = OptionButton.new()
	for m: int in MP_MODES:
		_mode_select.add_item(Session.MODE_NAMES[m])
	_mode_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(_mode_select)
	box.add_child(mode_row)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	for entry: Array in [["HOST (WI-FI)", _on_host], ["PRACTICE SOLO", _on_solo]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		buttons.add_child(button)

	var join_row := HBoxContainer.new()
	box.add_child(join_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Host IP, e.g. 192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	var join := Button.new()
	join.text = "JOIN"
	join.pressed.connect(_on_join)
	join_row.add_child(join)

	_lobby_info = Label.new()
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lobby_info)
	_lobby_list = Label.new()
	_lobby_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_lobby_list)

	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.disabled = true
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(_on_start)
	bottom.add_child(_start_button)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(_on_mp_back)
	bottom.add_child(back)

	var note := Label.new()
	note.text = "Wi-Fi play: all devices on the same network. Online play over the internet needs a game server (coming later)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 22)
	box.add_child(note)


func _selected_mode() -> int:
	return MP_MODES[_mode_select.selected]


func _on_host() -> void:
	var err := Net.host()
	if err != OK:
		_lobby_info.text = "Couldn't host (error %d)." % err
		return
	var ips := ", ".join(Net.local_addresses())
	_lobby_info.text = "Hosting %s. Friends join with: %s" % [Session.MODE_NAMES[_selected_mode()], ips if ips != "" else "(no Wi-Fi address found)"]
	_start_button.disabled = false
	_refresh_lobby()


func _on_join() -> void:
	if _ip_edit.text.strip_edges() == "":
		_lobby_info.text = "Type the host's IP first."
		return
	var err := Net.join(_ip_edit.text)
	_lobby_info.text = "Connecting…" if err == OK else "Couldn't start connecting (error %d)." % err


func _on_solo() -> void:
	Net.leave()
	var team := {1: "robbers"} if _selected_mode() == Session.MODE_HEIST else {}
	Session.start_match(_selected_mode(), randi(), team, false)


func _on_start() -> void:
	if Net.players.size() < 1:
		return
	Net.start_match(_selected_mode())


func _on_mp_back() -> void:
	Net.leave()
	_start_button.disabled = true
	_lobby_info.text = ""
	_mp_panel.visible = false


func _refresh_lobby() -> void:
	var lines := PackedStringArray()
	for id: int in Net.players:
		var p: Dictionary = Net.players[id]
		lines.append("• %s  (%s Bot)%s" % [p.get("name", "Player"), str(p.get("character", "x_bot")).left(1).to_upper(), "  [host]" if id == 1 else ""])
	_lobby_list.text = "Players:\n" + "\n".join(lines) if not lines.is_empty() else ""
