extends CanvasLayer

## 暂停菜单：仅在 get_tree().paused 时处理（Process Mode = When Paused）
## ESC 关闭菜单并继续游戏；仙侠风 UI：深色底、暖金点缀、清晰层级

@onready var _title: Label = %Title
@onready var _panel: PanelContainer = $CenterContainer/PanelContainer
@onready var _btn_continue: Button = %BtnContinue
@onready var _btn_settings: Button = %BtnSettings
@onready var _btn_quit: Button = %BtnQuit

var _settings_panel: PopupPanel

const _BG_OVERLAY := Color(0.04, 0.03, 0.06, 0.72)
const _PANEL_BG := Color(0.09, 0.08, 0.07, 0.96)
const _PANEL_BORDER := Color(0.55, 0.42, 0.18, 0.9)
const _BTN_BG := Color(0.14, 0.12, 0.10, 1.0)
const _BTN_HOVER := Color(0.22, 0.18, 0.14, 1.0)
const _BTN_PRESSED := Color(0.08, 0.07, 0.06, 1.0)
const _BTN_BORDER := Color(0.45, 0.35, 0.18, 0.8)
const _TITLE_COLOR := Color(0.92, 0.86, 0.72, 1.0)
const _FONT_TITLE := 22
const _FONT_BTN := 17


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()
	_apply_theme()
	var SettingsPanelScene := preload("res://Elements/SettingsPanel.tscn") as PackedScene
	_settings_panel = SettingsPanelScene.instantiate() as PopupPanel
	add_child(_settings_panel)
	_settings_panel.hide()
	if _btn_continue:
		_btn_continue.pressed.connect(_on_continue_pressed)
	if _btn_settings:
		_btn_settings.pressed.connect(_on_settings_pressed)
	if _btn_quit:
		_btn_quit.pressed.connect(_on_quit_pressed)


func _apply_theme() -> void:
	if $Background is ColorRect:
		($Background as ColorRect).color = _BG_OVERLAY
	if _panel:
		_panel.custom_minimum_size.x = 280
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = _PANEL_BG
		panel_style.border_color = _PANEL_BORDER
		panel_style.set_border_width_all(1)
		panel_style.set_corner_radius_all(14)
		panel_style.set_content_margin_all(0)
		_panel.add_theme_stylebox_override("panel", panel_style)
	if _title:
		_title.add_theme_font_size_override("font_size", _FONT_TITLE)
		_title.add_theme_color_override("font_color", _TITLE_COLOR)
	for btn in [_btn_continue, _btn_settings, _btn_quit]:
		if not btn is Button:
			continue
		btn.add_theme_font_size_override("font_size", _FONT_BTN)
		btn.custom_minimum_size.y = 44
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = _BTN_BG
		sb_normal.border_color = _BTN_BORDER
		sb_normal.set_border_width_all(1)
		sb_normal.set_corner_radius_all(10)
		sb_normal.set_content_margin_all(10)
		btn.add_theme_stylebox_override("normal", sb_normal)
		var sb_hover := sb_normal.duplicate()
		(sb_hover as StyleBoxFlat).bg_color = _BTN_HOVER
		btn.add_theme_stylebox_override("hover", sb_hover)
		var sb_pressed := sb_normal.duplicate()
		(sb_pressed as StyleBoxFlat).bg_color = _BTN_PRESSED
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_color_override("font_color", _TITLE_COLOR)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close_and_resume()
		get_viewport().set_input_as_handled()


func _close_and_resume() -> void:
	hide()
	get_tree().paused = false


func _on_continue_pressed() -> void:
	_close_and_resume()


func _on_settings_pressed() -> void:
	if _settings_panel:
		_settings_panel.popup_centered()


func _on_quit_pressed() -> void:
	get_tree().quit()
