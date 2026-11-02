class_name Loadout
extends Node
## Inventário e armas de um jogador. O servidor decide munição, acertos e itens. O dono
## mantém um espelho do estado e aplica o recuo na hora, pois controla a própria física.

const REVOLVER_DEF: ItemDef = preload("res://resources/items/revolver.tres")
const BATON_DEF: ItemDef = preload("res://resources/items/baton.tres")
const GRENADE_DEF: ItemDef = preload("res://resources/items/grenade.tres")
const AMMO_DEF: ItemDef = preload("res://resources/items/ammo.tres")
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

var has_revolver := false
var has_baton := false
var loaded := 0
var reserve := 0
var grenades := 0
var reloading := false
var equipped := ItemDef.Kind.NONE
var recoil_stack := 0
## Replicado pelo dono, apenas para os outros verem a arma na mão.
var net_equipped := ItemDef.Kind.NONE

var _next_shot_ms := 0
var _last_shot_ms := 0
var _next_melee_ms := 0
var _server_next_shot_ms := 0
var _server_next_melee_ms := 0
var _reload_left := 0.0
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
	return null


func _ready() -> void:
	player.body_parts_changed.connect(_reconcile_equipped)


func _process(delta: float) -> void:
	if net_equipped != _shown:
		_shown = net_equipped
		var def := def_of(_shown)
		_hand.mesh = make_mesh(def) if def else null
	if not multiplayer.is_server() or not reloading:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		var moved := mini(cylinder_size - loaded, reserve)
		loaded += moved
		reserve -= moved
		reloading = false
		_push_state()


func owns(kind: ItemDef.Kind) -> bool:
	match kind:
		ItemDef.Kind.REVOLVER:
			return has_revolver
		ItemDef.Kind.BATON:
			return has_baton
		ItemDef.Kind.GRENADE:
			return grenades > 0
	return false


func can_take(def: ItemDef) -> bool:
	match def.kind:
		ItemDef.Kind.REVOLVER:
			return not has_revolver
		ItemDef.Kind.BATON:
			return not has_baton
		ItemDef.Kind.GRENADE:
			return grenades < max_grenades
		ItemDef.Kind.AMMO:
			return reserve < max_reserve
	return false


func hud_text() -> String:
	var lines := PackedStringArray()
	if has_revolver:
		var status := "recarregando" if reloading else "%d/%d" % [loaded, cylinder_size]
		lines.append("%s[1] %s  %s" % [_mark(ItemDef.Kind.REVOLVER), REVOLVER_DEF.display_name, status])
	if has_revolver or reserve > 0:
		lines.append("%s: %d" % [AMMO_DEF.display_name, reserve])
	if has_baton:
		lines.append("%s[2] %s" % [_mark(ItemDef.Kind.BATON), BATON_DEF.display_name])
	if grenades > 0:
		lines.append("%s[3] %s x%d" % [_mark(ItemDef.Kind.GRENADE), GRENADE_DEF.display_name, grenades])
	return "\n".join(lines)


func _mark(kind: ItemDef.Kind) -> String:
	return "> " if equipped == kind else ""


# --- Dono: entrada do jogador ---


func equip(kind: ItemDef.Kind) -> void:
	equipped = ItemDef.Kind.NONE if kind == equipped or not owns(kind) or not player.can_hold_props() else kind
	net_equipped = equipped
	if equipped != ItemDef.Kind.NONE:
		player.release_grab(false)


func use_primary() -> void:
	# Caído ainda dá para apertar o gatilho, e é assim que a arma escapa da mão.
	if equipped == ItemDef.Kind.REVOLVER:
		_fire()
	if not player.can_act():
		return
	match equipped:
		ItemDef.Kind.BATON:
			_swing()
		ItemDef.Kind.GRENADE:
			_throw(ItemDef.Kind.GRENADE)


func use_secondary() -> void:
	if not player.can_act():
		return
	if equipped == ItemDef.Kind.BATON or equipped == ItemDef.Kind.GRENADE:
		_throw(equipped)


func reload() -> void:
	if has_revolver and not reloading and loaded < cylinder_size and reserve > 0:
		if not multiplayer.is_server():
			reloading = true
		_request_reload.rpc_id(1)


func drop_equipped() -> void:
	if equipped != ItemDef.Kind.NONE:
		_drop(equipped, _aim() * 3.0)


func try_take(item: WorldItem) -> void:
	if item.can_take() and can_take(item.def):
		_request_take.rpc_id(1, String(item.name))


func _aim() -> Vector3:
	return -_head.global_transform.basis.z


func _fire() -> void:
	var now := Time.get_ticks_msec()
	if reloading or loaded <= 0 or now < _next_shot_ms:
		return
	_next_shot_ms = now + int(fire_interval * 1000.0)
	var idle := (now - _last_shot_ms) / 1000.0
	recoil_stack = maxi(recoil_stack - int(idle / recoil_window), 0) + 1
	_last_shot_ms = now
	var direction := _with_spread(_aim(), recoil_spread * recoil_stack)
	if not multiplayer.is_server():
		loaded -= 1
	_request_fire.rpc_id(1, direction)
	_apply_recoil(direction)
	_kick_hand(Vector3(0.0, 0.03, 0.09))
	_play_kick.rpc(Vector3(0.0, 0.03, 0.09))
	if recoil_stack >= fumble_stack:
		_drop(ItemDef.Kind.REVOLVER, -direction * 2.0 + Vector3.UP * 2.0)


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


func _throw(kind: ItemDef.Kind) -> void:
	var direction := _aim()
	if kind == ItemDef.Kind.BATON:
		var flat := Vector3(direction.x, 0.0, direction.z).normalized()
		player.apply_recoil(flat * baton_lurch, baton_lurch_stagger, -0.04, randf_range(-0.12, 0.12))
	_predict_loss(kind)
	_request_throw.rpc_id(1, kind, direction)


func _drop(kind: ItemDef.Kind, toss: Vector3) -> void:
	_predict_loss(kind)
	_request_drop.rpc_id(1, kind, toss)


## No host o estado real já muda dentro da RPC local, então não há o que prever.
func _predict_loss(kind: ItemDef.Kind) -> void:
	if multiplayer.is_server():
		return
	match kind:
		ItemDef.Kind.REVOLVER:
			has_revolver = false
			reloading = false
		ItemDef.Kind.BATON:
			has_baton = false
		ItemDef.Kind.GRENADE:
			grenades -= 1
	_reconcile_equipped()


func _reconcile_equipped() -> void:
	if equipped != ItemDef.Kind.NONE and (not owns(equipped) or not player.can_hold_props()):
		equipped = ItemDef.Kind.NONE
		net_equipped = equipped


func _kick_hand(offset: Vector3) -> void:
	if _hand_tween:
		_hand_tween.kill()
	_hand.position = HAND_REST + offset
	_hand_tween = create_tween()
	_hand_tween.tween_property(_hand, "position", HAND_REST, 0.2).set_ease(Tween.EASE_OUT)


# --- Servidor ---


## Devolve false se o jogador não tem onde guardar o item.
func server_accept(item: WorldItem) -> bool:
	if not can_take(item.def):
		return false
	match item.def.kind:
		ItemDef.Kind.REVOLVER:
			has_revolver = true
			loaded = item.amount
		ItemDef.Kind.BATON:
			has_baton = true
		ItemDef.Kind.GRENADE:
			grenades += 1
		ItemDef.Kind.AMMO:
			reserve = mini(reserve + item.amount, max_reserve)
	_push_state()
	_item_taken.rpc_id(player.peer_id, item.def.kind)
	return true


## Morte e desconexão: tudo que o jogador carregava vai para o chão.
func server_drop_all() -> void:
	var main := get_tree().current_scene as Main
	var center := player.global_position + Vector3.UP * 0.8
	var scatter := func() -> Vector3: return Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	if has_revolver:
		main.spawn_item(REVOLVER_DEF, center, scatter.call(), false, loaded)
	if has_baton:
		main.spawn_item(BATON_DEF, center, scatter.call())
	for i in grenades:
		main.spawn_item(GRENADE_DEF, center, scatter.call())
	if reserve > 0:
		main.spawn_item(AMMO_DEF, center, scatter.call(), false, reserve)
	server_reset()


func server_reset() -> void:
	has_revolver = false
	has_baton = false
	loaded = 0
	reserve = 0
	grenades = 0
	reloading = false
	_push_state()


func _push_state() -> void:
	# Na desconexão o peer já saiu do roster e não pode mais receber a RPC.
	if Net.roster.has(player.peer_id):
		_sync_state.rpc_id(player.peer_id, has_revolver, has_baton, loaded, reserve, grenades, reloading)


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


@rpc("any_peer", "call_local", "reliable")
func _request_fire(direction: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if not _is_valid_use() or not has_revolver or reloading or loaded <= 0:
		return
	if now < _server_next_shot_ms or not direction.is_finite() or direction.is_zero_approx():
		return
	# Margem abaixo do intervalo do cliente, para o jitter da rede não engolir tiros.
	_server_next_shot_ms = now + int(fire_interval * 800.0)
	loaded -= 1
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


@rpc("any_peer", "call_local", "reliable")
func _request_reload() -> void:
	if _is_valid_request() and has_revolver and not reloading and loaded < cylinder_size and reserve > 0:
		reloading = true
		_reload_left = reload_seconds
		_push_state()


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


@rpc("any_peer", "call_local", "reliable")
func _request_throw(kind: int, direction: Vector3) -> void:
	if not _is_valid_use() or not direction.is_finite() or direction.is_zero_approx():
		return
	var aim := direction.normalized()
	var main := get_tree().current_scene as Main
	match kind:
		ItemDef.Kind.BATON when has_baton:
			has_baton = false
			main.spawn_item(BATON_DEF, _hand_point(aim, 0.7), aim * baton_throw_speed, true, 1, player.peer_id)
		ItemDef.Kind.GRENADE when grenades > 0:
			grenades -= 1
			var velocity := (aim + Vector3.UP * grenade_throw_lift) * grenade_throw_speed
			main.spawn_item(GRENADE_DEF, _hand_point(aim, 0.6), velocity, true, 1, player.peer_id)
		_:
			return
	_push_state()


@rpc("any_peer", "call_local", "reliable")
func _request_drop(kind: int, toss: Vector3) -> void:
	if not _is_valid_request() or not toss.is_finite():
		return
	var main := get_tree().current_scene as Main
	var at := _hand_point(_aim(), 0.5)
	var velocity := toss.limit_length(8.0)
	match kind:
		ItemDef.Kind.REVOLVER when has_revolver:
			has_revolver = false
			reloading = false
			main.spawn_item(REVOLVER_DEF, at, velocity, false, loaded)
			loaded = 0
		ItemDef.Kind.BATON when has_baton:
			has_baton = false
			main.spawn_item(BATON_DEF, at, velocity)
		ItemDef.Kind.GRENADE when grenades > 0:
			grenades -= 1
			main.spawn_item(GRENADE_DEF, at, velocity)
		_:
			return
	_push_state()


# --- Respostas do servidor e efeitos remotos ---


@rpc("any_peer", "call_local", "reliable")
func _sync_state(p_revolver: bool, p_baton: bool, p_loaded: int, p_reserve: int, p_grenades: int, p_reloading: bool) -> void:
	if Net.sender_id() != 1:
		return
	has_revolver = p_revolver
	has_baton = p_baton
	loaded = p_loaded
	reserve = p_reserve
	grenades = p_grenades
	reloading = p_reloading
	_reconcile_equipped()


## Item recém-pego vai para a mão, se ela estiver livre.
@rpc("any_peer", "call_local", "reliable")
func _item_taken(kind: int) -> void:
	if Net.sender_id() == 1 and kind != ItemDef.Kind.AMMO and equipped == ItemDef.Kind.NONE and not is_instance_valid(player.held_prop):
		equip(kind as ItemDef.Kind)


@rpc("authority", "call_remote", "unreliable")
func _play_kick(offset: Vector3) -> void:
	_kick_hand(offset)
