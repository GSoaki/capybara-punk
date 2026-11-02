extends Node
## Sessão de rede: host/join, roster e rejeição de entradas inválidas.
## Para trocar ENet por Steam, altere apenas _create_host_peer e _create_client_peer.

signal roster_changed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal session_started
signal session_ended(reason: String)

const GAME_VERSION := "0.1.0"
const DEFAULT_PORT := 24565
const MAX_PLAYERS := 8
const PALETTE: Array[Color] = [
	Color("f2c14e"), Color("5fa8d3"), Color("e4572e"), Color("76b041"),
	Color("b56576"), Color("9d8df1"), Color("2ec4b6"), Color("ff9f1c"),
]

## peer_id -> {"name": String, "color": Color}
var roster: Dictionary = {}
var in_session := false

var _reject_reason := ""
var _next_color := 0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: leave("Não foi possível conectar."))
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := _create_host_peer(port)
	if peer == null:
		return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = peer
	in_session = true
	_next_color = 0
	_add_player(1, Settings.player_name)
	session_started.emit()
	roster_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := _create_client_peer(address, port)
	if peer == null:
		return ERR_CANT_CONNECT
	multiplayer.multiplayer_peer = peer
	return OK


func leave(reason: String = "") -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	in_session = false
	_reject_reason = ""
	session_ended.emit(reason)
	roster_changed.emit()


## ID de quem chamou a RPC. Em chamadas locais do host a engine pode devolver 0.
func sender_id() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _create_host_peer(port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	return peer if peer.create_server(port, MAX_PLAYERS - 1) == OK else null


func _create_client_peer(address: String, port: int) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	return peer if peer.create_client(address, port) == OK else null


func _add_player(peer_id: int, player_name: String) -> void:
	var clean := player_name.strip_edges().left(24)
	roster[peer_id] = {
		"name": clean if not clean.is_empty() else "Jogador %d" % roster.size(),
		"color": PALETTE[_next_color % PALETTE.size()],
	}
	_next_color += 1
	player_joined.emit(peer_id)


func _on_connected_to_server() -> void:
	_register.rpc_id(1, Settings.player_name, GAME_VERSION)


func _on_server_disconnected() -> void:
	leave(_reject_reason if not _reject_reason.is_empty() else "O host encerrou a sessão.")


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or not roster.has(peer_id):
		return
	roster.erase(peer_id)
	player_left.emit(peer_id)
	_sync_roster.rpc(roster)


@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var refusal := ""
	if version != GAME_VERSION:
		refusal = "Versão diferente da do host (%s)." % GAME_VERSION
	elif Game.phase != Game.Phase.LOBBY:
		refusal = "A partida já começou. Aguarde o retorno ao lobby."
	if not refusal.is_empty():
		_reject.rpc_id(sender, refusal)
		await get_tree().create_timer(0.25).timeout
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	_add_player(sender, player_name)
	_sync_roster.rpc(roster)
	Game.send_state_to(sender)


@rpc("authority", "call_local", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	if not in_session and roster.has(multiplayer.get_unique_id()):
		in_session = true
		session_started.emit()
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	_reject_reason = reason
