extends Control
## First screen: pick X or Y, then Story / Multiplayer / Settings.
## Multiplayer: choose a mode, then HOST on Wi-Fi (others JOIN with the IP
## shown), or PRACTICE SOLO offline.

var _cards: Dictionary = {}
var _main: VBoxContainer
var _mp_panel: PanelContainer
var _mode_buttons: Array[Button] = []
var _shop_title: Label
var _shop_cars := false   # SHOP tab: guns or cars
var _shop_list: VBoxContainer
var _selected := 0
var _ip_edit: LineEdit
var _lobby_list: Label
var _lobby_info: Label
var _start_button: Button
var _status: Label
var _money: Label

## Battle Royale, Street Race, Robbers vs Police, Clean Hands (see Session.MODE_*).
const MP_MODES := [1, 2, 3, 4]


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
	title.add_theme_font_override("font", UITheme.TITLE_FONT)
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
	for entry: Array in [["STORY", _on_story], ["MULTIPLAYER", _on_multiplayer], ["RACE CAREER", _on_career], ["SHOP", _on_shop], ["SETTINGS", _on_settings], ["QUIT", _on_quit]]:
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


func _on_shop() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -620
	panel.offset_right = 620
	panel.offset_top = -420
	panel.offset_bottom = 420
	add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	_shop_title = Label.new()
	_shop_title.add_theme_font_size_override("font_size", 46)
	_shop_title.add_theme_font_override("font", UITheme.TITLE_FONT)
	root.add_child(_shop_title)
	var tabs := HBoxContainer.new()
	for entry: Array in [["GUNS", false], ["CARS", true]]:
		var tab := Button.new()
		tab.text = entry[0]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func() -> void:
			_shop_cars = entry[1]
			_rebuild_shop())
		tabs.add_child(tab)
	root.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_list)
	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(panel.queue_free)
	root.add_child(close)
	_rebuild_shop()


func _rebuild_shop() -> void:
	_shop_title.text = "%s   —   $%d" % ["CAR STORE" if _shop_cars else "GUN SHOP", GameSettings.money]
	_money.text = "$%d" % GameSettings.money
	for child in _shop_list.get_children():
		child.queue_free()
	if _shop_cars:
		_rebuild_car_shop()
		return
	for id: String in WeaponCatalog.shop_ids():
		var data := WeaponCatalog.get_data(id)
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "%s  (%s)   dmg %d  •  %d rpm  •  mag %d" % [data["name"], str(data["class"]).to_upper(), int(data["damage"]) * int(data["pellets"]), int(float(data["rate"]) * 60.0), int(data["mag"])]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 26)
		row.add_child(info)
		var action := Button.new()
		action.custom_minimum_size.x = 260
		if GameSettings.equipped_weapon == id:
			action.text = "EQUIPPED"
			action.disabled = true
		elif GameSettings.owned_weapons.has(id):
			action.text = "EQUIP"
			action.pressed.connect(_shop_equip.bind(id))
		else:
			action.text = "BUY $%d" % int(data["price"])
			action.disabled = GameSettings.money < int(data["price"])
			action.pressed.connect(_shop_buy.bind(id))
		row.add_child(action)
		_shop_list.add_child(row)


## Store exclusives (bars instead of the hidden class) + your garage.
func _rebuild_car_shop() -> void:
	var ids: Array = GameSettings.owned_cars.duplicate()
	for id: String in VehicleCatalog.STORE_CARS:
		if not ids.has(id):
			ids.append(id)
	for id: String in ids:
		var data := VehicleCatalog.get_data(id)
		var row := HBoxContainer.new()
		var info := Label.new()
		var bars := func(v: float, top: float) -> String: return "■".repeat(clampi(roundi(v / top * 8.0), 1, 8)).rpad(8, "□")
		info.text = "%s\n  SPEED %s   ACCEL %s   GRIP %s" % [data["name"], bars.call(float(data["top_speed"]), 84.0), bars.call(float(data["accel"]), 9.2), bars.call(float(data["grip"]), 4.2)]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 26)
		row.add_child(info)
		var action := Button.new()
		action.custom_minimum_size.x = 300
		var locked := int(data.get("unlock", 0)) > GameSettings.career_won
		if GameSettings.garage_car == id:
			action.text = "IN GARAGE"
			action.disabled = true
		elif GameSettings.owned_cars.has(id):
			action.text = "USE"
			action.pressed.connect(func() -> void:
				GameSettings.select_car(id)
				_rebuild_shop())
		elif locked:
			action.text = "WIN %d RACES" % int(data["unlock"])
			action.disabled = true
		else:
			action.text = "BUY $%d" % int(data["price"])
			action.disabled = GameSettings.money < int(data["price"])
			action.pressed.connect(func() -> void:
				GameSettings.buy_car(id)
				_rebuild_shop())
		row.add_child(action)
		_shop_list.add_child(row)


func _on_career() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -620
	panel.offset_right = 620
	panel.offset_top = -420
	panel.offset_bottom = 420
	add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	var title := Label.new()
	title.text = "RACE CAREER   —   car: %s" % VehicleCatalog.get_data(GameSettings.garage_car)["name"]
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_font_override("font", UITheme.TITLE_FONT)
	root.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in RaceCareer.EVENTS.size():
		var event: Dictionary = RaceCareer.EVENTS[i]
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "%d. %s   •   %d rivals   •   $%d%s" % [i + 1, event["name"], (event["rivals"] as Array).size(), int(event["reward"]), "   ✓" if i < GameSettings.career_won else ""]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 28)
		row.add_child(info)
		var go := Button.new()
		go.custom_minimum_size.x = 220
		go.text = "RACE" if RaceCareer.unlocked(i) else "LOCKED"
		go.disabled = not RaceCareer.unlocked(i)
		go.pressed.connect(Session.start_career_race.bind(i))
		row.add_child(go)
		list.add_child(row)
	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(panel.queue_free)
	root.add_child(close)


func _shop_equip(id: String) -> void:
	GameSettings.equip_weapon(id)
	_rebuild_shop()


func _shop_buy(id: String) -> void:
	GameSettings.buy_weapon(id)
	_rebuild_shop()


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

	# Big tap targets instead of a dropdown (dropdowns are fiddly on touch).
	var mode_row := HBoxContainer.new()
	for i in MP_MODES.size():
		var button := Button.new()
		button.text = Session.MODE_NAMES[MP_MODES[i]]
		button.toggle_mode = true
		button.custom_minimum_size.y = 80
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_pick_mode.bind(i))
		mode_row.add_child(button)
		_mode_buttons.append(button)
	box.add_child(mode_row)
	_refresh_mode_buttons()
	Net.lobby_mode_changed.connect(func(mode: int) -> void:
		_selected = maxi(MP_MODES.find(mode), 0)
		_refresh_mode_buttons()
	)

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
	return MP_MODES[_selected]


func _pick_mode(index: int) -> void:
	# Joined players can't change the host's mode.
	if Net.is_active() and not multiplayer.is_server():
		_refresh_mode_buttons()
		return
	_selected = index
	Net.set_lobby_mode(MP_MODES[index])
	_refresh_mode_buttons()
	if Net.is_active():
		_lobby_info.text = "Hosting %s. Friends join with: %s" % [Session.MODE_NAMES[_selected_mode()], ", ".join(Net.local_addresses())]


func _refresh_mode_buttons() -> void:
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = i == _selected


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
