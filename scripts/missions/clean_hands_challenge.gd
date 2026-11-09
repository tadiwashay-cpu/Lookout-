class_name CleanHandsChallenge
extends Node
## "Clean Hands" — the no-weapons level. The Low Tide crew is terrorising
## the old market district; take the streets back with your fists only.
## Objectives: put goons down, land combo finishers, and keep your police
## heat low (vigilante brawling caps at 1 star; anything above means you
## hurt someone you shouldn't have).

signal objectives_changed(text: String)
signal completed(summary: String)
signal failed(reason: String)

@export var goons_required: int = 12
@export var finishers_required: int = 5
@export var max_stars_allowed: int = 2

var weapons_allowed := false
var is_complete := false

var _goons_down := 0
var _finishers := 0
var _elapsed := 0.0
var _last_finisher_frame := -1


func _process(delta: float) -> void:
	if not is_complete:
		_elapsed += delta


func track_player(player: PlayerController) -> void:
	player.attack_landed.connect(_on_attack_landed)


func track_goon(goon: Goon) -> void:
	goon.defeated.connect(_on_goon_defeated)


func start() -> void:
	WantedSystem.stars_changed.connect(_on_stars_changed)
	_emit_objectives()


func _on_goon_defeated(_goon: Goon) -> void:
	_goons_down += 1
	_check_complete()


func _on_attack_landed(_target: Node3D, _damage: float, combo_step: int) -> void:
	# A finisher that hits three goons at once still only counts once.
	if combo_step >= 3 and Engine.get_physics_frames() != _last_finisher_frame:
		_last_finisher_frame = Engine.get_physics_frames()
		_finishers += 1
		_check_complete()


func _on_stars_changed(stars: int) -> void:
	if not is_complete and stars > max_stars_allowed:
		failed.emit("Too much heat — the cops are on you. Lose them and try again.")
	_emit_objectives()


func _check_complete() -> void:
	_emit_objectives()
	if is_complete:
		return
	if _goons_down >= goons_required and _finishers >= finishers_required:
		is_complete = true
		var minutes := floori(_elapsed / 60.0)
		var seconds := int(_elapsed) % 60
		completed.emit("DISTRICT CLEARED   %d:%02d" % [minutes, seconds])


func _emit_objectives() -> void:
	var text := "CLEAN HANDS — no weapons. Take back the market.\n"
	text += "Goons down %d/%d    Finishers %d/%d    Heat limit %d" % [
		mini(_goons_down, goons_required), goons_required,
		mini(_finishers, finishers_required), finishers_required,
		max_stars_allowed,
	]
	objectives_changed.emit(text)
