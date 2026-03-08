extends PopupPanel

## 设置面板：与 ESC 暂停菜单同风格（仙侠风）；Tab 通用/音量/LLM

@onready var _title: Label = %Title
@onready var _tab_container: TabContainer = %TabContainer
@onready var _api_base: LineEdit = %ApiBase
@onready var _api_key: LineEdit = %ApiKey
@onready var _btn_deepseek: Button = %BtnDeepSeek
@onready var _btn_openai: Button = %BtnOpenAI
@onready var _btn_qwen: Button = %BtnQwen
@onready var _btn_ollama: Button = %BtnOllama
@onready var _btn_validate: Button = %BtnValidate
@onready var _validate_status: Label = %ValidateStatus
@onready var _fast_model: OptionButton = %FastModel
@onready var _smart_model: OptionButton = %SmartModel
@onready var _btn_back: Button = %BtnBack

var _http: HTTPRequest
var _llm_config: Node

# 与暂停菜单一致的仙侠风配色
const _PANEL_BG := Color(0.09, 0.08, 0.07, 0.98)
const _PANEL_BORDER := Color(0.55, 0.42, 0.18, 0.9)
const _BTN_BG := Color(0.14, 0.12, 0.10, 1.0)
const _BTN_HOVER := Color(0.22, 0.18, 0.14, 1.0)
const _BTN_PRESSED := Color(0.08, 0.07, 0.06, 1.0)
const _BTN_BORDER := Color(0.45, 0.35, 0.18, 0.8)
const _TITLE_COLOR := Color(0.92, 0.86, 0.72, 1.0)
const _INPUT_BG := Color(0.12, 0.10, 0.09, 1.0)
const _FONT_TITLE := 22
const _FONT_BTN := 16
const _FONT_LABEL := 14

const _QUICK_FILL := {
	"DeepSeek": {"base": "https://api.deepseek.com/v1", "key": ""},
	"OpenAI": {"base": "https://api.openai.com/v1", "key": ""},
	"千问": {"base": "https://dashscope.aliyuncs.com/compatible-mode/v1", "key": ""},
	"Ollama": {"base": "http://localhost:11434/v1", "key": ""},
}


func _apply_theme() -> void:
	# 弹窗本体：深色底 + 暖金描边
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _PANEL_BG
	panel_style.border_color = _PANEL_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(14)
	panel_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", panel_style)
	# 标题
	if _title:
		_title.add_theme_font_size_override("font_size", _FONT_TITLE)
		_title.add_theme_color_override("font_color", _TITLE_COLOR)
	# Tab 内容区
	if _tab_container:
		var tab_panel := panel_style.duplicate()
		(tab_panel as StyleBoxFlat).bg_color = Color(0.07, 0.06, 0.06, 0.95)
		_tab_container.add_theme_stylebox_override("panel", tab_panel)
		_tab_container.add_theme_color_override("font_color", _TITLE_COLOR)
		_tab_container.add_theme_font_size_override("font_size", _FONT_LABEL)
	# 所有按钮（快速填充、验证、返回）
	var all_buttons: Array[Button] = [_btn_deepseek, _btn_openai, _btn_qwen, _btn_ollama, _btn_validate, _btn_back]
	for btn in all_buttons:
		if not is_instance_valid(btn):
			continue
		btn.add_theme_font_size_override("font_size", _FONT_BTN)
		btn.custom_minimum_size.y = 40
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = _BTN_BG
		sb_n.border_color = _BTN_BORDER
		sb_n.set_border_width_all(1)
		sb_n.set_corner_radius_all(8)
		sb_n.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", sb_n)
		btn.add_theme_stylebox_override("hover", _make_btn_style(_BTN_HOVER))
		btn.add_theme_stylebox_override("pressed", _make_btn_style(_BTN_PRESSED))
		btn.add_theme_color_override("font_color", _TITLE_COLOR)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))
	# 输入框
	for le in [_api_base, _api_key]:
		if not is_instance_valid(le):
			continue
		le.add_theme_color_override("font_color", _TITLE_COLOR)
		le.add_theme_font_size_override("font_size", _FONT_LABEL)
		var sb_le := StyleBoxFlat.new()
		sb_le.bg_color = _INPUT_BG
		sb_le.border_color = _BTN_BORDER
		sb_le.set_border_width_all(1)
		sb_le.set_corner_radius_all(6)
		sb_le.set_content_margin_all(8)
		le.add_theme_stylebox_override("normal", sb_le)
		le.add_theme_stylebox_override("focus", sb_le.duplicate())
	# 下拉框
	for opt in [_fast_model, _smart_model]:
		if not is_instance_valid(opt):
			continue
		opt.add_theme_color_override("font_color", _TITLE_COLOR)
		opt.add_theme_font_size_override("font_size", _FONT_LABEL)
		var sb_opt := StyleBoxFlat.new()
		sb_opt.bg_color = _INPUT_BG
		sb_opt.border_color = _BTN_BORDER
		sb_opt.set_border_width_all(1)
		sb_opt.set_corner_radius_all(6)
		sb_opt.set_content_margin_all(8)
		opt.add_theme_stylebox_override("normal", sb_opt)
		opt.add_theme_stylebox_override("hover", _make_btn_style(_BTN_HOVER))
		opt.add_theme_stylebox_override("pressed", _make_btn_style(_BTN_PRESSED))
	# 状态与页内标签
	if _validate_status:
		_validate_status.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65, 1.0))
		_validate_status.add_theme_font_size_override("font_size", _FONT_LABEL)
	_apply_label_color($MarginContainer/VBox/TabContainer/LLM/LLMPage)


func _make_btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = _BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	return s


func _apply_label_color(root: Node) -> void:
	if root is Label:
		(root as Label).add_theme_color_override("font_color", _TITLE_COLOR)
		(root as Label).add_theme_font_size_override("font_size", _FONT_LABEL)
	for c in root.get_children():
		_apply_label_color(c)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_apply_theme()
	_llm_config = get_node_or_null("/root/LLMConfig")
	_populate_llm_from_config()
	_btn_deepseek.pressed.connect(_on_quick_fill.bind("DeepSeek"))
	_btn_openai.pressed.connect(_on_quick_fill.bind("OpenAI"))
	_btn_qwen.pressed.connect(_on_quick_fill.bind("千问"))
	_btn_ollama.pressed.connect(_on_quick_fill.bind("Ollama"))
	_btn_validate.pressed.connect(_on_validate_pressed)
	_fast_model.item_selected.connect(_on_fast_model_selected)
	_smart_model.item_selected.connect(_on_smart_model_selected)
	_btn_back.pressed.connect(hide)
	close_requested.connect(hide)


func _populate_llm_from_config() -> void:
	if not _llm_config:
		return
	_llm_config.load_config()
	_api_base.text = _llm_config.api_base_url
	_api_key.text = _llm_config.api_key
	_fill_model_dropdowns(_llm_config.cached_model_ids)
	_select_model_option(_fast_model, _llm_config.fast_model_id)
	_select_model_option(_smart_model, _llm_config.smart_model_id)


func _fill_model_dropdowns(ids: PackedStringArray) -> void:
	_fast_model.clear()
	_smart_model.clear()
	_fast_model.add_item("（请先验证）", 0)
	_smart_model.add_item("（请先验证）", 0)
	for i in ids.size():
		_fast_model.add_item(ids[i], i + 1)
		_smart_model.add_item(ids[i], i + 1)


func _select_model_option(opt: OptionButton, model_id: String) -> void:
	if model_id.is_empty():
		opt.selected = 0
		return
	for i in opt.item_count:
		if i == 0:
			continue
		if opt.get_item_text(i) == model_id:
			opt.selected = i
			return
	opt.selected = 0


func _on_quick_fill(template_name: String) -> void:
	var t = _QUICK_FILL.get(template_name, {})
	if t.is_empty():
		return
	_api_base.text = t.base
	_api_key.text = t.get("key", "")
	_validate_status.text = ""


func _on_validate_pressed() -> void:
	var base := _api_base.text.strip_edges()
	var key := _api_key.text.strip_edges()
	if base.is_empty():
		_validate_status.text = "请填写 API Base URL"
		return
	if not base.ends_with("/"):
		base += "/"
	var url := base + "models"
	_validate_status.text = "验证中…"
	_btn_validate.disabled = true
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)
		_http.request_completed.connect(_on_models_request_completed)
	var headers := PackedStringArray()
	if not key.is_empty():
		headers.append("Authorization: Bearer " + key)
	var err := _http.request(url, headers)
	if err != OK:
		_validate_status.text = "请求失败"
		_btn_validate.disabled = false


func _on_models_request_completed(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_btn_validate.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_validate_status.text = "网络错误"
		return
	var json_str := body.get_string_from_utf8()
	var data = JSON.parse_string(json_str)
	if data == null:
		_validate_status.text = "响应解析失败"
		return
	if typeof(data) != TYPE_DICTIONARY:
		_validate_status.text = "响应格式错误"
		return
	var data_arr = data.get("data", null)
	if data_arr == null or typeof(data_arr) != TYPE_ARRAY:
		_validate_status.text = "未找到模型列表（非 OpenAI 兼容？）"
		return
	var ids: PackedStringArray = PackedStringArray()
	for o in data_arr:
		if typeof(o) == TYPE_DICTIONARY:
			var id_val = (o as Dictionary).get("id", "")
			if id_val:
				ids.append(str(id_val))
	if ids.is_empty():
		_validate_status.text = "模型列表为空"
		return
	_fill_model_dropdowns(ids)
	if _llm_config:
		_llm_config.set_api_and_models(_api_base.text.strip_edges(), _api_key.text.strip_edges(), ids)
		_select_model_option(_fast_model, _llm_config.fast_model_id)
		_select_model_option(_smart_model, _llm_config.smart_model_id)
	_validate_status.text = "已获取 %d 个模型" % ids.size()


func _on_fast_model_selected(idx: int) -> void:
	if not _llm_config or idx <= 0:
		return
	_llm_config.set_fast_model(_fast_model.get_item_text(idx))


func _on_smart_model_selected(idx: int) -> void:
	if not _llm_config or idx <= 0:
		return
	_llm_config.set_smart_model(_smart_model.get_item_text(idx))
