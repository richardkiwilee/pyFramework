extends CanvasLayer
## =============================================================================
## back_button.gd — 通用"返回主菜单"组件
## =============================================================================
## 每个功能子场景都挂一个：左上角常驻返回按钮，
## 点击回到主菜单（ai-discover 的统一约定）。
## =============================================================================

const MAIN_MENU := "res://scenes/menu.tscn"


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)

	var btn := Button.new()
	btn.text = "← 返回主菜单"
	btn.custom_minimum_size = Vector2(140, 42)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(_go_back)

	panel.add_child(btn)
	add_child(panel)


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
