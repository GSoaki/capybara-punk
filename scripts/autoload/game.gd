extends Node
## Máquina de estados da partida: lobby -> run -> resultado -> lobby.
## O servidor decide; os clientes recebem o estado por RPC.

enum Phase { LOBBY, RUN, RESULTS }

signal state_changed
signal run_started(level_seed: int)
signal run_ended(success: bool)
signal enemies_disabled_changed(disabled: bool)
## Somente no servidor. Monstros escutam este sinal.
signal noise_emitted(origin: Vector3, loudness: float)

const RUN_SECONDS := 300.0
const RESULTS_SECONDS := 6.0
const BASE_QUOTA := 300
const QUOTA_GROWTH := 1.35

var phase := Phase.LOBBY
var day := 1
var quota := BASE_QUOTA
var collected := 0
var time_left := 0.0
var last_success := false
var last_collected := 0
var last_quota := 0
## Opção para desativar inimigos (para testes).
var enemies_disabled := false

## peer_id -> Player
var players: Dictionary = {}

var _sync_timer := 0.0
var _results_timer := 0.0


func _ready() -> void:
	Net.session_ended.connect(func(_reason: String) -> void: _reset())


func _process(delta: float) -> void:
	if phase == Phase.RUN:
		time_left = maxf(time_left - delta, 0.0)
	if not Net.in_session or not multiplayer.is_server():
		return
	match phase:
		Phase.RUN:
			_sync_timer -= delta
			if _sync_timer <= 0.0:
				_sync_timer = 1.0
				_push_all()
			if time_left <= 0.0:
				end_run()
		Phase.RESULTS:
			_results_timer -= delta
			if _results_timer <= 0.0:
				phase = Phase.LOBBY
				_push_all()


func local_player() -> Player:
	return players.get(multiplayer.get_unique_id()) as Player


func register_player(player: Player) -> void:
	players[player.peer_id] = player


func unregister_player(player: Player) -> void:
	if players.get(player.peer_id) == player:
		players.erase(player.peer_id)


## Servidor: alavanca do van inicia a run no lobby e encerra durante a run.
func pull_lever() -> void:
	match phase:
		Phase.LOBBY:
			phase = Phase.RUN
			collected = 0
			time_left = RUN_SECONDS
			_push_all()
			_begin_run.rpc(randi())
		Phase.RUN:
			end_run()


func end_run() -> void:
	if phase != Phase.RUN:
		return
	var success := collected >= quota
	var collected_now := collected
	var quota_now := quota
	if success:
		day += 1
		quota = ceili(quota * QUOTA_GROWTH)
	else:
		day = 1
		quota = BASE_QUOTA
	phase = Phase.RESULTS
	_results_timer = RESULTS_SECONDS
	collected = 0
	_push_all()
	_finish_run.rpc(success, collected_now, quota_now)


func set_collected(value: int) -> void:
	if value != collected:
		collected = value
		_push_all()


func check_all_dead() -> void:
	for player: Player in players.values():
		if player.alive:
			return
	end_run()


func emit_noise(origin: Vector3, loudness: float) -> void:
	if multiplayer.is_server():
		noise_emitted.emit(origin, loudness)


func send_state_to(peer_id: int) -> void:
	_receive_state.rpc_id(peer_id, phase, day, quota, collected, time_left)
	_sync_enemies_disabled.rpc_id(peer_id, enemies_disabled)


func set_enemies_disabled(disabled: bool) -> void:
	if not Net.in_session:
		enemies_disabled = disabled
		enemies_disabled_changed.emit(disabled)
		return
	if multiplayer.is_server():
		_apply_enemies_disabled_server(disabled)
	else:
		request_set_enemies_disabled.rpc_id(1, disabled)


func _apply_enemies_disabled_server(disabled: bool) -> void:
	if not multiplayer.is_server():
		return
	enemies_disabled = disabled
	_sync_enemies_disabled.rpc(disabled)
	var main := get_tree().current_scene
	if main and main.has_method("apply_enemies_disabled"):
		main.apply_enemies_disabled(disabled)


@rpc("any_peer", "call_local", "reliable")
func request_set_enemies_disabled(disabled: bool) -> void:
	if multiplayer.is_server():
		_apply_enemies_disabled_server(disabled)


@rpc("authority", "call_local", "reliable")
func _sync_enemies_disabled(disabled: bool) -> void:
	enemies_disabled = disabled
	enemies_disabled_changed.emit(disabled)


func _push_all() -> void:
	_receive_state.rpc(phase, day, quota, collected, time_left)


func _reset() -> void:
	phase = Phase.LOBBY
	day = 1
	quota = BASE_QUOTA
	collected = 0
	time_left = 0.0
	state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _receive_state(p_phase: int, p_day: int, p_quota: int, p_collected: int, p_time: float) -> void:
	phase = p_phase as Phase
	day = p_day
	quota = p_quota
	collected = p_collected
	time_left = p_time
	state_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin_run(level_seed: int) -> void:
	run_started.emit(level_seed)


@rpc("authority", "call_local", "reliable")
func _finish_run(success: bool, collected_now: int, quota_now: int) -> void:
	last_success = success
	last_collected = collected_now
	last_quota = quota_now
	run_ended.emit(success)
