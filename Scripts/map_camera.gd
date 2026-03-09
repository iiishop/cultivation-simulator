extends Node

## 相机控制：鼠标滚轮缩放，中键/右键拖拽平移

@export var camera: Camera2D

const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15

var _dragging := false
var _last_drag_pos := Vector2.ZERO


func _ready() -> void:
	if not camera:
		camera = get_viewport().get_camera_2d()


func _input(event: InputEvent) -> void:
	if not camera:
		return
	# 滚轮缩放（以视口中心为基准）
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(get_viewport().get_visible_rect().get_center(), ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(get_viewport().get_visible_rect().get_center(), 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_dragging = true
				_last_drag_pos = event.position
			else:
				_dragging = false
	if event is InputEventMouseMotion and _dragging:
		var delta: Vector2 = event.position - _last_drag_pos
		_last_drag_pos = event.position
		camera.position -= delta / camera.zoom
		get_viewport().set_input_as_handled()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var vp := get_viewport()
	var vp_center := vp.get_visible_rect().get_center()
	var zoom_val := camera.zoom.x
	var world_at_point := camera.position + (screen_pos - vp_center) / zoom_val
	var new_zoom_val := clampf(zoom_val * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2.ONE * new_zoom_val
	camera.position = world_at_point - (screen_pos - vp_center) / new_zoom_val
