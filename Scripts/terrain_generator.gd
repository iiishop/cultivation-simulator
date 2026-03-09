extends TileMapLayer
class_name TerrainGenerator

## 地形生成器：带偏向与故事性的地图（大陆轮廓、圣山、干旱带、边陲感）
## 使用 TileMapLayer（Godot 4.x 推荐），替代已弃用的 TileMap

var noise: FastNoiseLite
var noise_continent: FastNoiseLite  # 大陆轮廓，低频大块
var noise_dry: FastNoiseLite       # 干旱带分布
var noise_ridge: FastNoiseLite    # 脊状噪声，形成山脉轮廓
var noise_chain: FastNoiseLite    # 低频方向性，决定山链走向与分布
var _story_peak_center: Vector2   # 圣山/世界中心
var _story_dry_center: Vector2    # 干旱带中心（沙漠叙事）
var _last_generation_report: Dictionary = {}

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
	[Terrain.GRASSLAND, Terrain.GRASSLAND, Terrain.GRASSLAND],   # 暖
	[Terrain.GRASSLAND, Terrain.GRASSLAND, Terrain.GRASSLAND],   # 热
]

## 第二层：森林覆盖率阈值 + 扰动幅度（破直线边界）
const FOREST_COVER_THRESHOLD := 0.47
const FOREST_THRESHOLD_NOISE := 0.09
## 第三层：温带/热带过渡带中心与扰动（连续过渡，不硬切）
const FOREST_TROPICAL_CENTER := 0.55
const FOREST_TYPE_NOISE := 0.14

## 沙漠判定：用连续得分而非硬分段，减少“纬线式荒漠带”
const DESERT_SCORE_THRESHOLD := 0.3
const DESERT_LAT_CENTER := 0.32
const DESERT_LAT_SIGMA := 0.18
const DESERT_ARIDITY_CENTER := 0.60
const DESERT_ARIDITY_GAIN := 1.9
const DESERT_CONTINENTALITY_GAIN := 1.2
const DESERT_RAIN_SHADOW_GAIN := 2.1
const DESERT_DRY_ZONE_GAIN := 7.0
const DESERT_TEMP_CENTER := 0.22
const DESERT_TEMP_SPAN := 0.58
const DESERT_ELEV_CENTER := 0.26
const DESERT_ELEV_SPAN := 0.30
const DESERT_NOISE_BASE := 0.85
const DESERT_NOISE_VARIATION := 0.30
const DESERT_WEIGHT_ARIDITY := 0.43
const DESERT_WEIGHT_CONTINENTALITY := 0.16
const DESERT_WEIGHT_RAIN_SHADOW := 0.18
const DESERT_WEIGHT_DRY_ZONE := 0.15
const DESERT_WEIGHT_LATITUDE := 0.08

## 连续沙漠块：高阈值核心 + 低阈值扩张 + 连通分量保留
const DESERT_CORE_MARGIN := 0.03
const DESERT_EXPAND_MARGIN := 0.10
const DESERT_EXPAND_STEPS := 5
const DESERT_CLEAN_STEPS := 2

var _size := 512
const TILE_SIZE := 16

## 高度米制：海平面 = 陆地/海洋分界（raw -0.25），陆地显示 ≥ 0 m
## raw -0.5 → 约 -1500 m（深海），-0.25 → 0 m（海岸），0.4 → 4000 m（雪线），1 → 约 7700 m
const SEA_LEVEL_RAW := -0.25
const METERS_PER_RAW_UNIT := 4000.0 / (0.4 - SEA_LEVEL_RAW)

## 湿度扩散：海岸高湿向内陆衰减（距离单位：格）
const COASTAL_DECAY_SCALE := 34.0
## 雨影：风向（风从西向东吹，背风侧=东侧变干）
const RAIN_SHADOW_RAY_STEPS := 55
const RAIN_SHADOW_HEIGHT_RAW := 0.14
const RAIN_SHADOW_FACTOR := 0.52
const RAIN_SHADOW_EXCESS_SCALE := 0.22

## 山链：脊状噪声强度；方向性采样缩放（形成连续山脉）
const RIDGE_STRENGTH := 0.26
const RIDGE_FREQ := 1.0 / 44.0
const CHAIN_FREQ := 1.0 / 95.0

const D4: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]

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
	var wobble := noise.get_noise_2d(pos.x * 0.025, pos.y * 0.025) * 0.18
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
	var base := coastal_humidity * rain_shadow * (0.69 + n * 0.31)
	return clampf(base - dry_bias * 1.8, 0.0, 1.0)


## 第一层：基础地表（仅沙漠/草原）
func _base_biome_from_climate(temperature: float, moisture: float) -> int:
	var ti := int(clampf(temperature * 4.0, 0.0, 3.0))
	var mi := int(clampf(moisture * 3.0, 0.0, 2.0))
	return BASE_BIOME_TABLE[ti][mi]


## 第二层：森林覆盖率 0~1（湿度×温度×地形，加扰动破硬边界）
func _forest_coverage(temperature: float, moisture: float, height_raw: float, pos: Vector2) -> float:
	var wet_warm := moisture * (0.38 + 0.48 * temperature)
	var elev := clampf((height_raw - 0.15) / 0.25, 0.0, 1.0)
	var elev_factor := 1.0 - 0.30 * elev
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


## 沙漠得分 0..1：综合干旱度、内陆性、雨影、叙事干旱带与纬度偏好
func _desert_score(
	temperature: float,
	moisture: float,
	height_raw: float,
	coastal_humidity: float,
	rain_shadow: float,
	pos: Vector2
) -> float:
	var aridity := clampf((DESERT_ARIDITY_CENTER - moisture) * DESERT_ARIDITY_GAIN, 0.0, 1.0)
	var continentality := clampf(1.0 - coastal_humidity * DESERT_CONTINENTALITY_GAIN, 0.0, 1.0)
	var rain_shadow_dry := clampf((1.0 - rain_shadow) * DESERT_RAIN_SHADOW_GAIN, 0.0, 1.0)
	var dry_zone := clampf(_story_dry_bias(pos) * DESERT_DRY_ZONE_GAIN, 0.0, 1.0)

	var lat := _latitude(pos)
	var lat_delta := (lat - DESERT_LAT_CENTER) / DESERT_LAT_SIGMA
	var latitude_pref := exp(-0.5 * lat_delta * lat_delta)

	var temp_factor := clampf((temperature - DESERT_TEMP_CENTER) / DESERT_TEMP_SPAN, 0.0, 1.0)
	var elev_damp := 1.0 - clampf((height_raw - DESERT_ELEV_CENTER) / DESERT_ELEV_SPAN, 0.0, 1.0)

	var n := (noise_dry.get_noise_2d(pos.x * 0.02, pos.y * 0.02) + 1.0) * 0.5
	var noise_factor := DESERT_NOISE_BASE + (n - 0.5) * DESERT_NOISE_VARIATION

	var score := (
		aridity * DESERT_WEIGHT_ARIDITY
		+ continentality * DESERT_WEIGHT_CONTINENTALITY
		+ rain_shadow_dry * DESERT_WEIGHT_RAIN_SHADOW
		+ dry_zone * DESERT_WEIGHT_DRY_ZONE
		+ latitude_pref * DESERT_WEIGHT_LATITUDE
	)
	score *= temp_factor
	score *= elev_damp
	score *= noise_factor
	return clampf(score, 0.0, 1.0)


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


func _idx_to_cell(idx: int, half: int) -> Vector2i:
	var x: int = (idx % _size) - half
	@warning_ignore("integer_division")
	var y: int = (idx / _size) - half
	return Vector2i(x, y)


func _is_land_for_desert(height_raw: float) -> bool:
	return height_raw > SEA_LEVEL_RAW and height_raw < 0.4


func _build_contiguous_desert_mask(
	height_grid: PackedFloat32Array,
	desert_score_grid: PackedFloat32Array,
	half: int
) -> PackedInt32Array:
	var total := _size * _size
	var core_threshold := DESERT_SCORE_THRESHOLD + DESERT_CORE_MARGIN
	var expand_threshold := DESERT_SCORE_THRESHOLD - DESERT_EXPAND_MARGIN

	var seed_idx := -1
	var best_score := -1.0

	var mask := PackedInt32Array()
	mask.resize(total)
	mask.fill(0)

	for idx in range(total):
		var h := height_grid[idx]
		if not _is_land_for_desert(h):
			continue
		var score := desert_score_grid[idx]
		if score > best_score:
			best_score = score
			seed_idx = idx
		if score >= core_threshold:
			mask[idx] = 1

	if seed_idx < 0:
		return mask

	if mask[seed_idx] == 0:
		mask[seed_idx] = 1

	for _iter in range(DESERT_EXPAND_STEPS):
		var next := mask.duplicate()
		for idx in range(total):
			if mask[idx] == 1:
				continue
			if desert_score_grid[idx] < expand_threshold:
				continue
			if not _is_land_for_desert(height_grid[idx]):
				continue
			var cell := _idx_to_cell(idx, half)
			for d in D4:
				var nx := cell.x + d.x
				var ny := cell.y + d.y
				if nx < -half or nx >= half or ny < -half or ny >= half:
					continue
				var nidx := _cell_idx(nx, ny, half)
				if mask[nidx] == 1:
					next[idx] = 1
					break
		mask = next

	var visited := PackedInt32Array()
	visited.resize(total)
	visited.fill(0)
	var keep := PackedInt32Array()
	keep.resize(total)
	keep.fill(0)

	var queue := PackedInt32Array()
	queue.append(seed_idx)
	visited[seed_idx] = 1
	while queue.size() > 0:
		var cur := queue[queue.size() - 1]
		queue.resize(queue.size() - 1)
		if mask[cur] == 0:
			continue
		keep[cur] = 1
		var cell := _idx_to_cell(cur, half)
		for d in D4:
			var nx := cell.x + d.x
			var ny := cell.y + d.y
			if nx < -half or nx >= half or ny < -half or ny >= half:
				continue
			var nidx := _cell_idx(nx, ny, half)
			if visited[nidx] == 1:
				continue
			visited[nidx] = 1
			if mask[nidx] == 1:
				queue.append(nidx)

	for _iter in range(DESERT_CLEAN_STEPS):
		var next_clean := keep.duplicate()
		for idx in range(total):
			if keep[idx] == 0:
				continue
			var cell := _idx_to_cell(idx, half)
			var neighbors := 0
			for d in D4:
				var nx := cell.x + d.x
				var ny := cell.y + d.y
				if nx < -half or nx >= half or ny < -half or ny >= half:
					continue
				var nidx := _cell_idx(nx, ny, half)
				if keep[nidx] == 1:
					neighbors += 1
			if neighbors <= 1 and desert_score_grid[idx] < core_threshold:
				next_clean[idx] = 0
		keep = next_clean

	return keep


func _build_generation_report(
	terrain_grid: PackedInt32Array,
	desert_mask: PackedInt32Array,
	desert_score_grid: PackedFloat32Array,
	temp_grid: PackedFloat32Array,
	moisture_grid: PackedFloat32Array,
	half: int
) -> Dictionary:
	var total := _size * _size
	var counts := {}
	for t in Terrain.values():
		counts[t] = 0

	var land_count := 0
	var temp_sum := 0.0
	var moisture_sum := 0.0
	var desert_score_sum := 0.0

	for idx in range(total):
		var t: int = terrain_grid[idx]
		if counts.has(t):
			counts[t] += 1
		if t >= Terrain.GRASSLAND:
			land_count += 1
			temp_sum += temp_grid[idx]
			moisture_sum += moisture_grid[idx]
		if desert_mask[idx] == 1:
			desert_score_sum += desert_score_grid[idx]

	var desert_cells: int = counts.get(Terrain.DESERT, 0)
	var avg_temp := temp_sum / maxf(1.0, float(land_count))
	var avg_moisture := moisture_sum / maxf(1.0, float(land_count))
	var avg_desert_score := desert_score_sum / maxf(1.0, float(desert_cells))

	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for idx in range(total):
		if desert_mask[idx] == 0:
			continue
		var c := _idx_to_cell(idx, half)
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
		max_x = maxi(max_x, c.x)
		max_y = maxi(max_y, c.y)

	var bbox_w := max_x - min_x + 1 if desert_cells > 0 else 0
	var bbox_h := max_y - min_y + 1 if desert_cells > 0 else 0
	var bbox_fill := float(desert_cells) / maxf(1.0, float(bbox_w * bbox_h))

	return {
		"total_cells": total,
		"land_cells": land_count,
		"counts": counts,
		"desert_cells": desert_cells,
		"desert_ratio": float(desert_cells) / maxf(1.0, float(total)),
		"avg_temperature": avg_temp,
		"avg_moisture": avg_moisture,
		"avg_desert_score": avg_desert_score,
		"desert_bbox_w": bbox_w,
		"desert_bbox_h": bbox_h,
		"desert_bbox_fill": bbox_fill,
	}


func _print_generation_report(report: Dictionary) -> void:
	var counts: Dictionary = report.get("counts", {})
	var total: int = report.get("total_cells", 1)
	var inv_total := 100.0 / maxf(1.0, float(total))
	var deep_pct := float(counts.get(Terrain.DEEP_OCEAN, 0)) * inv_total
	var ocean_pct := float(counts.get(Terrain.OCEAN, 0)) * inv_total
	var grass_pct := float(counts.get(Terrain.GRASSLAND, 0)) * inv_total
	var desert_pct := float(counts.get(Terrain.DESERT, 0)) * inv_total
	var temperate_pct := float(counts.get(Terrain.TEMPERATE_FOREST, 0)) * inv_total
	var tropical_pct := float(counts.get(Terrain.TROPICAL_FOREST, 0)) * inv_total
	var snow_pct := float(counts.get(Terrain.SNOW, 0)) * inv_total

	print("[Generator][Report] total=", total,
		" land=", report.get("land_cells", 0),
		" avg_temp=", snappedf(report.get("avg_temperature", 0.0), 0.001),
		" avg_moisture=", snappedf(report.get("avg_moisture", 0.0), 0.001))

	print("[Generator][Report] deep_ocean=", counts.get(Terrain.DEEP_OCEAN, 0), " (", snappedf(deep_pct, 0.01), "%)",
		" ocean=", counts.get(Terrain.OCEAN, 0), " (", snappedf(ocean_pct, 0.01), "%)",
		" grass=", counts.get(Terrain.GRASSLAND, 0), " (", snappedf(grass_pct, 0.01), "%)")

	print("[Generator][Report] desert=", counts.get(Terrain.DESERT, 0), " (", snappedf(desert_pct, 0.01), "%)",
		" temp_forest=", counts.get(Terrain.TEMPERATE_FOREST, 0), " (", snappedf(temperate_pct, 0.01), "%)",
		" tropical_forest=", counts.get(Terrain.TROPICAL_FOREST, 0), " (", snappedf(tropical_pct, 0.01), "%)",
		" snow=", counts.get(Terrain.SNOW, 0), " (", snappedf(snow_pct, 0.01), "%)")

	print("[Generator][Report] desert_shape bbox=", report.get("desert_bbox_w", 0), "x", report.get("desert_bbox_h", 0),
		" bbox_fill=", snappedf(report.get("desert_bbox_fill", 0.0), 0.001),
		" avg_desert_score=", snappedf(report.get("avg_desert_score", 0.0), 0.001))

	if _last_generation_report.is_empty():
		print("[Generator][Compare] baseline run")
		return

	var prev_desert_ratio: float = _last_generation_report.get("desert_ratio", 0.0)
	var new_desert_ratio: float = report.get("desert_ratio", 0.0)
	var prev_fill: float = _last_generation_report.get("desert_bbox_fill", 0.0)
	var new_fill: float = report.get("desert_bbox_fill", 0.0)
	var prev_moisture: float = _last_generation_report.get("avg_moisture", 0.0)
	var new_moisture: float = report.get("avg_moisture", 0.0)

	print("[Generator][Compare] desert_ratio Δ=", snappedf((new_desert_ratio - prev_desert_ratio) * 100.0, 0.01), "pp",
		" desert_fill Δ=", snappedf(new_fill - prev_fill, 0.001),
		" avg_moisture Δ=", snappedf(new_moisture - prev_moisture, 0.001))


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

	# 2) 从海洋向外 BFS（双缓冲，避免 Array.pop_front 的 O(n) 代价）
	var dist_grid := PackedInt32Array()
	dist_grid.resize(total)
	dist_grid.fill(-1)
	var frontier := PackedInt32Array()
	for x in range(-half, half):
		for y in range(-half, half):
			if height_grid[_cell_idx(x, y, half)] <= SEA_LEVEL_RAW:
				var idx := _cell_idx(x, y, half)
				dist_grid[idx] = 0
				frontier.append(idx)
	var next_frontier := PackedInt32Array()
	var d := 1
	while frontier.size() > 0:
		next_frontier.clear()
		for i in range(frontier.size()):
			var idx := frontier[i]
			var cx: int = (idx % _size) - half
			@warning_ignore("integer_division")
			var cy: int = (idx / _size) - half
			for di in D4:
				var nx: int = cx + di.x
				var ny: int = cy + di.y
				if nx < -half or nx >= half or ny < -half or ny >= half:
					continue
				var nidx := _cell_idx(nx, ny, half)
				if dist_grid[nidx] >= 0:
					continue
				dist_grid[nidx] = d
				next_frontier.append(nidx)
		var t := frontier
		frontier = next_frontier
		next_frontier = t
		d += 1

	# 3) 雨影：风从西向东，背风侧变干（早退 + 步长 2 减采样）
	var rain_shadow_grid := PackedFloat32Array()
	rain_shadow_grid.resize(total)
	for k in total:
		rain_shadow_grid[k] = 1.0
	var threshold_h := RAIN_SHADOW_HEIGHT_RAW
	for x in range(-half, half):
		for y in range(-half, half):
			var idx := _cell_idx(x, y, half)
			var my_h := height_grid[idx]
			var barrier_excess := 0.0
			var nearest_step := RAIN_SHADOW_RAY_STEPS
			var step := 2
			while step < RAIN_SHADOW_RAY_STEPS:
				var sx := x - step
				if sx < -half:
					break
				var h := height_grid[_cell_idx(sx, y, half)]
				var excess := h - (my_h + threshold_h)
				if excess > 0.0:
					barrier_excess = maxf(barrier_excess, excess)
					nearest_step = mini(nearest_step, step)
				step += 2

			if barrier_excess <= 0.0:
				continue

			var severity := clampf(barrier_excess / RAIN_SHADOW_EXCESS_SCALE, 0.0, 1.0)
			var distance_factor := 1.0 - clampf(float(nearest_step) / float(RAIN_SHADOW_RAY_STEPS), 0.0, 1.0)
			var dry_mix := severity * (0.55 + 0.45 * distance_factor)
			rain_shadow_grid[idx] = 1.0 - dry_mix * (1.0 - RAIN_SHADOW_FACTOR)

	# 4) 预计算温度与湿度网格，主循环只做查表与 set_cell（少重复噪声）
	var temp_grid := PackedFloat32Array()
	var moisture_grid := PackedFloat32Array()
	temp_grid.resize(total)
	moisture_grid.resize(total)
	for x in range(-half, half):
		for y in range(-half, half):
			var idx := _cell_idx(x, y, half)
			var pos := Vector2(x, y)
			var h := height_grid[idx]
			temp_grid[idx] = get_temperature(pos)
			var dist := dist_grid[idx]
			if dist < 0:
				dist = _size
			var coastal_humidity := 1.0 / (1.0 + float(dist) / COASTAL_DECAY_SCALE)
			moisture_grid[idx] = _moisture_with_diffusion(coastal_humidity, rain_shadow_grid[idx], pos, h)

	# 5) 先生成地形候选（不直接写图），再做“连续沙漠块”覆盖
	var terrain_grid := PackedInt32Array()
	terrain_grid.resize(total)
	terrain_grid.fill(Terrain.GRASSLAND)
	var desert_score_grid := PackedFloat32Array()
	desert_score_grid.resize(total)
	desert_score_grid.fill(0.0)

	for x in range(-half, half):
		for y in range(-half, half):
			var idx := _cell_idx(x, y, half)
			var h := height_grid[idx]
			if h >= -0.5 and h <= -0.25:
				terrain_grid[idx] = Terrain.OCEAN
				continue
			if h <= -0.5:
				terrain_grid[idx] = Terrain.DEEP_OCEAN
				continue
			if h >= 0.4:
				terrain_grid[idx] = Terrain.SNOW
				continue

			var pos := Vector2(x, y)
			var temperature := temp_grid[idx]
			var moisture := moisture_grid[idx]
			var dist := dist_grid[idx]
			if dist < 0:
				dist = _size
			var coastal_humidity := 1.0 / (1.0 + float(dist) / COASTAL_DECAY_SCALE)
			var rain_shadow := rain_shadow_grid[idx]

			var base_biome := _base_biome_from_climate(temperature, moisture)
			var forest_cover := _forest_coverage(temperature, moisture, h, pos)
			var threshold := _forest_cover_threshold(pos)
			if forest_cover >= threshold:
				terrain_grid[idx] = _forest_type(temperature, pos)
			else:
				terrain_grid[idx] = base_biome

			desert_score_grid[idx] = _desert_score(temperature, moisture, h, coastal_humidity, rain_shadow, pos)

	var desert_mask := _build_contiguous_desert_mask(height_grid, desert_score_grid, half)
	for idx in range(total):
		if desert_mask[idx] == 1:
			terrain_grid[idx] = Terrain.DESERT

	# 6) 统一写图块（一次流程，便于统计与比较）
	var i := 0
	for x in range(-half, half):
		for y in range(-half, half):
			var idx := _cell_idx(x, y, half)
			set_cell(Vector2i(x, y), SOURCE_ID, Vector2i(terrain_grid[idx], 0), 0)
			i += 1
			if i % 8192 == 0:
				print("[Generator]: ", snappedf(float(i) / total * 100.0, 0.1), "%")

	var report := _build_generation_report(terrain_grid, desert_mask, desert_score_grid, temp_grid, moisture_grid, half)
	_print_generation_report(report)
	_last_generation_report = report

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
	if get_cell_source_id(coords) < 0:
		return false
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
