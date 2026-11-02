class_name Main
extends Node3D
## Cena única da sessão. Instancia jogadores, loot e monstros pelos MultiplayerSpawner
## e reage as transições do autoload Game. Trocar de cena aqui quebraria os caminhos de RPC.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PROP_SCENE := preload("res://scenes/prop.tscn")
const MONSTER_SCENE := preload("res://scenes/monster.tscn")
const ITEM_SCENE := preload("res://scenes/item.tscn")
const DRONE_SCENE := preload("res://scenes/drone.tscn")

@export var loot_table: Array[PropDef] = []
@export var monster_count := 1
@export var drone_count := 2
## Salas em cada circuito de drone.
@export var drone_patrol_length := 4
## Colocados em fila no van ao abrir a sessão e de novo a cada fim de run.
@export var lobby_items: Array[ItemDef] = []
## Sorteados nas salas durante a run.
@export var item_table: Array[ItemDef] = []

var _next_id := 0

@onready var players: Node3D = $Players
@onready var props: Node3D = $Props
@onready var monsters: Node3D = $Monsters
@onready var items: Node3D = $Items
@onready var drones: Node3D = $Drones
@onready var weapon_fx: WeaponFx = $WeaponFx
@onready var level: LevelGenerator = $Level
@onready var menu_camera: Camera3D = $MenuCamera
@onready var gate: CSGBox3D = $Van/Gate
@onready var spawn_points: Node3D = $Van/SpawnPoints
@onready var lobby_item_spot: Marker3D = $Van/LobbyItemSpot
@onready var main_menu: Control = $UI/MainMenu
@onready var hud: Control = $UI/HUD
@onready var pause_menu: Control = $UI/PauseMenu


func _ready() -> void:
	$PlayerSpawner.spawn_function = _spawn_player
	$PropSpawner.spawn_function = _spawn_prop
	$MonsterSpawner.spawn_function = _spawn_monster
	$ItemSpawner.spawn_function = _spawn_item
	$DroneSpawner.spawn_function = _spawn_drone
	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Game.run_started.connect(_on_run_started)
	Game.run_ended.connect(_on_run_ended)
	_apply_command_line()


func _unhandled_input(event: InputEvent) -> void:
	if Net.in_session and event.is_action_pressed("pause"):
		pause_menu.visible = not pause_menu.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_menu.visible else Input.MOUSE_MODE_CAPTURED


## Atalhos para testes: --host, --join=IP, --name=X, --port=N, --smoke=host|client
func _apply_command_line() -> void:
	var args: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if args.has("name"):
		Settings.player_name = args.name
	var port := int(args.get("port", Net.DEFAULT_PORT))
	if args.has("smoke"):
		var test: Node = load("res://tests/smoke_test.gd").new()
		test.name = "SmokeTest"
		test.configure(args.smoke, port)
		add_child(test)
	elif args.has("host"):
		Net.host(port)
	elif args.has("join"):
		Net.join(args.join if not args.join.is_empty() else "127.0.0.1", port)


func spawn_point(index: int) -> Vector3:
	return spawn_points.get_child(index % spawn_points.get_child_count()).global_position


func spawn_prop(def: PropDef, at: Vector3, node_name: String = "", custom_value: int = -1) -> Prop:
	_next_id += 1
	var value := custom_value if custom_value >= 0 else randi_range(def.min_value, def.max_value)
	return $PropSpawner.spawn({
		"def": def.resource_path,
		"name": node_name if not node_name.is_empty() else "Prop%d" % _next_id,
		"value": value,
		"pos": at,
	})


## Servidor. Com amount negativo, usa a quantidade padrão do tipo de item.
func spawn_item(def: ItemDef, at: Vector3, velocity := Vector3.ZERO, active := false, amount := -1, thrower := 0) -> WorldItem:
	_next_id += 1
	return $ItemSpawner.spawn({
		"def": def.resource_path,
		"name": "Item%d" % _next_id,
		"amount": amount if amount >= 0 else def.amount,
		"pos": at,
		"velocity": velocity,
		"active": active,
		"thrower": thrower,
	})


func _spawn_player(data: Dictionary) -> Node:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(data.id)
	player.position = data.pos
	return player


func _spawn_prop(data: Dictionary) -> Node:
	var prop: Prop = PROP_SCENE.instantiate()
	prop.setup(data)
	return prop


func _spawn_monster(data: Dictionary) -> Node:
	var monster: Monster = MONSTER_SCENE.instantiate()
	monster.setup(data)
	return monster


func _spawn_item(data: Dictionary) -> Node:
	var item: WorldItem = ITEM_SCENE.instantiate()
	item.setup(data)
	return item


func _spawn_drone(data: Dictionary) -> Node:
	var drone: Drone = DRONE_SCENE.instantiate()
	drone.setup(data)
	return drone


func _on_player_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		$PlayerSpawner.spawn({"id": peer_id, "pos": spawn_point(players.get_child_count())})


func _on_player_left(peer_id: int) -> void:
	var player := players.get_node_or_null(str(peer_id))
	if player:
		if multiplayer.is_server():
			player.loadout.server_drop_all()
		player.free()
		Game.check_all_dead()


func _on_session_started() -> void:
	main_menu.hide()
	hud.show()
	if multiplayer.is_server():
		_spawn_lobby_items()


func _on_session_ended(reason: String) -> void:
	for container: Node in [players, props, monsters, items, drones]:
		for child in container.get_children():
			child.free()
	level.clear()
	gate.use_collision = true
	gate.show()
	menu_camera.make_current()
	hud.hide()
	pause_menu.hide()
	main_menu.show()
	main_menu.show_status(reason)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_run_started(level_seed: int) -> void:
	gate.use_collision = false
	gate.hide()
	level.generate(level_seed)
	if not multiplayer.is_server():
		return
	await level.navigation_ready
	if Game.phase != Game.Phase.RUN:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var weights := PackedFloat32Array()
	for def in loot_table:
		weights.append(def.spawn_weight)
	for spot in level.prop_spots:
		spawn_prop(loot_table[rng.rand_weighted(weights)], spot)
	_spawn_run_items(rng)
	for i in monster_count:
		_next_id += 1
		$MonsterSpawner.spawn({"name": "Monster%d" % _next_id, "pos": level.monster_spot})
	_spawn_drones()


func _spawn_lobby_items() -> void:
	for i in lobby_items.size():
		var offset := (i - (lobby_items.size() - 1) * 0.5) * 0.9
		spawn_item(lobby_items[i], lobby_item_spot.global_position + Vector3.RIGHT * offset)


func _spawn_drones() -> void:
	for i in drone_count:
		var rooms := level.patrol_spots.duplicate()
		rooms.shuffle()
		_next_id += 1
		$DroneSpawner.spawn({
			"name": "Drone%d" % _next_id,
			"waypoints": PackedVector3Array(rooms.slice(0, drone_patrol_length)),
		})


func _spawn_run_items(rng: RandomNumberGenerator) -> void:
	var weights := PackedFloat32Array()
	for def in item_table:
		weights.append(def.spawn_weight)
	for spot in level.item_spots:
		spawn_item(item_table[rng.rand_weighted(weights)], spot)


func _on_run_ended(_success: bool) -> void:
	gate.use_collision = true
	gate.show()
	level.clear()
	if not multiplayer.is_server():
		return
	for container: Node in [props, monsters, items, drones]:
		for child in container.get_children():
			child.queue_free()
	_spawn_lobby_items()
	var index := 0
	for player: Player in Game.players.values():
		player.server_revive(spawn_point(index))
		index += 1
