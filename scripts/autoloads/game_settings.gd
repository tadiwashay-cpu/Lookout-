extends Node
## Player preferences that persist between sessions (camera view, look speed).

signal camera_mode_changed(mode: int)

const THIRD_PERSON := 0
const FIRST_PERSON := 1
const SAVE_PATH := "user://settings.cfg"

var camera_mode: int = THIRD_PERSON
var look_sensitivity: float = 1.0
var haptics_enabled: bool = true


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		camera_mode = config.get_value("camera", "mode", THIRD_PERSON)
		look_sensitivity = config.get_value("camera", "look_sensitivity", 1.0)
		haptics_enabled = config.get_value("feedback", "haptics", true)


func set_camera_mode(mode: int) -> void:
	if mode == camera_mode:
		return
	camera_mode = mode
	camera_mode_changed.emit(camera_mode)
	save()


func toggle_camera_mode() -> void:
	set_camera_mode(FIRST_PERSON if camera_mode == THIRD_PERSON else THIRD_PERSON)


func vibrate(duration_ms: int) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("camera", "mode", camera_mode)
	config.set_value("camera", "look_sensitivity", look_sensitivity)
	config.set_value("feedback", "haptics", haptics_enabled)
	config.save(SAVE_PATH)
