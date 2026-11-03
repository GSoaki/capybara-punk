class_name VoiceOutput
extends AudioStreamPlayer3D
## Toca a voz recebida no espaço 3D, com buffer de jitter de 80 ms.

const PREBUFFER_SAMPLES := 1280
const MAX_QUEUED_SAMPLES := 8000

var _playback: AudioStreamGeneratorPlayback
var _queue := PackedFloat32Array()
var _buffering := true


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = VoiceCodec.SAMPLE_RATE
	generator.buffer_length = 0.25
	stream = generator
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func push(samples: PackedFloat32Array) -> void:
	_queue.append_array(samples)
	if _queue.size() > MAX_QUEUED_SAMPLES:
		_queue = _queue.slice(_queue.size() - PREBUFFER_SAMPLES)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	if _buffering:
		if _queue.size() < PREBUFFER_SAMPLES:
			return
		_buffering = false
	var count := mini(_playback.get_frames_available(), _queue.size())
	if count > 0:
		var frames := PackedVector2Array()
		frames.resize(count)
		for i in count:
			frames[i] = Vector2(_queue[i], _queue[i])
		_playback.push_buffer(frames)
		_queue = _queue.slice(count)
	if _queue.is_empty():
		_buffering = true
