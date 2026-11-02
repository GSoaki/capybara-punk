class_name Drone
extends CharacterBody3D
## Drone de segurança simulado no servidor. Voa em circuito fixo entre salas e repete o
## trajeto para sempre. Não enxerga, não escuta e não ataca: só desvia a rota se for atingido.

@export var patrol_speed := 2.5
@export var hover_height := 2.0
## Parada em cada ponto do circuito, em segundos.
@export var waypoint_pause := 1.0
@export var max_health := 40
## Desaceleração enquanto atordoado, em m/s².
@export var stun_drag := 7.0
## Rapidez com que volta à altitude de voo.
@export var lift_gain := 3.0
@export var rotor_speed := 40.0

const WAYPOINT_RADIUS := 0.4

var health := 0
var net_position := Vector3.ZERO
var net_yaw := 0.0
var waypoint_index := 0

var _waypoints := PackedVector3Array()
var _path := PackedVector3Array()
var _path_index := 0
var _pause_timer := 0.0
var _stun_timer := 0.0

@onready var _rotors: Node3D = $Rotors


func setup(data: Dictionary) -> void:
	name = data.name
	_waypoints = data.waypoints
	position = _waypoints[0] + Vector3.UP * hover_height
	net_position = position


func _ready() -> void:
	health = max_health
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0


func _process(delta: float) -> void:
	_rotors.rotate_y(rotor_speed * delta)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		var weight := 1.0 - exp(-12.0 * delta)
		position = position.lerp(net_position, weight)
		rotation.y = lerp_angle(rotation.y, net_yaw, weight)
		return
	if _stun_timer > 0.0:
		_stun_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, stun_drag * delta)
		velocity.z = move_toward(velocity.z, 0.0, stun_drag * delta)
		# Empurrado para fora da rota: ao se recuperar, traça um novo caminho até o mesmo ponto.
		_path = PackedVector3Array()
	else:
		_patrol(delta)
	velocity.y = (hover_height - position.y) * lift_gain
	move_and_slide()
	net_position = position
	net_yaw = rotation.y


func _patrol(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return
	if _path.is_empty() and not _plan_path():
		return
	if _path_index >= _path.size():
		waypoint_index = (waypoint_index + 1) % _waypoints.size()
		_pause_timer = waypoint_pause
		_path = PackedVector3Array()
		return
	var to_next := _path[_path_index] - position
	to_next.y = 0.0
	if to_next.length() < WAYPOINT_RADIUS:
		_path_index += 1
		return
	var horizontal := to_next.normalized() * patrol_speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	rotation.y = lerp_angle(rotation.y, atan2(-horizontal.x, -horizontal.z), 1.0 - exp(-6.0 * delta))


## O navmesh fica no chão, então o caminho é pedido a partir da projeção do drone nele.
## Devolve false enquanto o mapa não estiver pronto.
func _plan_path() -> bool:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(position.x, 0.0, position.z))
	var goal := NavigationServer3D.map_get_closest_point(map, _waypoints[waypoint_index])
	_path = NavigationServer3D.map_get_path(map, start, goal, true)
	_path_index = 0
	return not _path.is_empty()


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
