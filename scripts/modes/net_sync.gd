class_name NetSync
extends Node
## Streams our fighter and car to the other players and keeps an avatar of
## each of theirs. Hits on an avatar go to its owner (see RemoteFighter).

var world: Node3D
var player: Player
var fighters: Dictionary = {}     # peer -> RemoteFighter
var cars: Dictionary = {}         # peer -> Car (remote)
var _tick := 0.0


func _ready() -> void:
	Net.state_received.connect(_on_state)
	Net.event_received.connect(_on_event)


func _physics_process(delta: float) -> void:
	if not Net.is_online() or player == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0 / 15.0
	var s := RemoteFighter.snapshot(player)
	if player.car:
		var c := player.car
		s["car"] = {"id": c.car_id, "p": c.global_position, "q": c.global_basis.get_rotation_quaternion(), "v": c.linear_velocity,
			"st": c.steering, "w": c.wrecked, "n": c.nitro_on, "paint": c.paint}
	Net.send_state(s)


func _on_state(peer: int, s: Dictionary) -> void:
	if not fighters.has(peer):
		var f := RemoteFighter.new()
		f.peer_id = peer
		f.fighter_id = peer
		f.display_name = Net.name_of(peer)
		f.position = s.get("p", Vector3.ZERO)
		world.add_child(f)
		fighters[peer] = f
	(fighters[peer] as RemoteFighter).apply_state(s)
	var cs: Dictionary = s.get("car", {})
	if cs.is_empty():
		if cars.has(peer):
			(cars[peer] as Car).queue_free()
			cars.erase(peer)
		return
	if not cars.has(peer) or not is_instance_valid(cars[peer]) or (cars[peer] as Car).car_id != str(cs["id"]):
		if cars.has(peer) and is_instance_valid(cars[peer]):
			(cars[peer] as Car).queue_free()
		var c := Car.new()
		c.car_id = str(cs["id"])
		c.paint = cs.get("paint", Color(0, 0, 0, 0))
		c.owner_peer = peer
		c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		c.freeze = true
		c.position = cs["p"]
		world.add_child(c)
		cars[peer] = c
	var car := cars[peer] as Car
	car.global_transform = Transform3D(Basis(cs["q"] as Quaternion), cs["p"])
	car.set_meta(&"net_v", cs["v"])
	car.steering = cs["st"]
	car.nitro_on = cs["n"]
	if cs["w"] and not car.wrecked:
		car.explode()


func _on_event(_from: int, kind: String, d: Dictionary) -> void:
	if kind == "hit" and int(d.get("to", 0)) == Net.my_id() and player:
		var attacker: Fighter = fighters.get(int(d.get("from", 0)))
		player.receive_hit(float(d["dmg"]), d["push"], attacker, bool(d["heavy"]))
	elif kind == "cdmg" and int(d.get("to", 0)) == Net.my_id() and player and player.car:
		player.car.take_damage(float(d["amount"]))
		if d.get("stun", 0.0) > 0.0:
			player.car.stun(float(d["stun"]))
