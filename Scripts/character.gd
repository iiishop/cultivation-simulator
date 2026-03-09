extends Resource
class_name Character

## 人物：性别、姓名、基础属性、灵根等级、气运槽

enum Gender { MALE, FEMALE }
const GENDER_NAMES := ["男", "女"]

## 灵根类型
enum SpiritRoot {
	WATER,   ## 水
	FIRE,    ## 火
	WIND,    ## 风
	THUNDER, ## 雷
	EARTH,   ## 土
	WOOD     ## 木
}
const SPIRIT_ROOT_NAMES := ["水", "火", "风", "雷", "土", "木"]

# ---- 基础信息 ----
@export var gender: Gender = Gender.MALE
@export var surname: String = ""
@export var given_name: String = ""

# ---- 基础属性 ----
@export var lifespan_current: int = 60
@export var lifespan_max: int = 100
@export var stamina_max: int = 100   ## 体力（生命值上限）
@export var spirit_max: int = 100   ## 灵力上限
@export var luck: int = 50          ## 幸运值
@export var comprehension: int = 50 ## 悟性

# ---- 灵根等级（0 表示无/未开启） ----
@export var spirit_root_water: int = 0
@export var spirit_root_fire: int = 0
@export var spirit_root_wind: int = 0
@export var spirit_root_thunder: int = 0
@export var spirit_root_earth: int = 0
@export var spirit_root_wood: int = 0

# ---- 气运槽（预留，类型为 Fortune） ----
@export var fortune: Resource


func get_full_name() -> String:
	return surname + given_name


func get_spirit_root_level(root: SpiritRoot) -> int:
	match root:
		SpiritRoot.WATER: return spirit_root_water
		SpiritRoot.FIRE: return spirit_root_fire
		SpiritRoot.WIND: return spirit_root_wind
		SpiritRoot.THUNDER: return spirit_root_thunder
		SpiritRoot.EARTH: return spirit_root_earth
		SpiritRoot.WOOD: return spirit_root_wood
	return 0


func set_spirit_root_level(root: SpiritRoot, level: int) -> void:
	match root:
		SpiritRoot.WATER: spirit_root_water = level
		SpiritRoot.FIRE: spirit_root_fire = level
		SpiritRoot.WIND: spirit_root_wind = level
		SpiritRoot.THUNDER: spirit_root_thunder = level
		SpiritRoot.EARTH: spirit_root_earth = level
		SpiritRoot.WOOD: spirit_root_wood = level
