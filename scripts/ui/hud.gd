extends Control
## HUD principal da sessão. Constrói dinamicamente os 5 slots da barra de inventário (%HudBar),
## o modal anatômico de diagnóstico corporal (%BodyHudModal, tecla [I]) e o painel cooperativo
## de carga (%CarryPanel), além de atualizar barras vitais, objetivo e estado de voz.

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
@onready var hud_bar: HBoxContainer = %HudBar
@onready var body_hud_modal: PanelContainer = %BodyHudModal

var _slot_panels: Array[PanelContainer] = []
var _slot_styles: Array[StyleBoxFlat] = []
var _slot_swatches: Array[ColorRect] = []
var _slot_names: Array[Label] = []
var _slot_details: Array[Label] = []

var _body_part_styles: Dictionary = {}
var _body_part_swatches: Dictionary = {}
var _body_part_names: Dictionary = {}
var _body_part_tags: Dictionary = {}
var _body_part_stats: Dictionary = {}
var _body_summary_label: Label


func _ready() -> void:
	_build_hud_bar()
	_build_body_hud_modal()


func _build_hud_bar() -> void:
	for child in hud_bar.get_children():
		child.queue_free()
	_slot_panels.clear()
	_slot_styles.clear()
	_slot_swatches.clear()
	_slot_names.clear()
	_slot_details.clear()

	for i in Loadout.SLOT_COUNT:
		var panel := PanelContainer.new()
		panel.name = "Slot%d" % (i + 1)
		panel.custom_minimum_size = Vector2(98, 68)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
		style.border_color = Color(0.28, 0.32, 0.4, 0.9)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		panel.add_child(vbox)

		var header := HBoxContainer.new()
		vbox.add_child(header)

		var key_label := Label.new()
		key_label.text = "[%d]" % (i + 1)
		key_label.add_theme_font_size_override("font_size", 11)
		key_label.modulate = Color(0.7, 0.76, 0.85)
		header.add_child(key_label)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(10, 10)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = Color.TRANSPARENT
		header.add_child(swatch)

		var item_label := Label.new()
		item_label.text = "Vazio"
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.add_theme_font_size_override("font_size", 13)
		vbox.add_child(item_label)

		var detail_label := Label.new()
		detail_label.text = ""
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.add_theme_font_size_override("font_size", 11)
		detail_label.modulate = Color(0.82, 0.86, 0.92)
		vbox.add_child(detail_label)

		hud_bar.add_child(panel)
		_slot_panels.append(panel)
		_slot_styles.append(style)
		_slot_swatches.append(swatch)
		_slot_names.append(item_label)
		_slot_details.append(detail_label)


func _build_body_hud_modal() -> void:
	for child in body_hud_modal.get_children():
		child.queue_free()
	_body_part_styles.clear()
	_body_part_swatches.clear()
	_body_part_names.clear()
	_body_part_tags.clear()
	_body_part_stats.clear()

	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color = Color(0.05, 0.07, 0.11, 0.94)
	modal_style.border_color = Color(0.25, 0.78, 0.88, 0.9)
	modal_style.set_border_width_all(2)
	modal_style.set_corner_radius_all(8)
	modal_style.content_margin_left = 16
	modal_style.content_margin_right = 16
	modal_style.content_margin_top = 14
	modal_style.content_margin_bottom = 14
	body_hud_modal.add_theme_stylebox_override("panel", modal_style)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	body_hud_modal.add_child(root_vbox)

	var title := Label.new()
	title.text = "DIAGNÓSTICO CORPORAL — MEMBROS INSTALADOS [I]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color(0.35, 0.92, 1.0)
	root_vbox.add_child(title)

	# Layout anatômico:
	# Linha 1: Cabeça (centro)
	# Linha 2: Braço Esq. | Tronco | Braço Dir.
	# Linha 3: Perna Esq. | Perna Dir.
	var row_head := HBoxContainer.new()
	row_head.alignment = BoxContainer.ALIGNMENT_CENTER
	row_head.add_child(_create_body_slot_card(BodyPartDef.Slot.HEAD))
	root_vbox.add_child(row_head)

	var row_upper := HBoxContainer.new()
	row_upper.alignment = BoxContainer.ALIGNMENT_CENTER
	row_upper.add_theme_constant_override("separation", 10)
	row_upper.add_child(_create_body_slot_card(BodyPartDef.Slot.LEFT_ARM))
	row_upper.add_child(_create_body_slot_card(BodyPartDef.Slot.TORSO))
	row_upper.add_child(_create_body_slot_card(BodyPartDef.Slot.RIGHT_ARM))
	root_vbox.add_child(row_upper)

	var row_lower := HBoxContainer.new()
	row_lower.alignment = BoxContainer.ALIGNMENT_CENTER
	row_lower.add_theme_constant_override("separation", 14)
	row_lower.add_child(_create_body_slot_card(BodyPartDef.Slot.LEFT_LEG))
	row_lower.add_child(_create_body_slot_card(BodyPartDef.Slot.RIGHT_LEG))
	root_vbox.add_child(row_lower)

	_body_summary_label = Label.new()
	_body_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_summary_label.add_theme_font_size_override("font_size", 13)
	_body_summary_label.modulate = Color(0.85, 0.9, 0.96)
	root_vbox.add_child(_body_summary_label)

	var hint := Label.new()
	hint.text = "[E] Instalar membro na mira/mão   |   [G] Destacar membro   |   [I] Fechar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.62, 0.68, 0.78)
	root_vbox.add_child(hint)


func _create_body_slot_card(slot: BodyPartDef.Slot) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "BodySlot_%d" % slot
	card.custom_minimum_size = Vector2(152, 86)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.17, 0.92)
	style.border_color = Color(0.32, 0.38, 0.48, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var slot_title_lbl := Label.new()
	slot_title_lbl.text = BodyPartDef.slot_name(slot).to_upper()
	slot_title_lbl.add_theme_font_size_override("font_size", 11)
	slot_title_lbl.modulate = Color(0.68, 0.75, 0.86)
	header.add_child(slot_title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var tag_lbl := Label.new()
	tag_lbl.text = "ORGÂNICO"
	tag_lbl.add_theme_font_size_override("font_size", 10)
	header.add_child(tag_lbl)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = "---"
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	var stat_lbl := Label.new()
	stat_lbl.text = ""
	stat_lbl.add_theme_font_size_override("font_size", 11)
	stat_lbl.modulate = Color(0.78, 0.84, 0.92)
	vbox.add_child(stat_lbl)

	_body_part_styles[slot] = style
	_body_part_swatches[slot] = swatch
	_body_part_names[slot] = name_lbl
	_body_part_tags[slot] = tag_lbl
	_body_part_stats[slot] = stat_lbl
	return card


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
		body_status.text = "%s   [I] Membros   [G] Destacar   [V] Câmera" % me.get_body_summary()
		_update_hud_bar(me.loadout)
		_update_carry(me)
		body_hud_modal.visible = me.body_hud_open
		if me.body_hud_open:
			_update_body_hud_modal(me)


func _update_body_hud_modal(player: Player) -> void:
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var def := player.get_body_part_def(slot)
		var style := _body_part_styles.get(slot) as StyleBoxFlat
		var swatch := _body_part_swatches.get(slot) as ColorRect
		var name_lbl := _body_part_names.get(slot) as Label
		var tag_lbl := _body_part_tags.get(slot) as Label
		var stat_lbl := _body_part_stats.get(slot) as Label
		if style == null:
			continue

		if def == null:
			style.border_color = Color(0.75, 0.22, 0.22, 0.9)
			style.bg_color = Color(0.14, 0.06, 0.07, 0.88)
			swatch.color = Color.TRANSPARENT
			tag_lbl.text = "AUSENTE"
			tag_lbl.modulate = Color(0.95, 0.35, 0.35)
			name_lbl.text = "[Sem membro]"
			name_lbl.modulate = Color(0.75, 0.45, 0.45)
			stat_lbl.text = "Slot vazio"
		elif def.is_cybernetic:
			style.border_color = Color(0.2, 0.88, 0.96, 1.0)
			style.bg_color = Color(0.08, 0.16, 0.22, 0.94)
			swatch.color = def.color
			tag_lbl.text = "CYBER"
			tag_lbl.modulate = Color(0.25, 0.92, 1.0)
			name_lbl.text = def.display_name
			name_lbl.modulate = Color.WHITE
			stat_lbl.text = _part_stat_text(slot, def)
		else:
			style.border_color = Color(0.38, 0.65, 0.42, 0.9)
			style.bg_color = Color(0.08, 0.12, 0.15, 0.92)
			swatch.color = def.color
			tag_lbl.text = "ORGÂNICO"
			tag_lbl.modulate = Color(0.58, 0.88, 0.62)
			name_lbl.text = def.display_name
			name_lbl.modulate = Color(0.92, 0.95, 0.98)
			stat_lbl.text = _part_stat_text(slot, def)

	if _body_summary_label:
		_body_summary_label.text = "Força de Pegada Total: %d N   |   Velocidade Pernas: %d%%   |   Impulso Pulo: %d%%" % [
			roundi(player.get_grip_force()),
			roundi(player.get_leg_speed_multiplier() * 100.0),
			roundi(player.get_leg_jump_multiplier() * 100.0),
		]


func _part_stat_text(slot: BodyPartDef.Slot, def: BodyPartDef) -> String:
	if BodyPartDef.is_arm_slot(slot):
		return "Pegada: +%d N" % roundi(def.grip_force)
	if BodyPartDef.is_leg_slot(slot):
		return "Vel: %d%%  |  Pulo: %d%%" % [roundi(def.leg_speed_factor * 100.0), roundi(def.leg_jump_factor * 100.0)]
	if def.vital:
		return "Órgão Vital"
	return "Instalado"


func _update_hud_bar(loadout: Loadout) -> void:
	for i in Loadout.SLOT_COUNT:
		if i >= _slot_panels.size():
			break
		var kind := loadout.get_slot_kind(i)
		var is_active := loadout.active_slot == i
		var style := _slot_styles[i]
		if is_active:
			style.border_color = Color(0.95, 0.78, 0.25, 1.0)
			style.bg_color = Color(0.16, 0.19, 0.26, 0.95)
		elif kind != ItemDef.Kind.NONE:
			style.border_color = Color(0.42, 0.48, 0.58, 0.95)
			style.bg_color = Color(0.1, 0.12, 0.17, 0.88)
		else:
			style.border_color = Color(0.24, 0.27, 0.33, 0.75)
			style.bg_color = Color(0.06, 0.07, 0.1, 0.72)

		var def := Loadout.def_of(kind)
		_slot_swatches[i].color = def.color if def else Color.TRANSPARENT
		_slot_names[i].text = loadout.slot_title(i)
		_slot_names[i].modulate = Color.WHITE if kind != ItemDef.Kind.NONE else Color(0.5, 0.54, 0.6)
		_slot_details[i].text = loadout.slot_detail(i)


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
			var code_suffix := "   |   Sala: %s" % Net.room_code if not Net.room_code.is_empty() else ""
			return "Dia %d   Quota $%d%s   |   Puxe a alavanca para iniciar" % [Game.day, Game.quota, code_suffix]
	return ""


func _banner_text() -> String:
	if Game.phase != Game.Phase.RESULTS:
		return ""
	var title := "Quota batida" if Game.last_success else "Quota perdida: de volta ao dia 1"
	return "%s\n$%d de $%d" % [title, Game.last_collected, Game.last_quota]
