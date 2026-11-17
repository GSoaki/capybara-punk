extends ImplantAbility
## Tremedeira da empilhadeira: o servidor sacode o alvo do agarre enquanto o jogador corre com carga frágil ou leve.

const RETARGET_INTERVAL := 1.0 / 6.0
const FOLLOW_RATE := 20.0
const HOLD_TIMEOUT_MS := 150
const LIGHT_MASS_KG := 3.0
const FRAGILE_THRESHOLD := 0.2

var _current := Vector3.ZERO
var _target := Vector3.ZERO
var _retarget_timer := 0.0
var _last_tick_msec := 0
var _cleared := true


## Servidor: chamado a cada frame de física enquanto o jogador segura o prop.
func on_hold_tick(prop: Prop, delta: float) -> void:
	_last_tick_msec = Time.get_ticks_msec()
	_cleared = false
	var risky := prop.def.fragility >= FRAGILE_THRESHOLD or prop.mass <= LIGHT_MASS_KG
	if not player.net_sprinting or not risky:
		_current = Vector3.ZERO
		_target = Vector3.ZERO
		_retarget_timer = 0.0
		player.implants.set_hold_offset(Vector3.ZERO)
		return
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		_target = dir * def.grip_jitter
	_current = _current.lerp(_target, 1.0 - exp(-FOLLOW_RATE * delta))
	player.implants.set_hold_offset(_current)


## Servidor: zera o deslocamento uma única vez quando o agarre para de receber ticks.
func _physics_process(_delta: float) -> void:
	if not is_server() or _cleared:
		return
	if Time.get_ticks_msec() - _last_tick_msec < HOLD_TIMEOUT_MS:
		return
	_cleared = true
	_current = Vector3.ZERO
	_target = Vector3.ZERO
	_retarget_timer = 0.0
	player.implants.set_hold_offset(Vector3.ZERO)
