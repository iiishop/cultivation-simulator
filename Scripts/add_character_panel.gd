extends PopupPanel

## 新增角色弹窗：填写性别、姓名、基础属性、灵根、气运槽；与设置/暂停同风格

const CharacterScript := preload("res://Scripts/character.gd")

signal character_created(character: Resource)

@onready var _title: Label = %Title
@onready var _gender: OptionButton = %Gender
@onready var _surname: LineEdit = %Surname
@onready var _given_name: LineEdit = %GivenName
@onready var _lifespan_current: SpinBox = %LifespanCurrent
@onready var _lifespan_max: SpinBox = %LifespanMax
@onready var _stamina_max: SpinBox = %StaminaMax
@onready var _spirit_max: SpinBox = %SpiritMax
@onready var _luck: SpinBox = %Luck
@onready var _comprehension: SpinBox = %Comprehension
@onready var _root_water: SpinBox = %RootWater
@onready var _root_fire: SpinBox = %RootFire
@onready var _root_wind: SpinBox = %RootWind
@onready var _root_thunder: SpinBox = %RootThunder
@onready var _root_earth: SpinBox = %RootEarth
@onready var _root_wood: SpinBox = %RootWood
@onready var _fortune_slot: Label = %FortuneSlot
@onready var _btn_confirm: Button = %BtnConfirm
@onready var _btn_cancel: Button = %BtnCancel

const _PANEL_BG := Color(0.09, 0.08, 0.07, 0.98)
const _PANEL_BORDER := Color(0.55, 0.42, 0.18, 0.9)
const _BTN_BG := Color(0.14, 0.12, 0.10, 1.0)
const _BTN_HOVER := Color(0.22, 0.18, 0.14, 1.0)
const _BTN_PRESSED := Color(0.08, 0.07, 0.06, 1.0)
const _BTN_BORDER := Color(0.45, 0.35, 0.18, 0.8)
const _TITLE_COLOR := Color(0.92, 0.86, 0.72, 1.0)
const _INPUT_BG := Color(0.12, 0.10, 0.09, 1.0)
const _FONT_TITLE := 20
const _FONT_SECTION := 14
const _FONT_BTN := 15
const _FONT_LABEL := 13


func _ready() -> void:
	# 从侧栏打开时游戏可能未暂停，必须能接收输入
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	_gender.clear()
	_gender.add_item(CharacterScript.GENDER_NAMES[CharacterScript.Gender.MALE], int(CharacterScript.Gender.MALE))
	_gender.add_item(CharacterScript.GENDER_NAMES[CharacterScript.Gender.FEMALE], int(CharacterScript.Gender.FEMALE))
	_btn_confirm.pressed.connect(_on_confirm_pressed)
	_btn_cancel.pressed.connect(hide)
	close_requested.connect(hide)


func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _PANEL_BG
	panel_style.border_color = _PANEL_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(14)
	panel_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", panel_style)
	if _title:
		_title.add_theme_font_size_override("font_size", _FONT_TITLE)
		_title.add_theme_color_override("font_color", _TITLE_COLOR)
	for btn in [_btn_confirm, _btn_cancel]:
		if not is_instance_valid(btn):
			continue
		btn.add_theme_font_size_override("font_size", _FONT_BTN)
		btn.custom_minimum_size.y = 36
		var sb := StyleBoxFlat.new()
		sb.bg_color = _BTN_BG
		sb.border_color = _BTN_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", _make_style(_BTN_HOVER))
		btn.add_theme_stylebox_override("pressed", _make_style(_BTN_PRESSED))
		btn.add_theme_color_override("font_color", _TITLE_COLOR)
	for le in [_surname, _given_name]:
		if not is_instance_valid(le):
			continue
		le.add_theme_color_override("font_color", _TITLE_COLOR)
		var sb_le := StyleBoxFlat.new()
		sb_le.bg_color = _INPUT_BG
		sb_le.border_color = _BTN_BORDER
		sb_le.set_border_width_all(1)
		sb_le.set_corner_radius_all(6)
		sb_le.set_content_margin_all(6)
		le.add_theme_stylebox_override("normal", sb_le)
	if _gender:
		_gender.add_theme_color_override("font_color", _TITLE_COLOR)
		var sb_opt := StyleBoxFlat.new()
		sb_opt.bg_color = _INPUT_BG
		sb_opt.border_color = _BTN_BORDER
		sb_opt.set_border_width_all(1)
		sb_opt.set_corner_radius_all(6)
		sb_opt.set_content_margin_all(6)
		_gender.add_theme_stylebox_override("normal", sb_opt)
	_apply_spinbox_theme()
	_apply_label_color($MarginContainer/ScrollContainer/VBox)
	if _fortune_slot:
		_fortune_slot.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6, 1.0))


func _make_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = _BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.set_content_margin_all(8)
	return s


func _apply_spinbox_theme() -> void:
	var spinboxes: Array[SpinBox] = [
		_lifespan_current, _lifespan_max, _stamina_max, _spirit_max, _luck, _comprehension,
		_root_water, _root_fire, _root_wind, _root_thunder, _root_earth, _root_wood
	]
	for sb in spinboxes:
		if not is_instance_valid(sb):
			continue
		sb.custom_minimum_size.y = 28
		sb.add_theme_font_size_override("font_size", _FONT_LABEL)
		sb.add_theme_color_override("font_color", _TITLE_COLOR)
		var s := StyleBoxFlat.new()
		s.bg_color = _INPUT_BG
		s.border_color = _BTN_BORDER
		s.set_border_width_all(1)
		s.set_corner_radius_all(6)
		s.set_content_margin_all(6)
		sb.add_theme_stylebox_override("normal", s)


func _apply_label_color(root: Node) -> void:
	if root is Label:
		var lbl := root as Label
		lbl.add_theme_color_override("font_color", _TITLE_COLOR)
		var font_size := _FONT_SECTION if root.name == "SectionLabel" else _FONT_LABEL
		lbl.add_theme_font_size_override("font_size", font_size)
	for c in root.get_children():
		_apply_label_color(c)


func _on_confirm_pressed() -> void:
	var ch = CharacterScript.new()
	ch.gender = _gender.get_selected_id() as CharacterScript.Gender
	ch.surname = _surname.text.strip_edges()
	ch.given_name = _given_name.text.strip_edges()
	ch.lifespan_current = int(_lifespan_current.value)
	ch.lifespan_max = int(_lifespan_max.value)
	ch.stamina_max = int(_stamina_max.value)
	ch.spirit_max = int(_spirit_max.value)
	ch.luck = int(_luck.value)
	ch.comprehension = int(_comprehension.value)
	ch.set_spirit_root_level(CharacterScript.SpiritRoot.WATER, int(_root_water.value))
	ch.set_spirit_root_level(CharacterScript.SpiritRoot.FIRE, int(_root_fire.value))
	ch.set_spirit_root_level(CharacterScript.SpiritRoot.WIND, int(_root_wind.value))
	ch.set_spirit_root_level(CharacterScript.SpiritRoot.THUNDER, int(_root_thunder.value))
	ch.set_spirit_root_level(CharacterScript.SpiritRoot.EARTH, int(_root_earth.value))
	ch.set_spirit_root_level(CharacterScript.SpiritRoot.WOOD, int(_root_wood.value))
	# 气运槽预留，ch.fortune 保持 null
	character_created.emit(ch)
	hide()


func open_for_new() -> void:
	_gender.selected = CharacterScript.Gender.MALE
	_surname.text = ""
	_given_name.text = ""
	_lifespan_current.value = 60
	_lifespan_max.value = 100
	_stamina_max.value = 100
	_spirit_max.value = 100
	_luck.value = 50
	_comprehension.value = 50
	_root_water.value = 0
	_root_fire.value = 0
	_root_wind.value = 0
	_root_thunder.value = 0
	_root_earth.value = 0
	_root_wood.value = 0
	# 确保弹窗有固定尺寸，便于 ScrollContainer 正确计算滚动（Godot 4 文档：子节点 custom_minimum_size 决定可滚动范围）
	size = Vector2i(720, 400)
	min_size = Vector2i(600, 360)
	popup_centered()
	# 打开后焦点到第一个可编辑控件，便于键盘操作
	await get_tree().process_frame
	_surname.grab_focus()
