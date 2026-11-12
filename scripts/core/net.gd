extends Node
## Multiplayer over ENet. The host is also a player. Games on the same Wi-Fi
## find each other automatically (UDP beacon); anyone else can join by IP
## (online play needs the host's port forwarded).
##
## Each device simulates its own fighter / car and streams its state; hits,
## kills, checkpoints and explosions travel as reliable events.

signal players_changed
signal match_started(config: Dictionary)
signal state_received(peer_id: int, state: Dictionary)
signal event_received(peer_id: int, kind: String, data: Dictionary)
signal connection_failed
signal servers_changed

const PORT := 47810
const BEACON_PORT := 47811
const MAX_PLAYERS := 8

## peer_id -> {"name": String, "car": String}
var players: Dictionary = {}
## "ip" -> {"name": String, "players": int, "seen": float}
var servers: Dictionary = {}

var _beacon := PacketPeerUDP.new()
var _listener := PacketPeerUDP.new()
var _beacon_timer := 0.0
var _listening := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit(); leave())
	multiplayer.server_disconnected.connect(func() -> void: leave(); Game.back_to_menu())


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


# ------------------------------------------------------------- host / join

func host() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _my_info()}
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	players_changed.emit()
	return OK


func join(address: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_beacon.close()
	players_changed.emit()


func _my_info() -> Dictionary:
	return {"name": Game.player_name, "car": str(Game.match_config.get("car", "sport"))}


func _on_connected() -> void:
	_register.rpc_id(1, _my_info())


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	if multiplayer.is_server():
		_sync_players.rpc(players)
	players_changed.emit()


@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	players[multiplayer.get_remote_sender_id()] = info
	_sync_players.rpc(players)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


## Host only: everyone loads the world with the same config.
func start_match(config: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	config["networked"] = true
	config["seed"] = randi()
	config["roster"] = players.keys()
	_begin.rpc(config)
	_begin(config)


@rpc("authority", "call_remote", "reliable")
func _begin(config: Dictionary) -> void:
	match_started.emit(config)
	Game.start_match(config)


# -------------------------------------------------------------- in-match

## Unreliable state stream (positions, animation, speed...).
func send_state(state: Dictionary) -> void:
	if is_online():
		_state.rpc(state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _state(state: Dictionary) -> void:
	state_received.emit(multiplayer.get_remote_sender_id(), state)


## Reliable events to everyone (and to ourselves, so logic runs in one place).
func send_event(kind: String, data: Dictionary = {}) -> void:
	if is_online():
		_event.rpc(kind, data)
	event_received.emit(my_id(), kind, data)


@rpc("any_peer", "call_remote", "reliable")
func _event(kind: String, data: Dictionary) -> void:
	event_received.emit(multiplayer.get_remote_sender_id(), kind, data)


func name_of(peer_id: int) -> String:
	return str(players.get(peer_id, {}).get("name", "Player %d" % peer_id))


# ------------------------------------------------------------ discovery

func listen_for_games(on: bool) -> void:
	_listening = on
	servers.clear()
	_listener.close()
	if on:
		_listener.bind(BEACON_PORT)


func _process(delta: float) -> void:
	if is_online() and multiplayer.is_server():
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.0
			var msg := JSON.stringify({"lookout": 1, "name": Game.player_name, "players": players.size(), "mode": int(Game.match_config.get("mode", 0))})
			_beacon.put_packet(msg.to_utf8_buffer())
	if _listening:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data = JSON.parse_string(_listener.get_packet().get_string_from_utf8())
			var ip := _listener.get_packet_ip()
			if data is Dictionary and data.has("lookout"):
				if not servers.has(ip):
					changed = true
				servers[ip] = {"name": data.get("name", "?"), "players": data.get("players", 1), "mode": data.get("mode", 0), "seen": Time.get_ticks_msec()}
		for ip: String in servers.keys():
			if Time.get_ticks_msec() - int(servers[ip]["seen"]) > 4000:
				servers.erase(ip)
				changed = true
		if changed:
			servers_changed.emit()
