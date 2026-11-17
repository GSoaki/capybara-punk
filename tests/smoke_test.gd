extends Node
## Teste de integração real entre dois processos headless via ENet.
## Execute com tests/run_smoke.sh. Cada verificação imprime PASS ou FAIL.

var role := ""
var port := 0
var failures := 0

@onready var main: Main = get_parent()


func configure(p_role: String, p_port: int) -> void:
	role = p_role
	port = p_port


func _ready() -> void:
	Settings.player_name = role
	get_tree().create_timer(240.0).timeout.connect(_on_timeout)
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

	# Itens do lobby: já estão no van, podem ser pegos e continuam com o jogador na run.
	check("itens no lobby", main.items.get_child_count() == main.lobby_items.size())
	var lobby_baton: WorldItem = main.items.get_children().filter(func(i: WorldItem) -> bool: return i.def.kind == ItemDef.Kind.BATON)[0]
	me.loadout.try_take(lobby_baton)
	await pause(0.1)
	check("pega item no lobby", me.loadout.has_baton)

	$"../Van/Lever".request_use()
	check("fase RUN", Game.phase == Game.Phase.RUN)
	check("item do lobby segue na run", me.loadout.has_baton)
	me.loadout.server_reset()
	await main.level.navigation_ready
	await get_tree().physics_frame
	print("LAYOUT=", main.level.layout_signature)
	check("navmesh com poligonos", main.level.navigation_mesh.get_polygon_count() > 0)
	check("props gerados", main.props.get_child_count() > 0)
	check("monstro gerado", main.monsters.get_child_count() == 1)
	check("drones gerados", main.drones.get_child_count() == main.drone_count)

	# Monstro precisa encontrar caminho e andar pelo navmesh.
	var monster: Monster = main.monsters.get_child(0)
	check("monstro tem corpo com rig de 6 ossos", monster.rig != null and monster.rig.skeleton.get_bone_count() == 6 and monster.get_leg_count() == 2 and monster.get_arm_count() == 2)
	var monster_arm := monster.server_detach_part(BodyPartDef.Slot.LEFT_ARM, Vector3(0.0, 1.0, 2.0))
	check("destacar membro do monstro gera Prop", monster_arm != null and monster_arm.def is BodyPartDef and monster.get_arm_count() == 1)
	check("reinstalar membro no monstro", monster.server_attach_part_from_prop(monster_arm) and monster.get_arm_count() == 2)
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
	# Só de mirar, o painel já avisa que o objeto exige mais gente.
	var to_rack := rack.global_position - me.head.global_position
	me.rotation.y = atan2(-to_rack.x, -to_rack.z)
	me.head.rotation.x = atan2(to_rack.y, Vector2(to_rack.x, to_rack.z).length())
	var warned := func() -> bool: return main.hud.carry_panel.visible and "precisa de 2 jogadores" in main.hud.carry_status_label.text
	check("HUD: mirar avisa quantos são necessários", await wait_until(warned, 1.0))
	me.rotation.y = 0.0
	me.head.rotation.x = 0.6
	await pause(0.2)
	me.try_grab(rack)
	await pause(1.5)
	check("uma pessoa não ergue rack (dy=%.2f)" % (rack.global_position.y - rack_y), rack.global_position.y < rack_y + 0.3)
	var hud: Control = main.hud
	check("HUD: confirma que segura sozinho", "sozinho" in hud.carry_status(me, rack).text and "falta 1" in hud.carry_status(me, rack).text)
	check("HUD: conta relativa aos jogadores", hud.carry_count_text(rack) == "1 de 2 jogadores segurando")
	check("HUD: painel visível ao segurar", hud.carry_panel.visible and hud.carry_pips.get_child_count() == 2)
	_ready_for_client.rpc("grab_rack")
	check("cliente segura rack", await wait_until(func() -> bool: return rack.holders.has(client_id)))
	check("duas pessoas erguem rack", await wait_until(func() -> bool: return rack.global_position.y > rack_y + 0.4, 5.0))
	var helped := func() -> bool: return rack.net_holder_ids.size() == 2 and "client está ajudando você" in hud.carry_status(me, rack).text
	check("HUD: mostra que o aliado está ajudando", await wait_until(helped, 2.0))
	check("HUD: conta sobe com a ajuda", hud.carry_count_text(rack) == "2 de 2 jogadores segurando")
	check("HUD: força suficiente fica verde", rack.people_missing() == 0 and hud.carry_status(me, rack).color == hud.CARRY_OK)
	me.release_grab(false)
	_ready_for_client.rpc("release_rack")
	await wait_until(func() -> bool: return rack.holders.is_empty())

	# Agarre recusado pelo servidor não pode deixar o jogador achando que está segurando.
	var hold_spot := me.global_position
	me.global_position = Vector3(0.0, 0.1, -40.0)
	await pause(0.1)
	me.try_grab(crate)
	check("agarre longe é recusado e avisado", me.held_prop == null and "perdeu o agarre" in me.carry_notice)
	me.global_position = hold_spot
	await pause(0.1)

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
	var cyber_arm_def: BodyPartDef = load("res://resources/body_parts/forklift_arm.tres")
	var cyber_arm_prop: Prop = main.spawn_prop(cyber_arm_def, Vector3(0.0, 1.2, 2.0), "TestCyberArm")
	check("implante cibernético instalado", me.server_attach_part_from_prop(cyber_arm_prop))
	check("braço cibernético aumenta força para 485", is_equal_approx(me.get_grip_force(), 485.0))
	var cyber_arm_prop2: Prop = main.spawn_prop(cyber_arm_def, Vector3(0.0, 1.2, 2.0), "TestCyberArm2")
	check("segundo implante vai para o outro braço sem substituir o primeiro", me.server_attach_part_from_prop(cyber_arm_prop2))
	check("dois braços cibernéticos somam 620 de força", is_equal_approx(me.get_grip_force(), 620.0))
	var cyber_leg_def: BodyPartDef = load("res://resources/body_parts/pneumatic_leg.tres")
	var cyber_leg_prop1: Prop = main.spawn_prop(cyber_leg_def, Vector3(0.0, 1.2, 2.0), "TestCyberLeg1")
	var cyber_leg_prop2: Prop = main.spawn_prop(cyber_leg_def, Vector3(0.0, 1.2, 2.0), "TestCyberLeg2")
	check("primeira perna booster instala na perna dir", me.server_attach_part_from_prop(cyber_leg_prop1) and me.get_body_part_def(BodyPartDef.Slot.RIGHT_LEG).is_cybernetic)
	check("segunda perna booster instala na perna esq ao invés de substituir", me.server_attach_part_from_prop(cyber_leg_prop2) and me.get_body_part_def(BodyPartDef.Slot.LEFT_LEG).is_cybernetic and me.get_body_part_def(BodyPartDef.Slot.RIGHT_LEG).is_cybernetic)
	me.body_hud_open = true
	await get_tree().process_frame
	await get_tree().process_frame
	check("HUD de membros [I] abre e exibe os 6 slots", main.hud.body_hud_modal.visible and main.hud._body_part_names.size() == 6)
	me.body_hud_open = false
	remote.server_detach_part(BodyPartDef.Slot.LEFT_ARM, Vector3(0.5, 1.0, 2.0))
	remote.server_detach_part(BodyPartDef.Slot.RIGHT_ARM, Vector3(-0.5, 1.0, 2.0))
	check("sem os dois braços não segura prop", not remote.can_hold_props())
	me.set_third_person(true)
	check("camera 3a pessoa ativa visuals e recuo", me.third_person and me.visuals.visible and me.camera.position.z > 0.2)
	me.set_third_person(false)
	check("camera 1a pessoa restaura visao", not me.third_person and not me.visuals.visible and is_zero_approx(me.camera.position.z))
	await test_vital_swap_host(me, remote)
	await test_load_zones_host(me)
	await test_implants_host(me)
	test_implant_pool_host()

	# Voz: frame do cliente chega ao host e gera barulho que o monstro escuta.
	var heard := [0.0]
	Game.noise_emitted.connect(func(_o: Vector3, l: float) -> void: heard[0] = maxf(heard[0], l))
	_ready_for_client.rpc("send_voice")
	check("voz recebida", await wait_until(func() -> bool: return remote.voice_frames_received > 0, 5.0))
	check("voz vira barulho", heard[0] > 0.1)
	await test_drones_host(me)
	await test_weapons_host(me, remote, monster, crate)
	Game.set_enemies_disabled(true)
	await pause(0.1)
	check("opção desativar inimigos remove monstros", Game.enemies_disabled and main.monsters.get_child_count() == 0)
	check("opção desativar inimigos remove drones", main.drones.get_child_count() == 0)
	Game.set_enemies_disabled(false)
	await pause(0.1)
	check("reativar inimigos recria monstro na run", not Game.enemies_disabled and main.monsters.get_child_count() == 1)
	check("reativar inimigos recria drones na run", main.drones.get_child_count() == main.drone_count)

	# Todos mortos encerram a run com falha e voltam ao lobby revividos.
	remote.server_hit(999, Vector3.ZERO)
	me.server_hit(999, Vector3.ZERO)
	check("run encerra sem sobreviventes", Game.phase == Game.Phase.RESULTS)
	check("voltou ao lobby", await wait_until(func() -> bool: return Game.phase == Game.Phase.LOBBY, 10.0))
	check("todos revividos", me.alive and remote.alive and remote.health == 100 and remote.can_hold_props())
	check("props limpos", main.props.get_child_count() == 0)
	check("monstros limpos", main.monsters.get_child_count() == 0)
	check("drones limpos", main.drones.get_child_count() == 0)
	check("itens voltam ao lobby", await wait_until(func() -> bool: return main.items.get_child_count() == main.lobby_items.size()))
	check("inventário zerado ao voltar", not me.loadout.has_revolver and remote.loadout.reserve == 0)

	_ready_for_client.rpc("leave")
	var gone := func() -> bool: return Net.roster.size() == 1 and main.players.get_child_count() == 1
	check("cliente removido ao sair", await wait_until(gone))


func def_item(path: String) -> ItemDef:
	return load("res://resources/items/%s.tres" % path)


## Coloca o jogador em um ponto, olhando para o rumo dado (0 = -Z, PI = +Z), sem velocidade.
func place(player: Player, at: Vector3, yaw: float = 0.0) -> void:
	player.global_position = at
	player.rotation.y = yaw
	player.head.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


func spawn_and_take(player: Player, path: String) -> void:
	var item := main.spawn_item(def_item(path), player.global_position + Vector3(0.6, 0.5, 0.0))
	await pause(0.1)
	player.loadout.try_take(item)
	await pause(0.1)


func horizontal_speed(player: Player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func active_item(kind: ItemDef.Kind) -> WorldItem:
	for item: WorldItem in main.items.get_children():
		if item.net_active and item.def.kind == kind:
			return item
	return null


func test_drones_host(me: Player) -> void:
	var drone: Drone = main.drones.get_child(0)
	var other: Drone = main.drones.get_child(1)
	var start := drone.global_position
	check("drone voa na altitude", absf(drone.global_position.y - drone.hover_height) < 0.3)
	check("drone patrulha", await wait_until(func() -> bool: return drone.global_position.distance_to(start) > 2.0, 15.0))

	# Jogador colado e barulho alto não mudam a rota nem causam dano.
	var route := drone._waypoints
	var goal_before := drone.waypoint_index
	var health_before := me.health
	var noise_at := drone.global_position
	var near := Vector3(noise_at.x + 1.0, 0.1, noise_at.z)
	var chased := false
	for i in 60:
		me.global_position = near
		Game.emit_noise(noise_at, 1.0)
		await get_tree().physics_frame
		# A meta só pode ser a atual ou a próxima do circuito.
		var goal_now := drone.waypoint_index
		chased = chased or (goal_now != goal_before and goal_now != (goal_before + 1) % route.size())
	check("drone ignora jogador e barulho", drone._waypoints == route and not chased)
	check("drone não ataca", me.health == health_before)

	# O circuito fecha: passa por todos os pontos e volta ao primeiro.
	drone.patrol_speed = 40.0
	drone.waypoint_pause = 0.0
	var visited := {}
	var completed := func() -> bool:
		visited[drone.waypoint_index] = true
		return visited.size() == route.size() and drone.waypoint_index == goal_before
	check("circuito fecha", await wait_until(completed, 40.0))
	drone.patrol_speed = 2.5

	# Empurrado para fora da rota, retoma a patrulha.
	drone.server_hit(5, Vector3.RIGHT * 4.0, 0.3)
	check("drone sofre dano", drone.health == drone.max_health - 5)
	await pause(0.5)
	var after_stun := drone.global_position
	check("retoma após ser atingido", await wait_until(func() -> bool: return drone.global_position.distance_to(after_stun) > 1.0, 10.0))

	other.server_hit(999, Vector3.ZERO)
	await pause(0.1)
	check("drone pode ser destruído", main.drones.get_child_count() == main.drone_count - 1)

	# Sai do caminho do resto do teste, que acontece no van.
	drone.set_physics_process(false)
	drone.global_position = Vector3(0.0, 2.0, -60.0)


func test_vital_swap_host(me: Player, remote: Player) -> void:
	# Ruído: raio = min(loudness * 180, 45).
	check("ruído da corrida alcança 10,8 m", is_equal_approx(Game.noise_radius(Game.NOISE_SPRINT), 10.8))
	check("teto da voz alcança 27 m", is_equal_approx(Game.noise_radius(Game.NOISE_VOICE_CAP), 27.0))
	check("sobrecarga da mula alcança 45 m", is_equal_approx(Game.noise_radius(Game.NOISE_MULE_OVERLOAD), 45.0))
	check("tiro 0,5 satura em 45 m", is_equal_approx(Game.noise_radius(0.5), 45.0))

	# Slots vitais protegidos.
	var next_slot := me.get_next_self_detach_slot()
	check("autodestacar nunca escolhe cabeça ou torso", next_slot < 0 or not Player.is_vital_slot(next_slot))
	check("cabeça e torso protegidos em vida", me.is_protected_slot(BodyPartDef.Slot.HEAD) and me.is_protected_slot(BodyPartDef.Slot.TORSO))

	# Troca vital com canalização de 2 s.
	me.velocity = Vector3.ZERO
	var health_before := me.health
	var head_prop: Prop = main.spawn_prop(load("res://resources/body_parts/scanner_head.tres"), me.global_position + Vector3(0.5, 0.5, 0.0), "TestScannerHead")
	check("troca de cabeça inicia canalização", me.server_attach_part_from_prop(head_prop))
	check("cabeça ainda não trocada durante canalização", not me.get_body_part_def(BodyPartDef.Slot.HEAD).resource_path.ends_with("scanner_head.tres"))
	await pause(2.4)
	check("troca vital conclui sem matar", me.alive and me.health == health_before)
	check("cabeça scanner instalada", me.get_body_part_def(BodyPartDef.Slot.HEAD).resource_path.ends_with("scanner_head.tres"))
	var dropped_head := false
	for prop: Prop in main.props.get_children():
		if prop.def is BodyPartDef and prop.def.resource_path.ends_with("organic_head.tres"):
			dropped_head = true
	check("cabeça orgânica antiga vira Prop", dropped_head)

	# Dano durante a canalização cancela a troca.
	me.velocity = Vector3.ZERO
	var torso_prop: Prop = main.spawn_prop(load("res://resources/body_parts/coil_torso.tres"), me.global_position + Vector3(0.5, 0.5, 0.0), "TestCoilTorso")
	check("troca de torso inicia canalização", me.server_attach_part_from_prop(torso_prop))
	await pause(0.5)
	me.server_hit(5, Vector3.ZERO, 0.1)
	await pause(2.0)
	check("dano cancela a troca de torso", not me.get_body_part_def(BodyPartDef.Slot.TORSO).resource_path.ends_with("coil_torso.tres") and me.alive)

	# Limpeza: restaura vida e remove membros soltos para não atrapalhar mira e arremessos.
	me.health = 100
	for prop: Prop in main.props.get_children():
		if prop.def is BodyPartDef:
			prop.queue_free()
	await pause(0.1)


func expected_zone(ratio: float) -> Prop.LoadZone:
	if ratio >= 1.35:
		return Prop.LoadZone.EASY
	if ratio >= 1.02:
		return Prop.LoadZone.STRAIN
	if ratio >= 0.65:
		return Prop.LoadZone.DRAG
	return Prop.LoadZone.IMMOBILE


func drop_loose_parts() -> void:
	for prop: Prop in main.props.get_children():
		if prop.def is BodyPartDef:
			prop.queue_free()


## Instala um membro não vital e descarta o que for ejetado.
func swap_limb(me: Player, def: BodyPartDef, value: int, slot: BodyPartDef.Slot) -> void:
	var ejected := me.server_install_part(def, value, slot)
	if is_instance_valid(ejected):
		ejected.queue_free()


func test_load_zones_host(me: Player) -> void:
	# Zonas e velocidade são funções puras da razão força / peso.
	var masses := [3, 15, 26, 35, 54, 70, 79, 105]
	var forces := [350.0, 700.0, 1050.0, 1400.0]
	var mismatches := 0
	for m: int in masses:
		for f: float in forces:
			var ratio := f / (m * 9.8)
			if Prop.zone_for_ratio(ratio) != expected_zone(ratio):
				mismatches += 1
	check("zona bate com a tabela para todas as massas e forças", mismatches == 0)
	check("26 kg com 350 é EASY", Prop.zone_for_ratio(350.0 / (26 * 9.8)) == Prop.LoadZone.EASY)
	check("35 kg com 350 é STRAIN", Prop.zone_for_ratio(350.0 / (35 * 9.8)) == Prop.LoadZone.STRAIN)
	check("54 kg com 350 é DRAG", Prop.zone_for_ratio(350.0 / (54 * 9.8)) == Prop.LoadZone.DRAG)
	check("70 kg com 350 é IMMOBILE", Prop.zone_for_ratio(350.0 / (70 * 9.8)) == Prop.LoadZone.IMMOBILE)
	check("70 kg com 700 é STRAIN", Prop.zone_for_ratio(700.0 / (70 * 9.8)) == Prop.LoadZone.STRAIN)
	check("79 kg com 700 é DRAG", Prop.zone_for_ratio(700.0 / (79 * 9.8)) == Prop.LoadZone.DRAG)
	check("105 kg com 700 é DRAG", Prop.zone_for_ratio(700.0 / (105 * 9.8)) == Prop.LoadZone.DRAG)
	check("105 kg com 1050 é STRAIN", Prop.zone_for_ratio(1050.0 / (105 * 9.8)) == Prop.LoadZone.STRAIN)
	check("79 kg com 1050 é EASY", Prop.zone_for_ratio(1050.0 / (79 * 9.8)) == Prop.LoadZone.EASY)
	check("velocidade em r=1,35 é 0,75", absf(Prop.speed_mult_for_ratio(1.35) - 0.75) < 0.001)
	check("velocidade em r=1,02 é 0,55", absf(Prop.speed_mult_for_ratio(1.02) - 0.55) < 0.001)
	check("velocidade em r=0,65 é 0,25", absf(Prop.speed_mult_for_ratio(0.65) - 0.25) < 0.001)
	check("velocidade em r=4 é 1,0", is_equal_approx(Prop.speed_mult_for_ratio(4.0), 1.0))
	check("velocidade abaixo de 0,65 é 1,0", is_equal_approx(Prop.speed_mult_for_ratio(0.5), 1.0))

	# Pessoas necessárias: ceil(peso * 1,02 / 350), no mínimo 1.
	var people_ok := true
	var drag_ok := true
	for m: int in [35, 70, 105]:
		var prop: Prop = main.spawn_prop(load("res://resources/props/test/test_%dkg.tres" % m), Vector3(6.0, 0.6, 6.0), "TestPeople%d" % m)
		var expected := maxi(ceili(m * 9.8 * 1.02 / 350.0), 1)
		var got := prop.people_needed()
		print("people_needed %d kg = %d (esperado %d)" % [m, got, expected])
		people_ok = people_ok and got == expected
		drag_ok = drag_ok and prop.get_node_or_null("Drag") is PropDrag
		prop.queue_free()
	check("people_needed segue a fórmula", people_ok)
	check("70 kg exige 2 pessoas e 105 kg exige 3", maxi(ceili(70 * 9.8 * 1.02 / 350.0), 1) == 2 and maxi(ceili(105 * 9.8 * 1.02 / 350.0), 1) == 3)
	check("props do servidor têm nó Drag", drag_ok)
	await pause(0.1)

	# Razão ao vivo: braços orgânicos dão 350 de força, então 54 kg arrasta.
	var left_def := me.get_body_part_def(BodyPartDef.Slot.LEFT_ARM)
	var right_def := me.get_body_part_def(BodyPartDef.Slot.RIGHT_ARM)
	var left_value := int(me.body_part_values.get(BodyPartDef.Slot.LEFT_ARM, -1))
	var right_value := int(me.body_part_values.get(BodyPartDef.Slot.RIGHT_ARM, -1))
	swap_limb(me, load("res://resources/body_parts/organic_left_arm.tres"), -1, BodyPartDef.Slot.LEFT_ARM)
	swap_limb(me, load("res://resources/body_parts/organic_right_arm.tres"), -1, BodyPartDef.Slot.RIGHT_ARM)
	await pause(0.1)
	check("braços orgânicos dão 350 de força", is_equal_approx(me.get_grip_force(), 350.0))
	await place(me, Vector3(0.0, 0.1, 1.0))
	me.head.rotation.x = 0.3
	var heavy: Prop = main.spawn_prop(load("res://resources/props/test/test_54kg.tres"), Vector3(0.0, 0.5, -0.8), "TestLoad54")
	await pause(0.8)
	me.try_grab(heavy)
	var held := await wait_until(func() -> bool: return heavy.holders.has(1), 3.0)
	check("host segura o prop de 54 kg", held)
	await pause(0.3)
	var want := me.get_grip_force() / (54.0 * 9.8)
	check("razão de carga ao vivo (%.3f, esperado %.3f)" % [heavy.net_load_ratio, want], absf(heavy.net_load_ratio - want) < 0.01)
	check("54 kg com 350 é zona DRAG ao vivo", heavy.get_load_zone() == Prop.LoadZone.DRAG)
	check("prop de 54 kg tem nó Drag", heavy.get_node_or_null("Drag") is PropDrag)
	me.release_grab(false)
	await pause(0.2)
	check("prop de 54 kg solto", heavy.holders.is_empty())
	heavy.queue_free()

	# Restaura os braços de antes.
	if left_def:
		swap_limb(me, left_def, left_value, BodyPartDef.Slot.LEFT_ARM)
	if right_def:
		swap_limb(me, right_def, right_value, BodyPartDef.Slot.RIGHT_ARM)
	drop_loose_parts()
	await pause(0.2)


func test_implants_host(me: Player) -> void:
	var slots := [BodyPartDef.Slot.LEFT_ARM, BodyPartDef.Slot.RIGHT_ARM, BodyPartDef.Slot.LEFT_LEG, BodyPartDef.Slot.RIGHT_LEG]
	var saved_defs := {}
	var saved_values := {}
	for slot: BodyPartDef.Slot in slots:
		saved_defs[slot] = me.get_body_part_def(slot)
		saved_values[slot] = int(me.body_part_values.get(slot, -1))
	var organic_left_arm: BodyPartDef = load("res://resources/body_parts/organic_left_arm.tres")
	var organic_right_arm: BodyPartDef = load("res://resources/body_parts/organic_right_arm.tres")
	var organic_left_leg: BodyPartDef = load("res://resources/body_parts/organic_left_leg.tres")
	var organic_right_leg: BodyPartDef = load("res://resources/body_parts/organic_right_leg.tres")
	swap_limb(me, organic_left_arm, -1, BodyPartDef.Slot.LEFT_ARM)
	swap_limb(me, organic_right_arm, -1, BodyPartDef.Slot.RIGHT_ARM)
	swap_limb(me, organic_left_leg, -1, BodyPartDef.Slot.LEFT_LEG)
	swap_limb(me, organic_right_leg, -1, BodyPartDef.Slot.RIGHT_LEG)
	await pause(0.1)
	me.health = 100

	# A cabeça scanner foi instalada pela troca vital anterior.
	if me.get_body_part_def(BodyPartDef.Slot.HEAD).resource_path.ends_with("scanner_head.tres"):
		check("cabeça scanner limita a voz a 0,20", absf(me.implants.voice_cap() - 0.20) < 0.001)
		check("cabeça scanner dá scanner_pulse", me.implants.has_ability(&"scanner_pulse"))

	# Torso de bobina: troca vital canalizada de 2 s.
	check("torso orgânico sem redução de dano", is_equal_approx(me.implants.damage_mult(Game.HitSource.MONSTER), 1.0))
	me.velocity = Vector3.ZERO
	var coil: Prop = main.spawn_prop(load("res://resources/body_parts/coil_torso.tres"), me.global_position + Vector3(0.5, 0.5, 0.0), "TestCoilTorso2")
	check("troca para torso de bobina inicia", me.server_attach_part_from_prop(coil))
	await pause(2.4)
	me.velocity = Vector3.ZERO
	check("torso de bobina instalado sem matar", me.alive and me.get_body_part_def(BodyPartDef.Slot.TORSO).resource_path.ends_with("coil_torso.tres"))
	check("bobina reduz dano de monstro em 25%", absf(me.implants.damage_mult(Game.HitSource.MONSTER) - 0.75) < 0.001)
	check("bobina não reduz dano de queda", is_equal_approx(me.implants.damage_mult(Game.HitSource.FALL), 1.0))
	check("bobina reduz velocidade para 0,9", absf(me.implants.move_speed_mult() - 0.9) < 0.001)
	check("bobina dá coil_discharge", me.implants.has_ability(&"coil_discharge"))
	var organic_torso: Prop = main.spawn_prop(load("res://resources/body_parts/organic_torso.tres"), me.global_position + Vector3(0.5, 0.5, 0.0), "TestOrganicTorso")
	check("volta ao torso orgânico inicia", me.server_attach_part_from_prop(organic_torso))
	await pause(2.4)
	me.velocity = Vector3.ZERO
	check("torso orgânico restaurado", me.alive and me.get_body_part_def(BodyPartDef.Slot.TORSO).resource_path.ends_with("organic_torso.tres"))
	check("sem bobina o dano volta a 1,0", is_equal_approx(me.implants.damage_mult(Game.HitSource.MONSTER), 1.0) and not me.implants.has_ability(&"coil_discharge"))
	drop_loose_parts()

	# Pernas pneumáticas.
	var pneumatic: BodyPartDef = load("res://resources/body_parts/pneumatic_leg.tres")
	var base_fall := me.get_safe_fall_speed()
	swap_limb(me, pneumatic, -1, BodyPartDef.Slot.LEFT_LEG)
	swap_limb(me, pneumatic, -1, BodyPartDef.Slot.RIGHT_LEG)
	await pause(0.1)
	check("pernas pneumáticas: queda segura 16 (base %.1f)" % base_fall, absf(me.get_safe_fall_speed() - 16.0) < 0.1)
	check("pernas pneumáticas dão pneumatic_valve", me.implants.has_ability(&"pneumatic_valve"))
	swap_limb(me, organic_left_leg, -1, BodyPartDef.Slot.LEFT_LEG)
	swap_limb(me, organic_right_leg, -1, BodyPartDef.Slot.RIGHT_LEG)
	await pause(0.1)
	check("pernas orgânicas perdem pneumatic_valve", not me.implants.has_ability(&"pneumatic_valve"))

	# Braço de mula: 650 + 175.
	swap_limb(me, load("res://resources/body_parts/mule_arm.tres"), -1, BodyPartDef.Slot.LEFT_ARM)
	await pause(0.1)
	check("braço de mula soma 825 de força", is_equal_approx(me.get_grip_force(), 825.0))
	check("braço de mula dá mule_overload", me.implants.has_ability(&"mule_overload"))
	swap_limb(me, organic_left_arm, -1, BodyPartDef.Slot.LEFT_ARM)
	await pause(0.1)
	check("sem mula a força volta a 350", is_equal_approx(me.get_grip_force(), 350.0))

	# Lacre: remover implante instalado mantém 75% do valor.
	var forklift: BodyPartDef = load("res://resources/body_parts/forklift_arm.tres")
	swap_limb(me, forklift, 200, BodyPartDef.Slot.RIGHT_ARM)
	var sealed := me.server_detach_part(BodyPartDef.Slot.RIGHT_ARM, me.global_position + Vector3(0.0, 1.0, 2.0))
	check("implante destacado vira Prop", sealed != null and sealed.def == forklift)
	if sealed:
		check("lacre rompido mantém 75%% do valor (%d)" % sealed.net_value, sealed.net_value == 150)
		check("lacre rompido marcado no Prop", sealed.net_seal_broken)
		sealed.queue_free()
	swap_limb(me, organic_right_arm, -1, BodyPartDef.Slot.RIGHT_ARM)

	# Restaura os membros de antes e limpa.
	for slot: BodyPartDef.Slot in slots:
		var def: BodyPartDef = saved_defs[slot]
		if def:
			swap_limb(me, def, saved_values[slot], slot)
	me.health = 100
	me.velocity = Vector3.ZERO
	drop_loose_parts()
	await pause(0.2)


func test_implant_pool_host() -> void:
	var pool: ImplantPool = main.implant_pool
	if pool == null:
		pool = load("res://resources/loot/implant_pool.tres")
	check("pool de implantes carregado", pool != null and not pool.green.is_empty())
	if pool == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var all_valid := true
	var all_green := true
	for i in 200:
		var picked: BodyPartDef = pool.pick(rng)
		all_valid = all_valid and picked != null and picked.is_cybernetic
		var green: BodyPartDef = pool.pick_green(rng)
		all_green = all_green and green != null and green.rarity == BodyPartDef.Rarity.GREEN
	check("200 sorteios do pool são implantes válidos", all_valid)
	check("pick_green sempre devolve raridade verde", all_green)


func test_weapons_host(me: Player, remote: Player, monster: Monster, crate: Prop) -> void:
	var loadout := me.loadout
	check("hudbar tem 5 slots com lanterna no slot 1", loadout.slot_kinds.size() == 5 and loadout.get_slot_kind(0) == ItemDef.Kind.FLASHLIGHT)
	var organic_arm: BodyPartDef = load("res://resources/body_parts/organic_left_arm.tres")
	var cyber_leg: BodyPartDef = load("res://resources/body_parts/pneumatic_leg.tres")
	check("membro orgânico não cabe no inventário", not loadout.can_take(organic_arm) and not loadout.can_store_object(organic_arm))
	check("membro mecânico não cabe no inventário", not loadout.can_take(cyber_leg) and not loadout.can_store_object(cyber_leg))
	check("itens do lobby seguem no van", main.items.get_children().any(func(i: WorldItem) -> bool: return i.global_position.z > 0.0))
	for item: WorldItem in main.items.get_children():
		item.queue_free()
	# Os membros soltos pelo teste do corpo modular bloqueariam a mira e os arremessos.
	for prop: Prop in main.props.get_children():
		if prop.def is BodyPartDef:
			prop.queue_free()
	await pause(0.1)
	monster.global_position = Vector3(0.0, 0.0, -60.0)

	# Pegar do chão equipa o revólver, e munição fica na reserva sem trocar a mão.
	await place(me, Vector3(0.0, 0.1, 1.0), PI)
	var aimed := main.spawn_item(def_item("revolver"), Vector3(0.0, 0.3, 2.5))
	await pause(0.5)
	me.head.rotation.x = atan2(aimed.global_position.y - me.head.global_position.y, aimed.global_position.z - me.head.global_position.z)
	var prompted := func() -> bool: return me.hover_text == aimed.get_prompt()
	check("mirar no item mostra como pegar", await wait_until(prompted, 1.0))
	aimed.queue_free()
	await pause(0.1)
	await spawn_and_take(me, "revolver")
	check("pega revólver", loadout.has_revolver and loadout.loaded == loadout.cylinder_size)
	check("revólver equipado no slot 2", loadout.equipped == ItemDef.Kind.REVOLVER and loadout.active_slot == 1)
	check("item sai do chão", main.items.get_child_count() == 0)
	await spawn_and_take(me, "ammo")
	check("pente de munição ocupa slot e vai para reserva", loadout.get_slot_kind(2) == ItemDef.Kind.AMMO and loadout.reserve == 5 and loadout.equipped == ItemDef.Kind.REVOLVER)

	# Um tiro isolado empurra para trás; olhando para +Z, o recuo é -Z.
	await place(me, Vector3(0.0, 0.1, 1.0), PI)
	loadout.use_primary()
	var single_speed := horizontal_speed(me)
	check("tiro empurra para trás (v=%.1f)" % single_speed, me.velocity.z < -1.5)
	check("primeiro tiro não acumula", loadout.recoil_stack == 1)
	check("tiro gasta munição", loadout.loaded == loadout.cylinder_size - 1)
	await pause(1.2)
	loadout.use_primary()
	check("tiros espaçados não somam", loadout.recoil_stack == 1)
	await pause(1.2)

	# Recarregar não pode ultrapassar o tambor nem o que há na reserva.
	loadout.reload()
	check("recarga em andamento", loadout.reloading)
	check("recarga termina", await wait_until(func() -> bool: return not loadout.reloading, 3.0))
	check("tambor cheio", loadout.loaded == loadout.cylinder_size and loadout.reserve == 3)

	# Atirar rápido soma a força: o quinto tiro seguido derruba e faz a arma escapar.
	await pause(1.2)
	await place(me, Vector3(0.0, 0.1, 1.0), PI)
	me.health = 100
	var peak := 0.0
	var knocked := false
	for i in loadout.cylinder_size:
		loadout.use_primary()
		peak = maxf(peak, horizontal_speed(me))
		knocked = knocked or me.net_knocked
		await pause(loadout.fire_interval + 0.03)
	knocked = knocked or me.net_knocked
	check("força somada (pico=%.1f, um tiro=%.1f)" % [peak, single_speed], peak > single_speed * 2.5)
	check("rajada derruba", knocked)
	check("rajada faz a arma escapar", not loadout.has_revolver and loadout.equipped == ItemDef.Kind.NONE)
	check("arma caída vira item", main.items.get_child_count() == 1)
	await pause(1.5)
	for item: WorldItem in main.items.get_children():
		item.queue_free()
	await pause(0.1)

	# Tiro acerta monstro com pouco dano.
	await place(me, Vector3(0.0, 0.1, 1.0))
	await spawn_and_take(me, "revolver")
	monster.global_position = Vector3(0.0, 0.0, -2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await pause(1.0)
	var health_before := monster.health
	loadout.use_primary()
	check("tiro fere com pouco dano", monster.health == health_before - loadout.shot_damage)

	# Corpo a corpo fere e empurra quem está perto. Atravessar a parede não vale.
	await spawn_and_take(me, "baton")
	loadout.equip(ItemDef.Kind.BATON)
	check("troca para cacetete", loadout.equipped == ItemDef.Kind.BATON)
	monster.global_position = Vector3(0.0, 0.0, -0.3)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await place(me, Vector3(0.0, 0.1, 1.0))
	health_before = monster.health
	loadout.use_primary()
	check("cacetete fere de perto", monster.health == health_before - loadout.melee_damage)
	monster.global_position = Vector3(0.0, 0.0, -60.0)
	await get_tree().physics_frame

	# Arremesso: o corpo acompanha o braço e o cacetete acerta o outro jogador.
	_ready_for_client.rpc("stand_baton")
	await wait_until(func() -> bool: return remote.net_position.distance_to(Vector3(0.0, 0.0, -1.5)) < 0.5)
	await pause(1.6)
	await place(me, Vector3(0.0, 0.1, 2.0))
	var remote_health := remote.health
	loadout.use_secondary()
	check("arremesso puxa o jogador para a frente", me.velocity.z < -2.0)
	check("cacetete sai do inventário", not loadout.has_baton and loadout.equipped == ItemDef.Kind.NONE)
	var baton := active_item(ItemDef.Kind.BATON)
	check("cacetete em voo", baton != null)
	check("cacetete fere outro jogador", await wait_until(func() -> bool: return remote.health < remote_health, 2.0))
	check("cacetete derruba quem acerta", await wait_until(func() -> bool: return remote.net_knocked, 2.0))
	if baton:
		check("cacetete para e pode ser pego", await wait_until(func() -> bool: return baton.can_take(), 10.0))
		baton.queue_free()

	# Rebote: passado o intervalo de imunidade, o cacetete também machuca quem o jogou.
	await pause(1.5)
	await place(me, Vector3(3.0, 0.1, 3.0))
	var my_health := me.health
	main.spawn_item(def_item("baton"), Vector3(3.0, 1.3, -0.5), Vector3(0.0, 1.0, 10.0), true, 1, 1)
	check("rebote fere quem jogou", await wait_until(func() -> bool: return me.health < my_health, 2.0))
	for item: WorldItem in main.items.get_children():
		item.queue_free()
	await pause(0.1)

	# Granada: empurra aliados, inimigos, loot e itens, sem causar dano direto.
	await pause(1.5)
	await place(me, Vector3(0.0, 0.1, 2.0))
	await spawn_and_take(me, "grenade")
	check("granada equipada", loadout.equipped == ItemDef.Kind.GRENADE)
	# Largada, é um item comum: cai no chão, não detona e pode ser pega de novo.
	loadout.drop_equipped()
	await pause(1.0)
	var dropped: WorldItem = main.items.get_children().filter(func(i: WorldItem) -> bool: return i.def.kind == ItemDef.Kind.GRENADE)[0]
	check("granada largada não detona", is_instance_valid(dropped) and dropped.can_take())
	loadout.try_take(dropped)
	await pause(0.2)
	check("granada largada volta à mão", loadout.grenades == 1 and loadout.equipped == ItemDef.Kind.GRENADE)
	await place(me, Vector3(0.0, 0.1, 2.0))
	loadout.use_primary()
	check("granada sai da mão", loadout.grenades == 0 and loadout.equipped == ItemDef.Kind.NONE)
	var thrown := active_item(ItemDef.Kind.GRENADE)
	check("granada arremessada fica ativa", thrown != null and not thrown.can_take())
	var thrown_path := NodePath(String(thrown.name))
	check("granada explode no impacto", await wait_until(func() -> bool: return not main.items.has_node(thrown_path), 2.0))
	await pause(1.6)

	var blast_center := Vector3(0.0, 0.5, 0.0)
	monster.set_physics_process(true)
	monster.global_position = Vector3(2.5, 0.1, 0.0)
	_ready_for_client.rpc("stand_blast")
	await wait_until(func() -> bool: return remote.net_position.distance_to(Vector3(-2.5, 0.0, 0.0)) < 0.5)
	# O jogador sai antes de a caixa chegar: corpos sobrepostos lançam a caixa longe.
	await place(me, Vector3(0.0, 0.1, -2.5))
	crate.global_position = Vector3(0.0, 0.5, 1.5)
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	await pause(0.3)
	var floor_item := main.spawn_item(def_item("ammo"), Vector3(0.0, 0.3, -1.0))
	await pause(0.1)
	var drone: Drone = main.drones.get_child(0)
	drone.global_position = Vector3(1.5, 2.0, 0.5)
	drone.set_physics_process(true)
	var drone_start := drone.global_position
	var armed := main.spawn_item(def_item("grenade"), blast_center, Vector3.DOWN * 6.0, true, 1, 0)
	var monster_x := monster.global_position.x
	var crate_z := crate.global_position.z
	var floor_item_z := floor_item.global_position.z
	var me_z := me.global_position.z
	var remote_x := remote.net_position.x
	var healths := [me.health, remote.health, monster.health]
	await pause(0.5)
	check("granada some ao explodir", not is_instance_valid(armed))
	check("empurra monstro (x=%.1f)" % monster.global_position.x, monster.global_position.x > monster_x + 1.0)
	check("empurra host (z=%.1f)" % me.global_position.z, me.global_position.z < me_z - 1.0)
	check("empurra cliente (x=%.1f)" % remote.net_position.x, await wait_until(func() -> bool: return remote.net_position.x < remote_x - 1.0, 2.0))
	check("empurra loot (z=%.1f)" % crate.global_position.z, crate.global_position.z > crate_z + 0.5)
	check("empurra item", floor_item.global_position.z < floor_item_z - 0.5)
	check("empurra drone", drone.global_position.distance_to(drone_start) > 1.0)
	drone.set_physics_process(false)
	drone.global_position = Vector3(0.0, 2.0, -60.0)
	check("granada não fere direto", monster.health == healths[2])
	check("derruba quem é repelido", me.net_knocked)
	monster.global_position = Vector3(0.0, 0.0, -60.0)
	monster.set_physics_process(false)
	await pause(0.5)
	for item: WorldItem in main.items.get_children():
		item.queue_free()
	await pause(0.1)

	# Corpo modular: sem braços a arma volta ao inventário e não pode ser equipada.
	await spawn_and_take(me, "baton")
	check("cacetete na mão antes de perder os braços", loadout.equipped == ItemDef.Kind.BATON)
	me.server_detach_part(BodyPartDef.Slot.LEFT_ARM, Vector3(3.5, 1.0, 3.0))
	me.server_detach_part(BodyPartDef.Slot.RIGHT_ARM, Vector3(3.5, 1.0, 2.0))
	check("sem braços a arma sai da mão", loadout.equipped == ItemDef.Kind.NONE and loadout.has_baton)
	loadout.equip(ItemDef.Kind.BATON)
	check("sem braços não equipa", loadout.equipped == ItemDef.Kind.NONE)
	me.server_install_part(load("res://resources/body_parts/organic_left_arm.tres"))
	me.server_install_part(load("res://resources/body_parts/organic_right_arm.tres"))
	loadout.server_reset()
	await pause(0.1)

	# Cliente: fluxo completo pela rede, com o servidor decidindo munição.
	remote.server_install_part(load("res://resources/body_parts/organic_left_arm.tres"))
	remote.server_install_part(load("res://resources/body_parts/organic_right_arm.tres"))
	main.spawn_item(def_item("ammo"), Vector3(3.0, 0.3, 2.0))
	main.spawn_item(def_item("revolver"), Vector3(3.8, 0.3, 2.0))
	_ready_for_client.rpc("client_arm")
	var armed_up := func() -> bool: return remote.loadout.has_revolver and remote.loadout.reserve == 5
	check("servidor entrega itens ao cliente", await wait_until(armed_up))
	check("cliente disparou no servidor", await wait_until(func() -> bool: return remote.loadout.loaded == remote.loadout.cylinder_size - 1))
	check("host vê a arma na mão do cliente", await wait_until(func() -> bool: return remote.loadout.net_equipped == ItemDef.Kind.REVOLVER))

	# Morrer solta o que carrega no chão.
	_ready_for_client.rpc("client_done")
	await pause(0.3)
	var count := main.items.get_child_count()
	remote.server_hit(999, Vector3.ZERO)
	check("morto deixa os itens no chão", main.items.get_child_count() >= count + 2)
	check("morto fica sem itens", not remote.loadout.has_revolver and remote.loadout.reserve == 0)


func test_weapons_client(me: Player) -> void:
	await _wait_command("stand_baton")
	me.global_position = Vector3(0.0, 0.1, -1.5)
	me.velocity = Vector3.ZERO
	await _wait_command("stand_blast")
	me.global_position = Vector3(-2.5, 0.1, 0.0)
	me.velocity = Vector3.ZERO
	await _wait_command("client_arm")
	me.global_position = Vector3(3.0, 0.1, 2.0)
	me.velocity = Vector3.ZERO
	await pause(1.6)
	var ground := func() -> Array: return main.items.get_children().filter(func(i: WorldItem) -> bool: return i.def.kind == ItemDef.Kind.AMMO)
	check("cliente vê item no chão", await wait_until(func() -> bool: return not ground.call().is_empty()))
	var ammo: WorldItem = ground.call()[0]
	check("item congelado no cliente", ammo.freeze)
	me.global_position = ammo.net_position + Vector3(0.0, 0.0, 1.0)
	await pause(0.1)
	me.loadout.try_take(ammo)
	check("cliente recebe munição", await wait_until(func() -> bool: return me.loadout.reserve == 5))
	var revolver := func() -> Array: return main.items.get_children().filter(func(i: WorldItem) -> bool: return i.def.kind == ItemDef.Kind.REVOLVER)
	check("cliente vê revólver", await wait_until(func() -> bool: return not revolver.call().is_empty()))
	me.global_position = revolver.call()[0].net_position + Vector3(0.0, 0.0, 1.0)
	await pause(0.1)
	me.loadout.try_take(revolver.call()[0])
	check("cliente equipa revólver", await wait_until(func() -> bool: return me.loadout.equipped == ItemDef.Kind.REVOLVER))
	me.rotation.y = PI
	me.head.rotation.x = 0.0
	await pause(1.0)
	var before := me.velocity
	me.loadout.use_primary()
	check("recuo no cliente é imediato", me.velocity.distance_to(before) > 1.5)
	await _wait_command("client_done")


func run_client() -> void:
	await pause(0.5)
	check("client conecta", Net.join("127.0.0.1", port) == OK)
	check("sessão iniciada", await wait_until(func() -> bool: return Net.in_session, 20.0))
	check("dois players no cliente", await wait_until(func() -> bool: return Game.players.size() == 2))
	var me: Player = Game.local_player()
	check("player local existe", me != null and me.is_local())
	me.global_position = Vector3(2.0, 0.1, 0.0)

	check("cliente vê itens no lobby", await wait_until(func() -> bool: return main.items.get_child_count() >= main.lobby_items.size() - 1))
	check("recebe run", await wait_until(func() -> bool: return Game.phase == Game.Phase.RUN, 20.0))
	check("nível construido", await wait_until(func() -> bool: return not main.level.layout_signature.is_empty()))
	print("LAYOUT=", main.level.layout_signature)
	check("props replicados", await wait_until(func() -> bool: return main.props.get_child_count() > 0))
	check("monstro replicado", await wait_until(func() -> bool: return main.monsters.get_child_count() == 1))
	check("drones replicados", await wait_until(func() -> bool: return main.drones.get_child_count() == main.drone_count))
	var seen_drone: Drone = main.drones.get_child(0)
	var seen_at := seen_drone.net_position
	check("cliente vê drone voar", await wait_until(func() -> bool: return seen_drone.net_position.distance_to(seen_at) > 0.5, 10.0))
	var prop: Prop = main.props.get_child(0)
	check("prop congelado no cliente", prop.freeze)

	await _wait_command("grab_rack")
	var rack: Prop = main.props.get_node("TestRack")
	var hud: Control = main.hud
	check("cliente vê quem já carrega", await wait_until(func() -> bool: return rack.net_holder_ids.size() == 1 and "host está carregando" in hud.carry_status(me, rack).text))
	me.global_position = Vector3(1.2, 0.1, 0.5)
	await pause(0.1)
	var to_rack := rack.net_position - me.head.global_position
	me.rotation.y = atan2(-to_rack.x, -to_rack.z)
	me.head.rotation.x = atan2(to_rack.y, Vector2(to_rack.x, to_rack.z).length())
	check("mirar em carga de aliado oferece ajuda", await wait_until(func() -> bool: return "Ajudar a carregar" in me.hover_text, 1.0))
	me.rotation.y = 0.0
	me.head.rotation.x = 0.6
	await pause(0.2)
	me.try_grab(rack)
	me.net_hold_distance = 1.8
	check("cliente vê agarre pendente", "Agarrando" in hud.carry_status(me, rack).text)
	check("HUD do cliente: está ajudando", await wait_until(func() -> bool: return "Você está ajudando host" in hud.carry_status(me, rack).text))

	await _wait_command("release_rack")
	me.release_grab(false)
	check("HUD do cliente: deixou de ajudar", await wait_until(func() -> bool: return not rack.net_holder_ids.has(me.peer_id)))
	check("cliente ve valor coletado", await wait_until(func() -> bool: return Game.collected > 0, 8.0))
	check("cliente ve caixa mover", main.props.get_node("TestCrate").net_position.z < 0.0)

	await _wait_command("send_voice")
	var samples := PackedFloat32Array()
	for i in 640:
		samples.append(sin(i * 0.3) * 0.5)
	for i in 5:
		me.send_voice(VoiceCodec.encode(samples))
		await pause(0.04)
	await test_weapons_client(me)

	check("cliente volta ao lobby", await wait_until(func() -> bool: return Game.phase == Game.Phase.LOBBY, 15.0))
	check("cliente revivido", await wait_until(func() -> bool: return me.alive and me.health == 100))
	check("cliente sem props", await wait_until(func() -> bool: return main.props.get_child_count() == 0))
	check("cliente sem drones", await wait_until(func() -> bool: return main.drones.get_child_count() == 0))
	check("cliente vê itens de volta no lobby", await wait_until(func() -> bool: return main.items.get_child_count() == main.lobby_items.size()))
	check("cliente sem armas", await wait_until(func() -> bool: return not me.loadout.has_revolver and me.loadout.equipped == ItemDef.Kind.NONE))
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
