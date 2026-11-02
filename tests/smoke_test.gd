extends Node
## Teste de integração real entre dois processos headless via ENet.
## Execute com tests/run_smoke.sh. Cada verificação imprime PASS ou FAIL.

var role := ""
var port := 0
var failures := 0

@onready var main: Node = get_parent()


func configure(p_role: String, p_port: int) -> void:
	role = p_role
	port = p_port


func _ready() -> void:
	Settings.player_name = role
	get_tree().create_timer(150.0).timeout.connect(_on_timeout)
	test_codec()
	if role == "host":
		await run_host()
	else:
		await run_client()
	print("DONE role=%s failures=%d" % [role, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _on_timeout() -> void:
	print("FAIL timeout role=", role)
	get_tree().quit(2)


func check(label: String, ok: bool) -> void:
	print("%s [%s] %s" % ["PASS" if ok else "FAIL", role, label])
	if not ok:
		failures += 1


func wait_until(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false


func pause(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func test_codec() -> void:
	var samples := PackedFloat32Array()
	for i in 640:
		samples.append(sin(i * 0.1) * 0.4)
	var decoded := VoiceCodec.decode(VoiceCodec.encode(samples))
	var worst := 0.0
	for i in samples.size():
		worst = maxf(worst, absf(samples[i] - decoded[i]))
	check("codec roundtrip erro=%.4f" % worst, decoded.size() == 640 and worst < 0.02)


func run_host() -> void:
	check("host abre porta", Net.host(port) == OK)
	check("cliente entra no roster", await wait_until(func() -> bool: return Net.roster.size() == 2, 20.0))
	check("dois players no host", await wait_until(func() -> bool: return Game.players.size() == 2))
	var client_id: int = Net.roster.keys().filter(func(id: int) -> bool: return id != 1)[0]
	var remote: Player = Game.players[client_id]
	var me: Player = Game.players[1]
	check("nome replicado", Net.roster[client_id].name == "client")

	# O cliente se move para uma posição combinada; o host precisa enxergar.
	var reached := func() -> bool: return remote.global_position.distance_to(Vector3(2.0, 0.0, 0.0)) < 0.5
	check("posição do cliente replicada", await wait_until(reached))

	$"../Van/Lever".request_use()
	check("fase RUN", Game.phase == Game.Phase.RUN)
	await main.level.navigation_ready
	await get_tree().physics_frame
	print("LAYOUT=", main.level.layout_signature)
	check("navmesh com poligonos", main.level.navigation_mesh.get_polygon_count() > 0)
	check("props gerados", main.props.get_child_count() > 0)
	check("monstro gerado", main.monsters.get_child_count() == 1)

	# Monstro precisa encontrar caminho e andar pelo navmesh.
	var monster: Monster = main.monsters.get_child(0)
	var monster_start := monster.global_position
	me.global_position = Vector3(0.0, 0.1, 3.0)
	var walked := func() -> bool: return monster.global_position.distance_to(monster_start) > 2.0
	check("monstro anda", await wait_until(walked, 15.0))
	main.monsters.get_child(0).set_physics_process(false)

	# Carregar: objeto leve sobe com uma pessoa, pesado exige duas.
	var rack_def: PropDef = load("res://resources/props/server_rack.tres")
	var rack: Prop = main.spawn_prop(rack_def, Vector3(0.0, 0.85, 0.5), "TestRack")
	var crate: Prop = main.spawn_prop(load("res://resources/props/crate.tres"), Vector3(-3.0, 0.4, -1.5), "TestCrate")
	await pause(1.0)
	me.global_position = Vector3(-3.0, 0.1, 0.5)
	await pause(0.3)
	var crate_y := crate.global_position.y
	me.head.rotation.x = 0.3
	me.try_grab(crate)
	await pause(0.1)
	check("host agarra caixa", crate.holders.has(1))
	check("caixa sobe", await wait_until(func() -> bool: return crate.global_position.y > crate_y + 0.5, 4.0))
	me.release_grab(false)
	await pause(0.1)
	check("caixa solta", crate.holders.is_empty())

	me.global_position = Vector3(-1.2, 0.1, 0.5)
	me.head.rotation.x = 0.6
	await pause(0.2)
	var rack_y := rack.global_position.y
	me.try_grab(rack)
	await pause(1.5)
	check("uma pessoa não ergue rack (dy=%.2f)" % (rack.global_position.y - rack_y), rack.global_position.y < rack_y + 0.3)
	_ready_for_client.rpc("grab_rack")
	check("cliente segura rack", await wait_until(func() -> bool: return rack.holders.has(client_id)))
	check("duas pessoas erguem rack", await wait_until(func() -> bool: return rack.global_position.y > rack_y + 0.4, 5.0))
	me.release_grab(false)
	_ready_for_client.rpc("release_rack")
	await wait_until(func() -> bool: return rack.holders.is_empty())

	# Extração: objeto dentro da zona conta para a quota e o cliente recebe o total.
	crate.global_position = Vector3(-1.5, 0.5, -1.5)
	crate.linear_velocity = Vector3.ZERO
	rack.global_position = Vector3(1.5, 0.9, -1.5)
	rack.linear_velocity = Vector3.ZERO
	var tallied := func() -> bool: return Game.collected > 0 and Game.collected == crate.net_value + rack.net_value
	check("zona soma valor", await wait_until(tallied, 5.0))

	# Impacto forte reduz valor.
	var vase: Prop = main.spawn_prop(load("res://resources/props/vase.tres"), Vector3(3.5, 2.8, 2.5))
	var vase_value := vase.net_value
	await pause(1.2)
	vase.global_position = Vector3(3.5, 2.6, 2.5)
	vase.sleeping = false
	vase.linear_velocity = Vector3(0.0, -12.0, 0.0)
	var damaged := func() -> bool: return not is_instance_valid(vase) or vase.net_value < vase_value
	check("impacto reduz valor", await wait_until(damaged, 3.0))

	# Dano do servidor chega ao dono com knockback e ativa ragdoll na rig.
	check("rig com 6 ossos criada", me.rig != null and me.rig.skeleton.get_bone_count() == 6)
	remote.server_hit(20, Vector3(0.0, 4.0, 6.0))
	check("cliente derrubado em ragdoll", await wait_until(func() -> bool: return remote.net_knocked and remote.rig.is_ragdoll, 4.0))

	# Modularidade do corpo: destacar membro gera Prop físico e implantar membro altera atributos.
	check("força inicial com 2 braços = 350", is_equal_approx(me.get_grip_force(), 350.0))
	var detached_arm := me.server_detach_part(BodyPartDef.Slot.LEFT_ARM, Vector3(0.0, 1.0, 2.0))
	check("braço destacado vira Prop", detached_arm != null and detached_arm.def is BodyPartDef)
	check("sem braço esq reduz força para 175", is_equal_approx(me.get_grip_force(), 175.0))
	var cyber_arm_def: BodyPartDef = load("res://resources/body_parts/cyber_left_arm.tres")
	var cyber_arm_prop: Prop = main.spawn_prop(cyber_arm_def, Vector3(0.0, 1.2, 2.0), "TestCyberArm")
	check("implante cibernético instalado", me.server_attach_part_from_prop(cyber_arm_prop))
	check("braço cibernético aumenta força para 455", is_equal_approx(me.get_grip_force(), 455.0))
	remote.server_detach_part(BodyPartDef.Slot.LEFT_ARM, Vector3(0.5, 1.0, 2.0))
	remote.server_detach_part(BodyPartDef.Slot.RIGHT_ARM, Vector3(-0.5, 1.0, 2.0))
	check("sem os dois braços não segura prop", not remote.can_hold_props())
	me.set_third_person(true)
	check("camera 3a pessoa ativa visuals e recuo", me.third_person and me.visuals.visible and me.camera.position.z > 0.2)
	me.set_third_person(false)
	check("camera 1a pessoa restaura visao", not me.third_person and not me.visuals.visible and is_zero_approx(me.camera.position.z))

	# Voz: frame do cliente chega ao host e gera barulho que o monstro escuta.
	var heard := [0.0]
	Game.noise_emitted.connect(func(_o: Vector3, l: float) -> void: heard[0] = maxf(heard[0], l))
	_ready_for_client.rpc("send_voice")
	check("voz recebida", await wait_until(func() -> bool: return remote.voice_frames_received > 0, 5.0))
	check("voz vira barulho", heard[0] > 0.1)
	main.monsters.get_child(0).set_physics_process(true)

	# Todos mortos encerram a run com falha e voltam ao lobby revividos.
	me.server_hit(999, Vector3.ZERO)
	remote.server_hit(999, Vector3.ZERO)
	check("run encerra sem sobreviventes", Game.phase == Game.Phase.RESULTS)
	check("voltou ao lobby", await wait_until(func() -> bool: return Game.phase == Game.Phase.LOBBY, 10.0))
	check("todos revividos", me.alive and remote.alive and remote.health == 100 and remote.can_hold_props())
	check("props limpos", main.props.get_child_count() == 0)
	check("monstros limpos", main.monsters.get_child_count() == 0)

	_ready_for_client.rpc("leave")
	var gone := func() -> bool: return Net.roster.size() == 1 and main.players.get_child_count() == 1
	check("cliente removido ao sair", await wait_until(gone))


func run_client() -> void:
	await pause(0.5)
	check("client conecta", Net.join("127.0.0.1", port) == OK)
	check("sessão iniciada", await wait_until(func() -> bool: return Net.in_session, 20.0))
	check("dois players no cliente", await wait_until(func() -> bool: return Game.players.size() == 2))
	var me: Player = Game.local_player()
	check("player local existe", me != null and me.is_local())
	me.global_position = Vector3(2.0, 0.1, 0.0)

	check("recebe run", await wait_until(func() -> bool: return Game.phase == Game.Phase.RUN, 20.0))
	check("nível construido", await wait_until(func() -> bool: return not main.level.layout_signature.is_empty()))
	print("LAYOUT=", main.level.layout_signature)
	check("props replicados", await wait_until(func() -> bool: return main.props.get_child_count() > 0))
	check("monstro replicado", await wait_until(func() -> bool: return main.monsters.get_child_count() == 1))
	var prop: Prop = main.props.get_child(0)
	check("prop congelado no cliente", prop.freeze)

	await _wait_command("grab_rack")
	var rack: Prop = main.props.get_node("TestRack")
	me.global_position = Vector3(1.2, 0.1, 0.5)
	me.head.rotation.x = 0.6
	await pause(0.3)
	me.try_grab(rack)
	me.net_hold_distance = 1.8

	await _wait_command("release_rack")
	me.release_grab(false)
	check("cliente ve valor coletado", await wait_until(func() -> bool: return Game.collected > 0, 8.0))
	check("cliente ve caixa mover", main.props.get_node("TestCrate").net_position.z < 0.0)

	await _wait_command("send_voice")
	var samples := PackedFloat32Array()
	for i in 640:
		samples.append(sin(i * 0.3) * 0.5)
	for i in 5:
		me.send_voice(VoiceCodec.encode(samples))
		await pause(0.04)

	check("cliente volta ao lobby", await wait_until(func() -> bool: return Game.phase == Game.Phase.LOBBY, 15.0))
	check("cliente revivido", await wait_until(func() -> bool: return me.alive and me.health == 100))
	check("cliente sem props", await wait_until(func() -> bool: return main.props.get_child_count() == 0))
	check("nível limpo", main.level.layout_signature.is_empty())

	await _wait_command("leave")
	Net.leave("fim do teste")
	check("cliente offline", not Net.in_session and Game.players.is_empty())
	await pause(0.5)


var _commands: Array[String] = []


func _wait_command(command: String) -> void:
	await wait_until(func() -> bool: return command in _commands, 60.0)
	check("comando " + command, command in _commands)


@rpc("authority", "call_remote", "reliable")
func _ready_for_client(command: String) -> void:
	_commands.append(command)
