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
	"hero": {"name": "VVS", "scene": "res://assets/models/characters/hero.glb", "portrait": "res://assets/ui/portraits/hero_portrait.png"},
	"x_bot": {"name": "X", "scene": "res://assets/models/characters/x_bot.glb", "portrait": "res://assets/ui/portraits/x_bot_portrait.png"},
	"y_bot": {"name": "Y", "scene": "res://assets/models/characters/y_bot.glb", "portrait": "res://assets/ui/portraits/y_bot_portrait.png"},
}
## NPCs, goons, cops and bots (not selectable).
const NPC_SCENE := "res://assets/models/characters/npc_man.glb"

## Quaternius city characters (CC0). Each group shares one skeleton; the
## "_casual" file of each group carries the clips for the whole group.
const CIVILIAN_DIR := "res://assets/models/characters/civilians/"
const CIVILIANS_MEN := ["civ_m_casual", "civ_m_casual2", "civ_m_suit", "civ_m_worker", "civ_m_punk", "civ_m_beach", "civ_m_farmer", "civ_m_adventurer"]
const CIVILIANS_WOMEN := ["civ_f_casual", "civ_f_formal", "civ_f_suit", "civ_f_worker", "civ_f_punk", "civ_f_adventurer"]
const CIVILIANS_TACTICAL := ["civ_m_swat", "civ_f_soldier"]


static func random_civilian(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.45:
		return CIVILIANS_WOMEN[rng.randi() % CIVILIANS_WOMEN.size()]
	return CIVILIANS_MEN[rng.randi() % CIVILIANS_MEN.size()]

# --- profile
var character: String = "hero"
var player_name: String = "Player"
var money: int = 0
var owned_weapons: Array = ["m4a1"]
var equipped_weapon: String = "m4a1"
## Your garage: the car waiting at HQ and used in the race career.
var owned_cars: Array = ["coupe"]
var garage_car: String = "coupe"
## Race career: how many events you've won (they unlock in order).
var career_won: int = 0
## Money in the bank: safe from KO/bust fines, earns interest each in-game day.
var bank_balance: int = 0

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
var fps_cap: int = 60   # 30 judders against 60/120 Hz screens when driving fast
## Performance overlay (Debug Menu add-on): 0 off, 1 FPS only, 2 full graphs.
var perf_overlay: int = 0
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
		owned_cars = config.get_value("profile", "owned_cars", owned_cars)
		garage_car = config.get_value("profile", "garage_car", garage_car)
		career_won = config.get_value("profile", "career_won", career_won)
		bank_balance = config.get_value("profile", "bank_balance", bank_balance)
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
		perf_overlay = config.get_value("graphics", "perf_overlay", perf_overlay)
		master_volume = config.get_value("sound", "master", master_volume)
		music_volume = config.get_value("sound", "music", music_volume)
		sfx_volume = config.get_value("sound", "sfx", sfx_volume)
	# The main character arrived in an update: switch existing saves to him once.
	if not config.get_value("profile", "hero_intro", false):
		character = "hero"
		save.call_deferred()
	if not CHARACTERS.has(character):
		character = "hero"
	apply_all()


## Quality presets set sensible values for the individual options.
func set_quality(level: int) -> void:
	quality = clampi(level, QUALITY_LOW, QUALITY_HIGH)
	match quality:
		QUALITY_LOW:
			render_scale = 0.7
			shadows_enabled = false
			view_distance = 220.0
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
	_apply_perf_overlay.call_deferred()   # the DebugMenu autoload loads after this one
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


func _apply_perf_overlay() -> void:
	var overlay := get_node_or_null(^"/root/DebugMenu")
	if overlay:
		overlay.set(&"style", clampi(perf_overlay, 0, 2))


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


func buy_car(id: String) -> bool:
	var data: Dictionary = VehicleCatalog.STORE_CARS.get(id, {})
	if data.is_empty() or owned_cars.has(id) or money < int(data["price"]) or career_won < int(data.get("unlock", 0)):
		return false
	money -= int(data["price"])
	owned_cars.append(id)
	garage_car = id
	save()
	return true


func select_car(id: String) -> void:
	if owned_cars.has(id):
		garage_car = id
		save()


## Sell back to a pawn shop for half (never the last weapon you own).
func sell_weapon(id: String) -> int:
	if not owned_weapons.has(id) or owned_weapons.size() <= 1:
		return 0
	var value := int(WeaponCatalog.get_data(id)["price"]) / 2
	owned_weapons.erase(id)
	if equipped_weapon == id:
		equipped_weapon = owned_weapons[0]
	money += value
	save()
	return value


func bank_deposit(amount: int) -> void:
	amount = clampi(amount, 0, money)
	money -= amount
	bank_balance += amount
	save()


func bank_withdraw(amount: int) -> void:
	amount = clampi(amount, 0, bank_balance)
	bank_balance -= amount
	money += amount
	save()


func bank_interest(rate: float) -> int:
	var gain := int(bank_balance * rate)
	bank_balance += gain
	save()
	return gain


func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	save()


func vibrate(duration_ms: int) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms)


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "character", character)
	config.set_value("profile", "hero_intro", true)
	config.set_value("profile", "name", player_name)
	config.set_value("profile", "money", money)
	config.set_value("profile", "owned_weapons", owned_weapons)
	config.set_value("profile", "equipped_weapon", equipped_weapon)
	config.set_value("profile", "owned_cars", owned_cars)
	config.set_value("profile", "garage_car", garage_car)
	config.set_value("profile", "career_won", career_won)
	config.set_value("profile", "bank_balance", bank_balance)
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
	config.set_value("graphics", "perf_overlay", perf_overlay)
	config.set_value("sound", "master", master_volume)
	config.set_value("sound", "music", music_volume)
	config.set_value("sound", "sfx", sfx_volume)
	config.save(SAVE_PATH)
