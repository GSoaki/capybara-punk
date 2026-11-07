extends Node
## Sessão de rede: suporta Epic Online Services (P2P + Lobbies com código de sala) e
## fallback local via ENet para LAN, desenvolvimento sem credenciais e smoke tests headless.

signal roster_changed
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal session_started
signal session_ended(reason: String)
signal eos_status_changed(ready: bool, status_text: String)
signal room_code_changed(code: String)

const GAME_VERSION := "0.1.0"
const DEFAULT_PORT := 24565
const MAX_PLAYERS := 8
const EOS_CREDENTIALS_PATH := "res://eos_credentials.cfg"
const EOS_SOCKET_NAME := "CapybaraGame"
const EOS_BUCKET_ID := "CAPYBARA_PUNK_V1"
const EOS_ATTR_ROOM_CODE := "ROOM_CODE"
const EOS_ATTR_VERSION := "GAME_VERSION"
const ROOM_CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6

const PALETTE: Array[Color] = [
	Color("f2c14e"), Color("5fa8d3"), Color("e4572e"), Color("76b041"),
	Color("b56576"), Color("9d8df1"), Color("2ec4b6"), Color("ff9f1c"),
]

## peer_id -> {"name": String, "color": Color}
var roster: Dictionary = {}
var in_session := false
var room_code := ""
var eos_available := false
var eos_ready := false
var eos_connecting := false
var eos_status := "Modo Local (LAN)"
var active_lobby: HLobby = null

var _reject_reason := ""
var _next_color := 0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: leave("Não foi possível conectar."))
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_eos_if_configured.call_deferred()


func _init_eos_if_configured() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--smoke"):
			return
	var creds := _load_eos_credentials()
	if creds == null:
		eos_status = "Sem eos_credentials.cfg (Modo LAN ativo)"
		eos_status_changed.emit(false, eos_status)
		return
	if not ClassDB.class_exists(&"EOSGMultiplayerPeer"):
		eos_status = "Plugin EOSG ausente (Modo LAN ativo)"
		eos_status_changed.emit(false, eos_status)
		return

	eos_available = true
	eos_connecting = true
	eos_status = "Conectando aos serviços da Epic..."
	eos_status_changed.emit(false, eos_status)

	HLog.log_level = HLog.LogLevel.WARN
	HLobbies.local_rtc_options = null
	HLobbies.presence_enabled = false

	var setup_ok := await HPlatform.setup_eos_async(creds)
	if not setup_ok:
		eos_connecting = false
		eos_status = "Falha ao inicializar Epic SDK (Modo LAN ativo)"
		eos_status_changed.emit(false, eos_status)
		return

	HP2P.set_relay_control(EOS.P2P.RelayControl.AllowRelays)

	var display := Settings.player_name.strip_edges()
	if display.is_empty():
		display = "Capybara"
	var login_ok := await HAuth.login_anonymous_async(display)
	eos_connecting = false
	if not login_ok or HAuth.product_user_id.is_empty():
		eos_status = "Falha no login Epic DeviceID (Modo LAN ativo)"
		eos_status_changed.emit(false, eos_status)
		return

	eos_ready = true
	eos_status = "Epic Online Services pronto"
	eos_status_changed.emit(true, eos_status)


func _load_eos_credentials() -> HCredentials:
	var cfg := ConfigFile.new()
	if cfg.load(EOS_CREDENTIALS_PATH) != OK:
		return null
	var product_id := str(cfg.get_value("eos", "product_id", "")).strip_edges()
	var sandbox_id := str(cfg.get_value("eos", "sandbox_id", "")).strip_edges()
	var deployment_id := str(cfg.get_value("eos", "deployment_id", "")).strip_edges()
	var client_id := str(cfg.get_value("eos", "client_id", "")).strip_edges()
	var client_secret := str(cfg.get_value("eos", "client_secret", "")).strip_edges()
	if product_id.is_empty() or sandbox_id.is_empty() or deployment_id.is_empty() or client_id.is_empty() or client_secret.is_empty():
		return null
	var creds := HCredentials.new()
	creds.product_name = str(cfg.get_value("eos", "product_name", "Capybara Punk"))
	creds.product_version = str(cfg.get_value("eos", "product_version", GAME_VERSION))
	creds.product_id = product_id
	creds.sandbox_id = sandbox_id
	creds.deployment_id = deployment_id
	creds.client_id = client_id
	creds.client_secret = client_secret
	return creds


## Cria sala online via Epic Games P2P e retorna o código curto gerado (ou "" em falha).
func host_eos_async() -> String:
	if not eos_ready:
		return ""
	await _cleanup_lobby_async()

	var create_opts := EOS.Lobby.CreateLobbyOptions.new()
	create_opts.bucket_id = EOS_BUCKET_ID
	create_opts.max_lobby_members = MAX_PLAYERS
	create_opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	create_opts.presence_enabled = false
	create_opts.enable_rtc_room = false
	create_opts.allow_invites = true

	var lobby := await HLobbies.create_lobby_async(create_opts)
	if lobby == null:
		return ""

	var code := _generate_room_code()
	lobby.add_attribute(EOS_ATTR_ROOM_CODE, code, EOS.Lobby.LobbyAttributeVisibility.Public)
	lobby.add_attribute(EOS_ATTR_VERSION, GAME_VERSION, EOS.Lobby.LobbyAttributeVisibility.Public)
	var updated := await lobby.update_async()
	if not updated:
		await lobby.destroy_async()
		return ""

	var peer := EOSGMultiplayerPeer.new()
	peer.set_auto_accept_connection_requests(true)
	if peer.create_server(EOS_SOCKET_NAME) != OK:
		await lobby.destroy_async()
		return ""

	active_lobby = lobby
	multiplayer.multiplayer_peer = peer
	in_session = true
	_next_color = 0
	room_code = code
	room_code_changed.emit(room_code)
	_add_player(1, Settings.player_name)
	session_started.emit()
	roster_changed.emit()
	return code


## Busca uma sala na Epic pelo código de 6 caracteres (ou ProductUserId direto) e conecta via P2P.
func join_eos_by_code_async(code_or_puid: String) -> Error:
	if not eos_ready:
		return ERR_UNCONFIGURED
	var clean := code_or_puid.strip_edges().to_upper()
	if clean.is_empty():
		return ERR_INVALID_PARAMETER

	await _cleanup_lobby_async()

	var host_puid := ""
	var lobbies: Variant = await HLobbies.search_by_attribute_async([
		{
			"key": EOS_ATTR_ROOM_CODE,
			"value": clean,
			"comparison": EOS.ComparisonOp.Equal,
		},
	])
	if lobbies is Array and not lobbies.is_empty():
		var target_lobby: HLobby = lobbies[0]
		var joined_lobby: HLobby = await HLobbies.join_async(target_lobby)
		if joined_lobby == null:
			return ERR_CANT_CONNECT
		active_lobby = joined_lobby
		host_puid = joined_lobby.owner_product_user_id
		room_code = clean
		room_code_changed.emit(room_code)
	elif code_or_puid.strip_edges().length() >= 16:
		# Permite também colar diretamente o ProductUserId do host (útil para testes rápidos)
		host_puid = code_or_puid.strip_edges()
		room_code = "DIRETO"
		room_code_changed.emit(room_code)
	else:
		return ERR_DOES_NOT_EXIST

	if host_puid.is_empty() or host_puid == HAuth.product_user_id:
		await _cleanup_lobby_async()
		return ERR_CANT_CONNECT

	var peer := EOSGMultiplayerPeer.new()
	if peer.create_client(EOS_SOCKET_NAME, host_puid) != OK:
		await _cleanup_lobby_async()
		return ERR_CANT_CONNECT

	multiplayer.multiplayer_peer = peer
	return OK


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := _create_host_peer(port)
	if peer == null:
		return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = peer
	in_session = true
	_next_color = 0
	room_code = "LAN:%d" % port
	room_code_changed.emit(room_code)
	_add_player(1, Settings.player_name)
	session_started.emit()
	roster_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := _create_client_peer(address, port)
	if peer == null:
		return ERR_CANT_CONNECT
	room_code = address
	room_code_changed.emit(room_code)
	multiplayer.multiplayer_peer = peer
	return OK


func leave(reason: String = "") -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_cleanup_lobby_async()
	roster.clear()
	in_session = false
	room_code = ""
	room_code_changed.emit("")
	_reject_reason = ""
	session_ended.emit(reason)
	roster_changed.emit()


func _cleanup_lobby_async() -> void:
	if active_lobby == null:
		return
	var lobby := active_lobby
	active_lobby = null
	if lobby.is_valid():
		if lobby.is_owner():
			await lobby.destroy_async()
		else:
			await lobby.leave_async()


func _generate_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result := ""
	for i in ROOM_CODE_LENGTH:
		result += ROOM_CODE_CHARS[rng.randi_range(0, ROOM_CODE_CHARS.length() - 1)]
	return result


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
	elif roster.size() >= MAX_PLAYERS:
		refusal = "A sala está cheia (%d/%d)." % [MAX_PLAYERS, MAX_PLAYERS]
	if not refusal.is_empty():
		_reject.rpc_id(sender, refusal)
		await get_tree().create_timer(0.25).timeout
		if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
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
