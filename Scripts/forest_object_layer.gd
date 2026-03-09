extends Node2D

## 在森林格上放置树木对象，森林地表本身保持接近草地颜色。

@export var terrain_generator: TerrainGenerator
@export var forest_step := 3
@export_range(0.0, 1.0, 0.01) var temperate_density := 0.40
@export_range(0.0, 1.0, 0.01) var tropical_density := 0.55


func _ready() -> void:
	if terrain_generator == null:
		terrain_generator = get_parent().get_node_or_null("TerrainMap") as TerrainGenerator
	if terrain_generator == null:
		return

	terrain_generator.generation_completed.connect(_rebuild_forest_objects)
	if terrain_generator.is_node_ready():
		_rebuild_forest_objects(terrain_generator.get_last_generation_report())


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


func _rebuild_forest_objects(_report: Dictionary) -> void:
	if terrain_generator == null:
		return
	_clear_children()

	var half := terrain_generator.get_map_half_extent()
	if half <= 0:
		return

	for x in range(-half, half, forest_step):
		for y in range(-half, half, forest_step):
			var cell := Vector2i(x, y)
			var terrain_id := terrain_generator.get_terrain_at_cell(cell)
			if terrain_id != TerrainGenerator.Terrain.TEMPERATE_FOREST and terrain_id != TerrainGenerator.Terrain.TROPICAL_FOREST:
				continue

			var density := temperate_density if terrain_id == TerrainGenerator.Terrain.TEMPERATE_FOREST else tropical_density
			if randf() > density:
				continue

			var obj := ForestStandObject.new()
			obj.cell = cell
			obj.terrain_id = terrain_id
			obj.position = terrain_generator.map_to_local(cell) + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
			obj.scale_factor = randf_range(0.85, 1.20)
			obj.tropical_mix = 1.0 if terrain_id == TerrainGenerator.Terrain.TROPICAL_FOREST else 0.0
			add_child(obj)
