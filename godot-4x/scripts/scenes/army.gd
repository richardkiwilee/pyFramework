## 管理小队（对应 army.py，A 键/左下"管理小队"）。
## 顶部居中：在队/待命 切换。
## 在队：左侧上下滚动展示各部队的九宫格站位（焦点=某单位），右侧为焦点单位的
##       装备 / 能力值 / 编程策略；点空位 → 上场（选部队），单位右侧有 下场/换装。
## 待命：左侧按单位滚动，右侧同为单位详情。
class_name ArmyScreen
extends BasePage

enum Tab { ACTIVE, STANDBY }

const STAT_ORDER: Array[String] = ["hp", "ap", "pp", "mana", "speed", "p_atk", "m_atk",
	"p_def", "m_def", "acc", "eva", "block", "crit", "luck", "will", "leadership"]
const STAT_CN: Dictionary = {
	"hp": "生命", "ap": "行动", "pp": "能量", "mana": "法力", "speed": "速度",
	"p_atk": "物攻", "m_atk": "法攻", "p_def": "物防", "m_def": "法防",
	"acc": "命中", "eva": "闪避", "block": "格挡", "crit": "暴击",
	"luck": "幸运", "will": "意志", "leadership": "统率",
}

var _tab := Tab.ACTIVE
var _tab_btn_active: Button
var _tab_btn_standby: Button
var _left_scroll: ScrollContainer
var _left_box: VBoxContainer
var _detail: VBoxContainer
var _sel_uid := ""            # 焦点单位
var _sel_army := ""           # 焦点单位所在部队
var _deploy_popup: Control    # 上场选部队浮层
var _deploy_box: VBoxContainer
var _deploy_unit := ""

func build() -> void:
	page_title = Loc.t("squad")
	var vbox := make_content()
	vbox.add_theme_constant_override("separation", 6)
	# 顶部居中切换
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tab_row)
	_tab_btn_active = Button.new()
	_tab_btn_active.text = Loc.t("in_army")
	_tab_btn_active.toggle_mode = true
	_tab_btn_active.pressed.connect(func(): _set_tab(Tab.ACTIVE))
	tab_row.add_child(_tab_btn_active)
	_tab_btn_standby = Button.new()
	_tab_btn_standby.text = Loc.t("standby")
	_tab_btn_standby.toggle_mode = true
	_tab_btn_standby.pressed.connect(func(): _set_tab(Tab.STANDBY))
	tab_row.add_child(_tab_btn_standby)
	# 主体
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	# 左：滚动列表
	var left := Frame.new(Loc.t("in_army"))
	left.custom_minimum_size = Vector2(400, 0)
	hbox.add_child(left)
	_left_scroll = ScrollContainer.new()
	left.add_child(_left_scroll)
	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 6)
	_left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_scroll.add_child(_left_box)
	# 右：单位详情
	var right := Frame.new(Loc.t("unit_detail"))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	var right_scroll := ScrollContainer.new()
	right.add_child(right_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 4)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(_detail)
	# 上场选部队浮层（遮罩铺满整个浮层，点外部关闭）
	_deploy_popup = Control.new()
	_deploy_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_deploy_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_deploy_popup.visible = false
	add_child(_deploy_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_deploy_popup.add_child(dim)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_deploy_popup.visible = false)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不挡事件：外部点击透传到遮罩关闭
	_deploy_popup.add_child(center)
	var frame := Frame.new(Loc.t("deploy_to"))
	frame.custom_minimum_size = Vector2(380, 0)
	center.add_child(frame)
	_deploy_box = VBoxContainer.new()
	frame.add_child(_deploy_box)
	add_hint_label()

func enter_page(params: Variant = null) -> void:
	_set_tab(Tab.ACTIVE, true)   # force：首次打开必须重建左侧列表
	refresh_hints()

func _set_tab(tab: Tab, force: bool = false) -> void:
	if tab == _tab and not force:
		return
	_tab = tab
	_tab_btn_active.button_pressed = _tab == Tab.ACTIVE
	_tab_btn_standby.button_pressed = _tab == Tab.STANDBY
	_sel_uid = ""
	_sel_army = ""
	_rebuild_left()

func _rebuild_left() -> void:
	for ch in _left_box.get_children():
		ch.queue_free()
	match _tab:
		Tab.ACTIVE:
			for aid in GameController.game.armies:
				var a: Armies.Army = GameController.game.armies[aid]
				if a.owner != GameController.game.player_id or a.is_wiped(GameController.game.unit_index):
					continue
				_left_box.add_child(_make_squad_row(a))
		Tab.STANDBY:
			var p := GameController.player()
			for uid in p.standby_available_ids():
				var u: Variant = GameController.game.unit_index.get(uid)
				if u == null or not u.alive:
					continue
				_left_box.add_child(_make_unit_row(u, false))

# ---------- 左侧条目 ----------
func _make_squad_row(a: Armies.Army) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var head := HBoxContainer.new()
	vbox.add_child(head)
	var name := Label.new()
	name.text = _squad_row_title(a)
	name.add_theme_font_size_override("font_size", 14)
	name.add_theme_color_override("font_color", UiTheme.HEADING)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	var disband := Button.new()
	disband.text = Loc.t("disband")
	disband.add_theme_color_override("font_color", UiTheme.C_ENEMY)
	disband.pressed.connect(func():
		GameController.game.disband_army(a)
		GameController.push_log("%s %s" % [Loc.t("disbanded"), Loc.t(a.name)])
		_rebuild_left())
	head.add_child(disband)
	var grid := MiniGrid9.new()
	grid.army = a
	grid.unit_index = GameController.game.unit_index
	grid.cell_selected.connect(func(uid: String):
		_sel_uid = uid
		_sel_army = a.id
		_render_detail())
	vbox.add_child(grid)
	return panel

func _make_unit_row(u: Units.Unit, _in_army: bool) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 36)
	row.text = "%s  Lv%d  %s" % [Loc.t(u.name), u.level, _tag_abbr(u)]
	row.pressed.connect(func():
		_sel_uid = u.id
		_sel_army = ""
		_render_detail())
	return row

func _tag_abbr(u: Units.Unit) -> String:
	var parts: Array[String] = []
	for t in u.tags:
		parts.append(Units.TAG_CN.get(t, t))
	return "/".join(parts)

## 小队行标题（圣兽之王风格）：`先锋军 (3/9) ★[队长:关羽] · 玩家首都`。
func _squad_row_title(a: Armies.Army) -> String:
	var g := GameController.game
	var occupied := 0
	for s in a.grid:
		if s != null:
			occupied += 1
	var title := "%s (%d/%d)" % [Loc.t(a.name), occupied, Armies.GRID_SIZE]
	# 队长（UO: 队长标识 + 队长名）
	if a.captain_id != "" and g.unit_index.has(a.captain_id):
		var cap: Units.Unit = g.unit_index[a.captain_id]
		title += "  ★[%s: %s]" % [Loc.t("captain"), Loc.t(cap.name)]
	if a.node_id != "":
		title += " · %s" % Loc.t(g.map.node_name(a.node_id))
	return title

# ---------- 右侧单位详情 ----------
func _render_detail() -> void:
	for ch in _detail.get_children():
		ch.queue_free()
	if _sel_uid == "" or not GameController.game.unit_index.has(_sel_uid):
		var empty := Label.new()
		empty.text = Loc.t("select_unit")
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", UiTheme.DIM)
		_detail.add_child(empty)
		return
	var g := GameController.game
	var u: Units.Unit = g.unit_index[_sel_uid]
	# 头部
	var head := Label.new()
	head.text = "%s  Lv%d  %s" % [Loc.t(u.name), u.level, _tag_abbr(u)]
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", UiTheme.GOLD if u.is_hero else UiTheme.HEADING)
	_detail.add_child(head)
	# 操作按钮
	var ops := HBoxContainer.new()
	ops.add_theme_constant_override("separation", 8)
	_detail.add_child(ops)
	if _sel_army != "" and g.armies.has(_sel_army):
		var btn_discharge := Button.new()
		btn_discharge.text = Loc.t("discharge")
		btn_discharge.pressed.connect(func():
			var msg := g.action_discharge(g.player_id, _sel_army, _sel_uid)
			GameController.push_log(msg, msg.begins_with("失败"))
			_sel_uid = ""
			_rebuild_left()
			_render_detail())
		ops.add_child(btn_discharge)
	else:
		var btn_deploy := Button.new()
		btn_deploy.text = Loc.t("deploy")
		btn_deploy.pressed.connect(func(): _show_deploy_popup(u))
		ops.add_child(btn_deploy)
	# 能力值
	var stats := Frame.new(Loc.t("stats"))
	stats.draw_title = true
	_detail.add_child(stats)
	var stats_box := VBoxContainer.new()
	stats.add_child(stats_box)
	for key in STAT_ORDER:
		if not u.base.has(key):
			continue
		var l := Label.new()
		l.text = "%s  %d" % [STAT_CN.get(key, key), int(u.base[key])]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.FG)
		stats_box.add_child(l)
	var hp_line := Label.new()
	hp_line.text = "%s %d / %d" % [Loc.t("cur_hp"), int(u.cur_hp), int(u.base.get("hp", 1))]
	hp_line.add_theme_font_size_override("font_size", 13)
	hp_line.add_theme_color_override("font_color", UiTheme.C_OWN if u.cur_hp > 0 else UiTheme.C_ENEMY)
	stats_box.add_child(hp_line)
	# 装备
	var equip := Frame.new(Loc.t("equipment"))
	_detail.add_child(equip)
	var equip_box := VBoxContainer.new()
	equip_box.add_theme_constant_override("separation", 4)
	equip.add_child(equip_box)
	for slot in range(4):
		var btn := Button.new()
		if slot < u.artifacts.size() and u.artifacts[slot] != null:
			var def_id: String = u.artifacts[slot]
			var art: Variant = g.artifact_defs.get(def_id)
			btn.text = "%d. %s" % [slot + 1, Loc.t(art.name) if art != null else def_id]
			btn.tooltip_text = Loc.t("click_unequip")
			btn.pressed.connect(func():
				var msg := g.action_unequip(g.player_id, _sel_uid, slot)
				GameController.push_log(msg, msg.begins_with("失败"))
				_render_detail())
		else:
			btn.text = "%d. %s" % [slot + 1, Loc.t("empty_slot")]
			btn.tooltip_text = Loc.t("click_equip")
			btn.pressed.connect(func(): _open_equip_picker(u, slot))
		equip_box.add_child(btn)
	# 编程策略
	var strat := Frame.new(Loc.t("strategy"))
	_detail.add_child(strat)
	var strat_box := VBoxContainer.new()
	strat_box.add_theme_constant_override("separation", 2)
	strat.add_child(strat_box)
	var skill_defs: Dictionary = g.defs.get("skills", {})
	var s: Formation.UnitStrategy = Formation.default_strategy(u, skill_defs)
	var parts: Array[String] = ["%s: %s" % [Loc.t("target_pref"), s.target_pref]]
	if not s.active_rows.is_empty():
		parts.append(Loc.t("active_zone"))
		for r in s.active_rows:
			var sd: Variant = skill_defs.get(r.skill_id)
			parts.append("  - %s" % Loc.t(sd.get("name", r.skill_id)) if sd != null
				else "  - " + r.skill_id)
	if not s.passive_rows.is_empty():
		parts.append(Loc.t("passive_zone"))
		for r in s.passive_rows:
			var sd2: Variant = skill_defs.get(r.skill_id)
			parts.append("  - %s(%s)" % [Loc.t(sd2.get("name", r.skill_id)) if sd2 != null else r.skill_id,
				r.trigger_point])
	for line in parts:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.DIM if line.begins_with("  ") else UiTheme.FG)
		strat_box.add_child(l)

var _pending_equip_slot := -1

func _open_equip_picker(u: Units.Unit, slot: int) -> void:
	_pending_equip_slot = slot
	var g := GameController.game
	var options: Array = []
	var ids: Array = []
	for def_id in g.artifact_defs:
		if g.available_count(g.player_id, def_id) > 0:
			var art: Units.Artifact = g.artifact_defs[def_id]
			options.append(Loc.t(art.name))
			ids.append(def_id)
	if options.is_empty():
		GameController.push_log(Loc.t("no_artifact_avail"), true)
		return
	var picker: EquipPicker = load("res://scenes/windows/equip_picker.tscn").instantiate()
	picker.unit_id = u.id
	picker.slot = slot
	picker.ids = ids
	picker.labels = options
	SceneStack.open_window(picker)

func return_page(value: Variant = null) -> void:
	if value is Array and value.size() == 2:
		var msg := GameController.game.action_equip(GameController.game.player_id,
			value[0], value[1], _pending_equip_slot)
		GameController.push_log(msg, msg.begins_with("失败"))
	_render_detail()

# ---------- 上场选部队 ----------
func _show_deploy_popup(u: Units.Unit) -> void:
	_deploy_unit = u.id
	for ch in _deploy_box.get_children():
		ch.queue_free()
	var g := GameController.game
	var p := GameController.player()
	var has := false
	for aid in g.armies:
		var a: Armies.Army = g.armies[aid]
		if a.owner != g.player_id or a.node_id == "":
			continue
		if not p.stronghold_ids.has(a.node_id):
			continue
		var free := a.grid.find(null)
		if free < 0:
			continue
		has = true
		var btn := Button.new()
		btn.text = "%s (%s)" % [Loc.t(a.name), Loc.t(g.map.node_name(a.node_id))]
		btn.pressed.connect(func():
			var msg := g.action_deploy(g.player_id, a.id, _deploy_unit, free)
			GameController.push_log(msg, msg.begins_with("失败"))
			_deploy_popup.visible = false
			_sel_army = a.id
			_rebuild_left()
			_render_detail())
		_deploy_box.add_child(btn)
	if not has:
		var nl := Label.new()
		nl.text = Loc.t("no_deploy_target")
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", UiTheme.DIM)
		_deploy_box.add_child(nl)
	_deploy_popup.visible = true

func get_hints() -> Array:
	return [["↑↓", "move"], ["ESC", "close"]]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_left_scroll.scroll_vertical -= 26
	elif event.is_action_pressed("ui_down"):
		_left_scroll.scroll_vertical += 26

# ================= 迷你九宫格 =================
## 部队九宫格（小尺寸）：每格显示单位名缩写 + 血量条；点击格选中单位。
class MiniGrid9:
	extends Control
	signal cell_selected(uid: String)

	const CELL := 46.0
	const GAP := 5.0

	var army: Armies.Army = null
	var unit_index: Dictionary = {}

	func _init() -> void:
		custom_minimum_size = Vector2(CELL * 3 + GAP * 2 + 6, CELL * 3 + GAP * 2 + 6)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var font := get_theme_default_font()
		for slot in range(9):
			var col := slot % 3
			var row := slot / 3
			var pos := Vector2(3 + col * (CELL + GAP), 3 + row * (CELL + GAP))
			var r := Rect2(pos, Vector2(CELL, CELL))
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTheme.PANEL_BG.darkened(0.25)
			sb.set_corner_radius_all(6)
			sb.border_color = UiTheme.BORDER
			sb.set_border_width_all(1)
			draw_style_box(sb, r)
			var uid: Variant = army.grid[slot] if army != null else null
			if uid != null and unit_index.has(uid):
				var u: Units.Unit = unit_index[uid]
				var col_c := UiTheme.GOLD if u.is_hero else UiTheme.FG
				var abbr := Loc.t(u.name).left(2)
				draw_string(font, pos + Vector2(6, 18), abbr,
					HORIZONTAL_ALIGNMENT_LEFT, CELL - 12, 13, col_c)
				var hp_frac := clampf(float(u.cur_hp) / maxf(1.0, float(u.base.get("hp", 1))), 0.0, 1.0)
				draw_rect(Rect2(pos + Vector2(6, 28), Vector2(CELL - 12, 5)), Color(0.2, 0.2, 0.25))
				var hp_col := UiTheme.C_OWN if hp_frac > 0.5 else (UiTheme.WARN if hp_frac > 0.25 else UiTheme.C_ENEMY)
				draw_rect(Rect2(pos + Vector2(6, 28), Vector2((CELL - 12) * hp_frac, 5)), hp_col)
				if army != null and army.captain_id == uid:
					draw_string(font, pos + Vector2(CELL - 14, 14), "★",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.ACCENT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for slot in range(9):
				var col := slot % 3
				var row := slot / 3
				var r := Rect2(3 + col * (CELL + GAP), 3 + row * (CELL + GAP), CELL, CELL)
				if r.has_point(event.position):
					var uid: Variant = army.grid[slot] if army != null else null
					if uid != null:
						cell_selected.emit(uid)
					accept_event()
					return
