class_name ReferenceSheet
extends PanelContainer
## =============================================================================
## ReferenceSheet — 52 张牌背对照表（F1 开关，新手模式可用）
## =============================================================================
## 学习工具：按花色分 4 列，每列 13 张迷你牌背 + 中文标注。
## 地狱模式下不可打开（考验真实记忆）。
## =============================================================================


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0c0a08")
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color("d4af37")
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)
	size = Vector2(760, 640)  # 直接挂在根 Control 下，显式定尺寸
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := UITheme.make_label("牌背对照表 · 上沿铆钉数 = 点数，中央徽章色调/符号 = 花色", 18, UITheme.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(grid)

	for suit in CardData.Suit.values():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		grid.add_child(col)
		var header := UITheme.make_label(CardData.SUIT_NAMES_CN[int(suit)], 15, UITheme.INK2)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(header)
		for rank in CardData.Rank.values():
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 6)
			cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(cell)
			var tex := TextureRect.new()
			tex.texture = BackDrawer.back_texture(int(suit), int(rank))
			tex.custom_minimum_size = Vector2(49, 68)  # 140×196 缩到 49×68
			tex.stretch_mode = TextureRect.STRETCH_SCALE
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cell.add_child(tex)
			var label := UITheme.make_label(
				"%s %s" % [CardData.SUIT_NAMES_CN[int(suit)], CardData.RANK_NAMES[int(rank)]],
				12, UITheme.INK2)
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(label)
