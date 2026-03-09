extends Node

## 鼠标悬停格子信息显示：地形名称与高度

@export var tile_map: TerrainGenerator
@export var tile_info_label: Label

var _last_cell := Vector2i(2147483647, 2147483647)


func _ready() -> void:
	if not tile_map:
		tile_map = get_parent().get_node_or_null("TerrainMap") as TerrainGenerator
	if not tile_info_label:
		tile_info_label = get_parent().get_node_or_null("UI/TileInfo")
	if tile_info_label:
		tile_info_label.text = "—"


func _process(_delta: float) -> void:
	if tile_map == null or tile_info_label == null:
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	var global_mouse := viewport.get_mouse_position()
	var world_pos: Vector2 = viewport.get_canvas_transform().affine_inverse() * global_mouse
	var local_pos: Vector2 = tile_map.to_local(world_pos)
	var cell: Vector2i = tile_map.local_to_map(local_pos)

	if cell == _last_cell:
		return
	_last_cell = cell

	var terrain_id: int = tile_map.get_terrain_at_cell(cell)
	var terrain_name := tile_map.get_terrain_name(terrain_id)
	var h_m: float = tile_map.get_height_meters_at_cell(cell)
	var height_str := "%d m" % int(snappedf(h_m, 1.0))

	tile_info_label.text = "格子: %d, %d\n地形: %s\n高度: %s" % [cell.x, cell.y, terrain_name, height_str]
