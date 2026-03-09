extends Resource
class_name Fortune

## 气运：名字 + 品阶（凡品 → 天品），后续扩展用

enum Rank {
	MORTAL,    ## 凡品
	LOW,       ## 下品
	MID,       ## 中品
	HIGH,      ## 上品
	DIVINE,    ## 神品
	HEAVEN     ## 天品
}

const RANK_NAMES := ["凡品", "下品", "中品", "上品", "神品", "天品"]

@export var display_name: String = ""
@export var rank: Rank = Rank.MORTAL


func get_rank_name() -> String:
	if rank >= 0 and rank < RANK_NAMES.size():
		return RANK_NAMES[rank]
	return RANK_NAMES[0]
