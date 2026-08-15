class_name PickerFactory
extends RefCounted
## =============================================================================
## PickerFactory — 通用弹窗工厂（装备/技能/条件选择弹窗共用）
## =============================================================================
## 作用：在 Overlay 层动态创建统一的居中弹窗，
##       返回 {panel, body, foot_label, close_btn} 供调用方填充内容行。
##
## 结构（对齐网页版 .overlay）：
##   PanelContainer (居中 600×520，深棕底+金边+圆角)
##   └─ VBoxContainer
##       ├─ Header (HBox)：Title + CloseBtn "✕"
##       ├─ ScrollContainer (expand) → Body (VBox)
##       └─ Foot (Label 提示文字)
##
## 关闭方式：CloseBtn / Esc / 右侧空白点击（由 MainScreen 统一处理）。
## =============================================================================


## 构建弹窗并返回 {panel, body, foot_label, close_btn}
##   parent — 挂载节点（Overlay 层）
##   title  — 标题文字
##   foot   — 底部提示文字（可为空）
static func build_modal(parent: Node, title: String, foot: String = "") -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = "Picker_%d" % panel.get_instance_id()
	panel.visible = false  # 初始隐藏，需要时才显示

	# --- 位置与大小：占满左半区（对齐网页版 .overlay inset:0）---
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0

	# --- 面板样式：不透明深棕底 + 金边 + 圆角（网页版弹窗不透出下层棋盘）---
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.114, 0.094, 0.078, 1.0)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = UITheme.GOLD
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 12
	sb.content_margin_top = 12
	sb.content_margin_right = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	# --- 内部布局 ---
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# 标题栏
	var header := HBoxContainer.new()
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "×"  # U+2715 ✕ 主题字体无字形，用 ×(U+00D7)
	close_btn.focus_mode = Control.FOCUS_NONE
	# 点击关闭 → 隐藏并释放弹窗
	close_btn.pressed.connect(func():
		panel.visible = false
		panel.queue_free()
	)
	header.add_child(close_btn)
	vbox.add_child(header)

	# 可滚动内容（透明面板样式——弹窗底色即列表底色，对齐网页版 ov-body）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	vbox.add_child(scroll)

	# 底部提示
	var foot_label := Label.new()
	foot_label.text = foot
	foot_label.add_theme_color_override("font_color", UITheme.INK_DIM)
	foot_label.add_theme_font_size_override("font_size", 11)
	foot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(foot_label)

	parent.add_child(panel)
	return {"panel": panel, "body": body, "foot_label": foot_label, "close_btn": close_btn}
