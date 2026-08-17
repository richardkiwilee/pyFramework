class_name MapUI
extends Control
## =============================================================================
## UI 覆盖层 —— 地块信息 / 区域建造 / 加成面板
## =============================================================================
## · 左上:标题 + 当前地块信息(坐标/地形/海拔/特征/距海/防御/移动/区域);
## · 右上:区域建造面板(7 种区域按钮,带色块与规则提示);
## · 右下:已建区域与邻接加成明细 + 帝国总产出;
## · 底部:操作提示条。
## 中文字体使用 SystemFont(微软雅黑),整棵 UI 树共享一份复制自默认主题的
## Theme(保留按钮等默认样式,只替换默认字体)。
## =============================================================================

signal build_requested(id: int)
signal cancel_requested

var sys: DistrictSystem
var map: HexMap

var _info_coord: Label
var _info_terrain: Label
var _info_elev: Label
var _info_feat: Label
var _info_sea: Label
var _info_defense: Label
var _info_move: Label
var _info_district: Label
var _build_buttons: Dictionary[int, Button] = {}
var _cancel_btn: Button
var _bonus_text: RichTextLabel
var _hint: Label


func setup(s: DistrictSystem, m: HexMap) -> void:
	sys = s
	map = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 复制引擎默认主题(保留按钮等样式),仅替换默认字体为微软雅黑
	var base_theme: Theme = ThemeDB.get_default_theme()
	var theme: Theme = Theme.new()
	if base_theme != null:
		theme = base_theme.duplicate()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 15
	var font_bold := SystemFont.new()
	font_bold.font_names = font.font_names
	font_bold.font_weight = 700
	self.theme = theme
	_build_info_panel(font_bold)
	_build_build_panel(font_bold)
	_build_bonus_panel(font_bold)
	_build_hint_bar()


## ----------------------------------------------------------------------------
## 左上:标题 + 地块信息
## ----------------------------------------------------------------------------

func _build_info_panel(bold: SystemFont) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(14, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "文明 6 · 高度六边形地图"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("e8d9a0"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "海拔造就丘陵与山脉 · 区域沿河靠山吃加成"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.68, 0.74, 0.8))
	box.add_child(sub)
	box.add_child(HSeparator.new())
	_info_coord = _row(box, "坐标: —")
	_info_terrain = _row(box, "地形: —")
	_info_elev = _row(box, "海拔: —")
	_info_feat = _row(box, "特征: —")
	_info_sea = _row(box, "距海: —")
	_info_defense = _row(box, "防御加成: —")
	_info_move = _row(box, "移动消耗: —")
	box.add_child(HSeparator.new())
	_info_district = _row(box, "区域: 无")
	var dc := _row(box, "已建区域加成:")
	dc.add_theme_color_override("font_color", Color(0.62, 0.68, 0.75))


func _row(box: VBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
	box.add_child(l)
	return l


## ----------------------------------------------------------------------------
## 右上:区域建造面板
## ----------------------------------------------------------------------------

func _build_build_panel(bold: SystemFont) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-14, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var title := Label.new()
	title.text = "区域建造(城市 3 格内)"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("e8d9a0"))
	box.add_child(title)
	for def in sys.defs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(12, 12)
		sw.color = def.color
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var btn := Button.new()
		btn.text = "%s · %s" % [def.name, def.yield_name]
		btn.tooltip_text = def.note
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_build_pressed.bind(int(def.id)))
		row.add_child(btn)
		_build_buttons[int(def.id)] = btn
		box.add_child(row)
	_cancel_btn = Button.new()
	_cancel_btn.text = "取消建造(Esc)"
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(func() -> void: cancel_requested.emit())
	box.add_child(_cancel_btn)


func _on_build_pressed(id: int) -> void:
	build_requested.emit(id)


## 进入 / 退出建造模式(高亮选中的类型按钮)
func set_build_mode(id: int) -> void:
	for d in _build_buttons:
		_build_buttons[d].button_pressed = (d == id)
	_cancel_btn.visible = id >= 0


## ----------------------------------------------------------------------------
## 右下:区域加成面板
## ----------------------------------------------------------------------------

func _build_bonus_panel(bold: SystemFont) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position = Vector2(-14, -14)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style(panel)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "已建区域与邻接加成"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("e8d9a0"))
	box.add_child(title)
	_bonus_text = RichTextLabel.new()
	_bonus_text.bbcode_enabled = true
	_bonus_text.fit_content = true
	_bonus_text.scroll_active = false
	_bonus_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bonus_text.custom_minimum_size = Vector2(300, 0)
	box.add_child(_bonus_text)


func refresh_bonus_panel() -> void:
	var text := ""
	var totals: Dictionary[String, int] = {}
	for def in sys.defs:
		if def.base_yield > 0:
			totals[def.yield_name] = 0
		for coord in map.tiles:
			var t := map.tiles[coord]
			if t.district != int(def.id):
				continue
			var adj := sys.adjacency(map, t.district, coord)
			text += "[color=#%s]■[/color] %s (%d, %d) %s +%d\n" % [
				def.color.to_html(false), def.name, t.q, t.r, def.yield_name, adj.total]
			for line in adj.lines:
				text += "        %s\n" % line
			if def.base_yield > 0:
				totals[def.yield_name] = int(totals[def.yield_name]) + adj.total
	text += "\n[b]帝国总产出:[/b] "
	var parts: Array[String] = []
	for yn in totals:
		parts.append("%s +%d" % [yn, int(totals[yn])])
	text += " · ".join(parts)
	_bonus_text.clear()
	_bonus_text.append_text(text)


## ----------------------------------------------------------------------------
## 底部:提示条
## ----------------------------------------------------------------------------

func _build_hint_bar() -> void:
	_hint = Label.new()
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.position = Vector2(-340, -34)
	_hint.size = Vector2(680, 24)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 0.9))
	add_child(_hint)


func set_hint(text: String) -> void:
	_hint.text = text


## ----------------------------------------------------------------------------
## 地块信息刷新
## ----------------------------------------------------------------------------

func set_tile_info(td: HexMap.HexTile) -> void:
	if td == null:
		_info_coord.text = "坐标: —"
		_info_terrain.text = "地形: —"
		_info_elev.text = "海拔: —"
		_info_feat.text = "特征: —"
		_info_sea.text = "距海: —"
		_info_defense.text = "防御加成: —"
		_info_move.text = "移动消耗: —"
		_info_district.text = "区域: 无"
		return
	_info_coord.text = "坐标: (%d, %d)" % [td.q, td.r]
	_info_terrain.text = "地形: %s" % HexMap.terrain_name(td)
	_info_elev.text = "海拔: %d · %s" % [td.elevation, HexMap.elevation_name(td.elevation)]
	var feat := "无"
	if td.has_woods:
		feat = "森林"
	elif td.has_fish:
		feat = "鱼群(海洋资源)"
	_info_feat.text = "特征: %s" % feat
	var sea_text := "—"
	if td.terrain == HexMap.Terrain.OCEAN:
		sea_text = "海洋"
	else:
		var wd: int = int(map.water_dist.get(Vector2i(td.q, td.r), 99))
		sea_text = "%d 格" % wd
	_info_sea.text = "距海: %s" % sea_text
	var db := HexMap.defense_bonus(td)
	_info_defense.text = "防御加成: %s" % ("+3(丘陵)" if db > 0 else "无")
	var mc := HexMap.move_cost(td)
	_info_move.text = "移动消耗: %s" % ("不可通行" if mc > 10 else str(mc))
	_info_district.text = "区域: %s" % sys.get_name(td.district)


## ----------------------------------------------------------------------------
## 面板样式
## ----------------------------------------------------------------------------

func _style(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.09, 0.86)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	sb.border_color = Color(0.45, 0.55, 0.65, 0.4)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
