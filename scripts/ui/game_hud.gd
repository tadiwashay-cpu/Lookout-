class_name GameHUD
extends CanvasLayer
## In-game HUD: minimap (top-left) with health under it, heat stars and
## weapon info (top-right), mode status (top-centre), crosshair, banners,
## hints, speedometer, pause menu (II) and the end-of-match results.

var _world: World
var _player: PlayerController
var _root: Control
var _minimap: Minimap
var _health_bar: ProgressBar
var _status: Label
var _banner: Label
var _hint: Label
var _speed: Label
var _ammo: Label
var _gear: Label
var _crosshair: Control
var _wanted: WantedStars
var _pause_panel: PanelContainer
var _settings: SettingsPanel
var _results: PanelContainer
var _banner_tween: Tween
var _clock: Label
var _bust: ProgressBar
var _surge_bar: ProgressBar
var _surge_fill: StyleBoxFlat
var _hint_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_minimap = Minimap.new()
	_minimap.position = Vector2(20, 20)
	_root.add_child(_minimap)

	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.position = Vector2(28, 282)
	_health_bar.size = Vector2(240, 18)
	_health_bar.add_theme_stylebox_override("background", _flat_box(Color(0, 0, 0, 0.5)))
	_health_bar.add_theme_stylebox_override("fill", _flat_box(Color(0.93, 0.91, 0.86)))
	_root.add_child(_health_bar)

	_clock = _label(22, HORIZONTAL_ALIGNMENT_LEFT)
	_clock.position = Vector2(28, 304)
	_clock.size = Vector2(240, 30)
	_root.add_child(_clock)

	_bust = ProgressBar.new()
	_bust.show_percentage = false
	_place(_bust, Control.PRESET_CENTER, -220, 70, 220, 92)
	_bust.add_theme_stylebox_override("background", _flat_box(Color(0, 0, 0, 0.5)))
	_bust.add_theme_stylebox_override("fill", _flat_box(Color(0.25, 0.45, 1.0)))
	_bust.max_value = 1.0
	_bust.visible = false
	_root.add_child(_bust)

	# Surge meter (Clean Hands): fills as your punches land, glows when full.
	_surge_bar = ProgressBar.new()
	_surge_bar.show_percentage = false
	_surge_bar.position = Vector2(28, 340)
	_surge_bar.size = Vector2(240, 12)
	_surge_bar.max_value = 1.0
	_surge_fill = _flat_box(Color(1.0, 0.62, 0.2))
	_surge_bar.add_theme_stylebox_override("background", _flat_box(Color(0, 0, 0, 0.5)))
	_surge_bar.add_theme_stylebox_override("fill", _surge_fill)
	_surge_bar.visible = false
	_root.add_child(_surge_bar)

	_wanted = WantedStars.new()
	_place(_wanted, Control.PRESET_TOP_RIGHT, -420, 18, -120, 74)
	_root.add_child(_wanted)

	_ammo = _label(40, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_ammo, Control.PRESET_TOP_RIGHT, -420, 80, -40, 130)
	_root.add_child(_ammo)
	_gear = _label(24, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_gear, Control.PRESET_TOP_RIGHT, -520, 132, -40, 170)
	_root.add_child(_gear)

	_status = _label(28, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_status, Control.PRESET_CENTER_TOP, -560, 22, 560, 110)
	_root.add_child(_status)

	_banner = _label(72, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_banner, Control.PRESET_CENTER, -760, -220, 760, -60)
	_banner.modulate.a = 0.0
	_root.add_child(_banner)

	_hint = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_hint, Control.PRESET_CENTER_BOTTOM, -640, -300, 640, -150)
	_hint.modulate.a = 0.0
	_root.add_child(_hint)

	_speed = _label(54, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_speed, Control.PRESET_CENTER_BOTTOM, -200, -110, 200, -30)
	_speed.visible = false
	_root.add_child(_speed)

	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	_root.add_child(_crosshair)

	var pause := Button.new()
	pause.text = "II"
	_place(pause, Control.PRESET_TOP_RIGHT, -100, 18, -24, 90)
	pause.pressed.connect(_open_pause)
	_root.add_child(pause)
	_build_pause_menu()


func bind_world(world: World) -> void:
	_world = world
	_minimap.world = world


func bind_player(player: PlayerController) -> void:
	_player = player
	_minimap.player = player
	player.health.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health.current, player.health.max_health)
	player.knocked_out.connect(func() -> void: show_banner("DOWN", 2.0))
	player.vehicle_changed.connect(func(vehicle: DrivableCar) -> void: _speed.visible = vehicle != null)
	player.ammo_changed.connect(func(_a: int, _r: int) -> void: _refresh_weapon())
	player.loadout_changed.connect(_refresh_weapon)
	_refresh_weapon()


func bind_mode(mode: GameMode) -> void:
	mode.status_changed.connect(func(text: String) -> void: _status.text = text)
	_wanted.visible = Session.mode == Session.MODE_STORY


func _process(_delta: float) -> void:
	if _player == null:
		return
	if _player.current_vehicle:
		_speed.text = "%d km/h" % roundi(absf(_player.current_vehicle.forward_speed()) * 3.6)
	if _world and _world.day_night:
		_clock.text = _world.day_night.clock_text()
	if _world and _world.police:
		var progress := _world.police.busting_progress()
		_bust.visible = progress > 0.05
		_bust.value = progress
		if _bust.visible:
			_hint.text = "BUSTED…  get moving!"
			_hint.modulate.a = 1.0
	_surge_bar.visible = _player.surge_needs_meter and _player.current_vehicle == null
	if _surge_bar.visible:
		var fill := _player.surge_ready()
		_surge_bar.value = fill
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
		_surge_fill.bg_color = Color(1.0, 0.85, 0.35) * pulse if fill >= 1.0 else Color(1.0, 0.55, 0.2)
	_crosshair.visible = _player.is_armed() and _player.current_vehicle == null and _player.is_alive()
	_crosshair.queue_redraw()
	if _player.is_armed():
		_gear.text = "Grenades %d %s   Surge %s" % [_player.grenades, "" if _player.grenade_ready() >= 1.0 else "(%d%%)" % int(_player.grenade_ready() * 100), "READY" if _player.surge_ready() >= 1.0 else "%d%%" % int(_player.surge_ready() * 100)]
	else:
		_gear.text = "Fists only   Surge %s" % ("READY" if _player.surge_ready() >= 1.0 else "%d%%" % int(_player.surge_ready() * 100))


func _refresh_weapon() -> void:
	if _player == null:
		return
	if _player.is_armed():
		_ammo.text = "%d / %d%s" % [_player.ammo, _player.reserve, "  RELOADING" if _player.is_reloading() else ""]
	else:
		_ammo.text = ""


func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	var gap := 6.0 if _player and _player.aiming else 12.0
	var color := Color(1, 1, 1, 0.85)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_crosshair.draw_line(c + d * gap, c + d * (gap + 10.0), color, 2.0)
	_crosshair.draw_circle(c, 1.6, color)


func show_banner(text: String, hold: float, font_size: int = 72) -> void:
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", font_size)
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func show_hint(text: String) -> void:
	_hint.text = text
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 0.15)
	_hint_tween.tween_interval(3.5)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.4)


func show_results(title: String, detail: String, won: bool) -> void:
	if _results:
		return
	_results = PanelContainer.new()
	_place(_results, Control.PRESET_CENTER, -420, -220, 420, 220)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_results.add_child(box)
	var heading := _label(64, HORIZONTAL_ALIGNMENT_CENTER)
	heading.text = title
	heading.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45) if won else Color(0.9, 0.9, 0.88))
	box.add_child(heading)
	var info := _label(36, HORIZONTAL_ALIGNMENT_CENTER)
	info.text = detail
	box.add_child(info)
	var back := Button.new()
	back.text = "BACK TO MENU"
	back.pressed.connect(Session.back_to_menu)
	box.add_child(back)
	_root.add_child(_results)


# ---------------------------------------------------------------- pause

func _build_pause_menu() -> void:
	_pause_panel = PanelContainer.new()
	_place(_pause_panel, Control.PRESET_CENTER, -300, -260, 300, 260)
	_pause_panel.visible = false
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_panel.add_child(box)
	var title := _label(52, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "PAUSED"
	box.add_child(title)
	for entry: Array in [["RESUME", _close_pause], ["SETTINGS", _open_settings], ["QUIT TO MENU", Session.back_to_menu]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		box.add_child(button)
	_root.add_child(_pause_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _pause_panel.visible:
			_close_pause()
		else:
			_open_pause()


func _open_pause() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_panel.visible = true
	if not Session.networked:
		get_tree().paused = true


func _close_pause() -> void:
	_pause_panel.visible = false
	get_tree().paused = false


func _open_settings() -> void:
	_pause_panel.visible = false
	_settings = SettingsPanel.new()
	_place(_settings, Control.PRESET_CENTER, -560, -380, 560, 380)
	_settings.closed.connect(func() -> void:
		_settings.queue_free()
		_pause_panel.visible = true
	)
	_root.add_child(_settings)


# -------------------------------------------------------------- helpers

func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _place(control: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


func _label(font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	return label


func _flat_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	return box
