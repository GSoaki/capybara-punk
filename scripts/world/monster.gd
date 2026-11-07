class_name Monster
extends CharacterBody3D
## Inimigo simulado no servidor com corpo modular esquelético (6 membros + ragdoll).
## Persegue quem vê e investiga barulho, inclusive voz: quanto mais alto o jogador fala,
## de mais longe o monstro escuta.

signal body_parts_changed

enum State { ROAM, INVESTIGATE, CHASE }

const PlayerRigScript := preload("res://scripts/player/player_rig.gd")
const BODY_INTERACT_RANGE := 3.8
const RAGDOLL_MIN_STUN := 0.5
const BASE_COLOR := Color(0.32, 0.08, 0.1, 1.0)

const DEFAULT_BODY_PARTS: Dictionary = {
	BodyPartDef.Slot.HEAD: "res://resources/body_parts/organic_head.tres",
	BodyPartDef.Slot.TORSO: "res://resources/body_parts/organic_torso.tres",
	BodyPartDef.Slot.LEFT_ARM: "res://resources/body_parts/cyber_left_arm.tres",
	BodyPartDef.Slot.RIGHT_ARM: "res://resources/body_parts/organic_right_arm.tres",
	BodyPartDef.Slot.LEFT_LEG: "res://resources/body_parts/organic_left_leg.tres",
	BodyPartDef.Slot.RIGHT_LEG: "res://resources/body_parts/cyber_right_leg.tres",
}

const DETACH_PRIORITY: Array[BodyPartDef.Slot] = [
	BodyPartDef.Slot.LEFT_ARM,
	BodyPartDef.Slot.RIGHT_ARM,
	BodyPartDef.Slot.LEFT_LEG,
	BodyPartDef.Slot.RIGHT_LEG,
	BodyPartDef.Slot.HEAD,
	BodyPartDef.Slot.TORSO,
]

@export var roam_speed := 2.2
@export var investigate_speed := 3.5
@export var chase_speed := 5.2
@export var vision_range := 14.0
@export var hearing_gain := 180.0
@export var max_hearing_range := 28.0
@export var attack_range := 1.7
@export var attack_damage := 34
@export var attack_cooldown := 1.5
@export var knock_force := 9.0
@export var max_health := 100
## Desaceleração enquanto atordoado, em m/s².
@export var stun_drag := 7.0

## Usado por PlayerRig para escalonar a animação de corrida.
var sprint_speed: float:
	get:
		return chase_speed

var state := State.ROAM
var health := 0
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_stunned := false
var net_chasing := false
var net_attacking := false

## Slot (int) -> resource_path (String) do BodyPartDef instalado, ou "" se removido.
var body_parts: Dictionary = {}
## Slot (int) -> valor em $ preservado da parte instalada (usado no servidor).
var body_part_values: Dictionary = {}

var _target_player: Player
var _state_timer := 0.0
var _attack_timer := 0.0
var _stun_timer := 0.0
var _last_knock_impulse := Vector3.ZERO
var _part_cache: Dictionary = {}

@onready var agent: NavigationAgent3D = $Agent
@onready var visuals: Node3D = $Visuals
@onready var rig: PlayerRigScript = $Visuals/Rig

@onready var _slot_meshes: Dictionary = {
	BodyPartDef.Slot.HEAD: $Visuals/HeadMesh,
	BodyPartDef.Slot.TORSO: $Visuals/Torso,
	BodyPartDef.Slot.LEFT_ARM: $Visuals/LeftArm,
	BodyPartDef.Slot.RIGHT_ARM: $Visuals/RightArm,
	BodyPartDef.Slot.LEFT_LEG: $Visuals/LeftLeg,
	BodyPartDef.Slot.RIGHT_LEG: $Visuals/RightLeg,
}


func _enter_tree() -> void:
	_init_default_body_parts()


func setup(data: Dictionary) -> void:
	name = data.name
	position = data.pos
	net_position = data.pos


func _ready() -> void:
	health = max_health
	rig.setup_rig(_slot_meshes, get_rid())
	_refresh_body_visuals()
	Net.player_joined.connect(_on_peer_joined)
	if multiplayer.is_server():
		Game.noise_emitted.connect(_on_noise)
	else:
		collision_mask = 0


func _on_peer_joined(joined_peer_id: int) -> void:
	if multiplayer.is_server() and joined_peer_id != 1:
		_sync_body_parts.rpc_id(joined_peer_id, body_parts)


func _init_default_body_parts() -> void:
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var path: String = DEFAULT_BODY_PARTS[slot]
		body_parts[slot] = path
		var def := _load_part_def(path)
		if def:
			body_part_values[slot] = int((def.min_value + def.max_value) * 0.5)


func _load_part_def(path: String) -> BodyPartDef:
	if path.is_empty():
		return null
	if not _part_cache.has(path):
		_part_cache[path] = load(path) as BodyPartDef
	return _part_cache[path] as BodyPartDef


func has_body_part(slot: BodyPartDef.Slot) -> bool:
	return not String(body_parts.get(slot, "")).is_empty()


func get_body_part_def(slot: BodyPartDef.Slot) -> BodyPartDef:
	return _load_part_def(String(body_parts.get(slot, "")))


func get_arm_count() -> int:
	var count := 0
	if has_body_part(BodyPartDef.Slot.LEFT_ARM):
		count += 1
	if has_body_part(BodyPartDef.Slot.RIGHT_ARM):
		count += 1
	return count


func get_leg_count() -> int:
	var count := 0
	if has_body_part(BodyPartDef.Slot.LEFT_LEG):
		count += 1
	if has_body_part(BodyPartDef.Slot.RIGHT_LEG):
		count += 1
	return count


func has_vital_parts() -> bool:
	return has_body_part(BodyPartDef.Slot.HEAD) and has_body_part(BodyPartDef.Slot.TORSO)


func get_leg_speed_multiplier() -> float:
	if get_leg_count() == 0:
		return 0.28
	var count := get_leg_count()
	if count == 1:
		return 0.58
	return 1.0


func resolve_install_slot(part_def: BodyPartDef) -> BodyPartDef.Slot:
	if part_def == null:
		return BodyPartDef.Slot.LEFT_ARM
	var primary := part_def.slot
	var paired_idx := BodyPartDef.pair_slot(primary)
	if paired_idx < 0:
		return primary
	var paired := paired_idx as BodyPartDef.Slot
	if not has_body_part(primary):
		return primary
	if not has_body_part(paired):
		return paired
	var primary_def := get_body_part_def(primary)
	var paired_def := get_body_part_def(paired)
	if part_def.is_cybernetic:
		if primary_def and not primary_def.is_cybernetic:
			return primary
		if paired_def and not paired_def.is_cybernetic:
			return paired
	return primary


func get_aimed_slot(world_hit_point: Vector3) -> BodyPartDef.Slot:
	var local_hit := to_local(world_hit_point)
	var leg_offset := 0.55 if get_leg_count() == 0 else 0.0
	var y := (local_hit.y + leg_offset) / 1.18
	if y >= 1.36:
		return BodyPartDef.Slot.HEAD
	if y < 0.72:
		return BodyPartDef.Slot.LEFT_LEG if local_hit.x < 0.0 else BodyPartDef.Slot.RIGHT_LEG
	if local_hit.x < -0.14:
		return BodyPartDef.Slot.LEFT_ARM
	if local_hit.x > 0.14:
		return BodyPartDef.Slot.RIGHT_ARM
	return BodyPartDef.Slot.TORSO


func get_removable_slot_at(world_hit_point: Vector3) -> int:
	var aimed := get_aimed_slot(world_hit_point)
	if has_body_part(aimed):
		return aimed
	for slot: BodyPartDef.Slot in DETACH_PRIORITY:
		if has_body_part(slot):
			return slot
	return -1


func _refresh_body_visuals() -> void:
	if _slot_meshes.is_empty():
		return
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var mesh_node := _slot_meshes.get(slot) as MeshInstance3D
		if mesh_node == null:
			continue
		var def := get_body_part_def(slot)
		if def == null:
			mesh_node.visible = false
			continue
		mesh_node.visible = true
		var mat := StandardMaterial3D.new()
		if def.is_cybernetic:
			mat.albedo_color = def.color.darkened(0.15)
			mat.metallic = 0.8
			mat.roughness = 0.22
		else:
			mat.albedo_color = BASE_COLOR
			mat.metallic = 0.3
			mat.roughness = 0.55
		mesh_node.material_override = mat
	visuals.position.y = -0.55 if get_leg_count() == 0 else 0.0
	if is_instance_valid(rig):
		rig.refresh_active_parts(self)


func _process(delta: float) -> void:
	if not is_instance_valid(rig):
		return
	var want_ragdoll := net_stunned or health <= 0
	if want_ragdoll and not rig.is_ragdoll:
		rig.start_ragdoll(self, _last_knock_impulse)
	elif not want_ragdoll and rig.is_ragdoll:
		rig.stop_ragdoll()
	if not rig.is_ragdoll:
		var no_legs := get_leg_count() == 0
		var pitch := -0.25 if net_attacking else 0.0
		rig.update_pose(delta, self, no_legs, net_chasing, net_attacking, pitch, 0.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		var weight := 1.0 - exp(-12.0 * delta)
		position = position.lerp(net_position, weight)
		rotation.y = lerp_angle(rotation.y, net_yaw, weight)
		return
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	if _stun_timer > 0.0:
		_stun_timer -= delta
		_move_stunned(delta)
	else:
		_state_timer -= delta
		_think()
		_move(delta)
		_try_attack()
	net_position = position
	net_yaw = rotation.y
	net_stunned = _stun_timer >= RAGDOLL_MIN_STUN
	net_chasing = state == State.CHASE
	net_attacking = _attack_timer > (attack_cooldown - 0.35)


func _think() -> void:
	var seen := _find_visible_player()
	if seen:
		_target_player = seen
		state = State.CHASE
		_state_timer = 3.0
		agent.target_position = seen.global_position
		return
	if state == State.CHASE and is_instance_valid(_target_player) and _target_player.alive and _state_timer > 0.0:
		agent.target_position = _target_player.global_position
		return
	if state == State.CHASE or (state == State.INVESTIGATE and (_state_timer <= 0.0 or agent.is_navigation_finished())):
		state = State.ROAM
		_state_timer = 0.0
	if state == State.ROAM and (_state_timer <= 0.0 or agent.is_navigation_finished()):
		var map := agent.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			agent.target_position = NavigationServer3D.map_get_random_point(map, agent.navigation_layers, false)
			_state_timer = 12.0


func _move(delta: float) -> void:
	var speed := roam_speed
	if state == State.INVESTIGATE:
		speed = investigate_speed
	elif state == State.CHASE:
		speed = chase_speed
	speed *= get_leg_speed_multiplier()
	var horizontal := Vector3.ZERO
	if not agent.is_navigation_finished():
		var to_next := agent.get_next_path_position() - global_position
		to_next.y = 0.0
		if to_next.length_squared() > 0.001:
			horizontal = to_next.normalized() * speed
			rotation.y = lerp_angle(rotation.y, atan2(-horizontal.x, -horizontal.z), 1.0 - exp(-8.0 * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y + get_gravity().y * delta
	move_and_slide()


func _move_stunned(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, stun_drag * delta)
	velocity.z = move_toward(velocity.z, 0.0, stun_drag * delta)
	velocity.y += get_gravity().y * delta
	move_and_slide()


## Servidor: remove um membro do inimigo e o transforma em um Prop físico no mundo.
func server_detach_part(slot: BodyPartDef.Slot, drop_pos: Vector3 = Vector3.INF) -> Prop:
	if not multiplayer.is_server():
		return null
	var def := get_body_part_def(slot)
	if def == null:
		return null
	var saved_value: int = int(body_part_values.get(slot, -1))
	body_parts[slot] = ""
	body_part_values.erase(slot)
	_sync_body_parts.rpc(body_parts)
	var main := get_tree().current_scene
	var spawned: Prop = null
	if main and main.has_method("spawn_prop"):
		var spawn_at := drop_pos
		if not spawn_at.is_finite():
			var forward := -global_transform.basis.z
			if forward.length_squared() < 0.01:
				forward = Vector3.FORWARD
			spawn_at = global_position + Vector3.UP * 1.15 + forward.normalized() * 0.9
		spawned = main.spawn_prop(def, spawn_at, "", saved_value)
	if def.vital and health > 0:
		health = 0
		queue_free()
	return spawned


## Servidor: instala um BodyPartDef no inimigo.
func server_install_part(def: BodyPartDef, custom_value: int = -1, explicit_slot: int = -1) -> Prop:
	if not multiplayer.is_server() or def == null:
		return null
	var target_slot := (explicit_slot as BodyPartDef.Slot) if (explicit_slot >= 0 and explicit_slot < BodyPartDef.ALL_SLOTS.size()) else resolve_install_slot(def)
	var ejected: Prop = null
	if has_body_part(target_slot):
		ejected = server_detach_part(target_slot)
	body_parts[target_slot] = def.resource_path
	body_part_values[target_slot] = custom_value if custom_value >= 0 else int((def.min_value + def.max_value) * 0.5)
	_sync_body_parts.rpc(body_parts)
	return ejected


func server_attach_part_from_prop(prop: Prop, explicit_slot: int = -1) -> bool:
	if not multiplayer.is_server() or not is_instance_valid(prop):
		return false
	var part_def := prop.def as BodyPartDef
	if part_def == null:
		return false
	var target_slot := (explicit_slot as BodyPartDef.Slot) if (explicit_slot >= 0 and explicit_slot < BodyPartDef.ALL_SLOTS.size()) else resolve_install_slot(part_def)
	var part_value := prop.net_value
	var drop_origin := prop.global_position + Vector3.UP * 0.25
	for holder_id: int in prop.holders.keys():
		var holder := prop.holders[holder_id] as Player
		if is_instance_valid(holder):
			holder.grab_lost.rpc_id(holder_id)
	prop.holders.clear()
	prop.queue_free()
	if has_body_part(target_slot):
		server_detach_part(target_slot, drop_origin)
	body_parts[target_slot] = part_def.resource_path
	body_part_values[target_slot] = part_value
	_sync_body_parts.rpc(body_parts)
	return true


## Cliente -> Servidor: solicita destacar um membro do monstro a até BODY_INTERACT_RANGE.
@rpc("any_peer", "call_local", "reliable")
func request_detach_part(slot: int) -> void:
	if not multiplayer.is_server():
		return
	if slot < 0 or slot >= BodyPartDef.ALL_SLOTS.size():
		return
	var caller := Game.players.get(Net.sender_id()) as Player
	if caller == null or not caller.alive:
		return
	if caller.global_position.distance_to(global_position) > BODY_INTERACT_RANGE:
		return
	server_detach_part(slot as BodyPartDef.Slot)


## Cliente -> Servidor: solicita instalar um Prop de membro do mundo neste monstro.
@rpc("any_peer", "call_local", "reliable")
func request_attach_part_from_prop(prop_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var caller := Game.players.get(Net.sender_id()) as Player
	if caller == null or not caller.alive:
		return
	if caller.global_position.distance_to(global_position) > BODY_INTERACT_RANGE:
		return
	var prop := get_node_or_null(prop_path) as Prop
	if prop == null or prop.global_position.distance_to(caller.global_position) > Prop.BREAK_RANGE:
		return
	server_attach_part_from_prop(prop)


## Servidor -> Todos os peers: sincroniza os membros instalados no monstro e atualiza malhas/rig.
@rpc("any_peer", "call_local", "reliable")
func _sync_body_parts(new_parts: Dictionary) -> void:
	if Net.sender_id() != 1:
		return
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		if new_parts.has(slot):
			body_parts[slot] = String(new_parts[slot])
		elif new_parts.has(int(slot)):
			body_parts[slot] = String(new_parts[int(slot)])
		else:
			body_parts[slot] = ""
	_refresh_body_visuals()
	body_parts_changed.emit()


## Servidor. Mesma assinatura de Player.server_hit, para as armas tratarem os dois igual.
func server_hit(damage: int, knock: Vector3, stun := 1.5) -> void:
	if not multiplayer.is_server() or health <= 0:
		return
	health = maxi(health - damage, 0)
	if health == 0:
		queue_free()
		return
	velocity = knock
	_last_knock_impulse = knock
	_stun_timer = maxf(_stun_timer, stun)
	if stun >= RAGDOLL_MIN_STUN and is_instance_valid(rig):
		rig.start_ragdoll(self, knock)


func _find_visible_player() -> Player:
	var best: Player = null
	var best_distance := vision_range
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * (0.7 if get_leg_count() == 0 else 1.7)
	for player: Player in Game.players.values():
		if not player.alive:
			continue
		var distance := eye.distance_to(player.global_position)
		if distance >= best_distance:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, player.global_position + Vector3.UP * 1.2, 1)
		if space.intersect_ray(query).is_empty():
			best = player
			best_distance = distance
	return best


func _try_attack() -> void:
	if _attack_timer > 0.0:
		return
	var arms := get_arm_count()
	var dmg_scale := 0.35 if arms == 0 else (0.7 if arms == 1 else 1.0)
	var dmg := maxi(roundi(attack_damage * dmg_scale), 5)
	for player: Player in Game.players.values():
		if player.alive and global_position.distance_to(player.global_position) <= attack_range:
			_attack_timer = attack_cooldown
			var away := (player.global_position - global_position).normalized()
			player.server_hit(dmg, away * knock_force + Vector3.UP * 3.0)
			return


func _on_noise(origin: Vector3, loudness: float) -> void:
	if state == State.CHASE:
		return
	var radius := minf(loudness * hearing_gain, max_hearing_range)
	if global_position.distance_to(origin) <= radius:
		state = State.INVESTIGATE
		_state_timer = 8.0
		agent.target_position = origin
