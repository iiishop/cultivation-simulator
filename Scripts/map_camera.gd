extends Node

## 地图相机控制：鼠标滚轮缩放、中键/右键拖拽平移，右上角显示当前格子的地形信息
## 兼容 TileMapLayer（文档：Node2D.to_local + TileMapLayer.local_to_map）

@export var camera: Camera2D
@export var tile_map: TileMapLayer
@export var tile_info_label: Label

const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15
const PAN_SPEED := 1.0

var _dragging := false
var _last_drag_pos := Vector2.ZERO


func _ready() -> void:
	if not camera:
		camera = get_viewport().get_camera_2d()
	if not tile_map:
		tile_map = get_parent().get_node_or_null("TerrainMap")
	if not tile_info_label:
		tile_info_label = get_parent().get_node_or_null("UI/TileInfo")
	if tile_info_label:
		tile_info_label.text = "—"


func _input(event: InputEvent) -> void:
	if not camera:
		return
	# 滚轮缩放（以视口中心或鼠标位置为基准）
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


func _process(_delta: float) -> void:
	_update_tile_info()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var vp := get_viewport()
	var vp_center := vp.get_visible_rect().get_center()
	var zoom_val := camera.zoom.x
	var world_at_point := camera.position + (screen_pos - vp_center) / zoom_val
	var new_zoom_val := clampf(zoom_val * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2.ONE * new_zoom_val
	camera.position = world_at_point - (screen_pos - vp_center) / new_zoom_val


func _update_tile_info() -> void:
	if not tile_map or not tile_info_label:
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var global_mouse := viewport.get_mouse_position()
	# 文档：local_to_map 若传入全局坐标，先用 Node2D.to_local 再传
	var world_pos: Vector2 = viewport.get_canvas_transform().affine_inverse() * global_mouse
	var local_pos: Vector2 = tile_map.to_local(world_pos)
	var cell := tile_map.local_to_map(local_pos)

	var terrain_name := "—"
	var height_str := "—"
	if tile_map.has_method("get_terrain_at_cell"):
		var terrain_id: int = tile_map.get_terrain_at_cell(cell)
		if tile_map.has_method("get_terrain_name"):
			terrain_name = tile_map.get_terrain_name(terrain_id)
		elif terrain_id >= 0:
			terrain_name = "地形 %d" % terrain_id
		if tile_map.has_method("get_height_meters_at_cell"):
			var h_m: float = tile_map.get_height_meters_at_cell(cell)
			height_str = "%d m" % int(snappedf(h_m, 1.0))
		elif tile_map.has_method("get_heightv"):
			var h: float = tile_map.get_heightv(Vector2(cell))
			height_str = str(snappedf(h, 0.01))
	else:
		var sid := tile_map.get_cell_source_id(cell)
		if sid >= 0:
			terrain_name = "格子 %d" % sid

	tile_info_label.text = "格子: %d, %d\n地形: %s\n高度: %s" % [cell.x, cell.y, terrain_name, height_str]
