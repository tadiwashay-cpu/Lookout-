class_name SettingsPanel
extends PanelContainer
## Graphics / Controls / Sound / Profile. Changes apply live and are saved.

signal closed


func _ready() -> void:
	theme = UITheme.get_theme()
	custom_minimum_size = Vector2(1100, 720)
	var root := VBoxContainer.new()
	add_child(root)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 44)
	root.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var graphics := _page(tabs, "Graphics")
	_option(graphics, "Quality", ["Low (best battery)", "Medium", "High"], GameSettings.quality, func(i: int) -> void: GameSettings.set_quality(i))
	_slider(graphics, "Render scale", 0.5, 1.0, 0.05, GameSettings.render_scale, func(v: float) -> void: GameSettings.render_scale = v)
	_check(graphics, "Shadows", GameSettings.shadows_enabled, func(on: bool) -> void: GameSettings.shadows_enabled = on)
	_slider(graphics, "View distance (m)", 150.0, 800.0, 25.0, GameSettings.view_distance, func(v: float) -> void: GameSettings.view_distance = v)
	_option(graphics, "Frame rate", ["30 FPS", "60 FPS"], 1 if GameSettings.fps_cap >= 60 else 0, func(i: int) -> void: GameSettings.fps_cap = 60 if i == 1 else 30)
	_check(graphics, "Motion blur", GameSettings.motion_blur, func(on: bool) -> void: GameSettings.motion_blur = on)
	_slider(graphics, "Day length (minutes)", 4.0, 60.0, 1.0, GameSettings.day_length_minutes, func(v: float) -> void: GameSettings.day_length_minutes = v)

	var controls := _page(tabs, "Controls")
	_option(controls, "Camera", ["Third person", "First person"], GameSettings.camera_mode, func(i: int) -> void: GameSettings.set_camera_mode(i))
	_slider(controls, "Look sensitivity", 0.3, 2.5, 0.05, GameSettings.look_sensitivity, func(v: float) -> void: GameSettings.look_sensitivity = v)
	_check(controls, "Invert look up/down", GameSettings.invert_look_y, func(on: bool) -> void: GameSettings.invert_look_y = on)
	_slider(controls, "Button size", 0.8, 1.4, 0.05, GameSettings.button_scale, func(v: float) -> void: GameSettings.button_scale = v)
	_check(controls, "Vibration", GameSettings.haptics_enabled, func(on: bool) -> void: GameSettings.haptics_enabled = on)

	var sound := _page(tabs, "Sound")
	_slider(sound, "Master", 0.0, 1.0, 0.05, GameSettings.master_volume, func(v: float) -> void: GameSettings.master_volume = v)
	_slider(sound, "Music", 0.0, 1.0, 0.05, GameSettings.music_volume, func(v: float) -> void: GameSettings.music_volume = v)
	_slider(sound, "Effects", 0.0, 1.0, 0.05, GameSettings.sfx_volume, func(v: float) -> void: GameSettings.sfx_volume = v)

	var profile := _page(tabs, "Profile")
	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Player name"
	name_label.custom_minimum_size.x = 380
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = GameSettings.player_name
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t: String) -> void: GameSettings.player_name = t.strip_edges() if t.strip_edges() != "" else "Player")
	name_row.add_child(name_edit)
	profile.add_child(name_row)
	var money := Label.new()
	money.text = "Money: $%d" % GameSettings.money
	profile.add_child(money)

	var done := Button.new()
	done.text = "DONE"
	done.pressed.connect(_close)
	root.add_child(done)


func _close() -> void:
	GameSettings.apply_all()
	GameSettings.save()
	closed.emit()


func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 380
	row.add_child(label)
	parent.add_child(row)
	return row


func _slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> void:
	var row := _row(parent, text)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(460, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := Label.new()
	readout.custom_minimum_size.x = 110
	readout.text = str(snappedf(value, step))
	var handler := func(v: float) -> void:
		readout.text = str(snappedf(v, step))
		on_change.call(v)
		GameSettings.apply_all()
	slider.value_changed.connect(handler)
	row.add_child(slider)
	row.add_child(readout)


func _check(parent: Control, text: String, value: bool, on_change: Callable) -> void:
	var row := _row(parent, text)
	var toggle := CheckButton.new()
	toggle.button_pressed = value
	var handler := func(on: bool) -> void:
		on_change.call(on)
		GameSettings.apply_all()
	toggle.toggled.connect(handler)
	row.add_child(toggle)


func _option(parent: Control, text: String, items: Array, selected: int, on_change: Callable) -> void:
	var row := _row(parent, text)
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item)
	option.selected = clampi(selected, 0, items.size() - 1)
	var handler := func(i: int) -> void:
		on_change.call(i)
		GameSettings.apply_all()
	option.item_selected.connect(handler)
	row.add_child(option)
