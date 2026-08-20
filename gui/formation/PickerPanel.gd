## =====================================================================
## PickerPanel — 可选界面（readme 第 34-35 行）
## =====================================================================
## 「可选界面的位置完全覆盖队伍列表界面。
##   装备、技能和条件的卸下操作都在可选界面中，
##   可选界面是一个列表，第一行是卸下。」
##
## 一个面板伺候四种来源，靠 kind 区分：
##   "equip"  某个装备槽可装的全部装备      首行「卸下」
##   "skill"  可编入策略的全部主动技能      首行「卸下」
##   "cond"   全部触发条件                  首行「卸下」
##   "add"    待命池（给成员界面的加号用）  首行「取消」——没有东西可卸
##
## 「add」这一种是 readme 没写明的推断实现：readme 只说第一个空栏位显示加号
## 表示添加成员，没说点下去弹什么。按可选界面的定位（列表、覆盖左侧）实现成
## 弹待命池列表最自然，也是待命池唯一可见的地方。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control          → UI 控件基类
## ScrollContainer          → 可滚动容器。子节点超出范围时自动出滚动条。
## VBoxContainer            → 纵向排列容器（类似 flex column）
## size_flags_horizontal = SIZE_EXPAND_FILL
##                          → 在容器里横向撑满（类似 flex-grow: 1）
## ensure_control_visible(c)→ 滚动到让子控件 c 可见（键盘选择时保持光标在视野内）
## custom_minimum_size      → 最小尺寸，容器排版时不会压得比它更小
## queue_free()             → 安全删除节点
## Array.append(x)          → 等价于 Python 的 list.append
## =====================================================================
class_name PickerPanel
extends Control

## 选中了某一项。id 为空串表示「卸下」（或 add 模式下的「取消」）。
signal choice_made(id: String)
## 关闭而不选择。
signal canceled

const ROW_H := 46.0

var _panel: Panel
var _title: Label
var _foot: Label
var _scroll: ScrollContainer
var _list: VBoxContainer

var _kind: String = ""
var _ctx: Dictionary = {}       # 上下文：{slot_key} / {row, field} / 空
var _ids: Array = []            # 选项 id，索引 0 固定是「卸下/取消」占位（空串）
var _rows: Array = []           # 每项对应的 Panel
var _cursor: int = 0


func _init() -> void:
	name = "PickerPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP   # 覆盖层出现时接管输入

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel",
		FormationSkin.box(Color(0.086, 0.070, 0.043, 0.99), FormationSkin.GOLD, 2, 10))
	FormationSkin.add_filling(self, _panel)

	_title = FormationSkin.make_title("可选")
	_panel.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	_foot = FormationSkin.make_text("", FormationSkin.INK_DIM, 11)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_foot)


## 按覆盖层尺寸排版（覆盖层和左区同尺寸，所以这里直接铺满自己）。
func relayout() -> void:
	var pad := 12.0
	var w := size.x
	var h := size.y
	_title.position = Vector2(pad, pad)
	_title.size = Vector2(w - pad * 2.0, 30.0)

	var foot_h := 34.0
	_scroll.position = Vector2(pad, pad + 36.0)
	_scroll.size = Vector2(w - pad * 2.0, h - pad * 2.0 - 36.0 - foot_h)
	_list.custom_minimum_size = Vector2(_scroll.size.x, 0)

	_foot.position = Vector2(pad, h - pad - foot_h + 6.0)
	_foot.size = Vector2(w - pad * 2.0, foot_h)


# =====================================================================
#  打开四种列表
# =====================================================================

## 装备：列出该槽位可装的全部装备。
func open_equip(unit: UnitModel, slot_key: String, slot_label: String) -> void:
	_kind = "equip"
	_ctx = { "slot_key": slot_key }
	var cur := unit.equipped_id(slot_key)
	var entries: Array = []
	for eid in FormationData.equipment_for_slot(slot_key):
		var e := FormationData.get_equipment(str(eid))
		entries.append({
			"id": str(eid),
			"name": str(e.get("name_zh", eid)),
			"desc": _equip_desc(e),
			"marked": str(eid) == cur,
		})
	_open("%s　·　%s" % [slot_label, unit.display_name()],
		"第一行是卸下。W/S 选择，空格确认，ESC 返回。", entries, "卸下")


## 技能：列出全部主动技能。
func open_skill(unit: UnitModel, row: int) -> void:
	_kind = "skill"
	_ctx = { "row": row }
	var cur := ""
	if row >= 0 and row < unit.strategy.size():
		cur = str(unit.strategy[row].get("skill", ""))
	var entries: Array = []
	for sid in FormationData.active_skill_ids():
		var s := FormationData.get_skill(str(sid))
		entries.append({
			"id": str(sid),
			"name": str(s.get("name_zh", sid)),
			"desc": "AP %s　PP %s　%s" % [
				str(s.get("ap_cost", 0)), str(s.get("pp_cost", 0)),
				str(s.get("description_zh", "")).left(40)],
			"marked": str(sid) == cur,
		})
	_open("选择技能　·　第 %d 行" % (row + 1),
		"第一行是卸下。W/S 选择，空格确认，ESC 返回。", entries, "卸下")


## 条件：列出全部触发条件。field 是 "cond1" 或 "cond2"。
func open_condition(unit: UnitModel, row: int, field: String) -> void:
	_kind = "cond"
	_ctx = { "row": row, "field": field }
	var cur := ""
	if row >= 0 and row < unit.strategy.size():
		cur = str(unit.strategy[row].get(field, ""))
	var entries: Array = []
	for cid in FormationData.all_condition_ids():
		var c := FormationData.get_condition(str(cid))
		entries.append({
			"id": str(cid),
			"name": str(c.get("name_zh", cid)),
			"desc": str(c.get("description_zh", "")).left(48),
			"marked": str(cid) == cur,
		})
	_open("选择条件 %s　·　第 %d 行" % ["一" if field == "cond1" else "二", row + 1],
		"第一行是卸下。W/S 选择，空格确认，ESC 返回。", entries, "卸下")


## 待命池：给成员界面的加号用。首行是「取消」，因为这里没有东西可卸。
func open_reserve(pool: Array) -> void:
	_kind = "add"
	_ctx = {}
	var entries: Array = []
	for u in pool:
		var unit: UnitModel = u
		entries.append({
			"id": unit.id,
			"name": unit.display_name(),
			"desc": "Lv.%d　%s　规模 %d　AP %d / PP %d" % [
				unit.level, unit.class_label(), unit.size, unit.ap, unit.pp],
			"marked": false,
		})
	var foot := "待命池共 %d 人。W/S 选择，空格确认，ESC 返回。" % pool.size()
	if pool.is_empty():
		foot = "待命池是空的 —— 所有单位都已经编入队伍。"
	_open("待命池　·　添加成员", foot, entries, "取消")


## 通用打开逻辑。first_label 是首行的文字（「卸下」或「取消」）。
func _open(title: String, foot: String, entries: Array, first_label: String) -> void:
	_title.text = title
	_foot.text = foot
	_cursor = 0
	_ids = [""]          # 索引 0 恒为「卸下/取消」，id 用空串表示
	_rows = []
	for c in _list.get_children():
		c.queue_free()

	# ---- 首行：卸下 / 取消 ----
	_rows.append(_make_row(0, first_label,
		"清除当前选择" if first_label == "卸下" else "关闭列表，不做改动", false, true))

	# ---- 其余选项 ----
	for i in entries.size():
		var e: Dictionary = entries[i]
		_ids.append(str(e.id))
		_rows.append(_make_row(i + 1, str(e.name), str(e.desc), bool(e.marked), false))

	visible = true
	relayout()
	_paint()


## 造一行。idx 是它在 _ids / _rows 里的下标。
func _make_row(idx: int, title: String, desc: String, marked: bool, is_first: bool) -> Panel:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	# 闭包陷阱：循环变量必须先拷进局部变量。
	var idx_copy := idx
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_choose(idx_copy))
	row.mouse_entered.connect(func():
		_cursor = idx_copy
		_paint())

	var head := title
	if marked:
		head += "　✓ 当前"
	var t := FormationSkin.make_text(head,
		FormationSkin.RED if is_first else FormationSkin.INK, 14)
	t.position = Vector2(10, 5)
	t.size = Vector2(600, 20)
	t.clip_text = true
	row.add_child(t)

	var d := FormationSkin.make_text(desc, FormationSkin.INK_DIM, 11)
	d.position = Vector2(10, 25)
	d.size = Vector2(600, 18)
	d.clip_text = true
	row.add_child(d)

	_list.add_child(row)
	return row


## 装备的一句话描述：把 stats 里的加成拼出来。
func _equip_desc(e: Dictionary) -> String:
	var bits: Array = []
	var st = e.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st:
			bits.append("%s %+d" % [str(k).to_upper(), int(st[k])])
	var rarity := str(e.get("rarity", ""))
	if not rarity.is_empty():
		bits.append(rarity)
	return "　".join(bits) if not bits.is_empty() else str(e.get("subtype", ""))


# =====================================================================
#  交互
# =====================================================================

func close() -> void:
	visible = false


func kind() -> String:
	return _kind


func context() -> Dictionary:
	return _ctx


## W/S 移动光标，首尾循环，并自动滚动到可见。
func step(step_dir: int) -> void:
	if _rows.is_empty():
		return
	_cursor = posmod(_cursor + step_dir, _rows.size())
	_paint()
	# 让光标行保持在视野内，否则键盘选到列表下方就看不见了。
	_scroll.ensure_control_visible(_rows[_cursor])


## 空格确认当前光标项。
func activate_cursor() -> void:
	_choose(_cursor)


## 选定第 idx 项。idx == 0 是「卸下/取消」。
func _choose(idx: int) -> void:
	if idx < 0 or idx >= _ids.size():
		return
	if idx == 0 and _kind == "add":
		# add 模式的首行是「取消」，不是「卸下」，所以走取消而不是发空串。
		canceled.emit()
		return
	choice_made.emit(str(_ids[idx]))


func _paint() -> void:
	for i in _rows.size():
		var sel := i == _cursor
		var bg := Color(0.196, 0.153, 0.086) if sel else Color(0, 0, 0, 0.22)
		var edge := FormationSkin.GOLD if sel else FormationSkin.LINE
		_rows[i].add_theme_stylebox_override("panel",
			FormationSkin.box(bg, edge, 2 if sel else 1, 5))
