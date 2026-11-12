extends Node
## Dev: two copies of the game talk over ENet on this machine.
##   host:   godot --headless --path . res://tools/capture/net_test.tscn -- host MODE
##   client: godot --headless --path . res://tools/capture/net_test.tscn -- client MODE

var role := ""
var t := 0.0
var started := false
var _log := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	var mode := int(args[1])
	Game.player_name = "Host" if role == "host" else "Guest"
	_survive.call_deferred()
	Game.match_config = {"mode": mode, "minutes": 2, "laps": 1, "car": "sport"}
	if role == "host":
		print("HOST ", Net.host())
	else:
		Net.listen_for_games(true)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n.name == "World":
			print(role, " WORLD LOADED"))


## Live on after the scene changes to the world.
func _survive() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	var holder := Node.new()
	holder.name = "Holder"
	tree.root.add_child(holder)
	tree.current_scene = holder


func _process(delta: float) -> void:
	t += delta
	if role == "client" and not Net.is_online() and Net.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		if Net.servers.size() > 0:
			var ip: String = Net.servers.keys()[0]
			print("client found game at ", ip, " ", Net.servers[ip])
			Net.join(ip)
		elif t > 6.0:
			print("client: no beacon, joining 127.0.0.1")
			Net.join("127.0.0.1")
	if role == "host" and not started and Net.players.size() >= 2:
		started = true
		print("host: players ", Net.players)
		Net.start_match(Game.match_config.duplicate())
	_log -= delta
	if _log <= 0.0 and _world() != null:
		_log = 3.0
		var w := _world()
		var line := "%s t=%.0f " % [role, t]
		for f in get_tree().get_nodes_in_group(&"fighters"):
			line += "%s[%s hp%d] " % [(f as Fighter).display_name, f.get_class() if not f is RemoteFighter else "remote", int((f as Fighter).health)]
		var m = w.get("mode")
		if m and m.get("kos") != null:
			line += " kos=" + str(m.get("kos"))
		for c in get_tree().get_nodes_in_group(&"cars"):
			var car := c as Car
			if car.driver or car.owner_peer:
				line += " car(%s owner=%d %.0fkmh at %s)" % [car.car_id, car.owner_peer, car.speed_kmh() if not car.owner_peer else (car.get_meta(&"net_v", Vector3.ZERO) as Vector3).length() * 3.6, str(car.global_position.snapped(Vector3.ONE))]
		print(line)
		# Make the two players fight: walk at the other one and punch.
		var p: Player = w.get("player")
		for f in get_tree().get_nodes_in_group(&"fighters"):
			if f is RemoteFighter:
				var d := (f as Node3D).global_position - p.global_position
				d.y = 0.0
				if d.length() > 1.5:
					var local := Basis(Vector3.UP, p.cam.yaw).inverse() * d.normalized()
					TouchControls.stick = Vector2(local.x, local.z)
				else:
					TouchControls.stick = Vector2.ZERO
	if _world() != null:
		var p: Player = _world().get("player")
		if p and p.car:
			TouchControls.gas = true
			if fmod(t, 5.0) < delta:
				p.car.in_nitro = true
		elif p and fmod(t, 0.4) < delta:
			p.punch()
	if t > 60.0:
		get_tree().quit()


func _world() -> Node:
	return get_tree().root.get_node_or_null("World")
