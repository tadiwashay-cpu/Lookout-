extends Node
## Everything the player can change in Settings, plus their profile
## (chosen character, name, money). Saved to user://settings.cfg.

signal camera_mode_changed(mode: int)
signal settings_changed

const THIRD_PERSON := 0
const FIRST_PERSON := 1
const SAVE_PATH := "user://settings.cfg"

const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2

const CHARACTERS := {
	"x_bot": {"name": "X", "scene": "res://assets/models/characters/x_bot.glb", "portrait": "res://assets/ui/portraits/x_bot_portrait.png"},
	"y_bot": {"name": "Y", "scene": "res://assets/models/characters/y_bot.glb", "portrait": "res://assets/ui/portraits/y_bot_portrait.png"},
}
## NPCs, goons, cops and bots (not selectable).
const NPC_SCENE := "res://assets/models/characters/npc_man.glb"

# --- profile
var character: String = "x_bot"
var player_name: String = "Player"
var money: int = 0
var owned_weapons: Array = ["m4a1"]
var equipped_weapon: String = "m4a1"

# --- camera / controls
var camera_mode: int = THIRD_PERSON
var look_sensitivity: float = 1.0
var invert_look_y: bool = false
var button_scale: float = 1.0
var haptics_enabled: bool = true

# --- graphics
var quality: int = QUALITY_MEDIUM
var render_scale: float = 0.85
var shadows_enabled: bool = true
var view_distance: float = 350.0
var fps_cap: int = 30
var motion_blur: bool = true
var day_length_minutes: float = 16.0

# --- sound (0..1)
var master_volume: float = 0.9
var music_volume: float = 0.7
var sfx_volume: float = 0.9


func _ready() -> void:
	_ensure_audio_buses()
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		character = config.get_value("profile", "character", character)
		player_name = config.get_value("profile", "name", player_name)
		money = config.get_value("profile", "money", money)
		owned_weapons = config.get_value("profile", "owned_weapons", owned_weapons)
		equipped_weapon = config.get_value("profile", "equipped_weapon", equipped_weapon)
		motion_blur = config.get_value("graphics", "motion_blur", motion_blur)
		day_length_minutes = config.get_value("graphics", "day_length", day_length_minutes)
		camera_mode = config.get_value("camera", "mode", camera_mode)
		look_sensitivity = config.get_value("camera", "look_sensitivity", look_sensitivity)
		invert_look_y = config.get_value("controls", "invert_y", invert_look_y)
		button_scale = config.get_value("controls", "button_scale", button_scale)
		haptics_enabled = config.get_value("controls", "haptics", haptics_enabled)
		quality = config.get_value("graphics", "quality", quality)
		render_scale = config.get_value("graphics", "render_scale", render_scale)
		shadows_enabled = config.get_value("graphics", "shadows", shadows_enabled)
		view_distance = config.get_value("graphics", "view_distance", view_distance)
		fps_cap = config.get_value("graphics", "fps_cap", fps_cap)
		master_volume = config.get_value("sound", "master", master_volume)
		music_volume = config.get_value("sound", "music", music_volume)
		sfx_volume = config.get_value("sound", "sfx", sfx_volume)
	if not CHARACTERS.has(character):
		character = "x_bot"
	apply_all()


## Quality presets set sensible values for the individual options.
func set_quality(level: int) -> void:
	quality = clampi(level, QUALITY_LOW, QUALITY_HIGH)
	match quality:
		QUALITY_LOW:
			render_scale = 0.7
			shadows_enabled = false
			view_distance = 220.0
			motion_blur = false
		QUALITY_MEDIUM:
			render_scale = 0.85
			shadows_enabled = true
			view_distance = 350.0
		QUALITY_HIGH:
			render_scale = 1.0
			shadows_enabled = true
			view_distance = 600.0
	apply_all()
	save()


func apply_all() -> void:
	Engine.max_fps = fps_cap
	var viewport := get_tree().root
	viewport.scaling_3d_scale = render_scale
	viewport.msaa_3d = Viewport.MSAA_DISABLED if quality == QUALITY_LOW else Viewport.MSAA_2X
	_apply_audio()
	settings_changed.emit()


func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, &"Master")


func _apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


func character_scene() -> PackedScene:
	return load(CHARACTERS[character]["scene"]) as PackedScene


func set_camera_mode(mode: int) -> void:
	if mode == camera_mode:
		return
	camera_mode = mode
	camera_mode_changed.emit(camera_mode)
	save()


func toggle_camera_mode() -> void:
	set_camera_mode(FIRST_PERSON if camera_mode == THIRD_PERSON else THIRD_PERSON)


func buy_weapon(id: String) -> bool:
	var data := WeaponCatalog.get_data(id)
	if owned_weapons.has(id) or money < int(data["price"]):
		return false
	money -= int(data["price"])
	owned_weapons.append(id)
	equipped_weapon = id
	save()
	return true


func equip_weapon(id: String) -> void:
	if owned_weapons.has(id):
		equipped_weapon = id
		save()


func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	save()


func vibrate(duration_ms: int) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "character", character)
	config.set_value("profile", "name", player_name)
	config.set_value("profile", "money", money)
	config.set_value("profile", "owned_weapons", owned_weapons)
	config.set_value("profile", "equipped_weapon", equipped_weapon)
	config.set_value("graphics", "motion_blur", motion_blur)
	config.set_value("graphics", "day_length", day_length_minutes)
	config.set_value("camera", "mode", camera_mode)
	config.set_value("camera", "look_sensitivity", look_sensitivity)
	config.set_value("controls", "invert_y", invert_look_y)
	config.set_value("controls", "button_scale", button_scale)
	config.set_value("controls", "haptics", haptics_enabled)
	config.set_value("graphics", "quality", quality)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "shadows", shadows_enabled)
	config.set_value("graphics", "view_distance", view_distance)
	config.set_value("graphics", "fps_cap", fps_cap)
	config.set_value("sound", "master", master_volume)
	config.set_value("sound", "music", music_volume)
	config.set_value("sound", "sfx", sfx_volume)
	config.save(SAVE_PATH)
