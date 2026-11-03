class_name Prop
extends RigidBody3D
## Loot simulado no servidor. Cada jogador segurando soma uma força limitada,
## entao objetos pesados precisam de mais de uma pessoa para sair do chao.

const GRIP_FORCE := 350.0
const SPRING := 60.0
const DAMPING := 12.0
const GRAB_RANGE := 4.5
const BREAK_RANGE := 5.5
const THROW_IMPULSE := 9.0
const MAX_PUSH_IMPULSE := 12.0

var def: PropDef
var net_position := Vector3.ZERO
var net_rotation := Quaternion.IDENTITY
var net_value := 0
## Quem está segurando, em ordem de chegada. Replicado para o HUD de todos os peers.
var net_holder_ids := PackedInt32Array()

## peer_id -> Player. Somente no servidor.
var holders: Dictionary = {}

var _original_value := 0
var _prev_speed := 0.0
var _impact_cooldown := 1.0

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape


## Chamado pela função de spawn em todos os peers, antes de entrar na arvore.
func setup(data: Dictionary) -> void:
	def = load(data.def) as PropDef
	name = data.name
	net_value = data.value
	_original_value = data.value
	position = data.pos
	net_position = data.pos
	mass = def.mass


func _ready() -> void:
	var box_mesh := BoxMesh.new()
	box_mesh.size = def.size
	var material := StandardMaterial3D.new()
	material.albedo_color = def.color
	box_mesh.material = material
	_mesh.mesh = box_mesh
	var box_shape := BoxShape3D.new()
	box_shape.size = def.size
	_shape.shape = box_shape
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		var weight := 1.0 - exp(-18.0 * delta)
		position = position.lerp(net_position, weight)
		quaternion = quaternion.slerp(net_rotation, weight)
		return
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	_prev_speed = linear_velocity.length()
	_apply_holders()
	_publish_holders()
	if position.distance_squared_to(net_position) > 0.000001:
		net_position = position
	if not quaternion.is_equal_approx(net_rotation):
		net_rotation = quaternion


## Quantas pessoas de força normal são necessárias para tirar o objeto do chão.
func people_needed() -> int:
	return maxi(ceili(_weight() / GRIP_FORCE), 1)


## Quantas pessoas de força normal ainda faltam, considerando os braços de quem já segura.
func people_missing() -> int:
	if net_holder_ids.is_empty():
		return people_needed()
	var force := 0.0
	for peer_id: int in net_holder_ids:
		var player := Game.players.get(peer_id) as Player
		if player:
			force += player.get_grip_force()
	return maxi(ceili((_weight() - force) / GRIP_FORCE), 0)


func _weight() -> float:
	return mass * float(ProjectSettings.get_setting("physics/3d/default_gravity"))


func _publish_holders() -> void:
	if holders.is_empty() and net_holder_ids.is_empty():
		return
	var ids := PackedInt32Array(holders.keys())
	if ids != net_holder_ids:
		net_holder_ids = ids


func _apply_holders() -> void:
	angular_damp = 6.0 if not holders.is_empty() else 0.5
	for peer_id: int in holders.keys():
		var player := holders[peer_id] as Player
		if not is_instance_valid(player) or not player.alive or not player.can_hold_props():
			holders.erase(peer_id)
			if is_instance_valid(player):
				player.grab_lost.rpc_id(peer_id)
			continue
		var target := player.get_hold_target()
		if global_position.distance_to(target) > BREAK_RANGE:
			holders.erase(peer_id)
			player.grab_lost.rpc_id(peer_id)
			continue
		var acceleration := (target - global_position) * SPRING - linear_velocity * DAMPING
		acceleration.y += get_gravity().length()
		apply_central_force((acceleration * mass).limit_length(player.get_grip_force()))


func _on_body_entered(_body: Node) -> void:
	if _impact_cooldown > 0.0 or _prev_speed < def.impact_threshold:
		return
	_impact_cooldown = 0.3
	Game.emit_noise(global_position, _prev_speed * 0.02)
	var loss := ceili((_prev_speed - def.impact_threshold) * def.fragility * _original_value)
	if loss <= 0:
		return
	net_value -= loss
	_show_loss.rpc(loss)
	if net_value <= 0:
		queue_free()


@rpc("any_peer", "call_local", "reliable")
func request_grab() -> void:
	if not multiplayer.is_server():
		return
	var id := Net.sender_id()
	var player := Game.players.get(id) as Player
	if player and player.alive and player.can_hold_props() and player.global_position.distance_to(global_position) <= GRAB_RANGE:
		holders[id] = player
		sleeping = false
	elif player:
		# Sem o aviso, o cliente acreditaria estar segurando e ficaria lento pelo peso.
		player.grab_lost.rpc_id(id)


@rpc("any_peer", "call_local", "reliable")
func request_release(throw: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := Net.sender_id()
	var player := holders.get(id) as Player
	holders.erase(id)
	if throw and is_instance_valid(player) and player.can_hold_props():
		var throw_scale := clampf(player.get_grip_force() / GRIP_FORCE, 0.35, 2.0)
		apply_central_impulse(player.get_aim_direction() * THROW_IMPULSE * throw_scale * minf(mass, 15.0))


@rpc("any_peer", "call_local", "unreliable")
func request_push(impulse: Vector3) -> void:
	if multiplayer.is_server():
		sleeping = false
		apply_central_impulse(impulse.limit_length(MAX_PUSH_IMPULSE))


@rpc("authority", "call_local", "reliable")
func _show_loss(amount: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var label := Label3D.new()
	label.text = "-$%d" % amount
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("e4572e")
	label.top_level = true
	add_child(label)
	label.global_position = global_position + Vector3.UP * 0.6
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.0, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)
