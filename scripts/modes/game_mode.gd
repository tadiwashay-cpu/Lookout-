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
