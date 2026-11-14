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

var _hitstop_until := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	_load()
	render_scale = preset()["scale"]


# ------------------------------------------------------------------ profile

func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	save()


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("profile", "name", player_name)
	c.set_value("profile", "money", money)
	c.set_value("settings", "quality", quality)
	c.set_value("settings", "look", look_sensitivity)
	c.set_value("settings", "fps", show_fps)
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
	view_distance = preset()["view"]


# ---------------------------------------------------------------- graphics

## Graphics presets. The 3D scene renders at `scale` x screen resolution and
## FSR sharpens it back up (phones/tablets have far more pixels than their
## GPUs can shade at 60 fps); the governor lowers the scale only while the
## frame rate dips, then climbs back to the preset's `scale`.
const PRESETS := [
	{"name": "LOW", "scale": 0.62, "min_scale": 0.5, "msaa": 0, "shadow": 0.0, "shadow_size": 1024, "glow": false, "view": 550.0, "trees": 0.45},
	{"name": "MEDIUM", "scale": 0.75, "min_scale": 0.55, "msaa": 0, "shadow": 55.0, "shadow_size": 2048, "glow": false, "view": 750.0, "trees": 0.7},
	{"name": "HIGH", "scale": 0.85, "min_scale": 0.6, "msaa": 1, "shadow": 75.0, "shadow_size": 2048, "glow": true, "view": 900.0, "trees": 1.0},
	{"name": "ULTRA", "scale": 1.0, "min_scale": 0.7, "msaa": 2, "shadow": 120.0, "shadow_size": 4096, "glow": true, "view": 1200.0, "trees": 1.0},
]
var render_scale := 1.0


func preset() -> Dictionary:
	return PRESETS[clampi(quality, 0, PRESETS.size() - 1)]


func set_quality(q: int) -> void:
	quality = clampi(q, 0, PRESETS.size() - 1)
	view_distance = preset()["view"]
	render_scale = preset()["scale"]


## Viewport-level settings (called by the world).
func apply_viewport(vp: Viewport) -> void:
	var p := preset()
	render_scale = clampf(render_scale if render_scale > 0.0 else p["scale"], p["min_scale"], p["scale"])
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = render_scale
	vp.fsr_sharpness = 0.35
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(p["msaa"])]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 2.0 if quality < 2 else 1.0
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow_size"]), true)
	Engine.max_fps = 60


var _fps_time := 0.0
var _fps_frames := 0


## Dynamic resolution: keep 60 fps by trading a little sharpness, never
## more than the preset allows, and give it back when there's headroom.
func govern_resolution(vp: Viewport, delta: float) -> void:
	_fps_time += delta / maxf(Engine.time_scale, 0.05)
	_fps_frames += 1
	if _fps_time < 1.5:
		return
	var fps := _fps_frames / _fps_time
	_fps_time = 0.0
	_fps_frames = 0
	var p := preset()
	var before := render_scale
	if fps < 52.0:
		render_scale = maxf(render_scale - 0.05, p["min_scale"])
	elif fps > 58.5:
		render_scale = minf(render_scale + 0.025, p["scale"])
	if render_scale != before:
		vp.scaling_3d_scale = render_scale


# -------------------------------------------------------------------- flow

func start_match(config: Dictionary) -> void:
	match_config = config
	if not match_config.has("seed"):
		match_config["seed"] = randi()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(WORLD_SCENE)


func back_to_menu() -> void:
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
