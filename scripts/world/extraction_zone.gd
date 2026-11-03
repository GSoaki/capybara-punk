class_name ExtractionZone
extends Area3D
## Soma o valor dos props dentro da area. O total final da run vale ao encerrar.

var _timer := 0.0


func _physics_process(delta: float) -> void:
	if not Net.in_session or not multiplayer.is_server() or Game.phase != Game.Phase.RUN:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var total := 0
	for body in get_overlapping_bodies():
		if body is Prop:
			total += body.net_value
	Game.set_collected(total)
