extends Node
## Global game state: profile (money, name), settings, the input map and the
## match that is about to be played. Saved to user://lookout.cfg.

const SAVE_PATH := "user://lookout.cfg"
const WORLD_SCENE := "res://scenes/world.tscn"
const MENU_SCENE := "res://scenes/main.tscn"

enum Mode { FREE_ROAM, CLEAN_HANDS, RACE }

## Layers (see project settings).
const L_WORLD := 1
const L_CHARS := 2
const L_CARS := 4
const L_TRIGGERS := 8
const L_BARRIER := 16       # blocks characters, not the camera

var player_name := "Nash"
var money := 500
var quality := 2            # 0 low, 1 medium, 2 high, 3 ultra
var show_fps := false
var look_sensitivity := 1.0
var view_distance := 900.0

## The match being started: {"mode": Mode, "networked": bool, "minutes": int,
## "bots": int, "laps": int, "seed": int}
var match_config: Dictionary = {"mode": Mode.FREE_ROAM, "networked": false}

signal money_changed(amount: int)
signal tune_changed

const BUILD_NAME := "Playtest"

var _hitstop_until := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	_load()


func _notification(what: int) -> void:
	# Closing or backgrounding the app mid-match still logs the session.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_session_end()


# ------------------------------------------------------------------ profile

## "0.3.0" (project setting application/config/version).
func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	save()
	if amount != 0:
		money_changed.emit(amount)


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("profile", "name", player_name)
	c.set_value("profile", "money", money)
	c.set_value("settings", "quality", quality)
	c.set_value("settings", "look", look_sensitivity)
	c.set_value("settings", "fps", show_fps)
	c.set_value("settings", "tune", tune_stage)
	c.set_value("settings", "version", version())
	c.save(SAVE_PATH)


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(SAVE_PATH) != OK:
		return
	player_name = c.get_value("profile", "name", player_name)
	money = c.get_value("profile", "money", money)
	quality = c.get_value("settings", "quality", quality)
	look_sensitivity = c.get_value("settings", "look", look_sensitivity)
	show_fps = c.get_value("settings", "fps", show_fps)
	quality = clampi(quality, 0, 3)
	# What the auto-tuner learned on this device (forgotten on a new version).
	if str(c.get_value("settings", "version", "")) == version():
		tune_stage = clampi(int(c.get_value("settings", "tune", 0)), 0, TUNE_MAX)
	view_distance = preset()["view"]


# ---------------------------------------------------------------- graphics

## Graphics presets. The 3D scene renders at a fixed number of lines
## (`lines`), whatever the screen: a 2.5K tablet panel has four times the
## pixels its GPU can shade at 60 fps, so the picture is drawn at ~800p and
## FSR sharpens it up to the panel (the HUD stays native and crisp). The
## governor lowers the resolution a little while the frame rate dips and
## gives it back when there's headroom; if that isn't enough it switches
## off the most expensive effect, one step at a time (the "tune stage").
const PRESETS := [
	{"name": "LOW", "lines": 540.0, "min": 0.8, "msaa": 0, "shadow": 0.0, "shadow_size": 1024, "glow": false, "view": 550.0, "trees": 0.45, "fsr": false},
	{"name": "MEDIUM", "lines": 660.0, "min": 0.8, "msaa": 0, "shadow": 55.0, "shadow_size": 2048, "glow": false, "view": 750.0, "trees": 0.7, "fsr": true},
	{"name": "HIGH", "lines": 800.0, "min": 0.78, "msaa": 1, "shadow": 75.0, "shadow_size": 2048, "glow": true, "view": 900.0, "trees": 1.0, "fsr": true},
	{"name": "ULTRA", "lines": 1080.0, "min": 0.75, "msaa": 2, "shadow": 120.0, "shadow_size": 4096, "glow": true, "view": 1200.0, "trees": 1.0, "fsr": true},
]
const TUNE_MAX := 3
var render_scale := 0.0
var tune_stage := 0          # 0 full preset, 1 no glow, 2 short shadows + no MSAA, 3 no shadows
var _max_scale := 1.0
var _min_scale := 0.5
var _slow_windows := 0


func preset() -> Dictionary:
	return PRESETS[clampi(quality, 0, PRESETS.size() - 1)]


func set_quality(q: int) -> void:
	quality = clampi(q, 0, PRESETS.size() - 1)
	view_distance = preset()["view"]
	tune_stage = 0
	render_scale = 0.0


## Effective settings after auto-tuning.
func glow_on() -> bool:
	return bool(preset()["glow"]) and tune_stage < 1


func shadow_distance() -> float:
	var d: float = preset()["shadow"]
	return 0.0 if tune_stage >= 3 else (d * 0.6 if tune_stage >= 2 else d)


func msaa_level() -> int:
	return 0 if tune_stage >= 2 else int(preset()["msaa"])


## Viewport-level settings (called by the world).
func apply_viewport(vp: Viewport) -> void:
	var p := preset()
	var screen_lines := float(maxi(vp.get_window().size.y, 360))
	_max_scale = clampf(float(p["lines"]) / screen_lines, 0.3, 1.0)
	_min_scale = _max_scale * float(p["min"])
	render_scale = clampf(render_scale if render_scale > 0.0 else _max_scale, _min_scale, _max_scale)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if p["fsr"] and _max_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	vp.fsr_sharpness = 0.2
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa_level()]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 2.0 if quality < 2 else 1.0
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow_size"]), true)
	Engine.max_fps = 60


var _fps_time := 0.0
var _fps_frames := 0


## Dynamic resolution + auto-tune: hold 60 fps.
func govern_resolution(vp: Viewport, delta: float) -> void:
	_fps_time += delta / maxf(Engine.time_scale, 0.05)
	_fps_frames += 1
	if _fps_time < 1.5:
		return
	var fps := _fps_frames / _fps_time
	_fps_time = 0.0
	_fps_frames = 0
	_record(fps)
	if loading_active():
		return
	var before := render_scale
	if fps < 53.0:
		render_scale = maxf(render_scale - 0.06 * _max_scale, _min_scale)
	elif fps > 58.5:
		render_scale = minf(render_scale + 0.03 * _max_scale, _max_scale)
	if render_scale != before:
		vp.scaling_3d_scale = render_scale
	# Already at the lowest resolution and still slow: drop an effect.
	if fps < 50.0 and render_scale <= _min_scale + 0.001:
		_slow_windows += 1
		if _slow_windows >= 3 and tune_stage < TUNE_MAX:
			_slow_windows = 0
			tune_stage += 1
			vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa_level()]
			tune_changed.emit()
			save()
	else:
		_slow_windows = 0


# -------------------------------------------------------- playtest report

const REPORT_PATH := "user://playtest.json"
var _session: Dictionary = {}


func _session_begin() -> void:
	_session = {"mode": ["Free roam", "Clean Hands", "Race"][clampi(mode(), 0, 2)], "online": bool(match_config.get("networked", false)),
		"quality": preset()["name"], "sum": 0.0, "n": 0, "worst": 999.0, "low": 0, "scale": 0.0, "start": Time.get_ticks_msec()}


func _record(fps: float) -> void:
	if _session.is_empty() or loading_active():
		return
	_session["sum"] += fps
	_session["n"] += 1
	_session["worst"] = minf(_session["worst"], fps)
	_session["scale"] += render_scale
	if fps < 50.0:
		_session["low"] += 1


func _session_end() -> void:
	if _session.is_empty() or int(_session["n"]) < 4:
		_session = {}
		return
	var n := float(_session["n"])
	var entry := {"v": version(), "mode": _session["mode"], "online": _session["online"], "quality": _session["quality"],
		"secs": int((Time.get_ticks_msec() - int(_session["start"])) / 1000.0), "avg": snappedf(float(_session["sum"]) / n, 0.1),
		"worst": snappedf(float(_session["worst"]), 0.1), "slow_pct": int(100.0 * float(_session["low"]) / n),
		"lines": int(float(_session["scale"]) / n * float(get_window().size.y)), "tune": tune_stage,
		"when": Time.get_datetime_string_from_system(false, true)}
	_session = {}
	var list := sessions()
	list.append(entry)
	while list.size() > 20:
		list.pop_front()
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(list))


func sessions() -> Array:
	if not FileAccess.file_exists(REPORT_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REPORT_PATH))
	return parsed if parsed is Array else []


## Everything a tester needs to send back, as plain text.
func report_text() -> String:
	var size := get_window().size
	var lines: Array[String] = [
		"LOOKOUT v%s (%s) playtest report" % [version(), BUILD_NAME],
		"Device: %s  •  %s" % [OS.get_model_name(), OS.get_name()],
		"GPU: %s" % RenderingServer.get_video_adapter_name(),
		"Screen: %dx%d  •  RAM: %d MB" % [size.x, size.y, int(OS.get_memory_info().get("physical", 0) / 1048576.0)],
		"Graphics: %s  •  auto-tune stage %d/%d" % [preset()["name"], tune_stage, TUNE_MAX],
		"",
		"Sessions (newest last):",
	]
	var list := sessions()
	if list.is_empty():
		lines.append("  none yet: play a mode for at least 10 seconds, then come back here.")
	for e: Dictionary in list.slice(maxi(list.size() - 10, 0)):
		lines.append("  v%s %s%s  %s  %ds  avg %.0f fps  worst %.0f  slow %d%%  %dp  tune %d" % [e.get("v", "?"), e.get("mode", "?"),
			" (online)" if e.get("online", false) else "", e.get("quality", "?"), int(e.get("secs", 0)), float(e.get("avg", 0)),
			float(e.get("worst", 0)), int(e.get("slow_pct", 0)), int(e.get("lines", 0)), int(e.get("tune", 0))])
	return "\n".join(lines)


# ---------------------------------------------------------------- loading

const TIPS := [
	"Tap HEAVY next to a dazed fighter for a finisher.",
	"Hold BLOCK and face your opponent: blocked hits barely hurt.",
	"SURGE blasts everyone around you. It fills as you land and take hits.",
	"DRIFT through bends to refill nitro faster.",
	"A smoking car is about to blow. Find the AUTO REPAIR shop.",
	"Tap the radar to open the full map.",
	"Stomp a fighter who is on the ground with HEAVY.",
	"Light scrapes don't slow your car down. Head-on hits do.",
	"Friends on the same Wi-Fi see your hosted game under JOIN.",
]
var _loading: CanvasLayer
var _loading_bar: ProgressBar
var _loading_label: Label
var _loading_target := 0.0


func loading_active() -> bool:
	return _loading != null


func _loading_begin() -> void:
	if _loading:
		return
	_loading = CanvasLayer.new()
	_loading.layer = 100
	add_child(_loading)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(root)
	var black := ColorRect.new()
	black.color = Color(0.02, 0.025, 0.03)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(black)
	var art := TextureRect.new()
	art.texture = load("res://assets/ui/loading.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(art)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0.45)
	gt.fill_to = Vector2(0, 1.0)
	shade.texture = gt
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(shade)
	var title := Label.new()
	title.text = "LOOKOUT"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.12))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 12)
	Hud.pin(title, Vector2(0.0, 1.0), Vector2(70, -290), Vector2(900, 110))
	root.add_child(title)
	var tip := Label.new()
	tip.text = "TIP   " + TIPS[randi() % TIPS.size()]
	tip.add_theme_font_size_override("font_size", 28)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	Hud.pin(tip, Vector2(0.0, 1.0), Vector2(74, -176), Vector2(1100, 70))
	root.add_child(tip)
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.55, 0.12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	_loading_bar.add_theme_stylebox_override("fill", fill)
	_loading_bar.add_theme_stylebox_override("background", bg)
	_loading_bar.anchor_left = 0.0
	_loading_bar.anchor_right = 1.0
	_loading_bar.anchor_top = 1.0
	_loading_bar.anchor_bottom = 1.0
	_loading_bar.offset_left = 74
	_loading_bar.offset_right = -74
	_loading_bar.offset_top = -92
	_loading_bar.offset_bottom = -82
	root.add_child(_loading_bar)
	_loading_label = Label.new()
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading_label.modulate = Color(1, 1, 1, 0.75)
	Hud.pin(_loading_label, Vector2(0.0, 1.0), Vector2(74, -70), Vector2(800, 30))
	root.add_child(_loading_label)
	var ver := Label.new()
	ver.text = "v%s  %s" % [version(), BUILD_NAME]
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.add_theme_font_size_override("font_size", 22)
	ver.modulate = Color(1, 1, 1, 0.6)
	Hud.pin(ver, Vector2(1.0, 1.0), Vector2(-474, -70), Vector2(400, 30))
	root.add_child(ver)
	_loading_target = 0.0


## Called by the world between build stages (it awaits a frame after each
## so the bar really moves).
func loading_step(text: String, fraction: float) -> void:
	if _loading == null:
		return
	_loading_label.text = text
	_loading_target = fraction * 100.0
	_loading_bar.value = _loading_target


func loading_end() -> void:
	if _loading == null:
		return
	var layer := _loading
	_loading = null
	_fps_time = 0.0
	_fps_frames = 0
	var root := layer.get_child(0) as Control
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.45)
	tw.tween_callback(layer.queue_free)


# -------------------------------------------------------------------- flow

func start_match(config: Dictionary) -> void:
	match_config = config
	if not match_config.has("seed"):
		match_config["seed"] = randi()
	Engine.time_scale = 1.0
	_loading_begin()
	loading_step("Starting up", 0.02)
	# Two frames so the loading screen is really on the glass before the
	# heavy work starts.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(WORLD_SCENE)


func back_to_menu() -> void:
	_session_end()
	Engine.time_scale = 1.0
	if Net.is_online():
		Net.leave()
	get_tree().change_scene_to_file(MENU_SCENE)


func mode() -> int:
	return int(match_config.get("mode", Mode.FREE_ROAM))


## A short freeze on heavy impacts (fighting-game "hit stop").
func hitstop(seconds: float) -> void:
	if Net.is_online():
		return   # never freeze a shared match
	_hitstop_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	Engine.time_scale = 0.05


## Slow motion for finishers (local only).
func slowmo(scale: float, seconds: float) -> void:
	if Net.is_online():
		return
	Engine.time_scale = scale
	var t := get_tree().create_timer(seconds, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)


func _process(_delta: float) -> void:
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		Engine.time_scale = 1.0


# ------------------------------------------------------------------ inputs

func _setup_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "punch": [KEY_J], "heavy": [KEY_K], "block": [KEY_L],
		"dodge": [KEY_CTRL], "surge": [KEY_Q], "interact": [KEY_E], "nitro": [KEY_SHIFT],
		"handbrake": [KEY_SPACE], "grenade": [KEY_G], "camera": [KEY_C], "pause": [KEY_ESCAPE],
	}
	var pads := {
		"jump": [JOY_BUTTON_A], "punch": [JOY_BUTTON_X], "heavy": [JOY_BUTTON_Y], "dodge": [JOY_BUTTON_B],
		"block": [JOY_BUTTON_LEFT_SHOULDER], "surge": [JOY_BUTTON_RIGHT_STICK], "interact": [JOY_BUTTON_RIGHT_SHOULDER],
		"sprint": [JOY_BUTTON_LEFT_STICK], "camera": [JOY_BUTTON_BACK], "pause": [JOY_BUTTON_START],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k: int in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action: String in pads:
		for b: int in pads[action]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
	for pair in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0],
			["move_forward", JOY_AXIS_LEFT_Y, -1.0], ["move_back", JOY_AXIS_LEFT_Y, 1.0]]:
		var e := InputEventJoypadMotion.new()
		e.axis = pair[1]
		e.axis_value = pair[2]
		InputMap.action_add_event(pair[0], e)
	for pair in [["gas", JOY_AXIS_TRIGGER_RIGHT], ["brake", JOY_AXIS_TRIGGER_LEFT]]:
		InputMap.add_action(pair[0], 0.1)
		var e := InputEventJoypadMotion.new()
		e.axis = pair[1]
		e.axis_value = 1.0
		InputMap.action_add_event(pair[0], e)
	for pair in [["gas", KEY_W], ["brake", KEY_S]]:
		var e := InputEventKey.new()
		e.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], e)
