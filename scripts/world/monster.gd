class_name Monster
extends CharacterBody3D
## Inimigo simulado no servidor. Persegue quem ve e investiga barulho, inclusive voz:
## quanto mais alto o jogador fala, de mais longe o monstro escuta.

enum State { ROAM, INVESTIGATE, CHASE }

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

var state := State.ROAM
var health := 0
var net_position := Vector3.ZERO
var net_yaw := 0.0

var _target_player: Player
var _state_timer := 0.0
var _attack_timer := 0.0
var _stun_timer := 0.0

@onready var agent: NavigationAgent3D = $Agent


func setup(data: Dictionary) -> void:
	name = data.name
	position = data.pos
	net_position = data.pos


func _ready() -> void:
	health = max_health
	if multiplayer.is_server():
		Game.noise_emitted.connect(_on_noise)
	else:
		collision_layer = 0
		collision_mask = 0


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


## Servidor. Mesma assinatura de Player.server_hit, para as armas tratarem os dois igual.
func server_hit(damage: int, knock: Vector3, stun := 1.5) -> void:
	if not multiplayer.is_server() or health <= 0:
		return
	health = maxi(health - damage, 0)
	if health == 0:
		queue_free()
		return
	velocity = knock
	_stun_timer = maxf(_stun_timer, stun)


func _find_visible_player() -> Player:
	var best: Player = null
	var best_distance := vision_range
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * 1.7
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
	for player: Player in Game.players.values():
		if player.alive and global_position.distance_to(player.global_position) <= attack_range:
			_attack_timer = attack_cooldown
			var away := (player.global_position - global_position).normalized()
			player.server_hit(attack_damage, away * knock_force + Vector3.UP * 3.0)
			return


func _on_noise(origin: Vector3, loudness: float) -> void:
	if state == State.CHASE:
		return
	var radius := minf(loudness * hearing_gain, max_hearing_range)
	if global_position.distance_to(origin) <= radius:
		state = State.INVESTIGATE
		_state_timer = 8.0
		agent.target_position = origin
