class_name Player
extends CharacterBody3D
## Controlador em primeira pessoa com autoridade do proprio cliente: movimento sem
## atraso e sem predição. Vida e morte continuam decididas pelo servidor.

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const STAND_EYES := 1.6
const CROUCH_EYES := 0.95
const KILL_PLANE_Y := -25.0
const SAFE_FALL_SPEED := 11.0
const FALL_DAMAGE_PER_MS := 12.0
const PUSH_STRENGTH := 2.5
const SPRINT_NOISE := 0.06
## O primeiro movimento após capturar o mouse traz o salto do cursor até o centro da janela.
const MOUSE_SETTLE_SECONDS := 0.1

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

# Replicados pelo MultiplayerSynchronizer, com o dono como autoridade.
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_crouching := false
var net_sprinting := false
var net_knocked := false
var net_flashlight := false
var net_hold_distance := 2.0

var _knock_timer := 0.0
var _stagger_timer := 0.0
var _exhausted := false
var _spawn_position := Vector3.ZERO
var _prev_fall_speed := 0.0
var _push_cooldown := 0.0
var _noise_cooldown := 0.0
var _spectate_index := 0
var _spectate_yaw := 0.0
var _mouse_settle := MOUSE_SETTLE_SECONDS

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight
@onready var ray: RayCast3D = $Head/InteractRay
@onready var visuals: Node3D = $Visuals
@onready var collider: CollisionShape3D = $Collider
@onready var name_label: Label3D = $NameLabel
@onready var voice_output: VoiceOutput = $VoiceOutput
@onready var loadout: Loadout = $Loadout


func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)
	Game.register_player(self)


func _exit_tree() -> void:
	Game.unregister_player(self)


func _ready() -> void:
	collider.shape = collider.shape.duplicate()
	net_position = position
	_spawn_position = position
	Net.roster_changed.connect(_refresh_identity)
	_refresh_identity()
	if is_local():
		camera.make_current()
		visuals.hide()
		name_label.hide()
		voice_output.stream_paused = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		flashlight.shadow_enabled = true


func is_local() -> bool:
	return is_multiplayer_authority()


func get_aim_direction() -> Vector3:
	return Basis.from_euler(Vector3(net_pitch, net_yaw, 0.0)) * Vector3.FORWARD


func get_hold_target() -> Vector3:
	return head.global_position + get_aim_direction() * net_hold_distance


func _refresh_identity() -> void:
	var entry: Dictionary = Net.roster.get(peer_id, {})
	if entry.is_empty():
		return
	name_label.text = entry.name
	var material := StandardMaterial3D.new()
	material.albedo_color = entry.color
	($Visuals/Body as MeshInstance3D).material_override = material


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
		elif target is Prop:
			try_grab(target)
	elif event.is_action_released("grab"):
		release_grab(false)
	elif event.is_action_pressed("throw"):
		if is_instance_valid(held_prop):
			release_grab(true)
		else:
			loadout.use_secondary()
	elif event.is_action_pressed("interact"):
		var target: Variant = ray.get_collider()
		if target is Lever:
			target.request_use.rpc_id(1)
		elif target is WorldItem:
			loadout.try_take(target)
	elif event.is_action_pressed("slot_1"):
		loadout.equip(ItemDef.Kind.REVOLVER)
	elif event.is_action_pressed("slot_2"):
		loadout.equip(ItemDef.Kind.BATON)
	elif event.is_action_pressed("slot_3"):
		loadout.equip(ItemDef.Kind.GRENADE)
	elif event.is_action_pressed("reload"):
		loadout.reload()
	elif event.is_action_pressed("drop_item"):
		loadout.drop_equipped()
	elif event.is_action_pressed("flashlight"):
		net_flashlight = not net_flashlight
	elif event.is_action_pressed("hold_further"):
		net_hold_distance = minf(net_hold_distance + 0.25, 3.5)
	elif event.is_action_pressed("hold_nearer"):
		net_hold_distance = maxf(net_hold_distance - 0.25, 1.0)


func try_grab(prop: Prop) -> void:
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
	release_grab(false)


func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_settle = maxf(_mouse_settle - delta, 0.0)
	else:
		_mouse_settle = MOUSE_SETTLE_SECONDS
	flashlight.visible = net_flashlight and alive
	voice_level = move_toward(voice_level, 0.0, delta * 0.5)
	if not is_local():
		head.rotation.x = lerp_angle(head.rotation.x, net_pitch, 1.0 - exp(-15.0 * delta))
	var tilt := -PI * 0.5 if net_knocked else 0.0
	visuals.rotation.x = lerp_angle(visuals.rotation.x, tilt, 1.0 - exp(-10.0 * delta))


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
	var crouching := has_control and Input.is_action_pressed("crouch")
	if not crouching and net_crouching and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT)):
		crouching = true
	_apply_crouch(crouching, delta)
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
	if held_prop != null and not is_instance_valid(held_prop):
		held_prop = null


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
	var wants_sprint := has_control and Input.is_action_pressed("sprint") and input.y < 0.0 and not crouching
	if stamina <= 0.0:
		_exhausted = true
	elif stamina >= 25.0:
		_exhausted = false
	var sprinting := wants_sprint and not _exhausted
	stamina = clampf(stamina + (-stamina_drain if sprinting else stamina_regen) * delta, 0.0, 100.0)
	var speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	if is_instance_valid(held_prop):
		speed *= clampf(1.0 - held_prop.mass / 120.0, 0.45, 1.0)
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)) * speed
	var accel := acceleration if is_on_floor() else acceleration * 0.2
	if _knock_timer > 0.0 or _stagger_timer > 0.0:
		accel = 6.0
	velocity.x = move_toward(velocity.x, wish.x, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * delta)
	if has_control and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	return sprinting and input != Vector2.ZERO


func _apply_crouch(crouching: bool, delta: float) -> void:
	var capsule := collider.shape as CapsuleShape3D
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	capsule.height = move_toward(capsule.height, height, 6.0 * delta)
	collider.position.y = capsule.height * 0.5
	var eyes := CROUCH_EYES if crouching else STAND_EYES
	if _knock_timer > 0.0:
		eyes = 0.4
	head.position.y = lerpf(head.position.y, eyes, 1.0 - exp(-12.0 * delta))


## Props sao congelados nos clientes, entao o empurrao precisa ser pedido ao servidor.
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


func _update_hover() -> void:
	var target: Variant = ray.get_collider()
	if target is Prop:
		var action := "[Botão esq.] Agarrar" if loadout.equipped == ItemDef.Kind.NONE else "Guarde a arma para agarrar"
		hover_text = "%s  %s  $%d" % [action, target.def.display_name, target.net_value]
	elif target is WorldItem and target.can_take():
		hover_text = target.get_prompt() if loadout.can_take(target.def) else "Sem espaço para %s" % target.def.display_name
	elif target is Lever:
		hover_text = "[E] %s" % target.get_prompt()
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


## Servidor: aplica dano e empurrao. O dono executa o empurrao, pois controla a física.
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
	if multiplayer.is_server():
		loadout.server_reset()
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
	_knock_timer = stun
	release_grab(false)


@rpc("any_peer", "call_local", "reliable")
func _revive(spawn_position: Vector3) -> void:
	if Net.sender_id() != 1:
		return
	health = 100
	stamina = 100.0
	_knock_timer = 0.0
	_stagger_timer = 0.0
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
		if value:
			camera.transform = Transform3D.IDENTITY
		else:
			release_grab(false)
			net_flashlight = false
	else:
		visuals.visible = value
		name_label.visible = value


func send_voice(packet: PackedByteArray) -> void:
	_voice_frame.rpc(packet)
	if multiplayer.is_server():
		Game.emit_noise(global_position, VoiceCodec.rms(VoiceCodec.decode(packet)))


## Canal 1 separa a voz do trafego confiável. O servidor retransmite aos demais clientes.
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
