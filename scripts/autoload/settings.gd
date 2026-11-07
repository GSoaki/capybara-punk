extends Node
## Preferências locais do jogador, gravadas em user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name := "Jogador"
var last_address := "127.0.0.1"
var last_room_code := ""
var mouse_sensitivity := 0.0025
var voice_enabled := true
var voice_push_to_talk := false
var voice_gate := 0.015


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", player_name)
	last_address = cfg.get_value("net", "address", last_address)
	last_room_code = cfg.get_value("net", "room_code", last_room_code)
	mouse_sensitivity = cfg.get_value("input", "sensitivity", mouse_sensitivity)
	voice_enabled = cfg.get_value("voice", "enabled", voice_enabled)
	voice_push_to_talk = cfg.get_value("voice", "push_to_talk", voice_push_to_talk)
	voice_gate = cfg.get_value("voice", "gate", voice_gate)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("net", "address", last_address)
	cfg.set_value("net", "room_code", last_room_code)
	cfg.set_value("input", "sensitivity", mouse_sensitivity)
	cfg.set_value("voice", "enabled", voice_enabled)
	cfg.set_value("voice", "push_to_talk", voice_push_to_talk)
	cfg.set_value("voice", "gate", voice_gate)
	cfg.save(PATH)
