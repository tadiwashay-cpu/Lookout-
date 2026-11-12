class_name CleanHandsMode
extends Node
## Clean Hands: bare-knuckle brawl in the harbour ring. Everyone fights
## everyone; a KO scores a point and the loser is back in a corner three
## seconds later. When the timer (chosen in the lobby) runs out, the most
## KOs takes the biggest purse.

const PURSE := [1500, 800, 400]
const PER_KO := 60

var world: Node3D
var ring: Ring
var player: Player
var sync: NetSync
var kos: Dictionary = {}          # fighter_id -> KOs
var names: Dictionary = {}        # fighter_id -> name
var time_left := 180.0
var running := false
var _bots: Array[BotFighter] = []


func begin() -> void:
	ring = world.get("ring")
	player = world.get("player")
	time_left = float(Game.match_config.get("minutes", 3)) * 60.0
	player.fighter_id = Net.my_id()
	player.peer_id = Net.my_id()
	names[player.fighter_id] = Game.player_name
	kos[player.fighter_id] = 0
	var roster: Array = Game.match_config.get("roster", [1])
	var my_index := maxi(roster.find(Net.my_id()), 0)
	player.global_position = ring.corner(my_index)
	player.knocked_out.connect(_on_ko)
	if Game.match_config.get("networked", false):
		sync = NetSync.new()
		sync.world = world
		sync.player = player
		add_child(sync)
		for id in roster:
			names[int(id)] = Net.name_of(int(id))
			kos[int(id)] = 0
	var bots := int(Game.match_config.get("bots", 3)) if not Game.match_config.get("networked", false) else 0
	var bot_names := ["Rook", "Mason", "Dre", "Viktor", "Jax", "Tank", "Saint"]
	for i in bots:
		var b := BotFighter.new()
		b.fighter_id = 100 + i
		b.display_name = bot_names[i % bot_names.size()]
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 31 + 7
		b.model_path = Humanoid.random_npc(rng)
		b.max_health = 120.0
		b.skill = clampf(float(Game.match_config.get("difficulty", 0.6)) + rng.randf_range(-0.15, 0.15), 0.2, 0.95)
		b.arena_center = ring.global_position
		b.arena_radius = Ring.HALF
		b.position = ring.corner(i + 1)
		world.add_child(b)
		b.knocked_out.connect(_on_ko)
		_bots.append(b)
		names[b.fighter_id] = b.display_name
		kos[b.fighter_id] = 0
	Net.event_received.connect(_on_event)
	_countdown()


func _countdown() -> void:
	var hud: Hud = world.get("hud")
	player.controls_enabled = false
	for b in _bots:
		b.set_physics_process(false)
	for n in [3, 2, 1]:
		hud.banner(str(n), "CLEAN HANDS", 0.8)
		Sfx.play("beep")
		await get_tree().create_timer(1.0).timeout
	hud.banner("FIGHT!", "", 1.0)
	Sfx.play("bell")
	player.controls_enabled = true
	for b in _bots:
		b.set_physics_process(true)
	running = true


func _process(delta: float) -> void:
	if not running:
		return
	time_left -= delta
	var hud: Hud = world.get("hud")
	hud.set_top("CLEAN HANDS   %d:%02d" % [int(time_left) / 60, int(time_left) % 60], _scoreline())
	if time_left <= 0.0:
		running = false
		_finish()


func _scoreline() -> String:
	var ids := kos.keys()
	ids.sort_custom(func(a, b) -> bool: return kos[a] > kos[b])
	var parts: Array[String] = []
	for id in ids.slice(0, 4):
		parts.append("%s %d" % [names.get(id, "?"), kos[id]])
	return "   ".join(parts)


## A local fighter (us or a bot) went down.
func _on_ko(victim: Fighter, attacker: Fighter) -> void:
	var by := attacker.fighter_id if attacker else -1
	Net.send_event("ko", {"victim": victim.fighter_id, "by": by})
	var spot := ring.corner(randi() % 8)
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(victim):
		victim.respawn(spot)


func _on_event(_from: int, kind: String, d: Dictionary) -> void:
	if kind != "ko":
		return
	var by := int(d["by"])
	if kos.has(by) and by != int(d["victim"]):
		kos[by] += 1
	var hud: Hud = world.get("hud")
	hud.feed("%s  KO  %s" % [names.get(by, "The ring"), names.get(int(d["victim"]), "?")])
	ring.cheer()
	CameraRig.shake_all(0.3)


func _finish() -> void:
	player.controls_enabled = false
	Sfx.play("bell")
	var ids := kos.keys()
	ids.sort_custom(func(a, b) -> bool: return kos[a] > kos[b])
	var rows: Array = []
	var earned := 0
	for rank in ids.size():
		var id = ids[rank]
		var purse: int = (PURSE[rank] if rank < PURSE.size() else 150) + int(kos[id]) * PER_KO
		rows.append(["%d. %s" % [rank + 1, names.get(id, "?")], "%d KOs   $%d" % [kos[id], purse]])
		if id == player.fighter_id:
			earned = purse
	Game.add_money(earned)
	(world.get("hud") as Hud).results("CLEAN HANDS", rows, "You earned $%d" % earned)
