extends TileMapLayer

## 与 terrain_generator.gd 相同，使用 TileMapLayer 替代已弃用 TileMap（兼容旧场景引用）

var noise: FastNoiseLite

enum Terrain {
	DEEP_OCEAN,
	OCEAN,
	GRASSLAND,
	DESERT,
	TEMPERATE_FOREST,
	TROPICAL_FOREST,
	SNOW
}

const SOURCE_ID = 0
const TERRAIN_NAMES := [
	"深海", "海洋", "草原", "沙漠", "温带森林", "热带森林", "雪地"
]

var _size := 512
const TILE_SIZE := 16

func _ready() -> void:
	if tile_set == null or tile_set.get_source_count() == 0:
		tile_set = _create_placeholder_tileset()
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 1.0 / 32.0
	noise.fractal_octaves = 4
	print("[Generator]: 地形生成器启动 (TileMapLayer)")
	generate(_size)


func _create_placeholder_tileset() -> TileSet:
	var ts := TileSet.new()
	var atlas := TileSetAtlasSource.new()
	var img := Image.create(7 * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var colors := [
		Color(0.1, 0.15, 0.5),   # 深海
		Color(0.2, 0.35, 0.7),   # 海洋
		Color(0.3, 0.65, 0.2),   # 草原
		Color(0.9, 0.75, 0.3),   # 沙漠
		Color(0.2, 0.5, 0.25),   # 温带森林
		Color(0.1, 0.6, 0.2),    # 热带森林
		Color(0.95, 0.95, 1.0),  # 雪地
	]
	for i in 7:
		for px in range(i * TILE_SIZE, (i + 1) * TILE_SIZE):
			for py in range(TILE_SIZE):
				img.set_pixel(px, py, colors[i])
	var tex := ImageTexture.create_from_image(img)
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i in 7:
		atlas.create_tile(Vector2i(i, 0))
	ts.add_source(atlas, SOURCE_ID)
	return ts


func heat(pos: Vector2) -> float:
	return absf(pos.y / (0.5 * _size))


func falloff_value(pos: Vector2) -> float:
	var v := maxf(absf(pos.x) / (0.5 * _size), absf(pos.y) / (0.5 * _size))
	return evaluate(v)


func evaluate(x: float) -> float:
	const A := 3.0
	const B := 2.2
	return pow(x, A) / (pow(x, A) + pow(B - B * x, A))


func get_heightv(pos: Vector2) -> float:
	return noise.get_noise_2d(pos.x, pos.y) - falloff_value(pos)


func generate_land() -> void:
	print("[Generator]: 开始生成陆地")
	var total := _size * _size
	var i := 0
	var half := _size / 2

	for x in range(-half, half):
		for y in range(-half, half):
			var pos := Vector2(x, y)
			var h := get_heightv(pos)
			var t := heat(pos)
			var coords := Vector2i(x, y)

			if h >= -0.5 and h <= -0.25:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.OCEAN, 0), 0)
			elif h <= -0.5:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.DEEP_OCEAN, 0), 0)
			elif h >= 0.4:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.SNOW, 0), 0)
			elif h >= -0.25 and h <= 0.4:
				if (h + 0.3) * t < 0.05:
					set_cell(coords, SOURCE_ID, Vector2i(Terrain.DESERT, 0), 0)
				else:
					set_cell(coords, SOURCE_ID, Vector2i(Terrain.GRASSLAND, 0), 0)
			else:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.GRASSLAND, 0), 0)

			i += 1
			if i % 8192 == 0:
				print("[Generator]: ", snappedf(float(i) / total * 100.0, 0.1), "%")

	print("[Generator]: 陆地生成完成")


func get_terrain_at_cell(coords: Vector2i) -> int:
	var sid := get_cell_source_id(coords)
	if sid < 0:
		return -1
	var atlas := get_cell_atlas_coords(coords)
	return atlas.x


func get_terrain_name(terrain_id: int) -> String:
	if terrain_id < 0 or terrain_id >= TERRAIN_NAMES.size():
		return "—"
	return TERRAIN_NAMES[terrain_id]


func is_water_cell(coords: Vector2i) -> bool:
	var t := get_terrain_at_cell(coords)
	return t == Terrain.DEEP_OCEAN or t == Terrain.OCEAN


func get_closest_lower_cell(cell_p: Vector2i) -> Vector2:
	var dirs := [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]
	var best_dir := Vector2i.ZERO
	var min_h := get_heightv(Vector2(cell_p))

	for d in dirs:
		var p := Vector2(cell_p + d)
		var h := get_heightv(p)
		if h < min_h:
			min_h = h
			best_dir = d
	return Vector2(best_dir)


func create_pond(river: Array) -> void:
	for i in river.size():
		var r := pow(i / 32.0, 2.0)
		var center: Vector2 = river[i]
		var half_r := int(r * 0.5)
		for ox in range(-half_r, half_r + 1):
			for oy in range(-half_r, half_r + 1):
				var c := Vector2i(int(center.x) + ox, int(center.y) + oy)
				if get_terrain_at_cell(c) >= 0:
					set_cell(c, SOURCE_ID, Vector2i(Terrain.OCEAN, 0), 0)


func generate_river(start_x: int, start_y: int) -> void:
	var river: Array[Vector2] = []
	var cell_p := Vector2i(start_x, start_y)
	print("[Generator]: 河流起点 x:", start_x, " y:", start_y)

	while true:
		var direction := get_closest_lower_cell(cell_p)
		if direction == Vector2.ZERO:
			break
		var next := cell_p + Vector2i(int(direction.x), int(direction.y))
		if is_water_cell(next):
			break
		cell_p = next
		river.append(Vector2(cell_p))
		set_cell(cell_p, SOURCE_ID, Vector2i(Terrain.OCEAN, 0), 0)
		create_pond(river)

	print("[Generator]: 河流长度 ", river.size())


func generate(size: int) -> void:
	_size = size
	generate_land()
	var half := size / 2
	var river_count := randi() % 15 + 5
	for _i in river_count:
		var x := randi_range(-half, half - 1)
		var y := randi_range(-half, half - 1)
		if is_water_cell(Vector2i(x, y)):
			continue
		generate_river(x, y)
	update_internals()
