extends ImplantAbility
## Válvula pneumática: os estouros do pistão da perna cibernética geram ruído e deslocam o salto para o lado da perna orgânica.

const POP_FALL_SPEED := 4.0
const POP_STAMINA_THRESHOLD := 25.0
const POP_INTERVAL := 0.5
const SERVER_NOISE_INTERVAL_MS := 250
const JUMP_START_VY := 2.0
const DRIFT_SPEED := 0.6

var _pop_cooldown := 0.0
var _last_noise_msec := -SERVER_NOISE_INTERVAL_MS
var _was_on_floor := false


## Dono: uma queda acima da velocidade segura faz a válvula estourar.
func on_landed(fall_speed: float) -> void:
	if fall_speed > POP_FALL_SPEED:
		send_to_server({"kind": "pop"})


## Servidor: emite o ruído do estouro, com no máximo um por intervalo.
func on_server_request(payload: Dictionary) -> void:
	var kind: String = payload.get("kind", "")
	if kind != "pop":
		return
	var now := Time.get_ticks_msec()
	if now - _last_noise_msec < SERVER_NOISE_INTERVAL_MS:
		return
	_last_noise_msec = now
	Game.emit_noise(player.global_position, Game.NOISE_PNEUMATIC)


## Dono: estouros automáticos ao correr com pouca stamina e deriva do salto.
func _physics_process(delta: float) -> void:
	if not is_owner():
		return
	_pop_cooldown = maxf(_pop_cooldown - delta, 0.0)
	if player.net_sprinting and player.stamina < POP_STAMINA_THRESHOLD and _pop_cooldown <= 0.0:
		_pop_cooldown = POP_INTERVAL
		send_to_server({"kind": "pop"})
	var on_floor := player.is_on_floor()
	if _was_on_floor and not on_floor and player.velocity.y > JUMP_START_VY:
		_apply_asymmetric_drift()
	_was_on_floor = on_floor


## Retorna +1 se a perna orgânica é a direita, -1 se é a esquerda e 0 se não há drift.
func _drift_side() -> float:
	var left := player.get_body_part_def(BodyPartDef.Slot.LEFT_LEG)
	var right := player.get_body_part_def(BodyPartDef.Slot.RIGHT_LEG)
	var left_valve := left != null and left.ability_id == &"pneumatic_valve"
	var right_valve := right != null and right.ability_id == &"pneumatic_valve"
	if left_valve == right_valve:
		return 0.0
	var organic: BodyPartDef = right if left_valve else left
	if organic == null or organic.is_cybernetic:
		return 0.0
	return 1.0 if left_valve else -1.0


## Empurra o jogador lateralmente no início do salto, no plano horizontal.
func _apply_asymmetric_drift() -> void:
	var side := _drift_side()
	if side == 0.0:
		return
	var axis := player.transform.basis.x * side
	player.velocity += Vector3(axis.x, 0.0, axis.z) * DRIFT_SPEED
