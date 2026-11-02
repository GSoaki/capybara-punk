class_name WorldItem
extends RigidBody3D
## Item no mundo, simulado no servidor como os props. Parado, pode ser pego do chão.
## "Ativo" significa cacetete em voo, que machuca quem acertar, ou granada com o pino puxado.

const IDLE_MASK := 5
const ACTIVE_MASK := 23
## Folga para a caixa de colisão ser mais fácil de mirar que a malha.
const SHAPE_MARGIN := 0.12
const TAKE_RANGE := 4.5
const KILL_PLANE_Y := -25.0
## Quem arremessou fica imune neste intervalo. Depois, o rebote pode voltar na própria cara.
const THROWER_GRACE := 0.3
const BATON_MIN_HIT_SPEED := 3.0
const BATON_DAMAGE_PER_MS := 0.9
const BATON_KNOCK_PER_MS := 0.7
const BATON_STUN := 0.8
const BATON_SPIN := 25.0
const BATON_SETTLE_SPEED := 1.0
const BATON_MAX_FLIGHT := 8.0
const FUSE_SECONDS := 2.5
const BLAST_RADIUS := 7.0
const BLAST_FORCE := 14.0
const BLAST_EDGE_FALLOFF := 0.35
const BLAST_MIN_LIFT := 0.35
const BLAST_STUN := 1.5
const BLAST_NOISE := 0.6

var def: ItemDef
var amount := 0
var net_position := Vector3.ZERO
var net_rotation := Quaternion.IDENTITY
var net_active := false

var _launch_velocity := Vector3.ZERO
var _thrower_id := 0
var _timer := 0.0
var _grace := 0.0
var _settling := 0.0
var _hit_cooldown := 0.0
var _prev_velocity := Vector3.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape


## Chamado pela função de spawn em todos os peers, antes de entrar na arvore.
func setup(data: Dictionary) -> void:
	def = load(data.def) as ItemDef
	name = data.name
	amount = data.amount
	position = data.pos
	net_position = data.pos
	net_active = data.active
	_launch_velocity = data.velocity
	_thrower_id = data.thrower
	mass = def.mass


func _ready() -> void:
	_mesh.mesh = Loadout.make_mesh(def)
	var box_shape := BoxShape3D.new()
	box_shape.size = def.size + Vector3.ONE * SHAPE_MARGIN
	_shape.shape = box_shape
	if not multiplayer.is_server():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		return
	var material := PhysicsMaterial.new()
	material.bounce = def.bounce
	physics_material_override = material
	body_entered.connect(_on_body_entered)
	linear_velocity = _launch_velocity
	if net_active:
		collision_mask = ACTIVE_MASK
		_timer = FUSE_SECONDS if def.kind == ItemDef.Kind.GRENADE else BATON_MAX_FLIGHT
		angular_velocity = _launch_velocity.cross(Vector3.UP).normalized() * BATON_SPIN
		var thrower := Game.players.get(_thrower_id) as Player
		if thrower:
			add_collision_exception_with(thrower)
			_grace = THROWER_GRACE


func can_take() -> bool:
	return not net_active


func get_prompt() -> String:
	if def.kind == ItemDef.Kind.AMMO:
		return "[E] Pegar %s (%d)" % [def.display_name, amount]
	return "[E] Pegar %s" % def.display_name


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		var weight := 1.0 - exp(-18.0 * delta)
		position = position.lerp(net_position, weight)
		quaternion = quaternion.slerp(net_rotation, weight)
		return
	if global_position.y < KILL_PLANE_Y:
		queue_free()
		return
	_tick_grace(delta)
	if net_active:
		_timer -= delta
		if def.kind == ItemDef.Kind.GRENADE:
			if _timer <= 0.0:
				_explode()
				return
		else:
			_tick_baton_flight(delta)
	_prev_velocity = linear_velocity
	if position.distance_squared_to(net_position) > 0.000001:
		net_position = position
	if not quaternion.is_equal_approx(net_rotation):
		net_rotation = quaternion


func _tick_grace(delta: float) -> void:
	if _grace <= 0.0:
		return
	_grace -= delta
	var thrower := Game.players.get(_thrower_id) as Player
	if _grace <= 0.0 and thrower:
		remove_collision_exception_with(thrower)


func _tick_baton_flight(delta: float) -> void:
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	_settling = _settling + delta if linear_velocity.length() < BATON_SETTLE_SPEED else 0.0
	if _settling > 0.25 or _timer <= 0.0:
		net_active = false
		collision_mask = IDLE_MASK


func _on_body_entered(body: Node) -> void:
	if not net_active or def.kind != ItemDef.Kind.BATON:
		return
	var speed := _prev_velocity.length()
	if speed < BATON_MIN_HIT_SPEED:
		return
	Game.emit_noise(global_position, speed * 0.02)
	if _hit_cooldown <= 0.0 and body.has_method("server_hit"):
		_hit_cooldown = 0.3
		# O sinal chega durante o passo de física, quando morte e spawn de itens são proibidos.
		_strike.call_deferred(body, _prev_velocity)


func _strike(body: Node, hit_velocity: Vector3) -> void:
	if is_instance_valid(body):
		var damage := roundi(hit_velocity.length() * BATON_DAMAGE_PER_MS)
		body.server_hit(damage, hit_velocity * BATON_KNOCK_PER_MS + Vector3.UP * 2.0, BATON_STUN)


func _explode() -> void:
	var center := global_position
	var main := get_tree().current_scene as Main
	main.weapon_fx.blast.rpc(center, BLAST_RADIUS)
	Game.emit_noise(center, BLAST_NOISE)
	for player: Player in Game.players.values():
		if player.alive:
			var dir_force := _blast_push(center, player.global_position + Vector3.UP * 0.9)
			if dir_force != Vector3.ZERO:
				player.server_hit(0, dir_force, BLAST_STUN)
	for monster: Monster in main.monsters.get_children():
		var dir_force := _blast_push(center, monster.global_position + Vector3.UP * 1.1)
		if dir_force != Vector3.ZERO:
			monster.server_hit(0, dir_force, BLAST_STUN)
	for prop: Prop in main.props.get_children():
		var dir_force := _blast_push(center, prop.global_position)
		if dir_force != Vector3.ZERO:
			prop.sleeping = false
			prop.apply_central_impulse(dir_force * minf(prop.mass, 15.0))
	for item: WorldItem in main.items.get_children():
		var dir_force := _blast_push(center, item.global_position)
		if item != self and dir_force != Vector3.ZERO:
			item.sleeping = false
			item.apply_central_impulse(dir_force * item.mass)
	queue_free()


## Velocidade aplicada a quem está no raio e sem parede no caminho; zero para os demais.
func _blast_push(center: Vector3, target: Vector3) -> Vector3:
	var distance := center.distance_to(target)
	if distance > BLAST_RADIUS:
		return Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.create(center, target, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return Vector3.ZERO
	var direction := (target - center).normalized() if distance > 0.01 else Vector3.UP
	direction.y = maxf(direction.y, BLAST_MIN_LIFT)
	var falloff := lerpf(1.0, BLAST_EDGE_FALLOFF, distance / BLAST_RADIUS)
	return direction.normalized() * BLAST_FORCE * falloff
