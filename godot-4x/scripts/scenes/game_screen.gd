## 游戏主场景（现代 4X 布局，层级从底到顶）：
##   地图(底) → 左下按钮/据点信息层 → 建造浮层 → Toast → 帝国总览
##   → 全屏页面层（小队管理/招募/科技文化/百科等）→ 顶部状态栏(最顶，始终可见)。
## 顶栏：左侧日历 + 全局资源（图标占位+下回合变更），右侧 百科/日志/设置 按钮。
## 全屏页面：占满顶栏下空间、无关闭按钮、ESC 关闭（BasePage 页面栈）。
class_name GameScreen
extends BaseScreen

const TOP_H := 46
const PANEL_H := 212

var _day_label: Label
var _res_box: HBoxContainer
var _map_view: MapView
var _overlay: Control
var _overlay_box: VBoxContainer
var _overlay_visible := false
var _toast: Label
var _toast_timer: Timer
var _page_layer: Control          # 全屏页面层（顶栏之下）
var _pages: Array = []            # 页面栈 [BasePage]

# 底部据点信息栏
var _sel_node := ""
var _info_panel: PanelContainer
var _info_title: Label
var _slot_box: HBoxContainer
var _build_popup: Control
var _build_box: VBoxContainer
var _popup_for_stronghold := ""
var _more_popup: Control
var _more_box: VBoxContainer

## 资源条图标色（图标占位：彩色方块，日后换美术图标）。
const RES_ICON: Dictionary = {
	"gold": Color("f5d76e"), "food": Color("58c46b"), "wood": Color("8a6f4d"),
	"stone": Color("9aa5b1"), "iron": Color("c9d4e4"), "mana_stone": Color("7bd3e6"),
	"tech": Color("7bd3e6"), "culture": Color("d9a6e0"), "faith": Color("e8b33c"),
	"luxury": Color("e05a5a"), "decree": Color("9fb4d6"),
}

## 地标档位 → 中文源串（i18n msgid）。
const LANDMARK_TIER_CN: Dictionary = {
	"weak": "弱地标", "medium": "中地标", "strong": "强地标",
}

## 建筑分类（TW3K 五色分类简化版）：产出=绿 / 招募=红 / 特殊=金。
## label/tag 为 i18n msgid。
const KIND_GROUP: Dictionary = {
	"produce": {"label": "kind_produce", "tag": "kind_tag_produce", "color": UiTheme.C_OWN},
	"recruit": {"label": "kind_recruit", "tag": "kind_tag_recruit", "color": UiTheme.C_ENEMY},
	"special": {"label": "kind_special", "tag": "kind_tag_special", "color": UiTheme.GOLD},
}

func build() -> void:
	# 地图（主画面，最底层）
	_map_view = MapView.new()
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_view.offset_top = TOP_H + 2
	_map_view.selectable = true
	_map_view.node_clicked.connect(_on_node_clicked)
	_map_view.army_selected.connect(_on_army_selected)
	_map_view.army_move_requested.connect(_on_army_move)
	_map_view.army_cancelled.connect(func(): _toast_msg(Loc.t("move_cancel")))
	add_child(_map_view)
	# 左下角图标按钮：科技文化 / 管理小队 / 招募单位 / 更多
	var left_btns := VBoxContainer.new()
	left_btns.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left_btns.offset_left = 10
	left_btns.offset_top = -264
	left_btns.offset_bottom = -10
	left_btns.add_theme_constant_override("separation", 6)
	add_child(left_btns)
	var tech_btn := IconButton.new(IconButton.Kind.TECH, Loc.t("tech_culture"))
	tech_btn.pressed.connect(_open_tech_culture)
	left_btns.add_child(tech_btn)
	var squad_btn := IconButton.new(IconButton.Kind.SQUAD, Loc.t("squad"))
	squad_btn.pressed.connect(_open_army)
	left_btns.add_child(squad_btn)
	var recruit_btn := IconButton.new(IconButton.Kind.RECRUIT, Loc.t("recruit"))
	recruit_btn.pressed.connect(_open_recruit)
	left_btns.add_child(recruit_btn)
	var more_btn := IconButton.new(IconButton.Kind.MORE, Loc.t("more"))
	more_btn.pressed.connect(_show_more_popup)
	left_btns.add_child(more_btn)
	# 右下角：结束回合按钮（T 键的鼠标等价物；TW3K 结束回合常驻按钮）
	var end_btn := IconButton.new(IconButton.Kind.END_TURN, Loc.t("end_turn"))
	end_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	end_btn.offset_left = -70
	end_btn.offset_top = -70
	end_btn.offset_right = -12
	end_btn.offset_bottom = -12
	end_btn.pressed.connect(_end_turn)
	add_child(end_btn)
	# 更多弹窗（键盘页面的鼠标入口：单位名册/据点总览/背包/据点/地图/招募单位/菜单）
	_more_popup = Control.new()
	_more_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_more_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_more_popup.visible = false
	add_child(_more_popup)
	var more_dim := ColorRect.new()
	more_dim.color = Color(0, 0, 0, 0.45)
	more_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_more_popup.add_child(more_dim)
	more_dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_more_popup.visible = false)
	var more_center := CenterContainer.new()
	more_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	more_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more_popup.add_child(more_center)
	var more_frame := Frame.new(Loc.t("more"))
	more_frame.custom_minimum_size = Vector2(300, 0)
	more_center.add_child(more_frame)
	_more_box = VBoxContainer.new()
	_more_box.add_theme_constant_override("separation", 6)
	more_frame.add_child(_more_box)
	# Toast（左下角，最近日志反馈，3 秒隐藏）
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_toast.offset_left = 10
	_toast.offset_top = -30
	_toast.offset_bottom = -8
	_toast.add_theme_font_size_override("font_size", 13)
	_toast.add_theme_color_override("font_color", UiTheme.FG)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	_toast_timer = Timer.new()
	_toast_timer.wait_time = 3.0
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast.visible = false)
	add_child(_toast_timer)
	# 底部据点信息栏（初始隐藏）
	_info_panel = PanelContainer.new()
	_info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_info_panel.offset_top = -PANEL_H - 8
	_info_panel.offset_bottom = -8
	_info_panel.offset_left = 300
	_info_panel.offset_right = -300
	_info_panel.visible = false
	add_child(_info_panel)
	_build_info_panel()
	# 建造选项浮层（居中，初始隐藏）
	_build_popup = Control.new()   # 根：全屏（遮罩铺满 + 面板居中）
	_build_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_popup.visible = false
	add_child(_build_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_popup.add_child(dim)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_hide_build_popup())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡事件：外部点击透传到遮罩关闭
	_build_popup.add_child(center)
	var frame := Frame.new(Loc.t("build_candidates"))
	frame.custom_minimum_size = Vector2(420, 320)
	center.add_child(frame)
	# 分组后候补可能超出高度：内容放滚动容器
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	_build_box = VBoxContainer.new()
	_build_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_build_box)
	# 帝国总览 overlay（按住 Tab 显示）
	_overlay = _build_overlay()
	add_child(_overlay)
	_overlay.visible = false
	# 全屏页面层（占满顶栏下空间；顶栏在其上层，始终可见）
	_page_layer = Control.new()
	_page_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_layer.offset_top = TOP_H
	_page_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_layer)
	# 顶部状态栏（最后 add = 最顶层，任何页面之上都可见）
	_build_top_bar()

func _build_top_bar() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_top = 4
	top_bar.offset_bottom = TOP_H
	top_bar.add_theme_constant_override("separation", 8)
	add_child(top_bar)
	_day_label = Label.new()
	_day_label.add_theme_font_size_override("font_size", 13)
	_day_label.add_theme_color_override("font_color", UiTheme.HEADING)
	top_bar.add_child(_day_label)
	_res_box = HBoxContainer.new()
	_res_box.add_theme_constant_override("separation", 10)
	_res_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_res_box)
	# 右侧按钮：百科 / 日志 / 设置
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	top_bar.add_child(right)
	var wiki_btn := IconButton.new(IconButton.Kind.WIKI, Loc.t("wiki"))
	wiki_btn.custom_minimum_size = Vector2(40, 40)
	wiki_btn.pressed.connect(_open_wiki)
	right.add_child(wiki_btn)
	var log_btn := IconButton.new(IconButton.Kind.LOG, Loc.t("log"))
	log_btn.custom_minimum_size = Vector2(40, 40)
	log_btn.pressed.connect(_open_log)
	right.add_child(log_btn)
	var settings_btn := IconButton.new(IconButton.Kind.SETTINGS, Loc.t("settings"))
	settings_btn.custom_minimum_size = Vector2(40, 40)
	settings_btn.pressed.connect(_open_settings)
	right.add_child(settings_btn)

func _build_info_panel() -> void:
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 10)
	inner.add_theme_constant_override("margin_right", 10)
	inner.add_theme_constant_override("margin_top", 6)
	inner.add_theme_constant_override("margin_bottom", 6)
	_info_panel.add_child(inner)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	inner.add_child(vbox)
	# 标题行：据点名 + 归属 + 关闭
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 16)
	_info_title.add_theme_color_override("font_color", UiTheme.HEADING)
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_info_title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(func():
		_sel_node = ""
		_info_panel.visible = false)
	title_row.add_child(close_btn)
	# 槽位行：居中，从左到右 —— 最左大地标方块 + 按规模排列的普通槽方块
	_slot_box = HBoxContainer.new()
	_slot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_box.add_theme_constant_override("separation", 10)
	vbox.add_child(_slot_box)

func _build_overlay() -> Control:
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var frame := Frame.new(Loc.t("empire_overview"))
	frame.custom_minimum_size = Vector2(520, 420)
	center.add_child(frame)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	frame.add_child(vbox)
	for i in range(12):
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(l)
	_overlay_box = vbox
	return ov

func _fill_overlay() -> void:
	var g := GameController.game
	if g == null:
		return
	var p := GameController.player()
	var vbox: VBoxContainer = _overlay_box
	var lines: Array[String] = [
		Loc.t("faction") + "  " + p.name,
		g.calendar.describe(),
		"%s %d   %s %d   %s %d" % [Loc.t("strongholds_short"), p.stronghold_ids.size(),
			Loc.t("armies_short"), p.army_ids.size(), Loc.t("heroes_short"), p.hero_ids.size()],
	]
	for dim in Economy.BELIEF_DIMS:
		lines.append("%s:%+d" % [Economy.BELIEF_CN[dim], p.belief.get_value(dim)])
	lines.append(Loc.t("resources"))
	for k in Economy.RESOURCE_TYPES:
		lines.append("%s:%d" % [Economy.RESOURCE_CN[k], p.resources.get_amount(k)])
	if g.is_over():
		lines.append(Loc.t("game_over") + " · " + Loc.t("winner") + " " + g.winner)
	for i in range(vbox.get_child_count()):
		var l: Label = vbox.get_child(i)
		if i < lines.size():
			l.text = lines[i]
			l.add_theme_color_override("font_color", UiTheme.ACCENT if i == 1 else UiTheme.FG)
		else:
			l.text = ""

# ---------- 顶栏刷新 ----------
func refresh() -> void:
	var g := GameController.game
	if g == null:
		return
	var c := g.calendar
	var moon := Loc.t(c.moon_phase_name())
	var tod := Loc.t(c.time_of_day_name())
	_day_label.text = "%s %d · %s · %s" % [Loc.t("day"), c.day, tod, moon]
	# 资源行（重建，避免残留）
	for ch in _res_box.get_children():
		ch.queue_free()
	var p := GameController.player()
	for k in Economy.RESOURCE_TYPES:
		var v := p.resources.get_amount(k)
		if v == 0:
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 3)
		_res_box.add_child(item)
		# 图标占位：彩色小方块（美术替换点）
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(12, 12)
		icon.color = RES_ICON.get(k, UiTheme.FG)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(icon)
		var net := p.resources.resource(k).display_net()
		var txt := "%s %d" % [Economy.RESOURCE_CN[k], v]
		if net != 0:
			var sign := "+" if net > 0 else ""
			txt += "(%s%d)" % [sign, net]
		var l := Label.new()
		l.text = txt
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.FG)
		item.add_child(l)
		# 悬停细项（来源/数值）
		var deltas := p.resources.deltas_of(k)
		if not deltas.is_empty():
			var sub: Array[String] = []
			for d in deltas:
				sub.append("%s %+d%s" % [_source_cn(d.source), d.value,
					(" " + d.building if d.building != "" else "")])
			l.tooltip_text = "%s: %s" % [Economy.RESOURCE_CN[k], "、".join(sub)]
	_refresh_info_panel()

func _source_cn(src: String) -> String:
	match src:
		Economy.SOURCE_BUILD: return Loc.t("src_build")
		Economy.SOURCE_MAINT: return Loc.t("src_maint")
		Economy.SOURCE_EVENT: return Loc.t("src_event")
		Economy.SOURCE_RECRUIT: return Loc.t("src_recruit")
		Economy.SOURCE_TRAIN: return Loc.t("src_train")
		Economy.SOURCE_SUPPLY: return Loc.t("src_supply")
		_: return Loc.t("src_unknown")

# ---------- 底部据点信息栏 ----------
func _on_node_clicked(nid: String) -> void:
	var g := GameController.game
	if g == null:
		return
	if g.map.strongholds.has(nid):
		if _sel_node == nid:
			_sel_node = ""
			_info_panel.visible = false
			return
		_sel_node = nid
		_info_panel.visible = true
		_refresh_info_panel()
	else:
		# 小地点：Toast 提示地形
		var mi: MapSystem.MinorLocation = g.map.minors[nid]
		_toast_msg("%s · %s" % [Loc.t(mi.name), Loc.t(mi.terrain)])

func _refresh_info_panel() -> void:
	var g := GameController.game
	if _sel_node == "" or not g.map.strongholds.has(_sel_node):
		return
	var sh: MapSystem.Stronghold = g.map.strongholds[_sel_node]
	var own := sh.owner == g.player_id
	_info_title.text = "%s  %s" % [Loc.t(sh.name),
		Loc.t("you") if own else (
			Loc.t("neutral") if sh.owner == "" else Loc.t(g.factions[sh.owner].name))]
	# 槽位行：从左到右 —— 最左大地标方块 + 按规模排列的普通槽方块
	for ch in _slot_box.get_children():
		ch.queue_free()
	# 地标（稍大方块，金框）
	var lm := BuildingSlot.new(true)
	lm.title = Loc.t(sh.landmark.name) if sh.landmark != null else Loc.t("无地标")
	if sh.landmark != null:
		lm.state = BuildingSlot.State.BUILDING
		lm.subtitle = Loc.t(LANDMARK_TIER_CN.get(sh.landmark.tier, "地标"))
		lm.tooltip_text = Loc.t("landmark")
	else:
		lm.state = BuildingSlot.State.EMPTY
	lm.clicked.connect(func():
		if sh.landmark != null:
			_toast_msg("%s（%s）" % [Loc.t(sh.landmark.name), lm.subtitle]))
	_slot_box.add_child(lm)
	# 普通槽：数量 = 据点规模（size 1~5）
	for i in range(sh.size):
		var slot := BuildingSlot.new()
		if i < sh.buildings.size():
			var b: MapSystem.Building = sh.buildings[i]
			slot.state = BuildingSlot.State.BUILDING
			slot.title = Loc.t(b.name)
			slot.subtitle = _produces_str(b.produces)
			slot.tooltip_text = Loc.t("click_x_demolish")
			# 点方块本体：查看建筑信息（不拆除）；只有点右上角红×才拆除
			slot.clicked.connect(func():
				var prod := _produces_str(b.produces)
				_toast_msg(Loc.t(b.name) + (("：%s" % prod) if prod != "" else "")))
			slot.demolish_clicked.connect(func():
				var msg := g.action_demolish(g.player_id, _sel_node, b.id)
				GameController.push_log(msg, msg.begins_with("失败"))
				refresh())
		else:
			slot.title = Loc.t("empty_slot")
			if own:
				slot.state = BuildingSlot.State.EMPTY
				slot.tooltip_text = Loc.t("click_build")
				slot.clicked.connect(func(): _show_build_popup(_sel_node))
			else:
				slot.state = BuildingSlot.State.LOCKED
				slot.tooltip_text = Loc.t("not_yours")
		_slot_box.add_child(slot)

## 建筑产出描述（如 "+5 食物"）。
func _produces_str(produces: Dictionary) -> String:
	if produces.is_empty():
		return ""
	var parts: Array[String] = []
	for k in produces:
		parts.append("%+d%s" % [int(produces[k]), Economy.RESOURCE_CN.get(k, k)])
	return "、".join(parts)

# ---------- 建造选项浮层 ----------
func _show_build_popup(sid: String) -> void:
	var g := GameController.game
	_popup_for_stronghold = sid
	var p := GameController.player()
	for ch in _build_box.get_children():
		ch.queue_free()
	var sh: MapSystem.Stronghold = g.map.strongholds[sid]
	var title := Label.new()
	title.text = "%s - %s" % [Loc.t(sh.name), Loc.t("build_candidates")]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiTheme.HEADING)
	_build_box.add_child(title)
	# 按 kind 分组（TW3K 五色分类简化版：产出=绿 / 招募=红 / 特殊=金）
	var groups: Dictionary = {}   # kind -> [bid]
	for bid in g.building_defs:
		var bdef: Dictionary = g.building_defs[bid]
		var kind: String = bdef.get("kind", "")
		if not KIND_GROUP.has(kind):
			continue
		if not groups.has(kind):
			groups[kind] = []
		(groups[kind] as Array).append(bid)
	var has := false
	for kind in ["produce", "recruit", "special"]:
		if not groups.has(kind) or (groups[kind] as Array).is_empty():
			continue
		has = true
		_add_build_kind_group(g, p, kind, groups[kind])
	if not has:
		var nl := Label.new()
		nl.text = Loc.t("no_items")
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", UiTheme.DIM)
		_build_box.add_child(nl)
	var hint := Label.new()
	hint.text = Loc.t("click_empty_close")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.DIM)
	_build_box.add_child(hint)
	_build_popup.visible = true

## 一组同 kind 的建造候补：彩色分组标题 + 带 [分类] 标签的候补按钮。
func _add_build_kind_group(g: Game, p: Faction.Faction_, kind: String, bids: Array) -> void:
	var cfg: Dictionary = KIND_GROUP[kind]
	var head := Label.new()
	head.text = Loc.t(cfg["label"])
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", cfg["color"])
	_build_box.add_child(head)
	for bid in bids:
		var bdef: Dictionary = g.building_defs[bid]
		var requires: Array = bdef.get("requires", [])
		var unmet := g._unmet_requires(g.player_id, requires)
		var affordable := p.resources.can_afford(bdef.get("cost", {}))
		var btn := Button.new()
		var cost := _cost_str(bdef.get("cost", {}))
		var extra: String = ""
		if not unmet.is_empty():
			extra = Loc.t("req_not_met")
		elif not affordable:
			extra = Loc.t("req_poor")
		btn.text = "[%s] %s  %s%s" % [Loc.t(cfg["tag"]), Loc.t(bdef.get("name", bid)),
			cost, ("  [%s]" % extra if extra != "" else "")]
		btn.disabled = not unmet.is_empty() or not affordable
		btn.tooltip_text = bdef.get("desc", "")
		btn.pressed.connect(func():
			var msg := g.action_build(g.player_id, _popup_for_stronghold, bid)
			GameController.push_log(msg, msg.begins_with("失败"))
			_hide_build_popup()
			refresh())
		_build_box.add_child(btn)

func _hide_build_popup() -> void:
	_build_popup.visible = false

func _cost_str(cost: Dictionary) -> String:
	if cost.is_empty():
		return Loc.t("cost_free")
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [Economy.RESOURCE_CN.get(k, k), int(cost[k])])
	return "、".join(parts)

# ---------- 部队地图移动 ----------
func _on_army_selected(aid: String) -> void:
	var a: Armies.Army = GameController.game.armies[aid]
	_toast_msg("%s：%s" % [Loc.t("army_selected"), Loc.t(a.name)])

func _on_army_move(aid: String, nid: String) -> void:
	var msg := GameController.game.action_move_attack(GameController.game.player_id, aid, nid)
	GameController.push_log(msg, msg.begins_with("失败"))
	refresh()

# ---------- 全屏页面栈（层级：地图→按钮/据点→页面→顶栏） ----------
## 打开全屏页面：加入 _page_layer（顶栏之下），ESC 关闭。
func _open_page(scene: Control, params: Variant = null) -> void:
	if scene == null:
		return
	_pages.append(scene)
	_page_layer.add_child(scene)
	_page_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	if scene.has_signal("close_requested"):
		scene.close_requested.connect(func(v: Variant): _close_page(v))
	if scene.has_method("enter_page"):
		scene.enter_page(params)
	refresh()

## 关闭栈顶页面，回值交付给新栈顶 return_page（或主场景 _on_page_closed）。
func _close_page(value: Variant = null) -> void:
	if _pages.is_empty():
		return
	var page: Node = _pages.pop_back()
	if page.has_method("exit_page"):
		page.exit_page()
	page.queue_free()
	if not _pages.is_empty():
		var top: Node = _pages.back()
		if top.has_method("return_page"):
			top.return_page(value)
	else:
		_page_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_on_page_closed(value)
	refresh()

## 页面栈清空时收到回值（默认无操作；页面自定义回值应覆写 return_page）。
func _on_page_closed(value: Variant = null) -> void:
	pass

## 当前是否有页面打开。
func has_page() -> bool:
	return not _pages.is_empty()

# ---------- 窗口/页面打开 ----------
func _open_wiki() -> void:
	_open_page(load("res://scenes/wiki.tscn").instantiate())

func _open_log() -> void:
	SceneStack.open_window(load("res://scenes/windows/log_window.tscn").instantiate())

func _open_settings() -> void:
	SceneStack.open_window(load("res://scenes/windows/settings_window.tscn").instantiate())

func _open_tech_culture() -> void:
	_open_page(load("res://scenes/windows/tech_culture.tscn").instantiate(), {"kind": "tech"})

func _open_army() -> void:
	_open_page(load("res://scenes/windows/army.tscn").instantiate())

func _open_recruit() -> void:
	_open_page(load("res://scenes/windows/recruit.tscn").instantiate())

# ---------- 更多弹窗（键盘页面的鼠标入口） ----------
## 打开"更多"弹窗：列出所有仅键盘可达的页面 + 暂停菜单。
func _show_more_popup() -> void:
	for ch in _more_box.get_children():
		ch.queue_free()
	var entries: Array = [
		["unit_roster", func(): _open_page(load("res://scenes/windows/unit_roster.tscn").instantiate())],
		["stronghold_overview", func(): _open_page(load("res://scenes/windows/stronghold_overview.tscn").instantiate())],
		["inventory", func(): _open_page(load("res://scenes/windows/inventory.tscn").instantiate())],
		["stronghold", func(): _open_page(load("res://scenes/windows/stronghold.tscn").instantiate())],
		["map_overview", func(): _open_page(load("res://scenes/windows/map_screen.tscn").instantiate())],
		["recruit_unit", func(): _open_page(load("res://scenes/windows/recruit_unit.tscn").instantiate())],
		["esc_menu", func(): SceneStack.open_window(load("res://scenes/windows/esc_menu.tscn").instantiate())],
	]
	for e in entries:
		var btn := Button.new()
		btn.text = Loc.t(e[0])
		btn.custom_minimum_size = Vector2(0, 36)
		btn.pressed.connect(func():
			_more_popup.visible = false
			(e[1] as Callable).call())
		_more_box.add_child(btn)
	_more_popup.visible = true

# ---------- 据点循环切换 ----------
## Ctrl+T：按己方据点列表循环选中下一个（镜头聚焦 + 打开信息栏）。
func _cycle_stronghold() -> void:
	var g := GameController.game
	if g == null or _map_view == null:
		return
	var p := GameController.player()
	var owned: Array = []
	for sid in p.stronghold_ids:
		if g.map.strongholds.has(sid):
			owned.append(sid)
	if owned.is_empty():
		return
	var idx := owned.find(_sel_node)
	var next_id: String = owned[(idx + 1) % owned.size()] if idx >= 0 else owned[0]
	_map_view.center_on(next_id)
	if _sel_node != next_id:
		_on_node_clicked(next_id)

# ---------- Toast ----------
func _toast_msg(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	_toast_timer.start()

# ---------- 场景生命周期 ----------
func enter_scene(params: Variant = null) -> void:
	super(params)
	_map_view.set_game(GameController.game)
	_check_event_popup()
	refresh()

func return_window(value: Variant = null) -> void:
	# 页面内嵌窗口（如装备选择）关闭的回值 → 转发给当前顶层页面；
	# 无页面时 Array 回值无意义，丢弃（不参与字符串比较，避免类型报错）
	if value is Array:
		if not _pages.is_empty():
			var top: Node = _pages.back()
			if top.has_method("return_page"):
				top.return_page(value)
		return
	# 仅字符串/空回值参与分支；其他类型只刷新
	if not (value is String or value == null):
		refresh()
		return
	refresh()
	if value == "end_turn":
		_end_turn()
	elif value == "to_menu":
		SceneStack.change_scene(load("res://scenes/main_menu.tscn").instantiate())
	elif value == "event_chosen" or value == null:
		# 事件弹窗关闭：未选择则兜底自动选 0（同 Python TUI），防重弹死循环
		var g := GameController.game
		if g != null and g.pending_event != null:
			var msg := g.resolve_event(0)
			GameController.push_log("事件:%s" % msg)
		refresh()
	elif value == "saved":
		refresh()

func _check_event_popup() -> void:
	var g := GameController.game
	if g != null and g.pending_event != null:
		SceneStack.open_window(load("res://scenes/windows/event_dialog.tscn").instantiate(), g.pending_event)

func _end_turn() -> void:
	GameController.run_ai_and_advance()
	_sel_node = ""
	_info_panel.visible = false
	refresh()
	if GameController.game.is_over():
		var w := GameController.game.winner
		var msg: String
		if w != "" and GameController.game.factions.has(w):
			msg = "%s\n\n%s：%s" % [Loc.t("game_over"), Loc.t("winner"),
				GameController.game.factions[w].name]
		else:
			msg = Loc.t("game_over")
		SceneStack.open_window(load("res://scenes/windows/message.tscn").instantiate(), {"text": msg, "close_hint": "hint_menu"})

func handle_input(event: InputEvent) -> void:
	var g := GameController.game
	if g == null:
		return
	# 全屏页面打开时：主场景不响应快捷键（ESC/按键由页面自己处理）
	if not _pages.is_empty():
		return
	# Tab 帝国总览（按住显示，松开消失）
	if event is InputEventKey and event.keycode == KEY_TAB:
		_overlay_visible = event.pressed
		_overlay.visible = _overlay_visible
		if _overlay_visible:
			_fill_overlay()
		return
	if event.is_action_pressed("end_turn"):
		_end_turn()
		return
	if event.is_action_pressed("ui_cancel"):
		SceneStack.open_window(load("res://scenes/windows/esc_menu.tscn").instantiate())
		return
	# Ctrl+T: 在己方据点间循环切换（TW3K: Ctrl+T 切换城镇标签）——
	# 必须在 end_turn(T) 之前检查，否则 Ctrl+T 会先触发结束回合
	if event is InputEventKey and event.keycode == KEY_T and event.pressed \
			and Input.is_key_pressed(KEY_CTRL):
		_cycle_stronghold()
		return
	# Home: 镜头切到首都并选中（TW3K: Home 切首都）——已是首都则保持选中（不触发反选）
	if event.is_action_pressed("focus_capital"):
		var cap: String = GameController.player().capital_id
		if cap != "" and _map_view != null:
			_map_view.center_on(cap)
			if _sel_node != cap:
				_on_node_clicked(cap)
		return
	for action in ["open_tech", "open_culture", "open_wiki", "open_stronghold",
			"open_army", "open_unit", "open_inventory", "open_stronghold_overview",
			"open_recruit", "open_recruit_unit", "open_map"]:
		if event.is_action_pressed(action):
			match action:
				"open_tech": _open_tech_culture()
				"open_culture": _open_tech_culture()
				"open_wiki": _open_wiki()
				"open_stronghold": _open_page(load("res://scenes/windows/stronghold.tscn").instantiate())
				"open_army": _open_army()
				"open_unit": _open_page(load("res://scenes/windows/unit_roster.tscn").instantiate())
				"open_inventory": _open_page(load("res://scenes/windows/inventory.tscn").instantiate())
				"open_stronghold_overview": _open_page(load("res://scenes/windows/stronghold_overview.tscn").instantiate())
				"open_recruit": _open_recruit()
				"open_recruit_unit": _open_page(load("res://scenes/windows/recruit_unit.tscn").instantiate())
				"open_map": _open_page(load("res://scenes/windows/map_screen.tscn").instantiate())
			return
