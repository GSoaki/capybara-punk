class_name VoiceCodec
extends RefCounted
## Mu-law de 8 bits a 16 kHz: 16 kB/s por pessoa falando e nenhuma dependência nativa.
## Para usar Opus, troque encode e decode mantendo as assinaturas.

const SAMPLE_RATE := 16000
const MU := 255.0

static var _decode_table := PackedFloat32Array()


static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	var log_mu := log(1.0 + MU)
	for i in samples.size():
		var x := clampf(samples[i], -1.0, 1.0)
		var y := signf(x) * log(1.0 + MU * absf(x)) / log_mu
		out[i] = roundi((y + 1.0) * 127.5)
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	if _decode_table.is_empty():
		_build_table()
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = _decode_table[data[i]]
	return out


static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for s in samples:
		total += s * s
	return sqrt(total / samples.size())


static func _build_table() -> void:
	_decode_table.resize(256)
	for i in 256:
		var y := i / 127.5 - 1.0
		_decode_table[i] = signf(y) * (pow(1.0 + MU, absf(y)) - 1.0) / MU
