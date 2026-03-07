extends TileMapLayer

## 地形生成器：带偏向与故事性的地图（大陆轮廓、圣山、干旱带、边陲感）
## 使用 TileMapLayer（Godot 4.x 推荐），替代已弃用的 TileMap

var noise: FastNoiseLite
var noise_continent: FastNoiseLite  # 大陆轮廓，低频大块
var noise_dry: FastNoiseLite       # 干旱带分布
var noise_ridge: FastNoiseLite    # 脊状噪声，形成山脉轮廓
var noise_chain: FastNoiseLite    # 低频方向性，决定山链走向与分布
var _story_peak_center: Vector2   # 圣山/世界中心
var _story_dry_center: Vector2    # 干旱带中心（沙漠叙事）

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

## 第一层：基础地表（仅沙漠/草原），森林不在此表
## [温度带][湿度带] -> 沙漠 或 草原
const BASE_BIOME_TABLE := [
	[Terrain.GRASSLAND, Terrain.GRASSLAND, Terrain.GRASSLAND],   # 冷
	[Terrain.GRASSLAND, Terrain.GRASSLAND, Terrain.GRASSLAND],   # 凉
	[Terrain.DESERT, Terrain.GRASSLAND, Terrain.GRASSLAND],      # 暖
	[Terrain.DESERT, Terrain.GRASSLAND, Terrain.GRASSLAND],      # 热
]

## 第二层：森林覆盖率阈值 + 扰动幅度（破直线边界）
const FOREST_COVER_THRESHOLD := 0.48
const FOREST_THRESHOLD_NOISE := 0.09
## 第三层：温带/热带过渡带中心与扰动（连续过渡，不硬切）
const FOREST_TROPICAL_CENTER := 0.55
const FOREST_TYPE_NOISE := 0.14

var _size := 512
const TILE_SIZE := 16

## 高度米制：海平面 = 陆地/海洋分界（raw -0.25），陆地显示 ≥ 0 m
## raw -0.5 → 约 -1500 m（深海），-0.25 → 0 m（海岸），0.4 → 4000 m（雪线），1 → 约 7700 m
const SEA_LEVEL_RAW := -0.25
const METERS_PER_RAW_UNIT := 4000.0 / (0.4 - SEA_LEVEL_RAW)

## 湿度扩散：海岸高湿向内陆衰减（距离单位：格）
const COASTAL_DECAY_SCALE := 28.0
## 雨影：风向（风从西向东吹，背风侧=东侧变干）
const RAIN_SHADOW_RAY_STEPS := 55
const RAIN_SHADOW_HEIGHT_RAW := 0.1
const RAIN_SHADOW_FACTOR := 0.38

## 山链：脊状噪声强度；方向性采样缩放（形成连续山脉）
const RIDGE_STRENGTH := 0.26
const RIDGE_FREQ := 1.0 / 44.0
const CHAIN_FREQ := 1.0 / 95.0

func _ready() -> void:
	if tile_set == null or tile_set.get_source_count() == 0:
		tile_set = _create_placeholder_tileset()
	var seed_val := randi()
	noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 1.0 / 32.0
	noise.fractal_octaves = 4
	noise_continent = FastNoiseLite.new()
	noise_continent.seed = seed_val + 1
	noise_continent.frequency = 1.0 / 80.0
	noise_continent.fractal_octaves = 2
	noise_dry = FastNoiseLite.new()
	noise_dry.seed = seed_val + 2
	noise_dry.frequency = 1.0 / 100.0
	noise_dry.fractal_octaves = 1
	# 脊状噪声：山脉轮廓
	noise_ridge = FastNoiseLite.new()
	noise_ridge.seed = seed_val + 10
	noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_ridge.frequency = RIDGE_FREQ
	noise_ridge.fractal_octaves = 4
	noise_ridge.fractal_lacunarity = 2.2
	noise_ridge.fractal_gain = 0.5
	# 低频方向性：山链走向与分布
	noise_chain = FastNoiseLite.new()
	noise_chain.seed = seed_val + 11
	noise_chain.frequency = CHAIN_FREQ
	noise_chain.fractal_octaves = 2
	print("[Generator]: 地形生成器启动 (TileMapLayer, 故事性地图)")
	generate(_size)


func _create_placeholder_tileset() -> TileSet:
	var ts := TileSet.new()
	var atlas := TileSetAtlasSource.new()
	var colors := [
		Color(0.1, 0.15, 0.5),   # 深海
		Color(0.2, 0.35, 0.7),   # 海洋
		Color(0.3, 0.65, 0.2),   # 草原
		Color(0.9, 0.75, 0.3),   # 沙漠
		Color(0.2, 0.5, 0.25),   # 温带森林
		Color(0.1, 0.6, 0.2),    # 热带森林
		Color(0.95, 0.95, 1.0),  # 雪地
	]
	var n := colors.size()
	var img := Image.create(n * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for i in n:
		for px in range(i * TILE_SIZE, (i + 1) * TILE_SIZE):
			for py in range(TILE_SIZE):
				img.set_pixel(px, py, colors[i])
	var tex := ImageTexture.create_from_image(img)
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i in n:
		atlas.create_tile(Vector2i(i, 0))
	ts.add_source(atlas, SOURCE_ID)
	return ts


## 纬度因子：0=赤道，1=极地（用于温度）
func _latitude(pos: Vector2) -> float:
	return absf(pos.y / (0.5 * _size))


func heat(pos: Vector2) -> float:
	return _latitude(pos)


## 到世界中心的归一化距离（圆形衰减，避免南北/东西出现直线边界）
func falloff_value(pos: Vector2) -> float:
	var v := pos.length() / (0.5 * _size)
	return evaluate(v)


func evaluate(x: float) -> float:
	const A := 3.0
	const B := 2.2
	return pow(x, A) / (pow(x, A) + pow(B - B * x, A))


## 大陆轮廓：低频噪声，让陆地偏向成块而非均匀铺满
func _world_shape(pos: Vector2) -> float:
	var n := noise_continent.get_noise_2d(pos.x * 0.5, pos.y * 0.5)
	return (n + 1.0) * 0.5


## 圣山：中心点不变，范围缩小到约世界 1/9～1/8
func _story_peak(pos: Vector2) -> float:
	var d := pos.distance_to(_story_peak_center)
	var sigma := _size * 0.04
	var bump := exp(-d * d / (2.0 * sigma * sigma))
	return bump * 0.7


## 山链：脊状噪声 + 低频方向性，形成连续山脉（非到处小山包）
func _mountain_ridge(pos: Vector2) -> float:
	# 方向性采样：拉伸/旋转使脊状呈链状走向
	var ax := pos.x * 0.022 + pos.y * 0.014
	var ay := pos.y * 0.022 - pos.x * 0.009
	var ridge_raw := noise_ridge.get_noise_2d(ax, ay)
	# 脊状高值在 0~1，只取“山脊”侧
	var ridge := clampf((ridge_raw + 1.0) * 0.5, 0.0, 1.0)
	# 低频 mask：山链只出现在某些条带，避免全图乱峰
	var chain := (noise_chain.get_noise_2d(pos.x * 0.012, pos.y * 0.012) + 1.0) * 0.5
	chain = clampf(chain * 1.4 - 0.2, 0.0, 1.0)
	return ridge * chain * RIDGE_STRENGTH


## 干旱带：固定在世界一角（西南/东南/西北/东北），只占一隅
func _story_dry_bias(pos: Vector2) -> float:
	var d := pos.distance_to(_story_dry_center)
	var sigma := _size * 0.028
	var bump := exp(-d * d / (2.0 * sigma * sigma))
	return bump * 0.12


## 边陲感：适度压低边缘（与 falloff 一致用距离）
func _frontier_falloff(pos: Vector2) -> float:
	var v := pos.length() / (0.5 * _size)
	return v * v * 0.08


## 温度 0..1：1=炎热（赤道），0=寒冷（极地）；加噪声扰动避免南北直线分界
func get_temperature(pos: Vector2) -> float:
	var base := 1.0 - _latitude(pos)
	var wobble := noise.get_noise_2d(pos.x * 0.025, pos.y * 0.025) * 0.24
	return clampf(base + wobble, 0.0, 1.0)


## 湿度 0..1：海岸高湿向内陆衰减 + 雨影（背风侧变干）+ 噪声与干旱带偏置
func get_moisture(pos: Vector2, height_raw: float) -> float:
	var base := clampf((height_raw + 0.25) / 0.65, 0.0, 1.0) * 0.6
	var n := (noise_dry.get_noise_2d(pos.x * 0.15, pos.y * 0.15) + 1.0) * 0.5
	var dry_bias := _story_dry_bias(pos)
	return clampf(base + n * 0.4 - dry_bias * 2.5, 0.0, 1.0)


## 带湿度扩散与雨影的湿度（用于 generate_land 预计算后）
func _moisture_with_diffusion(coastal_humidity: float, rain_shadow: float, pos: Vector2, _height_raw: float) -> float:
	var n := (noise_dry.get_noise_2d(pos.x * 0.15, pos.y * 0.15) + 1.0) * 0.5
	var dry_bias := _story_dry_bias(pos)
	var base := coastal_humidity * rain_shadow * (0.65 + n * 0.35)
	return clampf(base - dry_bias * 2.2, 0.0, 1.0)


## 第一层：基础地表（仅沙漠/草原）
func _base_biome_from_climate(temperature: float, moisture: float) -> int:
	var ti := int(clampf(temperature * 4.0, 0.0, 3.0))
	var mi := int(clampf(moisture * 3.0, 0.0, 2.0))
	return BASE_BIOME_TABLE[ti][mi]


## 第二层：森林覆盖率 0~1（湿度×温度×地形，加扰动破硬边界）
func _forest_coverage(temperature: float, moisture: float, height_raw: float, pos: Vector2) -> float:
	var wet_warm := moisture * (0.38 + 0.55 * temperature)
	var elev := clampf((height_raw - 0.15) / 0.25, 0.0, 1.0)
	var elev_factor := 1.0 - 0.35 * elev
	var raw := wet_warm * elev_factor
	var wobble := noise.get_noise_2d(pos.x * 0.018, pos.y * 0.018) * 0.12
	return clampf(raw + wobble, 0.0, 1.0)


## 第二层：是否长森林（阈值带扰动，避免纬线状分界）
func _forest_cover_threshold(pos: Vector2) -> float:
	var wobble := noise.get_noise_2d(pos.x * 0.012, pos.y * 0.012) * FOREST_THRESHOLD_NOISE
	return FOREST_COVER_THRESHOLD + wobble


## 第三层：森林类型（连续温度过渡，温带↔热带无硬切）
func _forest_type(temperature: float, pos: Vector2) -> int:
	var wobble := noise.get_noise_2d(pos.x * 0.02, pos.y * 0.02) * FOREST_TYPE_NOISE
	var t_eff := temperature + wobble
	if t_eff >= FOREST_TROPICAL_CENTER:
		return Terrain.TROPICAL_FOREST
	return Terrain.TEMPERATE_FOREST


func get_heightv(pos: Vector2) -> float:
	var base := noise.get_noise_2d(pos.x, pos.y)
	var falloff := falloff_value(pos)
	var continent := (_world_shape(pos) - 0.5) * 0.25
	var peak := _story_peak(pos)
	var ridge := _mountain_ridge(pos)
	var frontier := _frontier_falloff(pos)
	return base - falloff + continent + peak + ridge - frontier


## 返回该位置高度（米），海平面 = 海岸线（raw -0.25）对应 0 m，陆地不再出现负海拔
func get_height_meters(pos: Vector2) -> float:
	var raw := get_heightv(pos)
	return (raw - SEA_LEVEL_RAW) * METERS_PER_RAW_UNIT


## 返回格子中心高度（米）
func get_height_meters_at_cell(coords: Vector2i) -> float:
	var raw := get_heightv(Vector2(coords))
	return (raw - SEA_LEVEL_RAW) * METERS_PER_RAW_UNIT


func _cell_idx(x: int, y: int, half: int) -> int:
	return (x + half) + (y + half) * _size


func generate_land() -> void:
	print("[Generator]: 开始生成陆地")
	var total := _size * _size
	var half := int(_size / 2.0)

	# 1) 预计算高度
	var height_grid := PackedFloat32Array()
	height_grid.resize(total)
	for x in range(-half, half):
		for y in range(-half, half):
			height_grid[_cell_idx(x, y, half)] = get_heightv(Vector2(x, y))

	# 2) 从海洋向外 BFS，得到每格到最近海岸的步数（湿度扩散用）
	var dist_grid := PackedInt32Array()
	dist_grid.resize(total)
	for k in total:
		dist_grid[k] = -1
	var q: Array = []
	for x in range(-half, half):
		for y in range(-half, half):
			var h := height_grid[_cell_idx(x, y, half)]
			if h <= SEA_LEVEL_RAW:
				var idx := _cell_idx(x, y, half)
				dist_grid[idx] = 0
				q.append([x, y])
	while q.size() > 0:
		var cell: Array = q.pop_front()
		var cx: int = cell[0]
		var cy: int = cell[1]
		var d := dist_grid[_cell_idx(cx, cy, half)]
		for dx in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var nx: int = cx + dx.x
			var ny: int = cy + dx.y
			if nx < -half or nx >= half or ny < -half or ny >= half:
				continue
			var nidx := _cell_idx(nx, ny, half)
			if dist_grid[nidx] >= 0:
				continue
			dist_grid[nidx] = d + 1
			q.append([nx, ny])

	# 3) 雨影：风从西向东，背风侧（山体东侧）变干
	var upwind := Vector2i(-1, 0)
	var rain_shadow_grid := PackedFloat32Array()
	rain_shadow_grid.resize(total)
	for x in range(-half, half):
		for y in range(-half, half):
			var idx := _cell_idx(x, y, half)
			var my_h := height_grid[idx]
			var max_h := my_h
			for step in range(1, RAIN_SHADOW_RAY_STEPS):
				var sx := x + upwind.x * step
				var sy := y + upwind.y * step
				if sx < -half or sx >= half or sy < -half or sy >= half:
					break
				var h := height_grid[_cell_idx(sx, sy, half)]
				if h > max_h:
					max_h = h
			if max_h > my_h + RAIN_SHADOW_HEIGHT_RAW:
				rain_shadow_grid[idx] = RAIN_SHADOW_FACTOR
			else:
				rain_shadow_grid[idx] = 1.0

	# 4) 写格：水域/雪按高度；陆地按 海岸湿度×雨影×噪声 查 Whittaker 表
	var i := 0
	for x in range(-half, half):
		for y in range(-half, half):
			var pos := Vector2(x, y)
			var h := height_grid[_cell_idx(x, y, half)]
			var coords := Vector2i(x, y)

			if h >= -0.5 and h <= -0.25:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.OCEAN, 0), 0)
			elif h <= -0.5:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.DEEP_OCEAN, 0), 0)
			elif h >= 0.4:
				set_cell(coords, SOURCE_ID, Vector2i(Terrain.SNOW, 0), 0)
			else:
				var dist := dist_grid[_cell_idx(x, y, half)]
				if dist < 0:
					dist = _size
				var coastal_humidity := 1.0 / (1.0 + float(dist) / COASTAL_DECAY_SCALE)
				var rain_shadow := rain_shadow_grid[_cell_idx(x, y, half)]
				var moisture := _moisture_with_diffusion(coastal_humidity, rain_shadow, pos, h)
				var temperature := get_temperature(pos)
				var base_biome := _base_biome_from_climate(temperature, moisture)
				var forest_cover := _forest_coverage(temperature, moisture, h, pos)
				var threshold := _forest_cover_threshold(pos)
				var terrain_id: int
				if forest_cover >= threshold:
					terrain_id = _forest_type(temperature, pos)
				else:
					terrain_id = base_biome
				set_cell(coords, SOURCE_ID, Vector2i(terrain_id, 0), 0)

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


func generate(size: int) -> void:
	_size = size
	_story_peak_center = Vector2(randf_range(-0.08, 0.08) * _size, randf_range(-0.08, 0.08) * _size)
	# 干旱带随机放在地图一角：西北/东北/西南/东南
	var half := _size * 0.5
	var corner := randi() % 4  # 0=西北 1=东北 2=西南 3=东南
	var cx := half * randf_range(0.28, 0.42)
	var cy := half * randf_range(0.28, 0.42)
	match corner:
		0: _story_dry_center = Vector2(-cx, -cy)
		1: _story_dry_center = Vector2(cx, -cy)
		2: _story_dry_center = Vector2(-cx, cy)
		_: _story_dry_center = Vector2(cx, cy)
	generate_land()
	update_internals()
