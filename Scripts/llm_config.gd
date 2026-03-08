extends Node

## LLM 配置单例：持久化到 user://llm_config.json（OpenAI 兼容：API Base、Key、快速/智能模型槽位）
## 使用方式：LLMConfig.load_config() / save_config() 等

const CONFIG_PATH := "user://llm_config.json"

var api_base_url: String = ""
var api_key: String = ""
var fast_model_id: String = ""
var smart_model_id: String = ""
var cached_model_ids: PackedStringArray = PackedStringArray()

const _DEFAULT_BASE := "https://api.openai.com/v1"


func load_config() -> bool:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return false
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	api_base_url = data.get("api_base_url", _DEFAULT_BASE)
	api_key = data.get("api_key", "")
	fast_model_id = data.get("fast_model_id", "")
	smart_model_id = data.get("smart_model_id", "")
	var arr = data.get("cached_model_ids", [])
	cached_model_ids.clear()
	for s in arr:
		cached_model_ids.append(str(s))
	return true


func save_config() -> bool:
	var data: Dictionary = {
		"api_base_url": api_base_url,
		"api_key": api_key,
		"fast_model_id": fast_model_id,
		"smart_model_id": smart_model_id,
		"cached_model_ids": Array(cached_model_ids),
	}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


func set_api_and_models(base: String, key: String, model_ids: PackedStringArray) -> void:
	api_base_url = base.strip_edges()
	if not api_base_url.ends_with("/"):
		api_base_url += "/"
	api_key = key
	cached_model_ids = model_ids
	save_config()


func set_fast_model(id: String) -> void:
	fast_model_id = id
	save_config()


func set_smart_model(id: String) -> void:
	smart_model_id = id
	save_config()
