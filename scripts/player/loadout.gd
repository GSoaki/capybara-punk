class_name Loadout
extends Node
## Inventário baseado em 5 slots (hudbar) e armas de um jogador.
## O slot 1 começa por padrão com a Lanterna. Armas e pentes de munição ocupam slots.
## Membros (orgânicos ou cibernéticos) são Props físicos (BodyPartDef) e nunca entram no inventário.

const SLOT_COUNT := 5

const REVOLVER_DEF: ItemDef = preload("res://resources/items/revolver.tres")
const BATON_DEF: ItemDef = preload("res://resources/items/baton.tres")
const GRENADE_DEF: ItemDef = preload("res://resources/items/grenade.tres")
const AMMO_DEF: ItemDef = preload("res://resources/items/ammo.tres")
const FLASHLIGHT_DEF: ItemDef = preload("res://resources/items/flashlight.tres")

## Mundo, jogadores, props e monstros. Armas não atingem os itens no chão.
const SHOT_MASK := 23
const MELEE_MASK := 22
const HAND_REST := Vector3(0.26, -0.22, -0.5)

@export_group("Revólver")
@export var cylinder_size := 5
@export var max_reserve := 20
@export var reload_seconds := 1.5
@export var fire_interval := 0.18
@export var shot_range := 60.0
@export var shot_damage := 12
@export var shot_knock := 2.0
@export var shot_stun := 0.2
@export var shot_prop_impulse := 8.0
@export var shot_noise := 0.5
@export_group("Recuo")
## Tiros com menos que este intervalo entre si acumulam. Cada intervalo parado desconta um.
@export var recoil_window := 0.45
@export var recoil_force := 2.5
## Multiplicador por tiro acumulado, somado ao impulso dos tiros anteriores.
@export var recoil_growth := 1.25
@export var recoil_stagger := 0.5
@export var recoil_pitch_kick := 0.045
@export var recoil_yaw_kick := 0.02
## Abertura extra da mira por tiro acumulado, em radianos.
@export var recoil_spread := 0.014
## A partir de quantos tiros acumulados o jogador sai do chão, cai e deixa a arma escapar.
@export var lift_stack := 3
@export var lift_force := 2.0
@export var knockdown_stack := 4
@export var knockdown_seconds := 0.9
@export var fumble_stack := 5
@export_group("Cacetete")
@export var melee_interval := 0.5
@export var melee_reach := 1.1
@export var melee_radius := 0.6
@export var melee_damage := 15
@export var melee_knock := 6.0
@export var melee_stun := 0.6
@export var melee_prop_impulse := 12.0
@export var baton_throw_speed := 16.0
## Empurrão para a frente de quem arremessa: o corpo acompanha o braço.
@export var baton_lurch := 4.5
@export var baton_lurch_stagger := 0.5
@export_group("Granada")
@export var max_grenades := 3
@export var grenade_throw_speed := 11.0
@export var grenade_throw_lift := 0.2

## 5 slots da hudbar: tipo de item e quantidade/munição em cada slot.
var slot_kinds: Array[int] = [ItemDef.Kind.FLASHLIGHT, ItemDef.Kind.NONE, ItemDef.Kind.NONE, ItemDef.Kind.NONE, ItemDef.Kind.NONE]
var slot_amounts: Array[int] = [1, 0, 0, 0, 0]
## Índice do slot selecionado (0..4), ou -1 se estiver com as mãos livres.
var active_slot := -1

var reloading := false
var recoil_stack := 0
## Replicado pelo dono, apenas para os outros verem o item na mão.
var net_equipped := ItemDef.Kind.NONE

# --- Propriedades de compatibilidade e consulta ---

var has_flashlight: bool:
	get:
		return find_slot(ItemDef.Kind.FLASHLIGHT) >= 0

var has_revolver: bool:
	get:
		return find_slot(ItemDef.Kind.REVOLVER) >= 0

var has_baton: bool:
	get:
		return find_slot(ItemDef.Kind.BATON) >= 0

var loaded: int:
	get:
		if active_slot >= 0 and active_slot < SLOT_COUNT and slot_kinds[active_slot] == ItemDef.Kind.REVOLVER:
			return slot_amounts[active_slot]
		var idx := find_slot(ItemDef.Kind.REVOLVER)
		return slot_amounts[idx] if idx >= 0 else 0
	set(v):
		var idx := _revolver_slot()
		if idx >= 0:
			slot_amounts[idx] = clampi(v, 0, cylinder_size)

var reserve: int:
	get:
		var total := 0
		for i in SLOT_COUNT:
			if slot_kinds[i] == ItemDef.Kind.AMMO:
				total += slot_amounts[i]
		return total

var grenades: int:
	get:
		var total := 0
		for i in SLOT_COUNT:
			if slot_kinds[i] == ItemDef.Kind.GRENADE:
				total += maxi(slot_amounts[i], 1)
		return total

var equipped: ItemDef.Kind:
	get:
		if active_slot >= 0 and active_slot < SLOT_COUNT:
			return slot_kinds[active_slot] as ItemDef.Kind
		return ItemDef.Kind.NONE
	set(v):
		if v == ItemDef.Kind.NONE:
			active_slot = -1
			net_equipped = ItemDef.Kind.NONE
		else:
			var idx := find_slot(v)
			active_slot = idx
			net_equipped = (slot_kinds[idx] as ItemDef.Kind) if idx >= 0 else ItemDef.Kind.NONE

var _next_shot_ms := 0
var _last_shot_ms := 0
var _next_melee_ms := 0
var _server_next_shot_ms := 0
var _server_next_melee_ms := 0
var _reload_left := 0.0
var _reload_slot := -1
var _shown := ItemDef.Kind.NONE
var _hand_tween: Tween

@onready var player: Player = get_parent()
@onready var _head: Node3D = $"../Head"
@onready var _hand: MeshInstance3D = $"../Head/Hand"


static func make_mesh(def: ItemDef) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = def.size
	var material := StandardMaterial3D.new()
	material.albedo_color = def.color
	material.emission_enabled = true
	material.emission = def.color
	material.emission_energy_multiplier = 0.4
	mesh.material = material
	return mesh


static func def_of(kind: ItemDef.Kind) -> ItemDef:
	match kind:
		ItemDef.Kind.REVOLVER:
			return REVOLVER_DEF
		ItemDef.Kind.BATON:
			return BATON_DEF
		ItemDef.Kind.GRENADE:
			return GRENADE_DEF
		ItemDef.Kind.AMMO:
			return AMMO_DEF
		ItemDef.Kind.FLASHLIGHT:
			return FLASHLIGHT_DEF
	return null


func _init() -> void:
	_init_default_slots()


func _ready() -> void:
	player.body_parts_changed.connect(_reconcile_equipped)


func _init_default_slots() -> void:
	slot_kinds = [ItemDef.Kind.FLASHLIGHT, ItemDef.Kind.NONE, ItemDef.Kind.NONE, ItemDef.Kind.NONE, ItemDef.Kind.NONE]
	slot_amounts = [1, 0, 0, 0, 0]
	active_slot = -1
	net_equipped = ItemDef.Kind.NONE


func _process(delta: float) -> void:
	if net_equipped != _shown:
		_shown = net_equipped
		var def := def_of(_shown)
		_hand.mesh = make_mesh(def) if def else null
	if not multiplayer.is_server() or not reloading:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		var rev_idx := _reload_slot if (_reload_slot >= 0 and _reload_slot < SLOT_COUNT and slot_kinds[_reload_slot] == ItemDef.Kind.REVOLVER) else _revolver_slot()
		if rev_idx >= 0:
			var needed := cylinder_size - slot_amounts[rev_idx]
			if needed > 0:
				var taken := _consume_ammo_from_slots(needed)
				slot_amounts[rev_idx] += taken
		reloading = false
		_reload_slot = -1
		_push_state()


func find_slot(kind: ItemDef.Kind) -> int:
	for i in SLOT_COUNT:
		if slot_kinds[i] == kind:
			return i
	return -1


func find_empty_slot() -> int:
	for i in SLOT_COUNT:
		if slot_kinds[i] == ItemDef.Kind.NONE:
			return i
	return -1


func _revolver_slot() -> int:
	if active_slot >= 0 and active_slot < SLOT_COUNT and slot_kinds[active_slot] == ItemDef.Kind.REVOLVER:
		return active_slot
	return find_slot(ItemDef.Kind.REVOLVER)


func _consume_ammo_from_slots(needed: int) -> int:
	var rem := needed
	for i in SLOT_COUNT:
		if rem <= 0:
			break
		if slot_kinds[i] == ItemDef.Kind.AMMO:
			var take := mini(rem, slot_amounts[i])
			slot_amounts[i] -= take
			rem -= take
			if slot_amounts[i] <= 0:
				_clear_slot(i)
	return needed - rem


func _clear_slot(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	var was_kind := slot_kinds[index]
	slot_kinds[index] = ItemDef.Kind.NONE
	slot_amounts[index] = 0
	if active_slot == index:
		active_slot = -1
		net_equipped = ItemDef.Kind.NONE
	if was_kind == ItemDef.Kind.FLASHLIGHT and not has_flashlight:
		player.net_flashlight = false


func get_slot_kind(index: int) -> ItemDef.Kind:
	if index < 0 or index >= SLOT_COUNT:
		return ItemDef.Kind.NONE
	return slot_kinds[index] as ItemDef.Kind


func get_slot_amount(index: int) -> int:
	if index < 0 or index >= SLOT_COUNT:
		return 0
	return slot_amounts[index]


func slot_title(index: int) -> String:
	var kind := get_slot_kind(index)
	if kind == ItemDef.Kind.NONE:
		return "Vazio"
	var def := def_of(kind)
	if def == null:
		return "Vazio"
	match kind:
		ItemDef.Kind.AMMO:
			return "Pente"
		ItemDef.Kind.GRENADE:
			return "Granada"
		_:
			return def.display_name


func slot_detail(index: int) -> String:
	var kind := get_slot_kind(index)
	var amt := get_slot_amount(index)
	match kind:
		ItemDef.Kind.FLASHLIGHT:
			return "LIGADA" if player.net_flashlight else "DESL."
		ItemDef.Kind.REVOLVER:
			if reloading and (active_slot == index or _revolver_slot() == index):
				return "Recarreg..."
			return "%d/%d" % [amt, cylinder_size]
		ItemDef.Kind.AMMO:
			return "%d balas" % amt
		ItemDef.Kind.BATON:
			return "Pronto"
		ItemDef.Kind.GRENADE:
			return "x%d" % maxi(amt, 1)
	return ""


func owns(kind: ItemDef.Kind) -> bool:
	return find_slot(kind) >= 0


## Membros (BodyPartDef / PropDef) nunca são aceitos no inventário: apenas ItemDef com slot livre.
func can_store_object(obj: Variant) -> bool:
	if obj is Prop or obj is PropDef or obj is BodyPartDef:
		return false
	if obj is WorldItem:
		return (obj as WorldItem).can_take() and can_take((obj as WorldItem).def)
	if obj is ItemDef:
		return can_take(obj as ItemDef)
	return false


func can_take(def: Resource) -> bool:
	if def == null or def is PropDef or def is BodyPartDef or not (def is ItemDef):
		return false
	var item_def := def as ItemDef
	if item_def.kind == ItemDef.Kind.NONE:
		return false
	if item_def.kind == ItemDef.Kind.FLASHLIGHT and has_flashlight:
		return false
	return find_empty_slot() >= 0


func hud_text() -> String:
	var parts := PackedStringArray()
	for i in SLOT_COUNT:
		var kind := get_slot_kind(i)
		var mark := ">" if active_slot == i else ""
		if kind == ItemDef.Kind.NONE:
			parts.append("%s[%d] ---" % [mark, i + 1])
		else:
			var detail := slot_detail(i)
			var suffix := (" " + detail) if not detail.is_empty() else ""
			parts.append("%s[%d] %s%s" % [mark, i + 1, slot_title(i), suffix])
	return "  |  ".join(parts)


# --- Dono: entrada do jogador ---


func select_slot(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	if active_slot == index or slot_kinds[index] == ItemDef.Kind.NONE or not player.can_hold_props():
		active_slot = -1
		net_equipped = ItemDef.Kind.NONE
		return
	active_slot = index
	net_equipped = slot_kinds[index] as ItemDef.Kind
	player.release_grab(false)


func equip(kind: ItemDef.Kind) -> void:
	if kind == ItemDef.Kind.NONE:
		active_slot = -1
		net_equipped = ItemDef.Kind.NONE
		return
	if equipped == kind:
		active_slot = -1
		net_equipped = ItemDef.Kind.NONE
		return
	var idx := find_slot(kind)
	if idx < 0 or not player.can_hold_props():
		active_slot = -1
		net_equipped = ItemDef.Kind.NONE
		return
	select_slot(idx)


func toggle_flashlight() -> void:
	if has_flashlight and player.alive:
		player.net_flashlight = not player.net_flashlight


func use_primary() -> void:
	# Caído ainda dá para apertar o gatilho, e é assim que a arma escapa da mão.
	if equipped == ItemDef.Kind.REVOLVER:
		_fire()
		return
	if not player.can_act():
		return
	match equipped:
		ItemDef.Kind.FLASHLIGHT:
			toggle_flashlight()
		ItemDef.Kind.BATON:
			_swing()
		ItemDef.Kind.GRENADE:
			_throw_slot(active_slot)
		ItemDef.Kind.AMMO:
			reload()


func use_secondary() -> void:
	if not player.can_act():
		return
	if equipped == ItemDef.Kind.BATON or equipped == ItemDef.Kind.GRENADE:
		_throw_slot(active_slot)


func reload() -> void:
	var rev_idx := _revolver_slot()
	if rev_idx >= 0 and not reloading and slot_amounts[rev_idx] < cylinder_size and reserve > 0:
		if not multiplayer.is_server():
			reloading = true
		_request_reload.rpc_id(1, rev_idx)


func drop_equipped() -> void:
	if active_slot >= 0 and active_slot < SLOT_COUNT and slot_kinds[active_slot] != ItemDef.Kind.NONE:
		_drop_slot(active_slot, _aim() * 3.0)


func try_take(item: WorldItem) -> void:
	if item and item.can_take() and can_take(item.def):
		_request_take.rpc_id(1, String(item.name))


func _aim() -> Vector3:
	return -_head.global_transform.basis.z


func _fire() -> void:
	var rev_idx := _revolver_slot()
	var now := Time.get_ticks_msec()
	if rev_idx < 0 or reloading or slot_amounts[rev_idx] <= 0 or now < _next_shot_ms:
		return
	_next_shot_ms = now + int(fire_interval * 1000.0)
	var idle := (now - _last_shot_ms) / 1000.0
	recoil_stack = maxi(recoil_stack - int(idle / recoil_window), 0) + 1
	_last_shot_ms = now
	var direction := _with_spread(_aim(), recoil_spread * recoil_stack)
	if not multiplayer.is_server():
		slot_amounts[rev_idx] -= 1
	_request_fire.rpc_id(1, direction, rev_idx)
	_apply_recoil(direction)
	_kick_hand(Vector3(0.0, 0.03, 0.09))
	_play_kick.rpc(Vector3(0.0, 0.03, 0.09))
	if recoil_stack >= fumble_stack:
		_drop_slot(rev_idx, -direction * 2.0 + Vector3.UP * 2.0)


## O impulso entra direto na velocidade atual, então tiros seguidos se somam.
func _apply_recoil(direction: Vector3) -> void:
	var impulse := -direction * recoil_force * pow(recoil_growth, recoil_stack - 1)
	if recoil_stack >= lift_stack:
		impulse.y += lift_force
	var pitch := recoil_pitch_kick * recoil_stack
	var yaw := randf_range(-1.0, 1.0) * recoil_yaw_kick * recoil_stack
	player.apply_recoil(impulse, recoil_stagger + 0.1 * recoil_stack, pitch, yaw)
	if recoil_stack >= knockdown_stack:
		player.knock_down(knockdown_seconds)


func _with_spread(direction: Vector3, angle: float) -> Vector3:
	var side := direction.cross(Vector3.UP)
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var tilted := direction.rotated(side.normalized(), randf() * angle)
	return tilted.rotated(direction, randf() * TAU).normalized()


func _swing() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_melee_ms:
		return
	_next_melee_ms = now + int(melee_interval * 1000.0)
	_request_melee.rpc_id(1, _aim())
	_kick_hand(Vector3(-0.12, 0.04, -0.3))
	_play_kick.rpc(Vector3(-0.12, 0.04, -0.3))


func _throw_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	var kind := slot_kinds[slot_idx] as ItemDef.Kind
	var direction := _aim()
	if kind == ItemDef.Kind.BATON:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		player.apply_recoil(flat * baton_lurch, baton_lurch_stagger, -0.04, randf_range(-0.12, 0.12))
	_predict_slot_loss(slot_idx)
	_request_throw.rpc_id(1, slot_idx, direction)


func _drop_slot(slot_idx: int, toss: Vector3) -> void:
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	_predict_slot_loss(slot_idx)
	_request_drop.rpc_id(1, slot_idx, toss)


## No host o estado real já muda dentro da RPC local, então não há o que prever.
func _predict_slot_loss(slot_idx: int) -> void:
	if multiplayer.is_server():
		return
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	if slot_kinds[slot_idx] == ItemDef.Kind.REVOLVER:
		reloading = false
	_clear_slot(slot_idx)
	_reconcile_equipped()


func _reconcile_equipped() -> void:
	if active_slot >= 0 and (active_slot >= SLOT_COUNT or slot_kinds[active_slot] == ItemDef.Kind.NONE or not player.can_hold_props()):
		active_slot = -1
		net_equipped = ItemDef.Kind.NONE
	elif active_slot >= 0:
		net_equipped = slot_kinds[active_slot] as ItemDef.Kind


func _kick_hand(offset: Vector3) -> void:
	if _hand_tween:
		_hand_tween.kill()
	_hand.position = HAND_REST + offset
	_hand_tween = create_tween()
	_hand_tween.tween_property(_hand, "position", HAND_REST, 0.2).set_ease(Tween.EASE_OUT)


# --- Servidor ---


## Devolve false se o jogador não tem um slot vazio para guardar o item.
func server_accept(item: WorldItem) -> bool:
	if not item or not can_take(item.def):
		return false
	var empty_idx := find_empty_slot()
	if empty_idx < 0:
		return false
	slot_kinds[empty_idx] = item.def.kind
	match item.def.kind:
		ItemDef.Kind.REVOLVER:
			slot_amounts[empty_idx] = clampi(item.amount, 0, cylinder_size)
		ItemDef.Kind.AMMO:
			slot_amounts[empty_idx] = maxi(item.amount, 1)
		_:
			slot_amounts[empty_idx] = 1
	_push_state()
	_item_taken.rpc_id(player.peer_id, empty_idx, item.def.kind)
	return true


## Morte e desconexão: tudo que o jogador carregava vai para o chão (exceto a lanterna padrão, que é restaurada no reset).
func server_drop_all() -> void:
	var main := get_tree().current_scene as Main
	var center := player.global_position + Vector3.UP * 0.8
	var scatter := func() -> Vector3: return Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	for i in SLOT_COUNT:
		var kind := slot_kinds[i] as ItemDef.Kind
		var amt := slot_amounts[i]
		match kind:
			ItemDef.Kind.REVOLVER:
				main.spawn_item(REVOLVER_DEF, center, scatter.call(), false, amt)
			ItemDef.Kind.BATON:
				main.spawn_item(BATON_DEF, center, scatter.call())
			ItemDef.Kind.GRENADE:
				main.spawn_item(GRENADE_DEF, center, scatter.call())
			ItemDef.Kind.AMMO:
				if amt > 0:
					main.spawn_item(AMMO_DEF, center, scatter.call(), false, amt)
	server_reset()


func server_reset() -> void:
	_init_default_slots()
	reloading = false
	_reload_slot = -1
	player.net_flashlight = false
	_push_state()


func _push_state() -> void:
	# Na desconexão o peer já saiu do roster e não pode mais receber a RPC.
	if Net.roster.has(player.peer_id):
		_sync_state.rpc_id(player.peer_id, slot_kinds.duplicate(), slot_amounts.duplicate(), reloading)


func _is_valid_request() -> bool:
	return multiplayer.is_server() and Net.sender_id() == player.peer_id and player.alive


## Usar uma arma exige ao menos um braço; pegar e largar, não.
func _is_valid_use() -> bool:
	return _is_valid_request() and player.can_hold_props()


## Ponto à frente da mão, recuado se houver parede, para o item não nascer do outro lado dela.
func _hand_point(direction: Vector3, reach: float) -> Vector3:
	var from := _head.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * reach, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return from + direction * reach
	return from + direction * maxf(from.distance_to(hit.position) - 0.2, 0.0)


func _strike(target: Object, direction: Vector3, damage: int, knock: float, stun: float, prop_impulse: float) -> void:
	if target is Prop:
		target.sleeping = false
		target.apply_central_impulse(direction * prop_impulse)
	elif target.has_method("server_hit"):
		target.server_hit(damage, direction * knock + Vector3.UP, stun)


## Cliente dono -> Servidor: solicita coletar um WorldItem do chão para um slot livre.
@rpc("any_peer", "call_local", "reliable")
func _request_take(item_name: String) -> void:
	if not _is_valid_request():
		return
	var main := get_tree().current_scene as Main
	var item := main.items.get_node_or_null(item_name) as WorldItem
	if not item or not item.can_take() or item.is_queued_for_deletion():
		return
	if player.global_position.distance_to(item.global_position) <= WorldItem.TAKE_RANGE and server_accept(item):
		item.queue_free()


## Cliente dono -> Servidor: valida munição e cadência e dispara raycast hitscan do revólver.
@rpc("any_peer", "call_local", "reliable")
func _request_fire(direction: Vector3, slot_idx: int = -1) -> void:
	var now := Time.get_ticks_msec()
	var rev_idx := slot_idx if (slot_idx >= 0 and slot_idx < SLOT_COUNT and slot_kinds[slot_idx] == ItemDef.Kind.REVOLVER) else _revolver_slot()
	if not _is_valid_use() or rev_idx < 0 or reloading or slot_amounts[rev_idx] <= 0:
		return
	if now < _server_next_shot_ms or not direction.is_finite() or direction.is_zero_approx():
		return
	# Margem abaixo do intervalo do cliente, para o jitter da rede não engolir tiros.
	_server_next_shot_ms = now + int(fire_interval * 800.0)
	slot_amounts[rev_idx] -= 1
	_push_state()
	var aim := direction.normalized()
	var from := _head.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + aim * shot_range, SHOT_MASK, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = hit.position if not hit.is_empty() else from + aim * shot_range
	var hit_entity := false
	if not hit.is_empty():
		hit_entity = hit.collider.has_method("server_hit")
		_strike(hit.collider, aim, shot_damage, shot_knock, shot_stun, shot_prop_impulse)
	Game.emit_noise(from, shot_noise)
	(get_tree().current_scene as Main).weapon_fx.shot.rpc(from + aim * 0.5, end, hit_entity)


## Cliente dono -> Servidor: inicia o timer de recarga do revólver consumindo balas dos slots AMMO ao concluir.
@rpc("any_peer", "call_local", "reliable")
func _request_reload(slot_idx: int = -1) -> void:
	var rev_idx := slot_idx if (slot_idx >= 0 and slot_idx < SLOT_COUNT and slot_kinds[slot_idx] == ItemDef.Kind.REVOLVER) else _revolver_slot()
	if _is_valid_request() and rev_idx >= 0 and not reloading and slot_amounts[rev_idx] < cylinder_size and reserve > 0:
		reloading = true
		_reload_slot = rev_idx
		_reload_left = reload_seconds
		_push_state()


## Cliente dono -> Servidor: executa golpe corpo a corpo com o cacetete usando SphereShape3D + checagem de visada.
@rpc("any_peer", "call_local", "reliable")
func _request_melee(direction: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if not _is_valid_use() or not has_baton or now < _server_next_melee_ms:
		return
	if not direction.is_finite() or direction.is_zero_approx():
		return
	_server_next_melee_ms = now + int(melee_interval * 800.0)
	var aim := direction.normalized()
	var from := _head.global_position
	var sphere := SphereShape3D.new()
	sphere.radius = melee_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, from + aim * melee_reach)
	query.collision_mask = MELEE_MASK
	query.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	var best: Object = null
	var best_distance := INF
	for result: Dictionary in space.intersect_shape(query, 8):
		var body := result.collider as Node3D
		var distance := from.distance_to(body.global_position)
		# Só o mundo bloqueia a visão; a esfera sozinha atravessaria paredes finas.
		var sight := PhysicsRayQueryParameters3D.create(from, body.global_position + Vector3.UP * 0.5, 1)
		if distance < best_distance and space.intersect_ray(sight).is_empty():
			best = body
			best_distance = distance
	if best:
		_strike(best, aim, melee_damage, melee_knock, melee_stun, melee_prop_impulse)
		Game.emit_noise(from, 0.1)


## Cliente dono -> Servidor: consome o slot e instancia cacetete ou granada como projétil ativo (net_active = true).
@rpc("any_peer", "call_local", "reliable")
func _request_throw(slot_idx: int, direction: Vector3) -> void:
	if not _is_valid_use() or not direction.is_finite() or direction.is_zero_approx():
		return
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	var kind := slot_kinds[slot_idx] as ItemDef.Kind
	var aim := direction.normalized()
	var main := get_tree().current_scene as Main
	match kind:
		ItemDef.Kind.BATON:
			_clear_slot(slot_idx)
			main.spawn_item(BATON_DEF, _hand_point(aim, 0.7), aim * baton_throw_speed, true, 1, player.peer_id)
		ItemDef.Kind.GRENADE:
			_clear_slot(slot_idx)
			var velocity := (aim + Vector3.UP * grenade_throw_lift) * grenade_throw_speed
			main.spawn_item(GRENADE_DEF, _hand_point(aim, 0.6), velocity, true, 1, player.peer_id)
		_:
			return
	_push_state()


## Cliente dono -> Servidor: larga o item do slot no chão como WorldItem inativo (net_active = false).
@rpc("any_peer", "call_local", "reliable")
func _request_drop(slot_idx: int, toss: Vector3) -> void:
	if not _is_valid_request() or not toss.is_finite():
		return
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	var kind := slot_kinds[slot_idx] as ItemDef.Kind
	var amt := slot_amounts[slot_idx]
	if kind == ItemDef.Kind.NONE:
		return
	var main := get_tree().current_scene as Main
	var at := _hand_point(_aim(), 0.5)
	var velocity := toss.limit_length(8.0)
	match kind:
		ItemDef.Kind.REVOLVER:
			reloading = false
			_clear_slot(slot_idx)
			main.spawn_item(REVOLVER_DEF, at, velocity, false, amt)
		ItemDef.Kind.BATON:
			_clear_slot(slot_idx)
			main.spawn_item(BATON_DEF, at, velocity)
		ItemDef.Kind.GRENADE:
			_clear_slot(slot_idx)
			main.spawn_item(GRENADE_DEF, at, velocity)
		ItemDef.Kind.AMMO:
			_clear_slot(slot_idx)
			main.spawn_item(AMMO_DEF, at, velocity, false, maxi(amt, 1))
		ItemDef.Kind.FLASHLIGHT:
			_clear_slot(slot_idx)
			main.spawn_item(FLASHLIGHT_DEF, at, velocity)
		_:
			return
	_push_state()


# --- Respostas do servidor e efeitos remotos ---


## Servidor -> Cliente dono: sincroniza tipos, quantidades e estado de recarga dos 5 slots.
@rpc("any_peer", "call_local", "reliable")
func _sync_state(p_kinds: Array, p_amounts: Array, p_reloading: bool) -> void:
	if Net.sender_id() != 1:
		return
	for i in SLOT_COUNT:
		slot_kinds[i] = int(p_kinds[i]) if i < p_kinds.size() else int(ItemDef.Kind.NONE)
		slot_amounts[i] = int(p_amounts[i]) if i < p_amounts.size() else 0
	reloading = p_reloading
	if not has_flashlight:
		player.net_flashlight = false
	_reconcile_equipped()


## Item recém-pego vai para a mão, se ela estiver livre (exceto pente de munição).
@rpc("any_peer", "call_local", "reliable")
func _item_taken(slot_idx: int, kind: int) -> void:
	if Net.sender_id() == 1 and kind != ItemDef.Kind.AMMO and active_slot < 0 and not is_instance_valid(player.held_prop):
		select_slot(slot_idx)


@rpc("authority", "call_remote", "unreliable")
func _play_kick(offset: Vector3) -> void:
	_kick_hand(offset)
