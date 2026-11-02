class_name LevelGenerator
extends NavigationRegion3D
## Gera um labirinto de salas a partir de uma seed. Todos os peers constroem a mesma
## geometria; apenas o servidor assa o navmesh e usa os pontos de spawn.
## Para usar salas modeladas, substitua _build_room por instancias de PackedScene.

signal navigation_ready

const ROOM_SIZE := 12.0
const ROOM_HEIGHT := 3.5
const WALL := 0.3
const DOOR_WIDTH := 2.4
const DOOR_HEIGHT := 2.5
const FACILITY_START_Z := -5.0
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

@export var columns := 5
@export var rows := 4
@export_range(0.0, 1.0) var extra_door_chance := 0.2

var prop_spots: Array[Vector3] = []
var item_spots: Array[Vector3] = []
## Logo depois do portão do van, na primeira sala.
var entry_spot := Vector3.ZERO
var monster_spot := Vector3.ZERO
var layout_signature := ""

var _openings: Dictionary = {}
var _entry := Vector2i.ZERO


func _ready() -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	# Exclui o topo do teto, que tambem seria uma superficie caminhável.
	mesh.filter_baking_aabb = AABB(Vector3(-500.0, -1.0, -500.0), Vector3(1000.0, 3.0, 1000.0))
	navigation_mesh = mesh


func generate(level_seed: int) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	_entry = Vector2i(columns / 2, 0)
	var last_cell := _carve_maze(rng)
	_add_extra_doors(rng)
	var palette: Array[StandardMaterial3D] = []
	for i in 4:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(rng.randf(), 0.12, rng.randf_range(0.3, 0.5))
		palette.append(material)
	layout_signature = ""
	for y in rows:
		for x in columns:
			var cell := Vector2i(x, y)
			_build_room(cell, palette[rng.randi() % palette.size()], rng)
			for dir in DIRECTIONS:
				layout_signature += "1" if _is_open(cell, dir) else "0"
	monster_spot = _cell_center(last_cell) + Vector3.UP
	entry_spot = _cell_center(_entry) + Vector3(0.0, 0.4, 3.0)
	if multiplayer.is_server():
		bake_finished.connect(func() -> void: navigation_ready.emit(), CONNECT_ONE_SHOT)
		bake_navigation_mesh(true)


func clear() -> void:
	for child in get_children():
		child.queue_free()
	prop_spots.clear()
	item_spots.clear()
	_openings.clear()
	layout_signature = ""
	if navigation_mesh:
		navigation_mesh.clear_polygons()


func _carve_maze(rng: RandomNumberGenerator) -> Vector2i:
	var visited: Dictionary = {_entry: true}
	var stack: Array[Vector2i] = [_entry]
	var deepest := _entry
	var deepest_len := 0
	while not stack.is_empty():
		var cell: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for dir in DIRECTIONS:
			var next := cell + dir
			if _in_bounds(next) and not visited.has(next):
				options.append(dir)
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen := options[rng.randi() % options.size()]
		_open(cell, chosen)
		visited[cell + chosen] = true
		stack.append(cell + chosen)
		if stack.size() > deepest_len:
			deepest_len = stack.size()
			deepest = cell + chosen
	return deepest


func _add_extra_doors(rng: RandomNumberGenerator) -> void:
	for y in rows:
		for x in columns:
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var cell := Vector2i(x, y)
				if _in_bounds(cell + dir) and rng.randf() < extra_door_chance:
					_open(cell, dir)


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows


func _edge_key(cell: Vector2i, dir: Vector2i) -> Vector4i:
	var other := cell + dir
	if cell.x < other.x or cell.y < other.y:
		return Vector4i(cell.x, cell.y, other.x, other.y)
	return Vector4i(other.x, other.y, cell.x, cell.y)


func _open(cell: Vector2i, dir: Vector2i) -> void:
	_openings[_edge_key(cell, dir)] = true


func _is_open(cell: Vector2i, dir: Vector2i) -> bool:
	if cell == _entry and dir == Vector2i.UP:
		return true
	return _openings.has(_edge_key(cell, dir))


func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3(
		(cell.x - _entry.x) * ROOM_SIZE,
		0.0,
		FACILITY_START_Z - (cell.y + 0.5) * ROOM_SIZE
	)


func _build_room(cell: Vector2i, material: Material, rng: RandomNumberGenerator) -> void:
	var center := _cell_center(cell)
	_add_box(center + Vector3.DOWN * 0.15, Vector3(ROOM_SIZE, 0.3, ROOM_SIZE), material)
	_add_box(center + Vector3.UP * (ROOM_HEIGHT + 0.15), Vector3(ROOM_SIZE, 0.3, ROOM_SIZE), material)
	# Cada aresta e construida uma vez: norte e oeste sempre, sul e leste apenas na borda.
	_build_edge(cell, Vector2i.UP, material)
	_build_edge(cell, Vector2i.LEFT, material)
	if cell.y == rows - 1:
		_build_edge(cell, Vector2i.DOWN, material)
	if cell.x == columns - 1:
		_build_edge(cell, Vector2i.RIGHT, material)
	if cell != _entry and rng.randf() < 0.3:
		var pillar := Vector3(rng.randf_range(-2.5, 2.5), ROOM_HEIGHT * 0.5, rng.randf_range(-2.5, 2.5))
		_add_box(center + pillar, Vector3(1.2, ROOM_HEIGHT, 1.2), material)
	if rng.randf() < 0.5:
		var lamp := OmniLight3D.new()
		lamp.position = center + Vector3.UP * (ROOM_HEIGHT - 0.4)
		lamp.omni_range = 9.0
		lamp.light_energy = 0.7
		lamp.light_color = Color(1.0, 0.85, 0.65)
		add_child(lamp)
	if cell != _entry:
		if rng.randf() < 0.6:
			item_spots.append(center + Vector3(rng.randf_range(-5.0, -3.2) * (1 if rng.randf() < 0.5 else -1), 0.4, rng.randf_range(-4.5, 4.5)))
		for i in rng.randi_range(1, 3):
			prop_spots.append(center + Vector3(rng.randf_range(-5.0, -3.2) * (1 if rng.randf() < 0.5 else -1), 1.2, rng.randf_range(-4.5, 4.5)))


func _build_edge(cell: Vector2i, dir: Vector2i, material: Material) -> void:
	var half := ROOM_SIZE * 0.5
	var along_x := dir.y != 0
	# Grid usa y crescente para o fundo da instalacao, que e -Z no mundo.
	var offset := Vector3(dir.x * half, 0.0, -dir.y * half)
	var base := _cell_center(cell) + offset
	var tall := Vector3(ROOM_SIZE, ROOM_HEIGHT, WALL) if along_x else Vector3(WALL, ROOM_HEIGHT, ROOM_SIZE)
	if not _is_open(cell, dir):
		_add_box(base + Vector3.UP * ROOM_HEIGHT * 0.5, tall, material)
		return
	var side := (ROOM_SIZE - DOOR_WIDTH) * 0.5
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	for sign_value: float in [-1.0, 1.0]:
		var size := Vector3(side, ROOM_HEIGHT, WALL) if along_x else Vector3(WALL, ROOM_HEIGHT, side)
		var shift := axis * sign_value * (DOOR_WIDTH + side) * 0.5
		_add_box(base + shift + Vector3.UP * ROOM_HEIGHT * 0.5, size, material)
	var lintel := ROOM_HEIGHT - DOOR_HEIGHT
	var lintel_size := Vector3(DOOR_WIDTH, lintel, WALL) if along_x else Vector3(WALL, lintel, DOOR_WIDTH)
	_add_box(base + Vector3.UP * (DOOR_HEIGHT + lintel * 0.5), lintel_size, material)


func _add_box(at: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)
