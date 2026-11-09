extends Node
## What kind of game is running (story or a multiplayer mode) and where
## everyone spawns. The world scene reads this when it loads.

const MODE_STORY := 0
const MODE_BATTLE_ROYALE := 1
const MODE_STREET_RACE := 2
const MODE_HEIST := 3

const MODE_NAMES := {
	MODE_STORY: "Story",
	MODE_BATTLE_ROYALE: "Battle Royale",
	MODE_STREET_RACE: "Street Race",
	MODE_HEIST: "Robbers vs Police",
}

## Multiplayer spawn regions (the city itself is the story's home turf).
const REGIONS := ["harbor", "suburb", "forest", "highway"]

const WORLD_SCENE := "res://scenes/levels/world.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var mode: int = MODE_STORY
var networked := false
var match_seed: int = 0
## peer_id -> "robbers" | "police" (heist only)
var teams: Dictionary = {}


func start_story() -> void:
	mode = MODE_STORY
	networked = false
	match_seed = randi()
	teams = {}
	get_tree().change_scene_to_file(WORLD_SCENE)


## Called on every peer (or locally for solo practice).
func start_match(new_mode: int, seed_value: int, team_map: Dictionary, is_networked: bool) -> void:
	mode = new_mode
	match_seed = seed_value
	teams = team_map
	networked = is_networked
	get_tree().change_scene_to_file(WORLD_SCENE)


func back_to_menu() -> void:
	Net.leave()
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func my_id() -> int:
	return multiplayer.get_unique_id() if networked else 1


func team_of(peer_id: int) -> String:
	return teams.get(peer_id, "")


## Each player gets a region from the match seed, so every device agrees.
func spawn_region_for(peer_id: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(match_seed) ^ hash(peer_id * 7919)
	return REGIONS[rng.randi() % REGIONS.size()]


func match_rng(salt: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(match_seed + salt * 104729)
	return rng
