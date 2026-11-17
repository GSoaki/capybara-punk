class_name ScannerPulse
extends ImplantAbility
## Pulso de scanner: revela tesouros, monstros e drones próximos e dá visão noturna.

const COOLDOWN := 20.0
const RADIUS := 14.0
const MIN_PROP_VALUE := 120
const REVEAL_SECONDS := 4.0
const STATIC_SECONDS := 1.5

var _cooldown_left := 0.0
var _static_left := 0.0
var _night_light: OmniLight3D
var _overlay: ScannerOverlay


func setup(p: Player, d: BodyPartDef) -> void:
	super.setup(p, d)
	if is_owner() and DisplayServer.get_name() != "headless":
		_night_light = OmniLight3D.new()
		_night_light.omni_range = 12.0
		_night_light.light_energy = 0.6
		_night_light.light_color = Color(0.6, 1.0, 0.7)
		_night_light.shadow_enabled = false
		player.camera.add_child(_night_light)
		_overlay = ScannerOverlay.new()
		add_child(_overlay)


func _exit_tree() -> void:
	if is_instance_valid(_night_light):
		_night_light.queue_free()
	if is_instance_valid(_overlay):
		_overlay.queue_free()


func _process(delta: float) -> void:
	if is_server():
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _night_light == null or not is_owner():
		return
	if player._stagger_timer > 0.0 or player._knock_timer > 0.0:
		_static_left = STATIC_SECONDS
	if _static_left > 0.0:
		_static_left -= delta
		_night_light.visible = false
		_overlay.set_static(true)
	else:
		_night_light.visible = true
		_overlay.set_static(false)


func on_action() -> void:
	send_to_server({})


## Servidor: valida o cooldown, coleta os alvos e responde só ao dono.
func on_server_request(_payload: Dictionary) -> void:
	if not is_server() or player == null or not player.alive:
		return
	if _cooldown_left > 0.0:
		_cooldown_notice.rpc_id(player.peer_id, _cooldown_left)
		return
	_cooldown_left = COOLDOWN
	var origin := player.global_position
	var positions := PackedVector3Array()
	var kinds := PackedInt32Array()
	var main := get_tree().current_scene
	if main != null:
		_collect(main.get("props") as Node, 0, origin, positions, kinds)
		_collect(main.get("monsters") as Node, 1, origin, positions, kinds)
		_collect(main.get("drones") as Node, 2, origin, positions, kinds)
	Game.emit_noise(origin, Game.NOISE_SCANNER_PULSE)
	_reveal.rpc_id(player.peer_id, positions, kinds)


func _collect(container: Node, kind: int, origin: Vector3, positions: PackedVector3Array, kinds: PackedInt32Array) -> void:
	if container == null:
		return
	for child in container.get_children():
		var node := child as Node3D
		if node == null:
			continue
		if kind == 0:
			var prop := node as Prop
			if prop == null or prop.net_value < MIN_PROP_VALUE:
				continue
		if node.global_position.distance_to(origin) > RADIUS:
			continue
		positions.append(node.global_position)
		kinds.append(kind)


@rpc("any_peer", "call_local", "reliable")
func _reveal(positions: PackedVector3Array, kinds: PackedInt32Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if _overlay != null and is_owner():
		_overlay.show_targets(positions, kinds, REVEAL_SECONDS)


@rpc("any_peer", "call_local", "reliable")
func _cooldown_notice(seconds_left: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if player == null or not is_owner():
		return
	player.carry_notice = "Scanner recarregando (%ds)" % ceili(seconds_left)
	player._carry_notice_timer = 1.5
