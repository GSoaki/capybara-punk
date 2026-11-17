class_name CoilDischarge
extends ImplantAbility
## Implante 4: descarga elétrica em área. Dispara quando um monstro acerta o
## jogador ou quando a energia se esgota. Recarga compartilhada entre gatilhos.

## Recarga entre descargas, em segundos (compartilhada pelos dois gatilhos).
const COOLDOWN := 12.0
## Raio da descarga em metros (distância 3D a partir do jogador).
const RADIUS := 3.0
## Dano causado a cada monstro no raio.
const MONSTER_DAMAGE := 20
## Atordoamento aplicado aos monstros, em segundos.
const MONSTER_STUN := 2.2
## Dano causado a cada drone no raio.
const DRONE_DAMAGE := 15
## Atordoamento aplicado aos drones, em segundos.
const DRONE_STUN := 4.0
## Atordoamento aplicado a aliados no raio (sem dano), em segundos.
const ALLY_STUN := 1.2

## Instante (ms) da última descarga no servidor; -1 se nunca disparou. Usado em testes.
var last_discharge_msec := -1


## SERVIDOR: dispara quando um monstro acerta o portador.
func on_hit(source: Game.HitSource, _damage: int) -> void:
	if not is_server():
		return
	if source == Game.HitSource.MONSTER:
		_try_discharge()


## DONO: energia esgotada pede a descarga ao servidor.
func on_exhausted() -> void:
	send_to_server({"kind": "overload"})


## SERVIDOR: pedido validado vindo do dono.
func on_server_request(payload: Dictionary) -> void:
	if not is_server():
		return
	if payload.get("kind", "") == "overload":
		_try_discharge()


func _try_discharge() -> void:
	if player == null or not player.alive:
		return
	var now := Time.get_ticks_msec()
	if last_discharge_msec >= 0 and now - last_discharge_msec < int(COOLDOWN * 1000.0):
		return
	last_discharge_msec = now
	_discharge()


func _discharge() -> void:
	var origin := player.global_position
	var scene := get_tree().current_scene
	if scene != null:
		var monsters = scene.get("monsters")
		if monsters is Node3D:
			for child in (monsters as Node3D).get_children():
				var m := child as Monster
				if m != null and _in_range(origin, m.global_position):
					m.server_hit(MONSTER_DAMAGE, _away(origin, m.global_position) * 4.0 + Vector3.UP * 2.0, MONSTER_STUN, Game.HitSource.DISCHARGE)
		var drones = scene.get("drones")
		if drones is Node3D:
			for child in (drones as Node3D).get_children():
				var d := child as Drone
				if d != null and _in_range(origin, d.global_position):
					d.server_hit(DRONE_DAMAGE, _away(origin, d.global_position) * 2.0, DRONE_STUN, Game.HitSource.DISCHARGE)
	for other in Game.players.values():
		var p := other as Player
		if p == null or p == player or not p.alive:
			continue
		if _in_range(origin, p.global_position):
			p.server_hit(0, _away(origin, p.global_position) * 4.0 + Vector3.UP * 2.0, ALLY_STUN, Game.HitSource.DISCHARGE)
	Game.emit_noise(origin, Game.NOISE_COIL_DISCHARGE)
	_flash.rpc()


func _in_range(origin: Vector3, target: Vector3) -> bool:
	return origin.distance_to(target) <= RADIUS


## Direção horizontal do jogador para o alvo; Vector3.FORWARD se coincidirem.
func _away(origin: Vector3, target: Vector3) -> Vector3:
	var dir := target - origin
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()


## Clarão visual em todos os pares. Só o servidor (id 1) ou a chamada local (id 0) é aceito.
@rpc("any_peer", "call_local", "reliable")
func _flash() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if DisplayServer.get_name() == "headless" or player == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 0.9, 1.0)
	light.light_energy = 6.0
	light.omni_range = 4.0
	light.position = Vector3(0.0, 1.2, 0.0)
	player.add_child(light)
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	tween.tween_callback(light.queue_free)
