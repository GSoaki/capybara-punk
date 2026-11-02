extends Control

const CARRY_OK := Color("76b041")
const CARRY_NEEDS_HELP := Color("f2c14e")
const PIP_EMPTY := Color(1.0, 1.0, 1.0, 0.2)

@onready var objective: Label = %Objective
@onready var prompt: Label = %Prompt
@onready var banner: Label = %Banner
@onready var roster_label: Label = %Roster
@onready var body_status: Label = %BodyStatus
@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mic_bar: ProgressBar = %MicBar
@onready var loadout_label: Label = %LoadoutLabel
@onready var carry_panel: Control = %CarryPanel
@onready var carry_status_label: Label = %CarryStatus
@onready var carry_count_label: Label = %CarryCount
@onready var carry_pips: HBoxContainer = %CarryPips

var _pips_signature := ""


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
		loadout_label.text = me.loadout.hud_text()
		body_status.text = "%s   [G] Destacar membro   [V] Câmera" % me.get_body_summary()
		_update_carry(me)


func _update_carry(me: Player) -> void:
	var prop := _carry_target(me)
	if prop == null:
		carry_panel.visible = not me.carry_notice.is_empty()
		carry_status_label.text = me.carry_notice
		carry_status_label.modulate = CARRY_NEEDS_HELP
		carry_count_label.text = ""
		_set_pips(me, PackedInt32Array(), 0)
		return
	var status := carry_status(me, prop)
	carry_panel.visible = true
	carry_status_label.text = status.text
	carry_status_label.modulate = status.color
	carry_count_label.text = carry_count_text(prop)
	_set_pips(me, prop.net_holder_ids, _alive_players())


## O objeto na mão tem prioridade. Na mira, só aparece se o trabalho for em grupo.
func _carry_target(me: Player) -> Prop:
	if not me.alive:
		return null
	if is_instance_valid(me.held_prop):
		return me.held_prop
	var aimed := me.ray.get_collider() as Prop
	if aimed and (not aimed.net_holder_ids.is_empty() or aimed.people_needed() > 1):
		return aimed
	return null


## Frase principal e cor do painel para quem olha ou segura o objeto.
func carry_status(me: Player, prop: Prop) -> Dictionary:
	var item_name := prop.def.display_name
	var ids := prop.net_holder_ids
	var holding := ids.has(me.peer_id)
	if me.held_prop == prop and not holding:
		return {"text": "Agarrando %s..." % item_name, "color": Color.WHITE}
	var allies := PackedStringArray()
	for peer_id: int in ids:
		if peer_id != me.peer_id:
			allies.append(str(Net.roster.get(peer_id, {}).get("name", "Aliado")))
	var names := ", ".join(allies)
	var missing := prop.people_missing()
	var missing_text := "  (falta %d)" % missing if missing > 0 else ""
	var color := CARRY_NEEDS_HELP if missing > 0 else CARRY_OK
	if holding:
		if allies.is_empty():
			var alone := "Segurando %s sozinho" % item_name if missing > 0 else "Segurando %s" % item_name
			return {"text": alone + missing_text, "color": color}
		if ids[0] == me.peer_id:
			var verb := "estão ajudando" if allies.size() > 1 else "está ajudando"
			return {"text": "%s %s você com %s%s" % [names, verb, item_name, missing_text], "color": color}
		return {"text": "Você está ajudando %s com %s%s" % [names, item_name, missing_text], "color": color}
	if allies.is_empty():
		return {"text": "%s precisa de %d jogadores" % [item_name, prop.people_needed()], "color": CARRY_NEEDS_HELP}
	var carrying := "estão carregando" if allies.size() > 1 else "está carregando"
	return {"text": "%s %s %s%s" % [names, carrying, item_name, missing_text], "color": CARRY_NEEDS_HELP if missing > 0 else Color.WHITE}


## Sempre relativo a quem pode ajudar agora: mortos não contam.
func carry_count_text(prop: Prop) -> String:
	return "%d de %d jogadores segurando" % [prop.net_holder_ids.size(), _alive_players()]


func _alive_players() -> int:
	var count := 0
	for player: Player in Game.players.values():
		if player.alive:
			count += 1
	return count


## Um bloco por jogador vivo: quem segura aparece na própria cor, e o seu bloco é mais alto.
func _set_pips(me: Player, ids: PackedInt32Array, total: int) -> void:
	var signature := "%s/%d/%d" % [ids, total, me.peer_id]
	if signature == _pips_signature:
		return
	_pips_signature = signature
	for pip in carry_pips.get_children():
		pip.free()
	for i in maxi(total, ids.size()):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(22.0, 10.0)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = PIP_EMPTY
		if i < ids.size():
			pip.color = Net.roster.get(ids[i], {}).get("color", Color.WHITE)
			if ids[i] == me.peer_id:
				pip.custom_minimum_size.y = 16.0
		carry_pips.add_child(pip)


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
