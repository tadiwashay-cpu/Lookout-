class_name GameMode
extends Node
## Base for story and multiplayer modes. The HUD asks the mode for its
## status line, minimap markers and (battle royale) the safe zone.

signal status_changed(text: String)

var world: World
## Bot id (negative) -> name, for the kill feed and scoreboards.
static var bot_names: Dictionary = {}
var kills: Dictionary = {}   # id -> eliminations this match
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
	var my_kills := int(kills.get(Session.my_id(), 0))
	if my_kills > 0:
		detail = "Eliminations %d    %s" % [my_kills, detail]
	hud().show_results(title, detail, won)


func name_of(id: int) -> String:
	if id == Session.my_id():
		return "You"
	if id < 0:
		return str(bot_names.get(id, "Bot"))
	if id == 0:
		return "the zone"
	return names_for([id])


## Kill feed + kill counts for every multiplayer mode.
func on_elimination_feed(victim: int, by: int) -> void:
	if by != 0 and by != victim:
		kills[by] = int(kills.get(by, 0)) + 1
	var mine := by == Session.my_id() or victim == Session.my_id()
	var text := "%s  ▸  %s" % [name_of(by), name_of(victim)] if by != 0 and by != victim else ("You're out" if victim == Session.my_id() else "%s is out" % name_of(victim))
	hud().feed(text, Color(1.0, 0.8, 0.35) if mine else Color(0.95, 0.93, 0.88))
	if by == Session.my_id() and by != victim:
		Audio.play_ui("click")


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
	bot_names[bot.bot_id] = bot.display_name
	bot.weapon_id = weapon
	bot.tint_colors = [Color(0.55, 0.4, 0.3), palette[index % palette.size()]]
	bot.position = pos + Vector3.UP * 0.4
	world.add_child(bot)
	return bot
