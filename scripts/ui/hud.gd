extends Control

@onready var objective: Label = %Objective
@onready var prompt: Label = %Prompt
@onready var banner: Label = %Banner
@onready var roster_label: Label = %Roster
@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mic_bar: ProgressBar = %MicBar


func _process(_delta: float) -> void:
	objective.text = _objective_text()
	banner.text = _banner_text()
	var lines := PackedStringArray()
	for peer_id: int in Net.roster:
		var player := Game.players.get(peer_id) as Player
		var mark := ""
		if player and not player.alive:
			mark = " (morto)"
		elif player and player.voice_level > 0.005:
			mark = " (falando)"
		lines.append(str(Net.roster[peer_id].name) + mark)
	roster_label.text = "\n".join(lines)
	mic_bar.value = Voice.mic_level * 100.0
	mic_bar.modulate = Color("76b041") if Voice.transmitting else Color.WHITE
	var me := Game.local_player()
	if me:
		health_bar.value = me.health
		stamina_bar.value = me.stamina
		prompt.text = me.hover_text


func _objective_text() -> String:
	match Game.phase:
		Game.Phase.RUN:
			var seconds := ceili(Game.time_left)
			return "Dia %d   $%d / $%d   %d:%02d" % [Game.day, Game.collected, Game.quota, seconds / 60, seconds % 60]
		Game.Phase.LOBBY:
			return "Dia %d   Quota $%d   Puxe a alavanca para iniciar" % [Game.day, Game.quota]
	return ""


func _banner_text() -> String:
	if Game.phase != Game.Phase.RESULTS:
		return ""
	var title := "Quota batida" if Game.last_success else "Quota perdida: de volta ao dia 1"
	return "%s\n$%d de $%d" % [title, Game.last_collected, Game.last_quota]
