extends Node

## 暂停控制：ESC 打开暂停菜单；关闭逻辑由菜单自身处理

@export var pause_menu: CanvasLayer


func _ready() -> void:
	if not pause_menu:
		pause_menu = get_parent().get_node_or_null("PauseMenu")


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if get_tree().paused:
		return
	if pause_menu == null:
		return

	get_tree().paused = true
	pause_menu.show()
	get_viewport().set_input_as_handled()
