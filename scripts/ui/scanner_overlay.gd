class_name ScannerOverlay
extends CanvasLayer
## Marcadores 2D dos alvos revelados pelo scanner e estática de interferência.

const COLORS := [Color("FFB300"), Color(1.0, 0.2, 0.2), Color(0.2, 0.9, 1.0)]
const LABELS := ["$", "!", "D"]

var _positions := PackedVector3Array()
var _kinds := PackedInt32Array()
var _time_left := 0.0
var _static_on := false
var _canvas: Control
var _static_rect: ColorRect


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_canvas_draw)
	add_child(_canvas)
	_static_rect = ColorRect.new()
	_static_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static_rect.color = Color(0.5, 0.5, 0.5, 0.25)
	_static_rect.visible = false
	add_child(_static_rect)


func show_targets(positions: PackedVector3Array, kinds: PackedInt32Array, seconds: float) -> void:
	_positions = positions
	_kinds = kinds
	_time_left = seconds


func set_static(on: bool) -> void:
	_static_on = on
	if _static_rect != null:
		_static_rect.visible = on


func _process(delta: float) -> void:
	if _time_left > 0.0:
		_time_left -= delta
		_canvas.queue_redraw()
		if _time_left <= 0.0:
			_positions = PackedVector3Array()
			_kinds = PackedInt32Array()
	if _static_on:
		_static_rect.color.a = randf_range(0.15, 0.35)


func _on_canvas_draw() -> void:
	if _time_left <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var font := ThemeDB.fallback_font
	for i in _positions.size():
		var p := _positions[i]
		if camera.is_position_behind(p):
			continue
		var kind := clampi(_kinds[i], 0, 2)
		var screen := camera.unproject_position(p)
		var color: Color = COLORS[kind]
		_canvas.draw_arc(screen, 14.0, 0.0, TAU, 32, color, 2.0)
		_canvas.draw_string(font, screen + Vector2(-4.0, 5.0), LABELS[kind], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, color)
