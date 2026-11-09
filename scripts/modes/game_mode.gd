class_name GameMode
extends Node
## Base for story and multiplayer modes. The HUD asks the mode for its
## status line, minimap markers and (battle royale) the safe zone.

signal status_changed(text: String)

var world: World
var finished := false


func player() -> PlayerController:
	return world.player


func hud() -> GameHUD:
	return world.hud


func begin() -> void:
	pass


## [{"pos": Vector3, "color": Color, "kind": "objective"|"danger"|"ally"}]
func minimap_markers() -> Array:
	return []


## {"center": Vector2, "radius": float} or {} when there is no zone.
func safe_zone() -> Dictionary:
	return {}


func set_status(text: String) -> void:
	status_changed.emit(text)


func end_match(title: String, won: bool, reward: int = 0) -> void:
	if finished:
		return
	finished = true
	if reward > 0:
		GameSettings.add_money(reward)
	var detail := ("+$%d" % reward) if reward > 0 else ""
	hud().show_results(title, detail, won)


func names_for(ids: Array) -> String:
	var out := PackedStringArray()
	for id in ids:
		out.append(str((Net.players.get(id, {}) as Dictionary).get("name", "Player %d" % id)))
	return ", ".join(out)


## Solo practice: AI opponents so multiplayer modes work offline.
static func make_bot(world: World, index: int, team: String, weapon: String, pos: Vector3) -> BotSoldier:
	var names := ["Ace", "Blaze", "Cruz", "Dex", "Echo", "Fox", "Gage", "Hex", "Iggy", "Jinx", "Knox", "Lux"]
	var palette := [Color(0.3, 0.35, 0.25), Color(0.4, 0.2, 0.15), Color(0.2, 0.25, 0.35), Color(0.45, 0.42, 0.35), Color(0.15, 0.15, 0.17)]
	var bot := BotSoldier.new()
	bot.bot_id = -(index + 1)
	bot.team = team
	bot.display_name = names[index % names.size()]
	bot.weapon_id = weapon
	bot.tint_colors = [Color(0.55, 0.4, 0.3), palette[index % palette.size()]]
	bot.position = pos + Vector3.UP * 0.4
	world.add_child(bot)
	return bot
