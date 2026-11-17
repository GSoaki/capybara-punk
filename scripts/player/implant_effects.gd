class_name ImplantEffects
extends Node
## Agrega os efeitos passivos dos implantes instalados e gerencia os nós de habilidade.

const ABILITY_DIR := "res://scripts/implants/"
const MAX_DAMAGE_REDUCTION := 0.9

var player: Player
var _damage_reduction := 0.0
var _move_speed_mult := 1.0
var _stamina_regen_mult := 1.0
var _voice_mult := 1.0
var _fall_speed_bonus := 0.0
var _voice_cap := Game.NOISE_VOICE_CAP
var _hold_offset := Vector3.ZERO
var _abilities: Dictionary = {}


func setup(p: Player) -> void:
	player = p
	player.body_parts_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if player == null:
		return
	_damage_reduction = 0.0
	_move_speed_mult = 1.0
	_stamina_regen_mult = 1.0
	_voice_mult = 1.0
	_fall_speed_bonus = 0.0
	_voice_cap = Game.NOISE_VOICE_CAP
	var wanted: Dictionary = {}
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var d := player.get_body_part_def(slot)
		if d == null:
			continue
		_damage_reduction += d.damage_reduction
		_move_speed_mult *= d.move_speed_mult
		_stamina_regen_mult *= d.stamina_regen_mult
		_voice_mult *= d.voice_noise_mult
		if BodyPartDef.is_leg_slot(slot):
			_fall_speed_bonus += d.fall_speed_bonus
		if d.ability_id == &"scanner_pulse":
			_voice_cap = Game.NOISE_VOICE_CAP_SCANNER
		if d.ability_id != &"" and not wanted.has(d.ability_id):
			wanted[d.ability_id] = d
	for id: StringName in _abilities.keys():
		if not wanted.has(id):
			var old: Node = _abilities[id]
			_abilities.erase(id)
			if is_instance_valid(old):
				old.queue_free()
	for id: StringName in wanted.keys():
		if _abilities.has(id):
			continue
		var path := "%s%s.gd" % [ABILITY_DIR, id]
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		var ability := script.new() as ImplantAbility
		if ability == null:
			continue
		ability.name = String(id)
		ability.setup(player, wanted[id])
		add_child(ability)
		_abilities[id] = ability


func damage_mult(source: Game.HitSource) -> float:
	match source:
		Game.HitSource.MONSTER, Game.HitSource.WEAPON, Game.HitSource.EXPLOSION:
			return 1.0 - clampf(_damage_reduction, 0.0, MAX_DAMAGE_REDUCTION)
	return 1.0


func move_speed_mult() -> float:
	return _move_speed_mult


func stamina_regen_mult() -> float:
	return _stamina_regen_mult


func voice_mult() -> float:
	return _voice_mult


func fall_speed_bonus() -> float:
	return _fall_speed_bonus


func voice_cap() -> float:
	return _voice_cap


func hold_offset() -> Vector3:
	return _hold_offset


func set_hold_offset(v: Vector3) -> void:
	_hold_offset = v


func has_ability(id: StringName) -> bool:
	return _abilities.has(id)


func get_ability(id: StringName) -> ImplantAbility:
	return _abilities.get(id) as ImplantAbility


func notify_landed(fall_speed: float) -> void:
	for ability: ImplantAbility in _list():
		ability.on_landed(fall_speed)


func notify_hit(source: Game.HitSource, damage: int) -> void:
	for ability: ImplantAbility in _list():
		ability.on_hit(source, damage)


func notify_exhausted() -> void:
	for ability: ImplantAbility in _list():
		ability.on_exhausted()


func notify_action() -> void:
	for ability: ImplantAbility in _list():
		ability.on_action()


func notify_hold_tick(prop: Prop, delta: float) -> void:
	for ability: ImplantAbility in _list():
		ability.on_hold_tick(prop, delta)


func _list() -> Array:
	return _abilities.values()
