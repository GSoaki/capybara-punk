class_name MuleOverload
extends ImplantAbility
## Mão de Mula (implante 5): segurar carga pesada por muito tempo sobrecarrega o braço.
## Após o aviso, a carga é repelida e o jogador é jogado para trás.

## Massa mínima (kg) da carga que conta para a sobrecarga.
const MIN_MASS := 40.0
## Segundos de carga contínua até o início do aviso.
const HOLD_LIMIT := 8.0
## Duração (s) do aviso antes da repulsão.
const WARNING := 1.5
## Impulso aplicado na carga, por kg de massa.
const PROP_IMPULSE_PER_KG := 8.0
## Intensidade do empurrão no jogador (m/s), no sentido oposto à mira.
const SELF_KNOCK := 8.0
## Atordoamento do jogador após a repulsão (s).
const SELF_STUN := 1.0
## Tempo sem tick (s) que indica que o jogador largou a carga.
const TICK_TIMEOUT := 0.15
## Frequência (Hz) do bipe de aviso.
const BEEP_FREQ := 880.0
## Duração (s) de cada bipe.
const BEEP_LENGTH := 0.05
## Intervalo inicial e final (s) entre bipes.
const BEEP_INTERVAL_START := 0.3
const BEEP_INTERVAL_END := 0.08
const MIX_RATE := 22050.0

## Tempo acumulado (s) segurando carga pesada (servidor).
var hold_time := 0.0

var _held_prop: Prop
var _last_tick_msec := 0
var _warning_started := false

# Estado do dono (aviso local).
var _warn_left := 0.0
var _warn_total := 1.0
var _beep_timer := 0.0
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback


func on_hold_tick(prop: Prop, _delta: float) -> void:
	if not is_server():
		return
	if prop.mass < MIN_MASS:
		_reset()
		return
	_held_prop = prop
	_last_tick_msec = Time.get_ticks_msec()
	hold_time += _delta
	if hold_time >= HOLD_LIMIT and not _warning_started:
		_warning_started = true
		_warn.rpc_id(player.peer_id, WARNING)
	if hold_time >= HOLD_LIMIT + WARNING:
		_repulse(prop)


func _physics_process(_delta: float) -> void:
	if not is_server() or _held_prop == null:
		return
	if (Time.get_ticks_msec() - _last_tick_msec) / 1000.0 > TICK_TIMEOUT:
		_reset()


func _process(delta: float) -> void:
	if _warn_left <= 0.0:
		return
	_warn_left -= delta
	if player != null:
		player.carry_notice = "SOBRECARGA! Solte a carga"
		player._carry_notice_timer = 0.2
	_update_beep(delta)
	if _warn_left <= 0.0 and player != null:
		player.carry_notice = ""
		player._carry_notice_timer = 0.0


func _reset() -> void:
	hold_time = 0.0
	_held_prop = null
	_warning_started = false


## Servidor: solta a carga com impulso e empurra o jogador para trás.
func _repulse(prop: Prop) -> void:
	var aim := player.get_aim_direction()
	prop.holders.erase(player.peer_id)
	player.grab_lost.rpc_id(player.peer_id)
	prop.apply_central_impulse(aim * PROP_IMPULSE_PER_KG * prop.mass)
	player.server_hit(0, -aim * SELF_KNOCK + Vector3.UP * 3.0, SELF_STUN, Game.HitSource.GENERIC)
	Game.emit_noise(player.global_position, Game.NOISE_MULE_OVERLOAD)
	_reset()


## Servidor -> dono: inicia o aviso de sobrecarga (aceita só o servidor ou chamada local).
@rpc("any_peer", "call_local", "reliable")
func _warn(duration: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_warn_total = maxf(duration, 0.01)
	_warn_left = duration
	_beep_timer = 0.0


## Dono: bipe acelerado (intervalo de 0.3 s até 0.08 s). Ignorado em modo headless.
func _update_beep(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _audio == null:
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = MIX_RATE
		stream.buffer_length = 0.2
		_audio = AudioStreamPlayer.new()
		_audio.stream = stream
		add_child(_audio)
		_audio.play()
		_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		return
	_beep_timer -= delta
	if _beep_timer > 0.0:
		return
	var progress := clampf(1.0 - _warn_left / _warn_total, 0.0, 1.0)
	_beep_timer = lerpf(BEEP_INTERVAL_START, BEEP_INTERVAL_END, progress)
	var frames := int(BEEP_LENGTH * MIX_RATE)
	for i in mini(frames, _playback.get_frames_available()):
		var s := sin(TAU * BEEP_FREQ * float(i) / MIX_RATE) * 0.3
		_playback.push_frame(Vector2(s, s))
