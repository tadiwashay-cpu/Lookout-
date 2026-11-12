class_name Hud
extends CanvasLayer
## In-game HUD in the spirit of NFS: Most Wanted: a radar top-left, the
## tachometer with a big digital speed and nitro gauge bottom-right while
## driving, race position / lap / time, health and surge bars on foot,
## banners, a kill feed, menus, results and a pause button.

const FONT_SIZE := 26

var world: Node3D
var player: Player
var _root: Control
var _gauge: Gauge
var _radar: Radar
var _health: ProgressBar
var _surge: ProgressBar
var _prompt: Label
var _banner: Label
var _banner_sub: Label
var _top: Label
var _top_sub: Label
var _race: Label
var _feed: VBoxContainer
var _flash: ColorRect
var _fader: ColorRect
var _menu: PanelContainer
var _menu_rows: VBoxContainer
var _menu_source: Callable
var _banner_time := 0.0


func _ready() -> void:
	layer = 10
	add_to_group(&"hud")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_flash = _rect(Color(0.7, 0.0, 0.0, 0.0))
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_radar = Radar.new()
	_radar.position = Vector2(24, 24)
	_root.add_child(_radar)
	_health = _bar(Vector2(24, 286), Color(0.85, 0.15, 0.12))
	_surge = _bar(Vector2(24, 304), Color(0.3, 0.75, 1.0))
	_gauge = Gauge.new()
	pin(_gauge, Vector2(0.5, 1.0), Vector2(-135, -280), Vector2(270, 270))
	_gauge.visible = false
	_root.add_child(_gauge)
	_prompt = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	pin(_prompt, Vector2(0.5, 1.0), Vector2(-400, -330), Vector2(800, 40))
	_banner = _label(110, HORIZONTAL_ALIGNMENT_CENTER)
	pin(_banner, Vector2(0.5, 0.5), Vector2(-600, -220), Vector2(1200, 130))
	_banner_sub = _label(32, HORIZONTAL_ALIGNMENT_CENTER)
	pin(_banner_sub, Vector2(0.5, 0.5), Vector2(-600, -80), Vector2(1200, 40))
	_top = _label(30, HORIZONTAL_ALIGNMENT_CENTER)
	pin(_top, Vector2(0.5, 0.0), Vector2(-450, 18), Vector2(900, 36))
	_top_sub = _label(22, HORIZONTAL_ALIGNMENT_CENTER)
	pin(_top_sub, Vector2(0.5, 0.0), Vector2(-450, 58), Vector2(900, 30))
	_race = _label(34, HORIZONTAL_ALIGNMENT_RIGHT)
	pin(_race, Vector2(1.0, 0.0), Vector2(-520, 90), Vector2(490, 200))
	_feed = VBoxContainer.new()
	pin(_feed, Vector2(1.0, 0.0), Vector2(-560, 300), Vector2(530, 200))
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)
	var pause := Button.new()
	pause.text = "II"
	pause.add_theme_font_size_override("font_size", 30)
	pin(pause, Vector2(1.0, 0.0), Vector2(-84, 16), Vector2(64, 60))
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(_pause_menu)
	_root.add_child(pause)
	_fader = _rect(Color(0, 0, 0, 0))
	_fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Pin `c` to a point of the screen (anchor 0..1) with an offset and size.
static func pin(c: Control, anchor: Vector2, offset: Vector2, size: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y


func bind(w: Node3D) -> void:
	world = w
	player = w.get("player")
	_radar.world = w
	_radar.player = player
	player.interact_changed.connect(func(text: String) -> void: _prompt.text = ("ENTER  •  " + text) if text != "" else "")


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _label(size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _bar(pos: Vector2, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = Vector2(240, 12)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(b)
	return b


func _process(delta: float) -> void:
	if player == null:
		return
	_health.value = player.health / player.max_health * 100.0
	_surge.value = player.surge
	var car := player.car
	_gauge.visible = car != null
	_health.visible = car == null
	_surge.visible = car == null
	if car:
		_gauge.speed = car.speed_kmh()
		_gauge.rpm = car.rpm
		_gauge.gear = car.gear if car.forward_speed() > -0.5 else -1
		_gauge.nitro = car.nitro
		_gauge.nitro_on = car.nitro_on
		_gauge.damage = 1.0 - car.health / float(car.data["health"])
		_gauge.queue_redraw()
	_flash.color.a = maxf(_flash.color.a - delta * 1.5, 0.0)
	if _banner_time > 0.0:
		_banner_time -= delta
		if _banner_time <= 0.0:
			_banner.text = ""
			_banner_sub.text = ""
	if _menu and _menu.visible and _menu_source.is_valid():
		pass


func banner(text: String, sub: String = "", seconds: float = 2.0) -> void:
	_banner.text = text
	_banner_sub.text = sub
	_banner_time = seconds
	_banner.scale = Vector2.ONE * 1.25
	_banner.pivot_offset = _banner.size * 0.5
	create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func set_top(text: String, sub: String = "") -> void:
	_top.text = text
	_top_sub.text = sub


func set_race(pos: int, total: int, lap: int, laps: int, t: float, grenades: int, surge: float) -> void:
	_race.text = "POS  %d/%d\nLAP  %d/%d\n%d:%05.2f\nGRENADES %d   SURGE %d%%" % [pos, total, lap, laps, int(t) / 60, fmod(t, 60.0), grenades, int(surge)]


func feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_feed.add_child(l)
	if _feed.get_child_count() > 5:
		_feed.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func damage_flash(strength: float) -> void:
	_flash.color.a = maxf(_flash.color.a, 0.35 * strength)


func fade(out: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_fader, "color:a", 1.0 if out else 0.0, 0.3)
	await tw.finished


# ----------------------------------------------------------------- menus

## rows_source() -> [[label, button_text, Callable], ...]
func open_menu(title: String, rows_source: Callable) -> void:
	_close_menu()
	_menu_source = rows_source
	_menu = PanelContainer.new()
	pin(_menu, Vector2(0.5, 0.5), Vector2(-420, -300), Vector2(840, 600))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.05, 0.94)
	style.border_color = Color(1.0, 0.55, 0.1)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	_menu.add_theme_stylebox_override("panel", style)
	_root.add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 44)
	box.add_child(head)
	_menu_rows = VBoxContainer.new()
	_menu_rows.add_theme_constant_override("separation", 10)
	box.add_child(_menu_rows)
	var close := Button.new()
	close.text = "CLOSE"
	close.add_theme_font_size_override("font_size", 30)
	close.custom_minimum_size = Vector2(0, 64)
	close.pressed.connect(_close_menu)
	box.add_child(close)
	_fill_menu()
	if player:
		player.controls_enabled = false


func _fill_menu() -> void:
	for c in _menu_rows.get_children():
		c.queue_free()
	for row: Array in _menu_source.call():
		var line := HBoxContainer.new()
		var l := Label.new()
		l.text = str(row[0])
		l.add_theme_font_size_override("font_size", 26)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_child(l)
		if str(row[1]) != "":
			var b := Button.new()
			b.text = str(row[1])
			b.custom_minimum_size = Vector2(170, 58)
			b.add_theme_font_size_override("font_size", 26)
			var action: Callable = row[2]
			b.pressed.connect(func() -> void:
				if action.is_valid():
					action.call()
				_fill_menu.call_deferred())
			line.add_child(b)
		_menu_rows.add_child(line)


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null
	if player:
		player.controls_enabled = true


func results(title: String, rows: Array, footer: String) -> void:
	open_menu(title, func() -> Array:
		var out: Array = []
		for r in rows:
			out.append([str(r[0]) + "     " + str(r[1]), "", Callable()])
		out.append([footer, "MENU", func() -> void: Game.back_to_menu()])
		return out)


func _pause_menu() -> void:
	open_menu("PAUSED", func() -> Array:
		return [
			["Cash: $%d" % Game.money, "", Callable()],
			["Back to the main menu", "QUIT", func() -> void: Game.back_to_menu()],
		])


# ================================================================= gauge

class Gauge:
	extends Control
	## NFS: Most Wanted style tach: arc, redline, needle, big digital speed,
	## gear, nitro arc and a damage bar.
	var speed := 0.0
	var rpm := 0.0
	var gear := 1
	var nitro := 0.0
	var nitro_on := false
	var damage := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		var a0 := deg_to_rad(140.0)
		var a1 := deg_to_rad(400.0)
		draw_circle(c, r + 8.0, Color(0, 0, 0, 0.55))
		draw_arc(c, r, a0, a1, 64, Color(1, 1, 1, 0.25), 6.0, true)
		draw_arc(c, r, lerpf(a0, a1, 0.82), a1, 16, Color(0.9, 0.12, 0.08), 8.0, true)
		for i in 9:
			var a := lerpf(a0, a1, i / 8.0)
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * (r - 18.0), c + dir * (r - 4.0), Color(1, 1, 1, 0.8), 3.0, true)
			draw_string(ThemeDB.fallback_font, c + dir * (r - 38.0) - Vector2(8, -8), str(i), HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(1, 1, 1, 0.75))
		var na := lerpf(a0, a1, clampf(rpm, 0.0, 1.0))
		draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 10.0), Color(1.0, 0.45, 0.1), 5.0, true)
		draw_circle(c, 10.0, Color(0.1, 0.1, 0.1))
		# Nitro: inner arc, blue, glows while burning.
		var nc := Color(0.35, 0.75, 1.0) if not nitro_on else Color(0.7, 0.95, 1.0)
		draw_arc(c, r - 54.0, a0, lerpf(a0, a0 + deg_to_rad(110.0), nitro), 32, nc, 10.0, true)
		draw_string(ThemeDB.fallback_font, c + Vector2(-90, 60), "N2O", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, nc)
		# Digital speed and gear.
		draw_string(ThemeDB.fallback_font, c + Vector2(-90, 34), "%3d" % int(speed), HORIZONTAL_ALIGNMENT_CENTER, 180, 64, Color(1, 1, 1))
		draw_string(ThemeDB.fallback_font, c + Vector2(-90, 64), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 180, 18, Color(1, 1, 1, 0.7))
		draw_string(ThemeDB.fallback_font, c + Vector2(30, -26), "R" if gear < 0 else str(gear), HORIZONTAL_ALIGNMENT_CENTER, 60, 40, Color(1.0, 0.55, 0.1))
		# Damage strip.
		draw_rect(Rect2(c + Vector2(-70, r - 6.0), Vector2(140, 8)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c + Vector2(-70, r - 6.0), Vector2(140 * (1.0 - damage), 8)), Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.2, 0.1), damage))


# ================================================================= radar

class Radar:
	extends Control
	## Round radar: roads and city blocks around you, rotated to your heading.
	var world: Node3D
	var player: Player
	const R := 120.0
	const RANGE := 260.0

	func _ready() -> void:
		size = Vector2(R * 2.0, R * 2.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if world == null or player == null:
			return
		var c := Vector2(R, R)
		draw_circle(c, R + 4.0, Color(0, 0, 0, 0.6))
		draw_circle(c, R, Color(0.06, 0.08, 0.1, 0.85))
		var focus: Node3D = player.car if player.car else player
		var p := focus.global_position
		var yaw := atan2(focus.global_basis.z.x, focus.global_basis.z.z) if player.car else player.cam.yaw + PI
		var to_map := func(w: Vector3) -> Vector2:
			var d := Vector2(w.x - p.x, w.z - p.z).rotated(yaw) * (R / RANGE)
			return c + Vector2(-d.x, -d.y) if false else c + Vector2(d.x, d.y)
		var roads: Roads = world.get("roads")
		for road_name in roads.paths:
			var pts: Array = roads.paths[road_name]
			for i in range(0, pts.size() - 4, 4):
				var a: Vector2 = to_map.call(pts[i])
				var b: Vector2 = to_map.call(pts[i + 4])
				if a.distance_to(c) < R and b.distance_to(c) < R:
					draw_line(a, b, Color(0.75, 0.75, 0.7), 4.0)
		for x: float in Layout.CITY_X:
			_clip_line(to_map.call(Vector3(x, 0, Layout.CITY_Z[0])), to_map.call(Vector3(x, 0, Layout.CITY_Z[Layout.CITY_Z.size() - 1])), c)
		for z: float in Layout.CITY_Z:
			_clip_line(to_map.call(Vector3(Layout.CITY_X[0], 0, z)), to_map.call(Vector3(Layout.CITY_X[Layout.CITY_X.size() - 1], 0, z)), c)
		for node in get_tree().get_nodes_in_group(&"cars"):
			var car := node as Car
			if car.driver == null and not car.ai_enabled and car.owner_peer == 0:
				continue
			var m: Vector2 = to_map.call(car.global_position)
			if m.distance_to(c) < R and car != player.car:
				draw_circle(m, 5.0, Color(1.0, 0.3, 0.2))
		for node in get_tree().get_nodes_in_group(&"fighters"):
			var f := node as Fighter
			if f == player or f.is_in_group(&"civilians") or not f.alive:
				continue
			var m: Vector2 = to_map.call(f.global_position)
			if m.distance_to(c) < R:
				draw_circle(m, 4.0, Color(1.0, 0.75, 0.2))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(8, 8), c + Vector2(-8, 8)]), Color(0.3, 0.8, 1.0))
		draw_string(ThemeDB.fallback_font, c + Vector2(-6, -R + 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))

	func _clip_line(a: Vector2, b: Vector2, c: Vector2) -> void:
		var steps := 12
		for i in steps:
			var p0 := a.lerp(b, float(i) / steps)
			var p1 := a.lerp(b, float(i + 1) / steps)
			if p0.distance_to(c) < R and p1.distance_to(c) < R:
				draw_line(p0, p1, Color(0.6, 0.6, 0.58), 5.0)
