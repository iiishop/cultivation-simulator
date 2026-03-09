extends PanelContainer

## 左侧边栏：与暂停/设置同风格（仙侠风），内含「新增角色」等按钮

@onready var _btn_add_character: Button = %BtnAddCharacter

var _add_character_panel: PopupPanel

const _PANEL_BG := Color(0.09, 0.08, 0.07, 0.92)
const _PANEL_BORDER := Color(0.55, 0.42, 0.18, 0.9)
const _BTN_BG := Color(0.14, 0.12, 0.10, 1.0)
const _BTN_HOVER := Color(0.22, 0.18, 0.14, 1.0)
const _BTN_PRESSED := Color(0.08, 0.07, 0.06, 1.0)
const _BTN_BORDER := Color(0.45, 0.35, 0.18, 0.8)
const _TITLE_COLOR := Color(0.92, 0.86, 0.72, 1.0)
const _FONT_BTN := 16


func _ready() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _PANEL_BG
	panel_style.border_color = _PANEL_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(0)
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", panel_style)
	if _btn_add_character:
		_btn_add_character.add_theme_font_size_override("font_size", _FONT_BTN)
		_btn_add_character.custom_minimum_size.y = 40
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = _BTN_BG
		sb_n.border_color = _BTN_BORDER
		sb_n.set_border_width_all(1)
		sb_n.set_corner_radius_all(8)
		sb_n.set_content_margin_all(10)
		_btn_add_character.add_theme_stylebox_override("normal", sb_n)
		_btn_add_character.add_theme_stylebox_override("hover", _make_style(_BTN_HOVER))
		_btn_add_character.add_theme_stylebox_override("pressed", _make_style(_BTN_PRESSED))
		_btn_add_character.add_theme_color_override("font_color", _TITLE_COLOR)
		_btn_add_character.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))
		_btn_add_character.pressed.connect(_on_add_character_pressed)


func _make_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = _BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(10)
	return s


func _on_add_character_pressed() -> void:
	if _add_character_panel == null:
		var AddCharacterPanelScene := preload("res://Elements/AddCharacterPanel.tscn") as PackedScene
		_add_character_panel = AddCharacterPanelScene.instantiate() as PopupPanel
		get_parent().add_child(_add_character_panel)
		_add_character_panel.character_created.connect(_on_character_created)
	_add_character_panel.open_for_new()


func _on_character_created(_character: Resource) -> void:
	# 预留：将角色加入列表或存档
	pass
