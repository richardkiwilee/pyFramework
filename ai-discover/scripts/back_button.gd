extends CanvasLayer
## =============================================================================
## back_button.gd — 通用"返回主菜单"组件
## =============================================================================
## 每个功能子场景都挂一个：右下角常驻返回按钮。
## 防遮挡的三个要点：
##   1. layer = 100：渲染在所有子场景自带 CanvasLayer（默认层号 ≤ 2）
##      之上，任何场景内容（HUD/特效/覆盖层）都盖不住它；
##   2. 半透明深色底 + 描边 + 悬停提亮：在亮背景（天空/雪地）上也清晰可见；
##   3. 等一帧拿到实际面板尺寸后贴齐视口右下角（留 12px 边距）。
## =============================================================================

const MAIN_MENU := "res://scenes/menu.tscn"


func _ready() -> void:
	layer = 100   # 置顶渲染，杜绝被场景内容遮挡

	var panel := PanelContainer.new()

	var btn := Button.new()
	btn.text = "← 返回主菜单"
	btn.custom_minimum_size = Vector2(140, 42)
	btn.add_theme_font_size_override("font_size", 15)

	# 面板样式：深色半透明 + 蓝色描边（任何背景下都醒目）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.13, 0.93)
	sb.border_color = Color(0.52, 0.58, 0.80)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 10.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)

	# 按钮样式：透明底融入面板，悬停/按下提亮
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(1, 1, 1, 0.04)
	btn_normal.set_corner_radius_all(6)
	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.30, 0.42, 0.75, 0.75)
	for state in ["normal", "focus"]:
		btn.add_theme_stylebox_override(state, btn_normal)
	for state in ["hover", "pressed"]:
		btn.add_theme_stylebox_override(state, btn_hover)

	btn.pressed.connect(_go_back)

	panel.add_child(btn)
	add_child(panel)
	# 等一帧拿到实际尺寸后贴齐视口右下角（留 12px 边距）
	await get_tree().process_frame
	panel.position = get_viewport().get_visible_rect().size - panel.size - Vector2(12, 12)


func _go_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
