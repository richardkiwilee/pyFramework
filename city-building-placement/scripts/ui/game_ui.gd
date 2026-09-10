class_name GameUI
extends Control
## UI 层：顶部资源栏、提示条、开拓确认框、三栏建造窗口、建筑弹窗（升级/拆除二次确认）。
## 注意：全部用普通 Label（RichTextLabel.fit_content 会撑出 230px 最小高度，见 topbar 教训）。

const BuildingData := preload("res://scripts/data/building_data.gd")
const TerrainData := preload("res://scripts/data/terrain_data.gd")

const RES_SHORT: Dictionary = {
	BuildingData.Res.GOLD: "金",
	BuildingData.Res.WOOD: "木",
	BuildingData.Res.FOOD: "食",
	BuildingData.Res.STONE: "石",
}

const RES_COLORS: Dictionary = {
	BuildingData.Res.GOLD: Color("#f9a825"),
	BuildingData.Res.WOOD: Color("#a1887f"),
	BuildingData.Res.FOOD: Color("#7cb342"),
	BuildingData.Res.STONE: Color("#bdbdbd"),
}

# 顶部资源栏（每个资源 3 个 Label：名称/数量/净产出）
var res_amount_labels: Dictionary = {}
var res_income_labels: Dictionary = {}
# 提示条
var toast_panel: PanelContainer
var toast_label: Label
var toast_timer: Timer
# 开拓确认框
var expand_overlay: CenterContainer
var expand_cell: Vector2i = Vector2i.ZERO
var expand_terrain: Label
var expand_cost_label: Label
var expand_res_label: Label
var expand_confirm: Button
# 三栏建造窗口
var bw_overlay: CenterContainer
var bw_cell: Vector2i = Vector2i.ZERO
var bw_selected: String = ""
var bw_filter: String = "all"
var bw_grid: GridContainer
var bw_detail: Label
var bw_reason: Label
var bw_build_button: Button
var bw_cancel_button: Button
var card_buttons: Dictionary = {}
var card_group: ButtonGroup
var tag_buttons: Dictionary = {}
# 建筑弹窗
var bp_overlay: CenterContainer
var bp_cell: Vector2i = Vector2i.ZERO
var bp_info: Label
var bp_actions: HBoxContainer
var bp_upgrade: Button
var bp_demolish: Button
var bp_confirm_box: VBoxContainer
var bp_close_row: HBoxContainer

var _icon_cache: Dictionary = {}
var _red_card_style: StyleBoxFlat


## headless -s 下 autoload 标识符编译期不可见，统一走 /root 访问
func _cs() -> CityCore:
	return get_node("/root/CityState") as CityCore


func _ready() -> void:
	_build_theme()
	_build_top_bar()
	_build_toast()
	_build_expand_panel()
	_build_build_window()
	_build_building_popup()
	_cs().changed.connect(refresh_all)


# ── 主题（微软雅黑，支持中文） ──

func _build_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	var theme: Theme = ThemeDB.get_default_theme().duplicate()
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("#eceff1"))
	theme.set_color("font_color", "Button", Color("#eceff1"))
	self.theme = theme


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#263238e6")
	s.border_color = Color("#546e7a")
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(12)
	return s


func _sub_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#1c262be6")
	s.border_color = Color("#37474f")
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(8)
	return s


# ── 顶部资源栏 ──

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.add_theme_stylebox_override("panel", _panel_style())
	add_child(bar)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	bar.add_child(hbox)
	for res: int in BuildingData.Res.values():
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var name_label := Label.new()
		name_label.text = str(BuildingData.RES_NAMES.get(res, "?"))
		name_label.add_theme_color_override("font_color", RES_COLORS.get(res, Color.WHITE))
		name_label.add_theme_font_size_override("font_size", 18)
		box.add_child(name_label)
		var amt_label := Label.new()
		amt_label.add_theme_font_size_override("font_size", 18)
		box.add_child(amt_label)
		var inc_label := Label.new()
		inc_label.add_theme_color_override("font_color", Color("#66bb6a"))
		inc_label.add_theme_font_size_override("font_size", 16)
		box.add_child(inc_label)
		res_amount_labels[res] = amt_label
		res_income_labels[res] = inc_label
		hbox.add_child(box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	var turn_btn := Button.new()
	turn_btn.text = "下一回合"
	turn_btn.pressed.connect(_cs().end_turn)
	hbox.add_child(turn_btn)
	var debug_btn := Button.new()
	debug_btn.text = "资源+100"
	debug_btn.pressed.connect(_cs().add_resources_debug)
	hbox.add_child(debug_btn)


func _refresh_top_bar() -> void:
	var income: Dictionary = _cs().net_income()
	for res: int in res_amount_labels.keys():
		var amt: Label = res_amount_labels[res]
		amt.text = str(int(_cs().resources.get(res, 0)))
		var inc: Label = res_income_labels[res]
		var inc_v: int = int(income.get(res, 0))
		if inc_v > 0:
			inc.text = "(+%d)" % inc_v
		else:
			inc.text = ""


# ── 提示条 ──

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.name = "Toast"
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.offset_top = 64.0
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.add_theme_stylebox_override("panel", _panel_style())
	toast_panel.visible = false
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_panel)
	toast_label = Label.new()
	toast_panel.add_child(toast_label)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 2.0
	toast_timer.timeout.connect(_hide_toast)
	add_child(toast_timer)


func show_toast(text: String) -> void:
	toast_label.text = text
	toast_panel.visible = true
	toast_timer.start()


func _hide_toast() -> void:
	toast_panel.visible = false


# ── 开拓确认框 ──

func _build_expand_panel() -> void:
	expand_overlay = CenterContainer.new()
	expand_overlay.name = "ExpandOverlay"
	expand_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	expand_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	expand_overlay.visible = false
	add_child(expand_overlay)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	expand_overlay.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "开拓地块"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	expand_terrain = Label.new()
	vbox.add_child(expand_terrain)
	expand_cost_label = Label.new()
	expand_cost_label.add_theme_font_size_override("font_size", 18)
	expand_cost_label.add_theme_color_override("font_color", Color("#ffd54f"))
	vbox.add_child(expand_cost_label)
	expand_res_label = Label.new()
	vbox.add_child(expand_res_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vbox.add_child(row)
	expand_confirm = Button.new()
	expand_confirm.text = "确认开拓"
	expand_confirm.pressed.connect(_on_expand_confirm)
	row.add_child(expand_confirm)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_on_expand_cancel)
	row.add_child(cancel)


func open_expand_confirm(cell: Vector2i) -> void:
	expand_cell = cell
	expand_overlay.visible = true
	_refresh_expand()


func _refresh_expand() -> void:
	if not expand_overlay.visible:
		return
	var terr: int = _cs().terrain_of(expand_cell)
	expand_terrain.text = "地形：%s" % TerrainData.terrain_name(terr)
	var cost: Dictionary = _cs().expand_cost(expand_cell)
	expand_cost_label.text = "开拓费用：%s" % format_cost(cost)
	expand_res_label.text = "当前资源：%s" % _format_res_amounts()
	expand_confirm.disabled = not _cs().can_afford(cost)


func _on_expand_confirm() -> void:
	if _cs().expand(expand_cell):
		expand_overlay.visible = false
	else:
		show_toast("资源不足，无法开拓")


func _on_expand_cancel() -> void:
	expand_overlay.visible = false


# ── 三栏建造窗口 ──

func _build_build_window() -> void:
	bw_overlay = CenterContainer.new()
	bw_overlay.name = "BuildWindowOverlay"
	bw_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	bw_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	bw_overlay.visible = false
	add_child(bw_overlay)
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", _panel_style())
	window.custom_minimum_size = Vector2(1240, 620)
	bw_overlay.add_child(window)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	window.add_child(vbox)
	var title := Label.new()
	title.text = "选择建筑"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	# 左：筛选 tag
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", _sub_panel_style())
	left.custom_minimum_size = Vector2(130, 0)
	hbox.add_child(left)
	var tag_box := VBoxContainer.new()
	tag_box.add_theme_constant_override("separation", 6)
	left.add_child(tag_box)
	var tag_group := ButtonGroup.new()
	_make_tag_button(tag_box, tag_group, "all", "全部", true)
	for cat: String in BuildingData.CATEGORIES:
		if cat == "special":
			continue
		_make_tag_button(tag_box, tag_group, cat, str(BuildingData.CATEGORY_NAMES.get(cat, cat)), false)
	# 中：卡片网格
	var mid := PanelContainer.new()
	mid.add_theme_stylebox_override("panel", _sub_panel_style())
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(mid)
	bw_grid = GridContainer.new()
	bw_grid.columns = 5
	bw_grid.add_theme_constant_override("h_separation", 8)
	bw_grid.add_theme_constant_override("v_separation", 8)
	mid.add_child(bw_grid)
	# 右：详情
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", _sub_panel_style())
	right.custom_minimum_size = Vector2(310, 0)
	hbox.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	bw_detail = Label.new()
	bw_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bw_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bw_detail.text = "选择建筑查看详情"
	rv.add_child(bw_detail)
	bw_reason = Label.new()
	bw_reason.add_theme_color_override("font_color", Color("#ef5350"))
	bw_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(bw_reason)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	rv.add_child(btn_row)
	bw_build_button = Button.new()
	bw_build_button.text = "建造"
	bw_build_button.add_theme_font_size_override("font_size", 18)
	bw_build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bw_build_button.pressed.connect(_on_build_pressed)
	btn_row.add_child(bw_build_button)
	bw_cancel_button = Button.new()
	bw_cancel_button.text = "取消建造"
	bw_cancel_button.pressed.connect(_on_cancel_build_pressed)
	btn_row.add_child(bw_cancel_button)
	card_group = ButtonGroup.new()


func _make_tag_button(box: VBoxContainer, group: ButtonGroup, cat: String, label_text: String, pressed: bool) -> void:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = group
	btn.text = label_text
	btn.button_pressed = pressed
	btn.custom_minimum_size = Vector2(0, 34)
	btn.pressed.connect(_on_tag_pressed.bind(cat))
	box.add_child(btn)
	tag_buttons[cat] = btn


func _on_tag_pressed(cat: String) -> void:
	bw_filter = cat
	_rebuild_cards()


func _update_tag_buttons() -> void:
	for cat: String in tag_buttons.keys():
		var btn: Button = tag_buttons[cat]
		btn.set_pressed_no_signal(cat == bw_filter)


func open_build_window(cell: Vector2i) -> void:
	bw_cell = cell
	bw_selected = ""
	bw_filter = "all"
	_update_tag_buttons()
	_rebuild_cards()
	bw_overlay.visible = true


func _category_icon(cat: String) -> Texture2D:
	if not _icon_cache.has(cat):
		var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		img.fill(BuildingData.CATEGORY_COLORS.get(cat, Color.GRAY))
		_icon_cache[cat] = ImageTexture.create_from_image(img)
	return _icon_cache[cat]


func _rebuild_cards() -> void:
	for child: Node in bw_grid.get_children():
		bw_grid.remove_child(child)
		child.free()
	card_buttons.clear()
	for id: String in BuildingData.BUILDINGS.keys():
		if id == BuildingData.CITY_CENTER_ID:
			continue
		var data: Dictionary = BuildingData.BUILDINGS[id]
		var cat: String = str(data.get("category", ""))
		if bw_filter != "all" and cat != bw_filter:
			continue
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = card_group
		btn.custom_minimum_size = Vector2(158, 92)
		btn.expand_icon = true
		btn.icon = _category_icon(cat)
		var cost_text: String = format_cost(data.get("cost", {}))
		btn.text = "%s\n%s" % [str(data.get("name", id)), cost_text]
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_card_pressed.bind(id))
		card_buttons[id] = btn
		bw_grid.add_child(btn)
	if bw_selected != "" and card_buttons.has(bw_selected):
		var sel: Button = card_buttons[bw_selected]
		sel.button_pressed = true
	_refresh_card_states()
	_refresh_details()


func _red_card_stylebox() -> StyleBoxFlat:
	if _red_card_style == null:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#3a1f1f")
		s.border_color = Color("#ef5350")
		s.set_border_width_all(2)
		s.set_corner_radius_all(4)
		s.set_content_margin_all(4)
		_red_card_style = s
	return _red_card_style


func _refresh_card_states() -> void:
	if not bw_overlay.visible:
		return
	for id: String in card_buttons.keys():
		var btn: Button = card_buttons[id]
		var reason: String = _cs().build_block_reason(bw_cell, id)
		if reason.is_empty():
			btn.remove_theme_stylebox_override("normal")
			btn.tooltip_text = ""
		else:
			btn.add_theme_stylebox_override("normal", _red_card_stylebox())
			btn.tooltip_text = reason


func _on_card_pressed(id: String) -> void:
	bw_selected = id
	_refresh_details()


func _on_build_pressed() -> void:
	if bw_selected == "":
		return
	if _cs().build(bw_cell, bw_selected):
		bw_overlay.visible = false
	else:
		show_toast("无法建造")


## 取消建造：关闭窗口、回到六边形地图
func _on_cancel_build_pressed() -> void:
	bw_overlay.visible = false


func _check_text(ok: bool) -> String:
	if ok:
		return "✓"
	return "✗"


func _terrain_req_text(req: Array) -> String:
	var parts: Array[String] = []
	for t: int in req:
		parts.append(TerrainData.terrain_name(t))
	var joined: String = "、".join(parts)
	if req.size() == 1:
		return "仅" + joined
	return joined


func adjacency_text(entry: Dictionary) -> String:
	var names: Array[String] = []
	for id: String in entry.get("ids", []):
		names.append(BuildingData.building_name(id))
	for c: String in entry.get("cats", []):
		names.append(str(BuildingData.CATEGORY_NAMES.get(c, c)) + "类建筑")
	var res: int = int(entry.get("res", 0))
	return "相邻" + "、".join(names) + " +%d%s" % [int(entry.get("amt", 0)), str(RES_SHORT.get(res, "?"))]


func _refresh_details() -> void:
	if bw_selected == "" or not card_buttons.has(bw_selected):
		bw_detail.text = "选择建筑查看详情"
		bw_reason.text = ""
		bw_build_button.disabled = true
		return
	var id: String = bw_selected
	var data: Dictionary = BuildingData.BUILDINGS[id]
	var cat: String = str(data.get("category", ""))
	var lines: Array[String] = []
	lines.append("%s（%s）" % [str(data.get("name", id)), str(BuildingData.CATEGORY_NAMES.get(cat, cat))])
	lines.append("建造费用：%s" % format_cost(data.get("cost", {})))
	lines.append("产出/回合：%s（每级 +50%%）" % format_yield(data.get("yields", {})))
	var adj: Array = data.get("adjacency", [])
	for entry: Dictionary in adj:
		lines.append("相邻加成：%s（每级 +1）" % adjacency_text(entry))
	var wb: Dictionary = data.get("water_bonus", {})
	if not wb.is_empty():
		lines.append("水域加成：相邻水域 %s（每格水域单独计，每级 +1）" % format_yield(wb))
	var mb: Dictionary = data.get("match_bonus", {})
	for t: int in mb.keys():
		lines.append("匹配加成：%s %s（每级 +1）" % [TerrainData.terrain_name(t), format_yield(mb[t])])
	var terr: int = _cs().terrain_of(bw_cell)
	var req: Array = data.get("terrain_req", [])
	var terr_ok: bool = req.has(terr)
	lines.append("地形要求：%s  %s（当前：%s）" % [_terrain_req_text(req), _check_text(terr_ok), TerrainData.terrain_name(terr)])
	var adj_req: Array = data.get("adj_req", [])
	for entry: Dictionary in adj_req:
		var tlist: Array = entry.get("terrains", [])
		var count: int = _cs().count_adjacent_terrain(bw_cell, tlist)
		lines.append("相邻要求：需相邻%s  %s（当前 %d 格相邻）" % [_cs().terrain_list_name(tlist), _check_text(count > 0), count])
	lines.append("等级上限：%d" % int(data.get("max_level", 1)))
	bw_detail.text = "\n".join(lines)
	var reason: String = _cs().build_block_reason(bw_cell, id)
	if reason.is_empty():
		bw_reason.text = ""
		bw_build_button.disabled = false
	else:
		bw_reason.text = "无法建造：%s" % reason
		bw_build_button.disabled = true


# ── 建筑弹窗（升级 / 拆除二次确认） ──

func _build_building_popup() -> void:
	bp_overlay = CenterContainer.new()
	bp_overlay.name = "BuildingPopupOverlay"
	bp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	bp_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	bp_overlay.visible = false
	add_child(bp_overlay)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(360, 0)
	bp_overlay.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	bp_info = Label.new()
	vbox.add_child(bp_info)
	bp_actions = HBoxContainer.new()
	bp_actions.add_theme_constant_override("separation", 10)
	vbox.add_child(bp_actions)
	bp_upgrade = Button.new()
	bp_upgrade.pressed.connect(_on_upgrade_pressed)
	bp_actions.add_child(bp_upgrade)
	bp_demolish = Button.new()
	bp_demolish.text = "拆除（不返还）"
	bp_demolish.pressed.connect(_on_demolish_ask)
	bp_actions.add_child(bp_demolish)
	bp_confirm_box = VBoxContainer.new()
	bp_confirm_box.add_theme_constant_override("separation", 10)
	bp_confirm_box.visible = false
	vbox.add_child(bp_confirm_box)
	var confirm_label := Label.new()
	confirm_label.text = "确定拆除？不返还资源"
	bp_confirm_box.add_child(confirm_label)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 10)
	bp_confirm_box.add_child(confirm_row)
	var confirm_btn := Button.new()
	confirm_btn.text = "确认拆除"
	confirm_btn.pressed.connect(_on_demolish_confirm)
	confirm_row.add_child(confirm_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_on_demolish_cancel)
	confirm_row.add_child(cancel_btn)
	# 关闭行：任何状态（含市中心纯信息弹窗）都可用，避免弹窗卡死
	bp_close_row = HBoxContainer.new()
	vbox.add_child(bp_close_row)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(_on_popup_close_pressed)
	bp_close_row.add_child(close_btn)


func open_building_popup(cell: Vector2i) -> void:
	bp_cell = cell
	bp_confirm_box.visible = false
	bp_overlay.visible = true
	_refresh_building_popup()


func _refresh_building_popup() -> void:
	if not bp_overlay.visible:
		return
	var b: Dictionary = _cs().building_at(bp_cell)
	var id: String = str(b.get("id", ""))
	var level: int = int(b.get("level", 1))
	var data: Dictionary = BuildingData.BUILDINGS.get(id, {})
	var max_level: int = int(data.get("max_level", 1))
	var y: Dictionary = _cs().building_yield(bp_cell)
	var is_center: bool = id == BuildingData.CITY_CENTER_ID
	bp_actions.visible = not is_center
	if is_center:
		bp_info.text = "%s\n每回合产出：%s\n（市中心：不可拆除、不可升级）" % [
			str(data.get("name", id)), format_yield(y)
		]
		return
	bp_info.text = "%s Lv.%d/%d\n每回合产出：%s" % [str(data.get("name", id)), level, max_level, format_yield(y)]
	if level >= max_level:
		bp_upgrade.text = "已满级"
		bp_upgrade.disabled = true
	else:
		var cost: Dictionary = _cs().upgrade_cost(bp_cell)
		bp_upgrade.text = "升级（%s）" % format_cost(cost)
		bp_upgrade.disabled = not _cs().can_afford(cost)


func _on_upgrade_pressed() -> void:
	if _cs().upgrade(bp_cell):
		bp_overlay.visible = false
	else:
		show_toast("资源不足，无法升级")


func _on_demolish_ask() -> void:
	bp_actions.visible = false
	bp_confirm_box.visible = true


func _on_demolish_confirm() -> void:
	_cs().demolish(bp_cell)
	bp_overlay.visible = false


func _on_demolish_cancel() -> void:
	bp_confirm_box.visible = false
	bp_actions.visible = true


func _on_popup_close_pressed() -> void:
	bp_overlay.visible = false


# ── 点击分发 ──

func on_tile_clicked(cell: Vector2i) -> void:
	if not TerrainData.LAYOUT.has(cell):
		return
	if _cs().is_built(cell):
		open_building_popup(cell)
	elif _cs().is_owned(cell):
		open_build_window(cell)
	elif _cs().can_expand(cell):
		open_expand_confirm(cell)
	else:
		show_toast("未与城市接壤，无法开拓")


# ── 刷新与格式化 ──

func refresh_all() -> void:
	_refresh_top_bar()
	_refresh_expand()
	_refresh_card_states()
	_refresh_details()
	_refresh_building_popup()


func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for res: int in BuildingData.Res.values():
		if cost.has(res) and int(cost[res]) > 0:
			parts.append("%d%s" % [int(cost[res]), str(RES_SHORT.get(res, "?"))])
	if parts.is_empty():
		return "免费"
	return " ".join(parts)


func format_yield(y: Dictionary) -> String:
	var parts: Array[String] = []
	for res: int in BuildingData.Res.values():
		if y.has(res) and int(y[res]) > 0:
			parts.append("+%d%s" % [int(y[res]), str(RES_SHORT.get(res, "?"))])
	if parts.is_empty():
		return "无"
	return " ".join(parts)


func _format_res_amounts() -> String:
	var parts: Array[String] = []
	for res: int in BuildingData.Res.values():
		parts.append("%d%s" % [int(_cs().resources.get(res, 0)), str(RES_SHORT.get(res, "?"))])
	return " ".join(parts)


# ── 测试驱动辅助 ──

func select_card(id: String) -> void:
	if not card_buttons.has(id):
		return
	bw_selected = id
	var btn: Button = card_buttons[id]
	btn.button_pressed = true
	_refresh_details()


func close_build_window() -> void:
	bw_overlay.visible = false


func close_building_popup() -> void:
	bp_overlay.visible = false


func show_popup_demolish_confirm() -> void:
	bp_actions.visible = false
	bp_confirm_box.visible = true
