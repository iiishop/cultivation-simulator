extends Node2D

## 按地形与海拔生成一张低分辨率颜色贴图，再拉伸覆盖到地图上，增强高低起伏感。

@export var terrain_generator: TerrainGenerator
@export_range(0.0, 1.0, 0.01) var land_shade_strength := 0.52
@export_range(0.0, 1.0, 0.01) var ocean_shade_strength := 0.52
@export_range(0.0, 1.0, 0.01) var mountain_shade_strength := 0.42
@export_range(0.0, 1.0, 0.01) var desert_shade_strength := 0.50
@export_range(0.0, 1.0, 0.01) var snow_shade_strength := 0.70
@export_range(0.0, 4.0, 0.05) var hillshade_strength := 2.25
@export_range(0.0, 1.0, 0.01) var hillshade_shadow_strength := 0.52
@export_range(0.0, 1.0, 0.01) var hillshade_highlight_strength := 0.24
@export_range(0.0, 4.0, 0.05) var snow_hillshade_boost := 2.9
@export_range(0.0, 1.0, 0.01) var snow_ridge_strength := 0.38
@export_range(0.5, 2.5, 0.01) var overlay_alpha_boost := 1.25

var _texture: ImageTexture
var _draw_rect := Rect2()


func _ready() -> void:
	if terrain_generator == null:
		terrain_generator = get_parent().get_node_or_null("TerrainMap") as TerrainGenerator
	if terrain_generator == null:
		return

	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	terrain_generator.generation_completed.connect(_rebuild_overlay)
	if terrain_generator.is_node_ready():
		_rebuild_overlay(terrain_generator.get_last_generation_report())


func _rebuild_overlay(_report: Dictionary) -> void:
	if terrain_generator == null:
		return

	var half := terrain_generator.get_map_half_extent()
	var size := terrain_generator.get_map_size()
	if half <= 0 or size <= 0:
		return

	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(-half, half):
		for x in range(-half, half):
			var cell := Vector2i(x, y)
			var terrain_id := terrain_generator.get_terrain_at_cell(cell)
			var raw_h := terrain_generator.get_height_raw_at_cell(cell)
			image.set_pixel(x + half, y + half, _color_for_cell(cell, terrain_id, raw_h))

	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)

	var top_left_cell := Vector2i(-half, -half)
	var top_left_center := terrain_generator.map_to_local(top_left_cell)
	var next_x_center := terrain_generator.map_to_local(Vector2i(-half + 1, -half))
	var next_y_center := terrain_generator.map_to_local(Vector2i(-half, -half + 1))
	var cell_w := absf(next_x_center.x - top_left_center.x)
	var cell_h := absf(next_y_center.y - top_left_center.y)
	if is_zero_approx(cell_w):
		cell_w = 16.0
	if is_zero_approx(cell_h):
		cell_h = 16.0

	var top_left := top_left_center - Vector2(cell_w, cell_h) * 0.5
	_draw_rect = Rect2(top_left, Vector2(size * cell_w, size * cell_h))
	queue_redraw()


func _hillshade(cell: Vector2i, terrain_id: int) -> float:
	var h_nw := terrain_generator.get_height_raw_at_cell(cell + Vector2i(-1, -1))
	var h_n := terrain_generator.get_height_raw_at_cell(cell + Vector2i(0, -1))
	var h_ne := terrain_generator.get_height_raw_at_cell(cell + Vector2i(1, -1))
	var h_w := terrain_generator.get_height_raw_at_cell(cell + Vector2i(-1, 0))
	var h_e := terrain_generator.get_height_raw_at_cell(cell + Vector2i(1, 0))
	var h_sw := terrain_generator.get_height_raw_at_cell(cell + Vector2i(-1, 1))
	var h_s := terrain_generator.get_height_raw_at_cell(cell + Vector2i(0, 1))
	var h_se := terrain_generator.get_height_raw_at_cell(cell + Vector2i(1, 1))

	var terrain_boost := snow_hillshade_boost if terrain_id == TerrainGenerator.Terrain.SNOW else 1.0
	var dzdx := ((h_ne + 2.0 * h_e + h_se) - (h_nw + 2.0 * h_w + h_sw)) * 0.25 * hillshade_strength * terrain_boost
	var dzdy := ((h_sw + 2.0 * h_s + h_se) - (h_nw + 2.0 * h_n + h_ne)) * 0.25 * hillshade_strength * terrain_boost

	var normal := Vector3(-dzdx, -dzdy, 1.0).normalized()
	var light_dir := Vector3(-0.55, -0.35, 0.76).normalized()
	return clampf(normal.dot(light_dir), 0.0, 1.0)


func _snow_ridge_tint(cell: Vector2i) -> float:
	var center := terrain_generator.get_height_raw_at_cell(cell)
	var highest_neighbor := center
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		highest_neighbor = maxf(highest_neighbor, terrain_generator.get_height_raw_at_cell(cell + offset))
	return clampf((center - highest_neighbor + 0.05) / 0.05, 0.0, 1.0)


func _apply_hillshade(base: Color, hill: float, terrain_id: int) -> Color:
	var lit := hill - 0.5
	if lit > 0.0:
		var highlight_t := pow(lit * 2.0, 1.12) * hillshade_highlight_strength
		var highlight_color := Color(1.0, 1.0, 0.96, base.a)
		if terrain_id == TerrainGenerator.Terrain.DESERT:
			highlight_color = Color(1.0, 0.92, 0.66, base.a)
		if terrain_id == TerrainGenerator.Terrain.SNOW:
			highlight_color = Color(1.0, 1.0, 1.0, base.a)
		return base.lerp(highlight_color, clampf(highlight_t, 0.0, 1.0))

	var shadow_t := pow((0.5 - hill) * 2.0, 1.10) * hillshade_shadow_strength
	var shadow_color := Color(0.02, 0.05, 0.10, min(0.82, base.a + 0.08))
	if terrain_id == TerrainGenerator.Terrain.DESERT:
		shadow_color = Color(0.24, 0.15, 0.04, min(0.86, base.a + 0.12))
	if terrain_id == TerrainGenerator.Terrain.SNOW:
		shadow_color = Color(0.28, 0.37, 0.52, min(0.93, base.a + 0.18))
	return base.lerp(shadow_color, clampf(shadow_t, 0.0, 1.0))


func _color_for_cell(cell: Vector2i, terrain_id: int, raw_h: float) -> Color:
	var base_color := Color(0, 0, 0, 0)
	match terrain_id:
		TerrainGenerator.Terrain.DEEP_OCEAN:
			var deep_t := clampf((raw_h + 0.55) / 0.30, 0.0, 1.0)
			base_color = Color(0.01, 0.03, 0.10 + deep_t * 0.10, 0.56)
		TerrainGenerator.Terrain.OCEAN:
			var ocean_t := clampf((raw_h + 0.50) / 0.25, 0.0, 1.0)
			base_color = Color(0.08 + ocean_t * 0.16, 0.14 + ocean_t * 0.16, 0.26 + ocean_t * 0.22, ocean_shade_strength)
		TerrainGenerator.Terrain.GRASSLAND, TerrainGenerator.Terrain.TEMPERATE_FOREST, TerrainGenerator.Terrain.TROPICAL_FOREST:
			var land_t := clampf((raw_h - TerrainGenerator.SEA_LEVEL_RAW) / (0.4 - TerrainGenerator.SEA_LEVEL_RAW), 0.0, 1.0)
			base_color = Color(0.20 + land_t * 0.18, 0.16 + land_t * 0.14, 0.05, land_shade_strength)
		TerrainGenerator.Terrain.DESERT:
			var desert_t := clampf((raw_h - TerrainGenerator.SEA_LEVEL_RAW) / (0.4 - TerrainGenerator.SEA_LEVEL_RAW), 0.0, 1.0)
			base_color = Color(0.42 + desert_t * 0.20, 0.30 + desert_t * 0.16, 0.05 + desert_t * 0.05, desert_shade_strength)
		TerrainGenerator.Terrain.SNOW:
			var snow_t := clampf((raw_h - 0.20) / 0.30, 0.0, 1.0)
			base_color = Color(0.52 + snow_t * 0.20, 0.60 + snow_t * 0.22, 0.74 + snow_t * 0.20, snow_shade_strength)
		_:
			return Color(0, 0, 0, 0)

	var hill := _hillshade(cell, terrain_id)
	var shaded := _apply_hillshade(base_color, hill, terrain_id)
	if terrain_id == TerrainGenerator.Terrain.SNOW:
		var ridge_t := _snow_ridge_tint(cell) * snow_ridge_strength
		shaded = shaded.lerp(Color(1.0, 1.0, 1.0, shaded.a), ridge_t)
		var cold_shadow := clampf((0.58 - hill) * 1.45, 0.0, 1.0)
		shaded = shaded.lerp(Color(0.26, 0.34, 0.48, min(0.94, shaded.a + 0.16)), cold_shadow * 0.36)

	shaded.a = clampf(shaded.a * overlay_alpha_boost, 0.0, 0.95)
	return shaded


func _draw() -> void:
	if _texture == null:
		return
	draw_texture_rect(_texture, _draw_rect, false)
