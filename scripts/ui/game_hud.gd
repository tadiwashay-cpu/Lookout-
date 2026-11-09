class_name GameHUD
extends CanvasLayer
## Minimal, readable HUD: health top-left, heat top-right, objective top-centre,
## big centre banner for knock-outs and mission results.

var _health_bar: ProgressBar
var _objective: Label
var _banner: Label
var _wanted: WantedStars


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.position = Vector2(48, 40)
	_health_bar.size = Vector2(420, 22)
	_health_bar.add_theme_stylebox_override("background", _flat_box(Color(0, 0, 0, 0.45)))
	_health_bar.add_theme_stylebox_override("fill", _flat_box(Color(0.93, 0.91, 0.86)))
	root.add_child(_health_bar)

	_wanted = WantedStars.new()
	_place(_wanted, Control.PRESET_TOP_RIGHT, -348, 24, -48, 80)
	root.add_child(_wanted)

	_objective = _make_label(28, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_objective, Control.PRESET_CENTER_TOP, -600, 28, 600, 118)
	root.add_child(_objective)

	_banner = _make_label(72, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_banner, Control.PRESET_CENTER, -700, -160, 700, 0)
	_banner.modulate.a = 0.0
	root.add_child(_banner)


func bind_player(player: PlayerController) -> void:
	player.health.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health.current, player.health.max_health)
	player.knocked_out.connect(func() -> void: show_banner("KNOCKED OUT", 2.5))


func bind_challenge(challenge: CleanHandsChallenge) -> void:
	challenge.objectives_changed.connect(func(text: String) -> void: _objective.text = text)
	challenge.completed.connect(func(summary: String) -> void: show_banner(summary, 6.0))
	challenge.failed.connect(func(reason: String) -> void: show_banner(reason, 4.0, 36))


func show_banner(text: String, hold: float, font_size: int = 72) -> void:
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", font_size)
	var tween := create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 0.2)
	tween.tween_interval(hold)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


## Anchors a control to a preset and positions it with offsets from that anchor.
func _place(control: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


func _make_label(font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
