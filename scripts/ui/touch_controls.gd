class_name TouchControls
extends Control
## Android touch layout (multi-touch):
##  * left side  — floating joystick wherever your thumb lands; push to the
##                 edge to sprint
##  * right side — drag anywhere to look
##  * buttons    — on foot: PUNCH / HEAVY / DODGE / JUMP / CAM, plus ENTER
##                 when a car is close; driving: GAS / REV / BRAKE / EXIT / CAM
##                 and the joystick steers
## Everything is translated into the same input actions the keyboard and
## gamepad use, so gameplay code is device-agnostic.

const JOY_RADIUS := 130.0
const SPRINT_THRESHOLD := 0.95
const LOOK_GAIN := 1.0

var player: PlayerController

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
var _button_touches: Dictionary = {}   # touch index -> action
var _buttons: Array[Dictionary] = []
var _in_vehicle := false
var _can_interact := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	resized.connect(_layout)
	if player:
		player.vehicle_changed.connect(_on_vehicle_changed)
		player.nearby_vehicle_changed.connect(_on_nearby_vehicle_changed)
	_layout()


func _on_vehicle_changed(vehicle: DrivableCar) -> void:
	_release_all()
	_in_vehicle = vehicle != null
	_layout()


func _on_nearby_vehicle_changed(vehicle: DrivableCar) -> void:
	_can_interact = vehicle != null
	_layout()


func _notification(what: int) -> void:
	# Android: if the app loses focus mid-touch we never get the release events.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_VISIBILITY_CHANGED:
		_release_all()


func _release_all() -> void:
	for button in _buttons:
		Input.action_release(button["action"])
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]:
		Input.action_release(action)
	_button_touches.clear()
	_joy_index = -1
	_look_index = -1
	queue_redraw()


func _layout() -> void:
	var s := size
	# Release anything held by buttons that are about to disappear.
	for index: int in _button_touches:
		Input.action_release(_button_touches[index])
	_button_touches.clear()
	if _in_vehicle:
		_buttons = [
			{"action": &"move_forward", "label": "GAS", "pos": Vector2(s.x - 190, s.y - 190), "r": 100.0},
			{"action": &"move_back", "label": "REV", "pos": Vector2(s.x - 400, s.y - 130), "r": 78.0},
			{"action": &"jump", "label": "BRAKE", "pos": Vector2(s.x - 150, s.y - 410), "r": 74.0},
			{"action": &"interact", "label": "EXIT", "pos": Vector2(s.x - 360, s.y - 330), "r": 66.0},
			{"action": &"toggle_camera", "label": "CAM", "pos": Vector2(s.x - 110, 190), "r": 52.0},
		]
	else:
		_buttons = [
			{"action": &"punch_light", "label": "PUNCH", "pos": Vector2(s.x - 190, s.y - 190), "r": 100.0},
			{"action": &"punch_heavy", "label": "HEAVY", "pos": Vector2(s.x - 400, s.y - 130), "r": 78.0},
			{"action": &"dodge", "label": "DODGE", "pos": Vector2(s.x - 150, s.y - 410), "r": 74.0},
			{"action": &"jump", "label": "JUMP", "pos": Vector2(s.x - 360, s.y - 330), "r": 66.0},
			{"action": &"toggle_camera", "label": "CAM", "pos": Vector2(s.x - 110, 190), "r": 52.0},
		]
		if _can_interact:
			_buttons.append({"action": &"interact", "label": "ENTER", "pos": Vector2(s.x - 560, s.y - 300), "r": 70.0})
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_touch_down(touch.index, touch.position)
		else:
			_on_touch_up(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_on_drag(drag.index, drag.position, drag.relative)


func _on_touch_down(index: int, pos: Vector2) -> void:
	for button in _buttons:
		if pos.distance_to(button["pos"]) <= float(button["r"]) * 1.15:
			_button_touches[index] = button["action"]
			Input.action_press(button["action"])
			queue_redraw()
			return
	if pos.x < size.x * 0.45 and _joy_index == -1:
		_joy_index = index
		_joy_origin = pos
		_joy_knob = pos
		queue_redraw()
	elif pos.x >= size.x * 0.45 and _look_index == -1:
		_look_index = index


func _on_touch_up(index: int) -> void:
	if _button_touches.has(index):
		Input.action_release(_button_touches[index])
		_button_touches.erase(index)
		queue_redraw()
	elif index == _joy_index:
		_joy_index = -1
		_apply_move(Vector2.ZERO)
		queue_redraw()
	elif index == _look_index:
		_look_index = -1


func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _joy_index:
		var offset := (pos - _joy_origin).limit_length(JOY_RADIUS)
		_joy_knob = _joy_origin + offset
		_apply_move(offset / JOY_RADIUS)
		queue_redraw()
	elif index == _look_index and player:
		player.add_look_input(relative * LOOK_GAIN)


func _apply_move(stick: Vector2) -> void:
	_set_axis(&"move_left", &"move_right", stick.x)
	if _in_vehicle:
		return   # GAS / REV buttons own the pedals; the stick only steers.
	_set_axis(&"move_forward", &"move_back", stick.y)
	if stick.length() >= SPRINT_THRESHOLD:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


func _set_axis(negative: StringName, positive: StringName, value: float) -> void:
	if value < 0.0:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	elif value > 0.0:
		Input.action_press(positive, value)
		Input.action_release(negative)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _draw() -> void:
	var font := get_theme_default_font()
	var light := Color(0.95, 0.93, 0.88)

	if _joy_index != -1:
		draw_circle(_joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.08))
		draw_arc(_joy_origin, JOY_RADIUS, 0.0, TAU, 48, Color(light, 0.35), 3.0, true)
		draw_circle(_joy_knob, 52.0, Color(light, 0.55))
	else:
		var hint := Vector2(260, size.y - 240)
		draw_arc(hint, JOY_RADIUS, 0.0, TAU, 48, Color(light, 0.15), 3.0, true)

	for button in _buttons:
		var center: Vector2 = button["pos"]
		var radius: float = button["r"]
		var pressed := Input.is_action_pressed(button["action"])
		draw_circle(center, radius, Color(0.05, 0.05, 0.06, 0.6 if pressed else 0.38))
		draw_arc(center, radius, 0.0, TAU, 48, Color(light, 0.9 if pressed else 0.45), 3.0, true)
		var text: String = button["label"]
		var font_size := 26 if radius > 60.0 else 20
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, center + Vector2(-text_size.x * 0.5, font_size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(light, 0.9))
