class_name Player
extends CharacterBody3D
## Controlador em primeira pessoa com autoridade do próprio cliente: movimento sem
## atraso e sem predição. Vida, morte e modularidade física do corpo são decididas pelo servidor.

signal body_parts_changed

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const CRAWL_HEIGHT := 0.8
const STAND_EYES := 1.6
const CROUCH_EYES := 0.95
const CRAWL_EYES := 0.55
const KILL_PLANE_Y := -25.0
const SAFE_FALL_SPEED := 11.0
const FALL_DAMAGE_PER_MS := 12.0
const PUSH_STRENGTH := 2.5
const SPRINT_NOISE := 0.06
const BODY_INTERACT_RANGE := 3.8
const THIRD_PERSON_OFFSET := Vector3(0.4, 0.3, 2.6)
const PlayerRigScript := preload("res://scripts/player/player_rig.gd")
## O primeiro movimento após capturar o mouse traz o salto do cursor até o centro da janela.
const MOUSE_SETTLE_SECONDS := 0.1
## Abaixo disto, um golpe só desequilibra, sem derrubar o corpo em ragdoll.
const RAGDOLL_MIN_STUN := 0.5

const DEFAULT_BODY_PARTS: Dictionary = {
	BodyPartDef.Slot.HEAD: "res://resources/body_parts/organic_head.tres",
	BodyPartDef.Slot.TORSO: "res://resources/body_parts/organic_torso.tres",
	BodyPartDef.Slot.LEFT_ARM: "res://resources/body_parts/organic_left_arm.tres",
	BodyPartDef.Slot.RIGHT_ARM: "res://resources/body_parts/organic_right_arm.tres",
	BodyPartDef.Slot.LEFT_LEG: "res://resources/body_parts/organic_left_leg.tres",
	BodyPartDef.Slot.RIGHT_LEG: "res://resources/body_parts/organic_right_leg.tres",
}

const DETACH_PRIORITY: Array[BodyPartDef.Slot] = [
	BodyPartDef.Slot.LEFT_ARM,
	BodyPartDef.Slot.RIGHT_ARM,
	BodyPartDef.Slot.LEFT_LEG,
	BodyPartDef.Slot.RIGHT_LEG,
	BodyPartDef.Slot.HEAD,
	BodyPartDef.Slot.TORSO,
]

@export var walk_speed := 4.5
@export var sprint_speed := 7.0
@export var crouch_speed := 2.2
@export var jump_velocity := 4.6
@export var acceleration := 40.0
@export var stamina_drain := 25.0
@export var stamina_regen := 18.0

var peer_id := 0
var health := 100
var alive := true
var stamina := 100.0
var held_prop: Prop
var hover_text := ""
var voice_level := 0.0
var voice_frames_received := 0
var third_person := false
var body_hud_open := false

## Slot (int) -> resource_path (String) do BodyPartDef instalado, ou "" se removido.
var body_parts: Dictionary = {}
## Slot (int) -> valor em $ preservado da parte instalada (usado no servidor).
var body_part_values: Dictionary = {}

# Replicados pelo MultiplayerSynchronizer, com o dono como autoridade.
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_crouching := false
var net_sprinting := false
var net_knocked := false
var net_flashlight := false
var net_hold_distance := 2.0
var net_holding := false

var _knock_timer := 0.0
var _stagger_timer := 0.0
var _last_knock_impulse := Vector3.ZERO
var _exhausted := false
var _spawn_position := Vector3.ZERO
var _prev_fall_speed := 0.0
var _push_cooldown := 0.0
var _noise_cooldown := 0.0
var _spectate_index := 0
var _spectate_yaw := 0.0
var _mouse_settle := MOUSE_SETTLE_SECONDS
var _part_cache: Dictionary = {}

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight
@onready var ray: RayCast3D = $Head/InteractRay
@onready var visuals: Node3D = $Visuals
@onready var rig: PlayerRigScript = $Visuals/Rig
@onready var collider: CollisionShape3D = $Collider
@onready var name_label: Label3D = $NameLabel
@onready var voice_output: VoiceOutput = $VoiceOutput
@onready var loadout: Loadout = $Loadout

@onready var _slot_meshes: Dictionary = {
	BodyPartDef.Slot.HEAD: $Visuals/HeadMesh,
	BodyPartDef.Slot.TORSO: $Visuals/Torso,
	BodyPartDef.Slot.LEFT_ARM: $Visuals/LeftArm,
	BodyPartDef.Slot.RIGHT_ARM: $Visuals/RightArm,
	BodyPartDef.Slot.LEFT_LEG: $Visuals/LeftLeg,
	BodyPartDef.Slot.RIGHT_LEG: $Visuals/RightLeg,
}


func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	_init_default_body_parts()
	Game.register_player(self)


func _exit_tree() -> void:
	Game.unregister_player(self)


func _ready() -> void:
	collider.shape = collider.shape.duplicate()
	ray.add_exception(self)
	rig.setup_rig(_slot_meshes, get_rid())
	net_position = position
	_spawn_position = position
	Net.roster_changed.connect(_refresh_identity)
	Net.player_joined.connect(_on_peer_joined)
	_refresh_identity()
	_refresh_body_visuals()
	if is_local():
		camera.make_current()
		visuals.hide()
		name_label.hide()
		voice_output.stream_paused = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		flashlight.shadow_enabled = true


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


func is_local() -> bool:
	return is_multiplayer_authority()


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


func get_grip_force() -> float:
	var total := 0.0
	for slot: BodyPartDef.Slot in [BodyPartDef.Slot.LEFT_ARM, BodyPartDef.Slot.RIGHT_ARM]:
		var def := get_body_part_def(slot)
		if def:
			total += def.grip_force
	return total


func can_hold_props() -> bool:
	return alive and get_arm_count() > 0 and get_grip_force() > 0.0


func get_leg_speed_multiplier() -> float:
	if get_leg_count() == 0:
		return 0.28
	var factor := 0.0
	for slot: BodyPartDef.Slot in [BodyPartDef.Slot.LEFT_LEG, BodyPartDef.Slot.RIGHT_LEG]:
		var def := get_body_part_def(slot)
		if def:
			factor += def.leg_speed_factor
	return maxf(factor, 0.28)


func get_leg_jump_multiplier() -> float:
	if get_leg_count() == 0:
		return 0.0
	var factor := 0.0
	for slot: BodyPartDef.Slot in [BodyPartDef.Slot.LEFT_LEG, BodyPartDef.Slot.RIGHT_LEG]:
		var def := get_body_part_def(slot)
		if def:
			factor += def.leg_jump_factor
	return maxf(factor, 0.0)


func get_body_summary() -> String:
	var tags := PackedStringArray()
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var def := get_body_part_def(slot)
		var label := BodyPartDef.slot_name(slot)
		if def == null:
			tags.append("%s: [Sem]" % label)
		elif def.is_cybernetic:
			tags.append("%s: [Cyber]" % label)
		else:
			tags.append("%s: OK" % label)
	return "  |  ".join(tags)


func get_aim_direction() -> Vector3:
	return Basis.from_euler(Vector3(net_pitch, net_yaw, 0.0)) * Vector3.FORWARD


func get_hold_target() -> Vector3:
	return head.global_position + get_aim_direction() * net_hold_distance


## Escolhe o melhor slot para instalar um membro (braço ou perna usa o lado vazio ou o lado orgânico antes de substituir um cibernético).
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
	if primary_def and primary_def.resource_path == part_def.resource_path and paired_def and paired_def.resource_path != part_def.resource_path:
		return paired
	return primary
func get_aimed_slot(world_hit_point: Vector3) -> BodyPartDef.Slot:
	var local_hit := to_local(world_hit_point)
	var leg_offset := 0.55 if get_leg_count() == 0 else 0.0
	var y := local_hit.y + leg_offset
	if y >= 1.36:
		return BodyPartDef.Slot.HEAD
	if y < 0.72:
		return BodyPartDef.Slot.LEFT_LEG if local_hit.x < 0.0 else BodyPartDef.Slot.RIGHT_LEG
	if local_hit.x < -0.14:
		return BodyPartDef.Slot.LEFT_ARM
	if local_hit.x > 0.14:
		return BodyPartDef.Slot.RIGHT_ARM
	return BodyPartDef.Slot.TORSO


## Retorna o slot mirado se estiver presente, ou o próximo membro removível disponível.
func get_removable_slot_at(world_hit_point: Vector3) -> int:
	var aimed := get_aimed_slot(world_hit_point)
	if has_body_part(aimed):
		return aimed
	return get_next_self_detach_slot()


## Ordem segura para remover um membro de si mesmo (braços -> pernas -> cabeça/tronco).
func get_next_self_detach_slot() -> int:
	for slot: BodyPartDef.Slot in DETACH_PRIORITY:
		if has_body_part(slot):
			return slot
	return -1


func _refresh_identity() -> void:
	var entry: Dictionary = Net.roster.get(peer_id, {})
	if not entry.is_empty():
		name_label.text = entry.name
	_refresh_body_visuals()


func _refresh_body_visuals() -> void:
	if _slot_meshes.is_empty():
		return
	var entry: Dictionary = Net.roster.get(peer_id, {})
	var base_color: Color = entry.get("color", Color("5fa8d3"))
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
			mat.albedo_color = def.color
			mat.metallic = 0.75
			mat.roughness = 0.25
		else:
			mat.albedo_color = base_color
			mat.metallic = 0.1
			mat.roughness = 0.7
		mesh_node.material_override = mat
	visuals.position.y = -0.55 if get_leg_count() == 0 else 0.0
	if is_instance_valid(rig):
		rig.refresh_active_parts(self)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		if _mouse_settle > 0.0:
			return
		var sensitivity := Settings.mouse_sensitivity
		if alive:
			rotation.y -= event.relative.x * sensitivity
			head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, -1.5, 1.5)
		else:
			_spectate_yaw -= event.relative.x * sensitivity
		return
	if not alive:
		if event.is_action_pressed("spectate_next"):
			_spectate_index += 1
		return
	if event.is_action_pressed("grab"):
		var target: Variant = ray.get_collider()
		if loadout.equipped != ItemDef.Kind.NONE:
			loadout.use_primary()
		elif target is Prop and can_hold_props():
			try_grab(target)
	elif event.is_action_released("grab"):
		release_grab(false)
	elif event.is_action_pressed("throw"):
		if is_instance_valid(held_prop):
			release_grab(true)
		else:
			loadout.use_secondary()
	elif event.is_action_pressed("interact"):
		_handle_interact()
	elif event.is_action_pressed("slot_1"):
		loadout.select_slot(0)
	elif event.is_action_pressed("slot_2"):
		loadout.select_slot(1)
	elif event.is_action_pressed("slot_3"):
		loadout.select_slot(2)
	elif event.is_action_pressed("slot_4"):
		loadout.select_slot(3)
	elif event.is_action_pressed("slot_5"):
		loadout.select_slot(4)
	elif event.is_action_pressed("reload"):
		loadout.reload()
	elif event.is_action_pressed("drop_item"):
		loadout.drop_equipped()
	elif event.is_action_pressed("detach_part"):
		_handle_detach_input()
	elif event.is_action_pressed("body_hud"):
		body_hud_open = not body_hud_open
	elif event.is_action_pressed("toggle_camera"):
		set_third_person(not third_person)
	elif event.is_action_pressed("flashlight"):
		loadout.toggle_flashlight()
	elif event.is_action_pressed("hold_further"):
		net_hold_distance = minf(net_hold_distance + 0.25, 3.5)
	elif event.is_action_pressed("hold_nearer"):
		net_hold_distance = maxf(net_hold_distance - 0.25, 1.0)


func _handle_interact() -> void:
	var target: Variant = ray.get_collider()
	# 1. Segurando um membro: instala no jogador/inimigo mirado ou em si mesmo.
	if is_instance_valid(held_prop) and held_prop.def is BodyPartDef:
		var part_prop := held_prop
		release_grab(false)
		if target is Player and target != self:
			(target as Player).request_attach_part_from_prop.rpc_id(1, part_prop.get_path())
		elif target is Monster:
			(target as Monster).request_attach_part_from_prop.rpc_id(1, part_prop.get_path())
		else:
			request_attach_part_from_prop.rpc_id(1, part_prop.get_path())
		return
	# 2. Mirando na alavanca.
	if target is Lever:
		target.request_use.rpc_id(1)
		return
	if target is WorldItem:
		loadout.try_take(target)
		return
	# 3. Mirando num membro no chão: encaixa diretamente no próprio corpo (mesmo sem braços).
	if target is Prop and (target as Prop).def is BodyPartDef:
		request_attach_part_from_prop.rpc_id(1, (target as Prop).get_path())
		return
	# 4. Mirando em outro jogador ou inimigo: remove o membro na mira.
	if target is Player and target != self:
		var other := target as Player
		var slot := other.get_removable_slot_at(ray.get_collision_point())
		if slot >= 0:
			other.request_detach_part.rpc_id(1, slot)
		return
	if target is Monster:
		var monster := target as Monster
		var slot := monster.get_removable_slot_at(ray.get_collision_point())
		if slot >= 0:
			monster.request_detach_part.rpc_id(1, slot)


func _handle_detach_input() -> void:
	var target: Variant = ray.get_collider()
	if target is Player and target != self:
		var other := target as Player
		var slot := other.get_removable_slot_at(ray.get_collision_point())
		if slot >= 0:
			other.request_detach_part.rpc_id(1, slot)
		return
	if target is Monster:
		var monster := target as Monster
		var slot := monster.get_removable_slot_at(ray.get_collision_point())
		if slot >= 0:
			monster.request_detach_part.rpc_id(1, slot)
		return
	var own_slot := get_next_self_detach_slot()
	if own_slot >= 0:
		request_detach_part.rpc_id(1, own_slot)


func try_grab(prop: Prop) -> void:
	if not can_hold_props():
		return
	release_grab(false)
	held_prop = prop
	net_hold_distance = clampf(head.global_position.distance_to(prop.global_position), 1.0, 3.5)
	prop.request_grab.rpc_id(1)


func release_grab(throw: bool) -> void:
	if is_instance_valid(held_prop):
		held_prop.request_release.rpc_id(1, throw)
	held_prop = null


func can_act() -> bool:
	return alive and _knock_timer <= 0.0


## Dono: recuo de arma. Soma à velocidade e reduz o controle, sem derrubar por si só.
func apply_recoil(impulse: Vector3, stagger: float, pitch_kick: float, yaw_kick: float) -> void:
	velocity += impulse
	_stagger_timer = maxf(_stagger_timer, stagger)
	head.rotation.x = clampf(head.rotation.x + pitch_kick, -1.5, 1.5)
	rotation.y += yaw_kick


func knock_down(seconds: float) -> void:
	_knock_timer = maxf(_knock_timer, seconds)
	_last_knock_impulse = velocity
	release_grab(false)
func set_third_person(enabled: bool) -> void:
	third_person = enabled
	if is_local() and alive:
		visuals.visible = third_person
		_update_camera_view(1.0)


func _update_camera_view(delta: float) -> void:
	var weight := 1.0 if delta >= 1.0 else (1.0 - exp(-18.0 * delta))
	if not third_person:
		camera.position = camera.position.lerp(Vector3.ZERO, weight)
		return
	var target_local := THIRD_PERSON_OFFSET
	var origin := head.global_position
	var desired_global := head.to_global(THIRD_PERSON_OFFSET)
	var query := PhysicsRayQueryParameters3D.create(origin, desired_global, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit.position
		var safe_dist := maxf(origin.distance_to(hit_pos) - 0.2, 0.35)
		var total_dist := THIRD_PERSON_OFFSET.length()
		target_local = THIRD_PERSON_OFFSET * (safe_dist / total_dist)
	camera.position = camera.position.lerp(target_local, weight)


func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_settle = maxf(_mouse_settle - delta, 0.0)
	else:
		_mouse_settle = MOUSE_SETTLE_SECONDS
	flashlight.visible = net_flashlight and alive
	voice_level = move_toward(voice_level, 0.0, delta * 0.5)
	if is_local() and alive:
		_update_camera_view(delta)
	elif not is_local():
		head.rotation.x = lerp_angle(head.rotation.x, net_pitch, 1.0 - exp(-15.0 * delta))
	var want_ragdoll := net_knocked or not alive
	if want_ragdoll and not rig.is_ragdoll:
		rig.start_ragdoll(self, _last_knock_impulse)
	elif not want_ragdoll and rig.is_ragdoll:
		rig.stop_ragdoll()
	if not rig.is_ragdoll:
		rig.update_pose(delta, self, net_crouching, net_sprinting, net_holding, head.rotation.x, voice_level)


func _physics_process(delta: float) -> void:
	if is_local():
		_local_physics(delta)
	else:
		_remote_physics(delta)
	if multiplayer.is_server() and net_sprinting and alive:
		_noise_cooldown -= delta
		if _noise_cooldown <= 0.0:
			_noise_cooldown = 0.5
			Game.emit_noise(global_position, SPRINT_NOISE)


func _remote_physics(delta: float) -> void:
	if global_position.distance_squared_to(net_position) > 25.0:
		global_position = net_position
	else:
		global_position = global_position.lerp(net_position, 1.0 - exp(-15.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-15.0 * delta))
	if get_leg_count() == 0:
		head.position.y = CRAWL_EYES
	else:
		head.position.y = CROUCH_EYES if net_crouching else STAND_EYES


func _local_physics(delta: float) -> void:
	if not alive:
		_update_spectator()
		_publish_state(false, false)
		return
	if global_position.y < KILL_PLANE_Y:
		global_position = _spawn_position
		velocity = Vector3.ZERO
	var has_control := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _knock_timer <= 0.0
	var no_legs := get_leg_count() == 0
	var crouching := no_legs or (has_control and Input.is_action_pressed("crouch"))
	if not crouching and net_crouching and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT)):
		crouching = true
	_apply_crouch(crouching, no_legs, delta)
	var sprinting := _update_movement(delta, has_control, crouching)
	var was_airborne := not is_on_floor()
	_prev_fall_speed = -velocity.y
	var velocity_before := velocity
	move_and_slide()
	if was_airborne and is_on_floor() and _prev_fall_speed > SAFE_FALL_SPEED:
		_request_fall_damage.rpc_id(1, _prev_fall_speed)
	_check_wall_slam(velocity_before)
	_push_props(delta)
	_publish_state(crouching, sprinting)
	_update_hover()
	if held_prop != null and (not is_instance_valid(held_prop) or not can_hold_props()):
		release_grab(false)


## Bater numa parede depois de ser arremessado dói como uma queda da mesma velocidade.
func _check_wall_slam(velocity_before: Vector3) -> void:
	if (_stagger_timer > 0.0 or _knock_timer > 0.0) and is_on_wall():
		var slam_speed := -velocity_before.dot(get_wall_normal())
		if slam_speed > SAFE_FALL_SPEED:
			_request_fall_damage.rpc_id(1, slam_speed)


func _update_movement(delta: float, has_control: bool, crouching: bool) -> bool:
	if not is_on_floor():
		velocity += get_gravity() * delta
	_knock_timer = maxf(_knock_timer - delta, 0.0)
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	var input := Vector2.ZERO
	if has_control:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var can_sprint := get_leg_count() > 0 and not crouching
	var wants_sprint := has_control and Input.is_action_pressed("sprint") and input.y < 0.0 and can_sprint
	if stamina <= 0.0:
		_exhausted = true
	elif stamina >= 25.0:
		_exhausted = false
	var sprinting := wants_sprint and not _exhausted
	stamina = clampf(stamina + (-stamina_drain if sprinting else stamina_regen) * delta, 0.0, 100.0)
	var base_speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	var speed := base_speed * get_leg_speed_multiplier()
	if is_instance_valid(held_prop):
		speed *= clampf(1.0 - held_prop.mass / 120.0, 0.45, 1.0)
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)) * speed
	var accel := acceleration if is_on_floor() else acceleration * 0.2
	if _knock_timer > 0.0 or _stagger_timer > 0.0:
		accel = 6.0
	velocity.x = move_toward(velocity.x, wish.x, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	var jump_mult := get_leg_jump_multiplier()
	if has_control and is_on_floor() and jump_mult > 0.0 and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity * jump_mult
	return sprinting and input != Vector2.ZERO


func _apply_crouch(crouching: bool, no_legs: bool, delta: float) -> void:
	var capsule := collider.shape as CapsuleShape3D
	var height := CRAWL_HEIGHT if no_legs else (CROUCH_HEIGHT if crouching else STAND_HEIGHT)
	capsule.height = move_toward(capsule.height, height, 6.0 * delta)
	collider.position.y = capsule.height * 0.5
	var eyes := CRAWL_EYES if no_legs else (CROUCH_EYES if crouching else STAND_EYES)
	if _knock_timer > 0.0:
		eyes = 0.4
	head.position.y = lerpf(head.position.y, eyes, 1.0 - exp(-12.0 * delta))


## Props são congelados nos clientes, então o empurrão precisa ser pedido ao servidor.
func _push_props(delta: float) -> void:
	_push_cooldown -= delta
	if _push_cooldown > 0.0:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var prop := hit.get_collider() as Prop
		if prop and prop != held_prop:
			_push_cooldown = 0.1
			prop.request_push.rpc_id(1, -hit.get_normal() * PUSH_STRENGTH)
			return


func _publish_state(crouching: bool, sprinting: bool) -> void:
	net_position = global_position
	net_yaw = rotation.y
	net_pitch = head.rotation.x
	net_crouching = crouching
	net_sprinting = sprinting
	net_knocked = _knock_timer > 0.0
	net_holding = is_instance_valid(held_prop)


func _update_hover() -> void:
	var target: Variant = ray.get_collider()
	if is_instance_valid(held_prop) and held_prop.def is BodyPartDef:
		var part_def := held_prop.def as BodyPartDef
		if target is Player and target != self:
			var other := target as Player
			var other_name: String = Net.roster.get(other.peer_id, {}).get("name", "aliado")
			var target_slot := other.resolve_install_slot(part_def)
			hover_text = "[E] Implantar %s em %s (%s)" % [part_def.display_name, other_name, BodyPartDef.slot_name(target_slot)]
			return
		if target is Monster:
			var monster := target as Monster
			var target_slot := monster.resolve_install_slot(part_def)
			hover_text = "[E] Implantar %s no Inimigo (%s)" % [part_def.display_name, BodyPartDef.slot_name(target_slot)]
			return
		var self_slot := resolve_install_slot(part_def)
		hover_text = "[E] Implantar %s (%s)" % [part_def.display_name, BodyPartDef.slot_name(self_slot)]
		return
	if target is Prop:
		var prop := target as Prop
		var weapon_in_hand := loadout.equipped != ItemDef.Kind.NONE
		if prop.def is BodyPartDef:
			var part_def := prop.def as BodyPartDef
			var target_slot := resolve_install_slot(part_def)
			var slot_label := BodyPartDef.slot_name(target_slot)
			if can_hold_props() and not weapon_in_hand:
				hover_text = "[Botão esq.] Agarrar  |  [E] Instalar %s (%s)  $%d" % [part_def.display_name, slot_label, prop.net_value]
			else:
				hover_text = "[E] Instalar %s (%s)  $%d" % [part_def.display_name, slot_label, prop.net_value]
		elif weapon_in_hand:
			hover_text = "Guarde a arma para agarrar  %s  $%d" % [prop.def.display_name, prop.net_value]
		elif can_hold_props():
			hover_text = "[Botão esq.] Agarrar  %s  $%d" % [prop.def.display_name, prop.net_value]
		else:
			hover_text = "Sem braços para agarrar  %s  $%d" % [prop.def.display_name, prop.net_value]
	elif target is WorldItem and target.can_take():
		hover_text = target.get_prompt() if loadout.can_take(target.def) else "Sem espaço para %s" % target.def.display_name
	elif target is Lever:
		hover_text = "[E] %s" % target.get_prompt()
	elif target is Player and target != self:
		var other := target as Player
		var other_name: String = Net.roster.get(other.peer_id, {}).get("name", "aliado")
		var slot := other.get_removable_slot_at(ray.get_collision_point())
		if slot >= 0:
			var part_def := other.get_body_part_def(slot as BodyPartDef.Slot)
			var part_label := part_def.display_name if part_def else BodyPartDef.slot_name(slot as BodyPartDef.Slot)
			hover_text = "[E / G] Remover %s de %s" % [part_label, other_name]
		else:
			hover_text = "%s não possui membros removíveis" % other_name
	elif target is Monster:
		var monster := target as Monster
		var slot := monster.get_removable_slot_at(ray.get_collision_point())
		if slot >= 0:
			var part_def := monster.get_body_part_def(slot as BodyPartDef.Slot)
			var part_label := part_def.display_name if part_def else BodyPartDef.slot_name(slot as BodyPartDef.Slot)
			hover_text = "[E / G] Remover %s do Inimigo" % part_label
		else:
			hover_text = "Inimigo não possui membros removíveis"
	else:
		hover_text = ""


func _update_spectator() -> void:
	hover_text = ""
	var others: Array = Game.players.values().filter(func(p: Player) -> bool: return p.alive)
	if others.is_empty():
		return
	var target: Player = others[_spectate_index % others.size()]
	var offset := Basis(Vector3.UP, _spectate_yaw) * Vector3(0.0, 0.8, 3.5)
	camera.global_position = target.global_position + Vector3.UP * 1.4 + offset
	camera.look_at(target.global_position + Vector3.UP * 1.4)


## Servidor: remove um membro do jogador e o transforma em um Prop físico no mundo.
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
	if not can_hold_props() and is_instance_valid(held_prop):
		held_prop.holders.erase(peer_id)
		grab_lost.rpc_id(peer_id)
	var main := get_tree().current_scene
	var spawned: Prop = null
	if main and main.has_method("spawn_prop"):
		var spawn_at := drop_pos
		if not spawn_at.is_finite():
			var forward := -global_transform.basis.z
			if forward.length_squared() < 0.01:
				forward = Vector3.FORWARD
			spawn_at = global_position + Vector3.UP * 1.05 + forward.normalized() * 0.85
		spawned = main.spawn_prop(def, spawn_at, "", saved_value)
	if def.vital and alive:
		health = 0
		_sync_vitals.rpc(0, false)
		loadout.server_drop_all()
		Game.check_all_dead()
	return spawned


## Servidor: instala um BodyPartDef no slot correspondente (ou no slot pareado se livre/orgânico, ejetando o anterior apenas se ambos ocupados).
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


## Servidor: consome um Prop físico de membro do mundo e o instala neste jogador.
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


@rpc("any_peer", "call_local", "reliable")
func request_detach_part(slot: int) -> void:
	if not multiplayer.is_server():
		return
	if slot < 0 or slot >= BodyPartDef.ALL_SLOTS.size():
		return
	var caller := Game.players.get(Net.sender_id()) as Player
	if caller == null or not caller.alive:
		return
	if caller != self and caller.global_position.distance_to(global_position) > BODY_INTERACT_RANGE:
		return
	server_detach_part(slot as BodyPartDef.Slot)


@rpc("any_peer", "call_local", "reliable")
func request_attach_part_from_prop(prop_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var caller := Game.players.get(Net.sender_id()) as Player
	if caller == null or not caller.alive:
		return
	if caller != self and caller.global_position.distance_to(global_position) > BODY_INTERACT_RANGE:
		return
	var prop := get_node_or_null(prop_path) as Prop
	if prop == null or prop.global_position.distance_to(caller.global_position) > Prop.BREAK_RANGE:
		return
	server_attach_part_from_prop(prop)


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
	if not can_hold_props() and is_instance_valid(held_prop):
		release_grab(false)
	_refresh_body_visuals()
	body_parts_changed.emit()


## Servidor: aplica dano e empurrão. O dono executa o empurrão, pois controla a física.
func server_hit(damage: int, knock: Vector3, stun := 1.5) -> void:
	if not multiplayer.is_server() or not alive:
		return
	health = maxi(health - damage, 0)
	_sync_vitals.rpc(health, health > 0)
	if health > 0:
		_receive_knock.rpc_id(peer_id, knock, stun)
	else:
		loadout.server_drop_all()
		Game.check_all_dead()


func server_revive(spawn_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	loadout.server_reset()
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		if not has_body_part(slot):
			var default_path: String = DEFAULT_BODY_PARTS[slot]
			body_parts[slot] = default_path
			var def := _load_part_def(default_path)
			if def:
				body_part_values[slot] = int((def.min_value + def.max_value) * 0.5)
	_sync_body_parts.rpc(body_parts)
	_revive.rpc(spawn_position)


@rpc("any_peer", "call_local", "reliable")
func _sync_vitals(new_health: int, is_alive: bool) -> void:
	if Net.sender_id() != 1:
		return
	health = new_health
	if alive and not is_alive:
		_set_alive(false)


@rpc("any_peer", "call_local", "reliable")
func _receive_knock(knock: Vector3, stun: float) -> void:
	if Net.sender_id() != 1:
		return
	velocity = knock
	_last_knock_impulse = knock
	# Golpe leve só desequilibra; o ragdoll fica para o que realmente derruba.
	if stun < RAGDOLL_MIN_STUN:
		_stagger_timer = maxf(_stagger_timer, stun)
		return
	_knock_timer = stun
	release_grab(false)
	if is_instance_valid(rig):
		rig.start_ragdoll(self, knock)


@rpc("any_peer", "call_local", "reliable")
func _revive(spawn_position: Vector3) -> void:
	if Net.sender_id() != 1:
		return
	health = 100
	stamina = 100.0
	_knock_timer = 0.0
	_stagger_timer = 0.0
	_last_knock_impulse = Vector3.ZERO
	if is_instance_valid(rig):
		rig.stop_ragdoll()
	_set_alive(true)
	net_position = spawn_position
	global_position = spawn_position
	if is_local():
		velocity = Vector3.ZERO
		_spawn_position = spawn_position


## Usada pelo servidor para avisar que o objeto escapou da mão do jogador.
@rpc("any_peer", "call_local", "reliable")
func grab_lost() -> void:
	if Net.sender_id() == 1:
		held_prop = null


@rpc("any_peer", "call_local", "reliable")
func _request_fall_damage(speed: float) -> void:
	if multiplayer.is_server() and Net.sender_id() == peer_id:
		server_hit(roundi((speed - SAFE_FALL_SPEED) * FALL_DAMAGE_PER_MS), Vector3.ZERO)


func _set_alive(value: bool) -> void:
	alive = value
	collider.set_deferred("disabled", not value)
	if is_local():
		camera.top_level = not value
		visuals.visible = third_person or not value
		if value:
			camera.transform = Transform3D.IDENTITY
			_update_camera_view(1.0)
		else:
			release_grab(false)
			net_flashlight = false
	else:
		visuals.visible = true
		name_label.visible = value
	if not value and is_instance_valid(rig):
		rig.start_ragdoll(self, _last_knock_impulse)
	elif value and is_instance_valid(rig):
		rig.stop_ragdoll()


func send_voice(packet: PackedByteArray) -> void:
	_voice_frame.rpc(packet)
	if multiplayer.is_server():
		Game.emit_noise(global_position, VoiceCodec.rms(VoiceCodec.decode(packet)))


## Canal 1 separa a voz do tráfego confiável. O servidor retransmite aos demais clientes.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _voice_frame(packet: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != peer_id or packet.size() > 2048:
		return
	var samples := VoiceCodec.decode(packet)
	voice_level = VoiceCodec.rms(samples)
	voice_frames_received += 1
	if multiplayer.is_server():
		Game.emit_noise(global_position, voice_level)
	var listener := Game.local_player()
	# Mortos falam apenas entre si; vivos não os escutam.
	if not alive and listener and listener.alive:
		return
	voice_output.push(samples)
