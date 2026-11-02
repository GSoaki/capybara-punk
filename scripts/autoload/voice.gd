extends Node
## Captura do microfone: reamostra para 16 kHz mono, aplica gate e envia pelo Player local.

const FRAME_SAMPLES := VoiceCodec.SAMPLE_RATE / 25
const GATE_HOLD_SECONDS := 0.3

var mic_level := 0.0
var transmitting := false

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _pending := PackedFloat32Array()
var _accumulator := 0.0
var _accumulated := 0
var _resample_pos := 0.0
var _gate_hold := 0.0


func _ready() -> void:
	Net.session_started.connect(start)
	Net.session_ended.connect(func(_reason: String) -> void: stop())
	set_process(false)


func start() -> void:
	if DisplayServer.get_name() == "headless" or not Settings.voice_enabled:
		return
	var bus := AudioServer.get_bus_index("Mic")
	if bus < 0:
		push_warning("Bus Mic ausente; voz desativada.")
		return
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = &"Mic"
		add_child(_mic_player)
	_capture.clear_buffer()
	_mic_player.play()
	set_process(true)


func stop() -> void:
	if _mic_player:
		_mic_player.stop()
	_pending.clear()
	mic_level = 0.0
	transmitting = false
	set_process(false)


func _process(delta: float) -> void:
	var available := _capture.get_frames_available()
	if available > 0:
		_resample(_capture.get_buffer(available))
	while _pending.size() >= FRAME_SAMPLES:
		var frame := _pending.slice(0, FRAME_SAMPLES)
		_pending = _pending.slice(FRAME_SAMPLES)
		_handle_frame(frame, float(FRAME_SAMPLES) / VoiceCodec.SAMPLE_RATE)
	_gate_hold = maxf(_gate_hold - delta, 0.0)


func _resample(stereo: PackedVector2Array) -> void:
	var ratio := AudioServer.get_mix_rate() / VoiceCodec.SAMPLE_RATE
	for sample in stereo:
		_accumulator += (sample.x + sample.y) * 0.5
		_accumulated += 1
		_resample_pos += 1.0
		if _resample_pos >= ratio:
			_resample_pos -= ratio
			_pending.append(_accumulator / _accumulated)
			_accumulator = 0.0
			_accumulated = 0


func _handle_frame(frame: PackedFloat32Array, duration: float) -> void:
	mic_level = VoiceCodec.rms(frame)
	var open: bool
	if Settings.voice_push_to_talk:
		open = Input.is_action_pressed("push_to_talk")
	else:
		if mic_level >= Settings.voice_gate:
			_gate_hold = GATE_HOLD_SECONDS + duration
		open = _gate_hold > 0.0
	transmitting = open
	var player := Game.local_player()
	if open and player:
		player.send_voice(VoiceCodec.encode(frame))
