class_name WeaponFx
extends Node3D
## Efeitos visuais das armas. Fica na cena main porque sobrevive ao item que os dispara.

const TRACER_COLOR := Color(1.0, 0.85, 0.45)
const HIT_COLOR := Color(1.0, 0.25, 0.15)
const BLAST_COLOR := Color(0.3, 0.95, 0.85)


@rpc("authority", "call_local", "unreliable")
func shot(from: Vector3, to: Vector3, hit_entity: bool) -> void:
	if DisplayServer.get_name() == "headless" or from.is_equal_approx(to):
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, from.distance_to(to))
	var tracer := _spawn_mesh(mesh, TRACER_COLOR, (from + to) * 0.5)
	var up := Vector3.RIGHT if absf((to - from).normalized().y) > 0.99 else Vector3.UP
	tracer.look_at(to, up)
	_fade(tracer, 0.08)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.06
	spark_mesh.height = 0.12
	_fade(_spawn_mesh(spark_mesh, HIT_COLOR if hit_entity else TRACER_COLOR, to), 0.2)
	_flash(from, TRACER_COLOR, 1.5, 0.08)


@rpc("authority", "call_local", "reliable")
func blast(center: Vector3, radius: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mesh := SphereMesh.new()
	var sphere := _spawn_mesh(mesh, BLAST_COLOR, center)
	sphere.scale = Vector3.ONE * 0.3
	var tween := sphere.create_tween()
	tween.tween_property(sphere, "scale", Vector3.ONE * radius * 2.0, 0.3).set_ease(Tween.EASE_OUT)
	_fade(sphere, 0.3)
	_flash(center, BLAST_COLOR, 5.0, 0.3)


func _spawn_mesh(mesh: PrimitiveMesh, color: Color, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	instance.global_position = at
	return instance


func _fade(instance: MeshInstance3D, seconds: float) -> void:
	var tween := instance.create_tween()
	tween.tween_property(instance.mesh.material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(instance.queue_free)


func _flash(at: Vector3, color: Color, energy: float, seconds: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 9.0
	add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, seconds)
	tween.tween_callback(light.queue_free)
