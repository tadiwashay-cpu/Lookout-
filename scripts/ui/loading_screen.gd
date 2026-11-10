extends Control
## Loading screen between the menu and the world: key art, the title, a
## progress bar and a gameplay tip. Loads the world scene on a thread so
## the bar moves, then swaps scenes (the art stays up while the world builds).

const TIPS := [
	"Bank your cash. Money in the bank is safe if you get knocked out or busted.",
	"Tap the handbrake at speed to start a drift. Hold gas and steer to keep it going.",
	"The pawn shop buys guns back at half price and sells med kits, ammo and grenades.",
	"Heat cools down only when the police can't see you. Break line of sight, then wait.",
	"HEAVY cycles a front kick, a roundhouse and a heavy punch. Sprint + HEAVY is a flying kick.",
	"In Clean Hands, landing hits fills your surge meter. A knock-out tops it up by 20%.",
	"Rare cars never park in the open. Win races to unlock them in the car store.",
	"A smoking car is about to burn. Get out before it reaches zero.",
	"Tap the minimap to open the full map. The green marker is the bank, orange is the pawn shop.",
	"Your gun stays holstered until you shoot or aim, and goes away after ten quiet seconds.",
	"CAM cycles the driving views: close chase, far chase, free look and hood.",
	"Police send SWAT from three stars. Stealing a police car gets you there fast.",
	"Blocking cuts damage to a quarter and stops you being knocked down.",
	"Win career races to earn cash for the car store. Rivals get faster every event.",
]

var _bar: ProgressBar
var _target := ""


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art := TextureRect.new()
	art.texture = preload("res://assets/ui/loading_bg.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var title := Label.new()
	title.text = "LOOKOUT"
	title.add_theme_font_override("font", UITheme.TITLE_FONT)
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 14)
	title.position = Vector2(60, 40)
	add_child(title)
	var mode := Label.new()
	mode.text = str(Session.MODE_NAMES.get(Session.mode, "")).to_upper()
	mode.add_theme_font_override("font", UITheme.HUD_FONT)
	mode.add_theme_font_size_override("font_size", 34)
	mode.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	mode.position = Vector2(66, 176)
	add_child(mode)
	var tip := Label.new()
	tip.text = "TIP   " + TIPS[randi() % TIPS.size()]
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 30)
	tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tip.add_theme_constant_override("outline_size", 8)
	tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tip.offset_left = 60
	tip.offset_right = -60
	tip.offset_top = -150
	tip.offset_bottom = -70
	add_child(tip)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_left = 60
	_bar.offset_right = -60
	_bar.offset_top = -50
	_bar.offset_bottom = -38
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.62, 0.2)
	_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.15)
	_bar.add_theme_stylebox_override("background", back)
	add_child(_bar)
	_target = Session.pending_scene
	ResourceLoader.load_threaded_request(_target)


func _process(_delta: float) -> void:
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_target, progress)
	_bar.value = lerpf(_bar.value, float(progress[0]) if not progress.is_empty() else 0.0, 0.2)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		set_process(false)
		_bar.value = 1.0
		await get_tree().process_frame
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(_target) as PackedScene)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		get_tree().change_scene_to_file(_target)
