class_name TouchControls
extends Control
## On-screen controls for phones: a floating joystick on the left, drag the
## right half to look, buttons that change with context (on foot / driving).

static var stick := Vector2.ZERO
static var look_delta := Vector2.ZERO
static var gas := false
static var brake := false
static var handbrake := false
static var nitro_held := false
static var _taps: Dictionary = {}

const JOY_R := 110.0

var player: Player
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
var _held: Dictionary = {}        # touch index -> button dict
var _buttons: Array[Dictionary] = []
var _layout := ""


static func consume(action: StringName) -> bool:
	if _taps.get(action, false):
		_taps[action] = false
		return true
	return false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.get_name() == "Android"


func _layout_for() -> String:
	if player and player.car:
		return "car"
	return "foot"


func _build(kind: String) -> void:
	_layout = kind
	_buttons.clear()
	var s := get_viewport_rect().size
	var br := s - Vector2(110, 110)
	if kind == "foot":
		_buttons = [
			{"a": &"punch", "t": "PUNCH", "p": br, "r": 78.0},
			{"a": &"heavy", "t": "HEAVY", "p": br + Vector2(-175, 20), "r": 64.0},
			{"a": &"block", "t": "BLOCK", "p": br + Vector2(-20, -175), "r": 60.0, "hold": true},
			{"a": &"dodge", "t": "DODGE", "p": br + Vector2(-175, -150), "r": 56.0},
			{"a": &"jump", "t": "JUMP", "p": br + Vector2(-330, 40), "r": 54.0},
			{"a": &"surge", "t": "SURGE", "p": br + Vector2(-320, -120), "r": 56.0},
			{"a": &"interact", "t": "ENTER", "p": br + Vector2(-60, -330), "r": 54.0},
		]
	else:
		_buttons = [
			{"a": &"gas", "t": "GAS", "p": br, "r": 84.0, "hold": true},
			{"a": &"brake", "t": "BRAKE", "p": br + Vector2(-190, 30), "r": 70.0, "hold": true},
			{"a": &"nitro", "t": "NITRO", "p": br + Vector2(-20, -190), "r": 62.0, "hold": true},
			{"a": &"handbrake", "t": "DRIFT", "p": br + Vector2(-190, -150), "r": 58.0, "hold": true},
			{"a": &"grenade", "t": "GRENADE", "p": br + Vector2(-350, -40), "r": 56.0},
			{"a": &"surge", "t": "SURGE", "p": br + Vector2(-350, -180), "r": 56.0},
			{"a": &"interact", "t": "EXIT", "p": br + Vector2(-60, -350), "r": 50.0},
		]


func _process(_d: float) -> void:
	if not visible:
		return
	if _layout != _layout_for():
		_release_all()
		_build(_layout_for())
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_down(t.index, t.position)
		else:
			_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_index:
			var off := (d.position - _joy_origin).limit_length(JOY_R)
			_joy_knob = _joy_origin + off
			stick = off / JOY_R
		elif d.index == _look_index:
			look_delta += d.relative * 1.6


func _down(index: int, pos: Vector2) -> void:
	# Leave the radar, pause button and open menus alone.
	if Rect2(0, 0, 300, 320).has_point(pos) or pos.y < 90 and pos.x > get_viewport_rect().size.x - 110:
		return
	for b in _buttons:
		if pos.distance_to(b["p"]) <= float(b["r"]) * 1.15:
			_held[index] = b
			_press(b, true)
			return
	if pos.x < get_viewport_rect().size.x * 0.42 and _joy_index == -1:
		_joy_index = index
		_joy_origin = pos
		_joy_knob = pos
	elif _look_index == -1:
		_look_index = index


func _up(index: int) -> void:
	if index == _joy_index:
		_joy_index = -1
		stick = Vector2.ZERO
	if index == _look_index:
		_look_index = -1
	if _held.has(index):
		_press(_held[index], false)
		_held.erase(index)


func _press(b: Dictionary, on: bool) -> void:
	var a: StringName = b["a"]
	match a:
		&"gas":
			gas = on
		&"brake":
			brake = on
		&"handbrake":
			handbrake = on
		&"nitro":
			nitro_held = on
		_:
			if on:
				Input.action_press(a)
				_taps[a] = true
			else:
				Input.action_release(a)


func _release_all() -> void:
	for idx in _held:
		_press(_held[idx], false)
	_held.clear()
	gas = false
	brake = false
	handbrake = false
	nitro_held = false


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_R, Color(1, 1, 1, 0.12))
		draw_circle(_joy_knob, 46.0, Color(1, 1, 1, 0.35))
	else:
		var home := Vector2(190, get_viewport_rect().size.y - 190)
		draw_arc(home, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.18), 3.0)
	for b in _buttons:
		var pressed := _held.values().has(b)
		draw_circle(b["p"], b["r"], Color(0.05, 0.05, 0.06, 0.55) if not pressed else Color(1.0, 0.55, 0.1, 0.6))
		draw_arc(b["p"], b["r"], 0, TAU, 40, Color(1.0, 0.55, 0.1, 0.8), 3.0, true)
		draw_string(font, b["p"] + Vector2(-b["r"], 8), b["t"], HORIZONTAL_ALIGNMENT_CENTER, b["r"] * 2.0, 22, Color(1, 1, 1, 0.9))
