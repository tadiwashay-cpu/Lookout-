class_name TouchControls
extends Control
## Android multi-touch layout. Left: MOVE stick (push to the edge to run).
## Right half: drag to look. Buttons change with what you're doing:
##  * armed:   FIRE (hold; drag on it to aim while shooting), AIM, RELOAD,
##             GRENADE, SURGE, JUMP, SWAP (fists/rifle), CAM
##  * fists:   PUNCH, HEAVY, SURGE, JUMP, SWAP (when allowed), CAM
##  * driving: GAS, REV, BRAKE, EXIT (not in races), GRENADE (races), CAM
## Plus ENTER when you stand next to a car. Every button just presses an
## input action, so gameplay code never cares about the device.

const JOY_RADIUS := 130.0
const SPRINT_THRESHOLD := 0.95

var player: PlayerController

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
var _button_touches: Dictionary = {}   # touch index -> button dict
var _buttons: Array[Dictionary] = []
var _in_vehicle := false
var _can_interact := false
var _layout_key := ""


func _ready() -> void:
	# Keep receiving touch-ups while the game is paused so nothing stays held.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	get_viewport().size_changed.connect(_layout)
	if player:
		player.vehicle_changed.connect(_on_vehicle_changed)
		player.nearby_vehicle_changed.connect(func(v: DrivableCar) -> void:
			_can_interact = v != null
			_layout()
		)
		player.loadout_changed.connect(_layout)
	GameSettings.settings_changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _release_all() -> void:
	for index: int in _button_touches:
		Input.action_release((_button_touches[index] as Dictionary)["action"])
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]:
		Input.action_release(action)
	_button_touches.clear()
	_joy_index = -1
	_look_index = -1
	queue_redraw()


func _on_vehicle_changed(vehicle: DrivableCar) -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]:
		Input.action_release(action)
	_in_vehicle = vehicle != null
	_layout()
	if _joy_index != -1:
		_apply_move((_joy_knob - _joy_origin) / JOY_RADIUS)


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


func _joy_home() -> Vector2:
	var s := _screen()
	return Vector2(clampf(s.x * 0.15, 200.0, 320.0), s.y - 240.0)


func _add(action: StringName, label: String, pos: Vector2, radius: float, look: bool = false) -> void:
	_buttons.append({"action": action, "label": label, "pos": pos, "r": radius * GameSettings.button_scale, "look": look})


func _layout() -> void:
	if not is_inside_tree():
		return
	var s := _screen()
	var k := GameSettings.button_scale
	var held: Array = []
	for index: int in _button_touches:
		held.append((_button_touches[index] as Dictionary)["action"])
	_buttons.clear()
	var br := Vector2(s.x, s.y)   # bottom-right anchor
	if _in_vehicle:
		_add(&"move_forward", "GAS", br + Vector2(-190, -190) * k, 100.0)
		_add(&"move_back", "REV", br + Vector2(-410, -130) * k, 78.0)
		_add(&"jump", "BRAKE", br + Vector2(-160, -420) * k, 74.0)
		var locked := player and player.current_vehicle and player.current_vehicle.locked
		if locked:
			_add(&"grenade", "NADE", br + Vector2(-380, -340) * k, 66.0)
		else:
			_add(&"interact", "EXIT", br + Vector2(-380, -340) * k, 66.0)
	elif player and player.is_armed():
		_add(&"fire", "FIRE", br + Vector2(-200, -200) * k, 104.0, true)
		_add(&"aim", "AIM", br + Vector2(-430, -150) * k, 70.0)
		_add(&"jump", "JUMP", br + Vector2(-160, -440) * k, 64.0)
		_add(&"reload", "RELOAD", br + Vector2(-400, -360) * k, 64.0)
		_add(&"grenade", "NADE", br + Vector2(-610, -150) * k, 62.0)
		_add(&"surge", "SURGE", br + Vector2(-590, -330) * k, 62.0)
		_add(&"swap_weapon", "FISTS", br + Vector2(-110, -620) * k, 50.0)
	else:
		_add(&"punch_light", "PUNCH", br + Vector2(-190, -190) * k, 100.0)
		_add(&"punch_heavy", "HEAVY", br + Vector2(-410, -130) * k, 78.0)
		_add(&"jump", "JUMP", br + Vector2(-160, -420) * k, 70.0)
		_add(&"surge", "SURGE", br + Vector2(-380, -340) * k, 66.0)
		_add(&"block", "BLOCK", br + Vector2(-610, -150) * k, 62.0)
		if player and player.weapons_allowed:
			_add(&"swap_weapon", "RIFLE", br + Vector2(-110, -620) * k, 50.0)
	_add(&"toggle_camera", "CAM", Vector2(s.x - 190, 190), 46.0)
	if _can_interact and not _in_vehicle:
		_add(&"interact", "ENTER", br + Vector2(-640, -340) * k, 70.0)
	# Release held buttons whose action vanished from this layout.
	var available: Array = []
	for b in _buttons:
		available.append(b["action"])
	for index: int in _button_touches.keys():
		var action: StringName = (_button_touches[index] as Dictionary)["action"]
		if not available.has(action):
			Input.action_release(action)
			_button_touches.erase(index)
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
			_button_touches[index] = button
			Input.action_press(button["action"])
			queue_redraw()
			return
	var half := _screen().x * 0.45
	if pos.x < half and _joy_index == -1:
		_joy_index = index
		_joy_origin = _joy_home() if pos.distance_to(_joy_home()) <= JOY_RADIUS else pos
		var offset := (pos - _joy_origin).limit_length(JOY_RADIUS)
		_joy_knob = _joy_origin + offset
		_apply_move(offset / JOY_RADIUS)
		queue_redraw()
	elif pos.x >= half and _look_index == -1:
		_look_index = index


func _on_touch_up(index: int) -> void:
	if _button_touches.has(index):
		Input.action_release((_button_touches[index] as Dictionary)["action"])
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
	elif player and (index == _look_index or (_button_touches.has(index) and (_button_touches[index] as Dictionary)["look"])):
		player.add_look_input(relative)


func _apply_move(stick: Vector2) -> void:
	_set_axis(&"move_left", &"move_right", stick.x)
	if _in_vehicle:
		return   # GAS / REV own the pedals; the stick only steers
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
		var home := _joy_home()
		draw_circle(home, JOY_RADIUS, Color(1, 1, 1, 0.06))
		draw_arc(home, JOY_RADIUS, 0.0, TAU, 48, Color(light, 0.4), 3.0, true)
		draw_circle(home, 52.0, Color(light, 0.35))
		var hint := "STEER" if _in_vehicle else "MOVE"
		var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, home + Vector2(-w * 0.5, JOY_RADIUS + 34), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(light, 0.6))
	for button in _buttons:
		var center: Vector2 = button["pos"]
		var radius: float = button["r"]
		var pressed := Input.is_action_pressed(button["action"])
		draw_circle(center, radius, Color(0.05, 0.05, 0.06, 0.6 if pressed else 0.38))
		draw_arc(center, radius, 0.0, TAU, 48, Color(light, 0.9 if pressed else 0.45), 3.0, true)
		var text: String = button["label"]
		var font_size := 26 if radius > 60.0 else 20
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, center + Vector2(-text_size.x * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(light, 0.9))
