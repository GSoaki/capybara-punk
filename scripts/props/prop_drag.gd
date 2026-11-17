class_name PropDrag
extends Node
## Arrasto de props no servidor: ruido, abrasao (perda de valor) e freio no chao.
## O pai deve ser um Prop. Roda somente no servidor.

## Velocidade horizontal minima (m/s) para considerar o objeto arrastado.
const DRAG_MIN_SPEED := 0.3
## Intervalo (s) entre emissoes de ruido enquanto arrasta.
const NOISE_INTERVAL := 0.4
## Distancia horizontal (m) arrastada entre cada perda por abrasao.
const ABRASION_STEP := 4.0
## Fracao do valor original perdida a cada passo, na fragilidade de referencia.
const ABRASION_FRACTION := 0.015
## Fragilidade de referencia que escala a perda por abrasao.
const ABRASION_REF_FRAGILITY := 0.05
## Amortecimento linear aplicado quando solto no chao.
const BRAKE_DAMP := 4.0

## Verdadeiro enquanto alguem arrasta o objeto pelo chao.
var is_dragging := false
## Distancia horizontal total arrastada (m), para testes.
var dragged_distance := 0.0

var _prop: Prop
var _base_damp := 0.0
var _braking := false
var _noise_timer := 0.0
var _abrasion_acc := 0.0


func _ready() -> void:
	_prop = get_parent() as Prop
	if _prop == null or not multiplayer.is_server():
		set_physics_process(false)
		return
	_base_damp = _prop.linear_damp


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_prop):
		return
	var on_floor := _has_floor_contact()
	var held := not _prop.holders.is_empty()
	var velocity := _prop.linear_velocity
	var h_speed := Vector2(velocity.x, velocity.z).length()

	# Freio: solto no chao freia; caso contrario volta ao amortecimento original.
	var should_brake := not held and on_floor
	if should_brake != _braking:
		_braking = should_brake
		_prop.linear_damp = BRAKE_DAMP if should_brake else _base_damp

	is_dragging = held and on_floor and h_speed > DRAG_MIN_SPEED
	if not is_dragging:
		_noise_timer = 0.0
		return

	var step := h_speed * delta
	dragged_distance += step
	_abrasion_acc += step

	_noise_timer -= delta
	if _noise_timer <= 0.0:
		_noise_timer = NOISE_INTERVAL
		var loudness := (0.03 + 0.0009 * _prop.mass) * clampf(h_speed / 1.5, 0.3, 1.0)
		Game.emit_noise(_prop.global_position, loudness)

	while _abrasion_acc >= ABRASION_STEP:
		_abrasion_acc -= ABRASION_STEP
		var loss := maxi(ceili(_prop._original_value * ABRASION_FRACTION * (_prop.def.fragility / ABRASION_REF_FRAGILITY)), 1)
		_prop.net_value -= loss
		_prop._show_loss.rpc(loss)
		if _prop.net_value <= 0:
			_prop.queue_free()
			return


## Contato com o chao: qualquer contato com normal local apontando para cima.
func _has_floor_contact() -> bool:
	var state := PhysicsServer3D.body_get_direct_state(_prop.get_rid())
	if state == null:
		return false
	for i in state.get_contact_count():
		if state.get_contact_local_normal(i).y > 0.7:
			return true
	return false
