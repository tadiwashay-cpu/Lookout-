extends Node
## Local multiplayer over Wi-Fi (Godot ENet). One device hosts, others join
## with the host's IP shown in its lobby. Online play across the internet
## needs a relay/dedicated server — see docs/multiplayer.md.
##
## Lobby: players register with the host, the host starts the match.
## In-game: each device simulates its own player and sends a small state
## packet ~15x a second; damage and match events are reliable RPCs.

signal players_changed
signal connected_ok
signal connection_failed
signal session_ended(reason: String)
signal state_received(peer_id: int, state: Dictionary)
signal damage_received(amount: float, from_peer: int, knockback: Vector3)
signal slow_received(seconds: float)
signal player_eliminated(peer_id: int, by_peer: int)
signal match_event(kind: String, data: Dictionary)
signal lobby_mode_changed(mode: int)

const PORT := 7777
const MAX_PLAYERS := 12

## peer_id -> {"name": String, "character": String}
var players: Dictionary = {}
## The mode the host picked (shown to everyone in the lobby).
var lobby_mode: int = 1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	session_ended.emit("Host left the game.")


func _me() -> Dictionary:
	return {"name": GameSettings.player_name, "character": GameSettings.character}


func is_active() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _me()}
	players_changed.emit()
	return OK


func join(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	players_changed.emit()


func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254"):
			out.append(address)
	return out


# ------------------------------------------------------------------- lobby

func _on_connected_to_server() -> void:
	_register.rpc_id(1, _me())
	connected_ok.emit()


func _on_peer_connected(_id: int) -> void:
	pass   # the new peer registers itself


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	players_changed.emit()
	if multiplayer.is_server():
		_sync_players.rpc(players)
		_eliminated.rpc(id, 0)   # a dropped player counts as out


@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	players[multiplayer.get_remote_sender_id()] = {
		"name": str(info.get("name", "Player")).left(16),
		"character": info.get("character", "x_bot"),
	}
	_sync_players.rpc(players)
	_sync_mode.rpc(lobby_mode)
	players_changed.emit()


@rpc("authority", "reliable")
func _sync_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


## Host only.
func set_lobby_mode(mode: int) -> void:
	lobby_mode = mode
	lobby_mode_changed.emit(mode)
	if is_active() and multiplayer.is_server():
		_sync_mode.rpc(mode)


@rpc("authority", "reliable")
func _sync_mode(mode: int) -> void:
	lobby_mode = mode
	lobby_mode_changed.emit(mode)


## Host only: pick a seed and (for the heist) split teams, then start everyone.
func start_match(mode: int) -> void:
	if not multiplayer.is_server():
		return
	var ids: Array = players.keys()
	ids.shuffle()
	var teams := {}
	if mode == Session.MODE_HEIST:
		for i in ids.size():
			teams[ids[i]] = "robbers" if i % 2 == 0 else "police"
	_begin.rpc(mode, randi(), teams)


@rpc("authority", "call_local", "reliable")
func _begin(mode: int, seed_value: int, teams: Dictionary) -> void:
	Session.start_match(mode, seed_value, teams, true)


# ------------------------------------------------------------------ in game

func send_state(state: Dictionary) -> void:
	if is_active():
		_state.rpc(state)


@rpc("any_peer", "unreliable_ordered")
func _state(state: Dictionary) -> void:
	state_received.emit(multiplayer.get_remote_sender_id(), state)


func send_damage(target_peer: int, amount: float, knockback: Vector3 = Vector3.ZERO) -> void:
	if is_active() and target_peer != multiplayer.get_unique_id():
		_damage.rpc_id(target_peer, amount, knockback)


@rpc("any_peer", "reliable")
func _damage(amount: float, knockback: Vector3) -> void:
	damage_received.emit(clampf(amount, 0.0, 200.0), multiplayer.get_remote_sender_id(), knockback.limit_length(20.0))


func send_slow(target_peer: int, seconds: float) -> void:
	if is_active():
		_slow.rpc_id(target_peer, seconds)


@rpc("any_peer", "reliable")
func _slow(seconds: float) -> void:
	slow_received.emit(clampf(seconds, 0.0, 5.0))


func announce_eliminated(peer_id: int, by_peer: int) -> void:
	if is_active():
		_eliminated.rpc(peer_id, by_peer)
	else:
		player_eliminated.emit(peer_id, by_peer)


@rpc("any_peer", "call_local", "reliable")
func _eliminated(peer_id: int, by_peer: int) -> void:
	player_eliminated.emit(peer_id, by_peer)


## Generic reliable match events (checkpoints, extraction, results...).
func send_event(kind: String, data: Dictionary) -> void:
	if is_active():
		_event.rpc(kind, data)
	else:
		data["sender"] = 1
		match_event.emit(kind, data)


@rpc("any_peer", "call_local", "reliable")
func _event(kind: String, data: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	data["sender"] = sender if sender != 0 else multiplayer.get_unique_id()
	match_event.emit(kind, data)
