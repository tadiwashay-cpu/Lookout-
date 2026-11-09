extends Node
## Registers every gameplay action in code.
## Keyboard and gamepad bindings make desktop testing easy; on Android the
## TouchControls overlay presses these same actions, so gameplay code only
## ever reads actions and never cares which device produced them.

const MOVE_DEADZONE := 0.15
const DEFAULT_DEADZONE := 0.5

const KEY_BINDINGS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"punch_light": [KEY_J],
	&"punch_heavy": [KEY_K],
	&"dodge": [KEY_L],
	&"toggle_camera": [KEY_V],
	&"pause": [KEY_ESCAPE],
}

const PAD_BUTTONS := {
	&"jump": JOY_BUTTON_A,
	&"dodge": JOY_BUTTON_B,
	&"punch_light": JOY_BUTTON_X,
	&"punch_heavy": JOY_BUTTON_Y,
	&"sprint": JOY_BUTTON_LEFT_STICK,
	&"toggle_camera": JOY_BUTTON_BACK,
	&"pause": JOY_BUTTON_START,
}

const PAD_AXES := {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	&"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	&"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	&"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	&"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}


func _enter_tree() -> void:
	for action: StringName in KEY_BINDINGS:
		_ensure_action(action)
		for keycode: int in KEY_BINDINGS[action]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode
			InputMap.action_add_event(action, key_event)

	for action: StringName in PAD_BUTTONS:
		_ensure_action(action)
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, button_event)

	for action: StringName in PAD_AXES:
		_ensure_action(action)
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = PAD_AXES[action][0]
		axis_event.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, axis_event)


func _ensure_action(action: StringName) -> void:
	if InputMap.has_action(action):
		return
	var is_analog := String(action).begins_with("move_") or String(action).begins_with("look_")
	InputMap.add_action(action, MOVE_DEADZONE if is_analog else DEFAULT_DEADZONE)
