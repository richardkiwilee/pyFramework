## =====================================================================
## UnitDetailPanel — 单位详细界面（readme 第 32 行）
## =====================================================================
## 「单位详细界面，位置完全覆盖队伍成员界面，是一个单位的详细信息，
##   包含了完整的角色属性、装备栏和技能编程。
##   点击装备栏的格子或是技能或是条件的时候，弹出「可选界面」。」
##
## 三段结构：
##   ┌─ 头部：头像 + 名字 + 等级 + 职业 ────────────┐
##   ├─ 属性：生命/物攻/物防/魔攻/魔防/先制/命中/回避 ┤ 2 列
##   ├─ 装备栏：武器 / 盾牌 / 饰品一 / 饰品二 ───────┤ 可点 → 可选界面
##   └─ 技能编程：[技能 | 条件一 | 条件二 | ×] × 8   ┘ 可点 → 可选界面
##
## 本文件只负责显示和「报告点了哪个格子」，弹哪个列表由 FormationScreen 决定。
##
## ⚠️ 数据坑：角色 hermann 没有 base_stats 字段，所以取属性一律走 .get() 判空，
## 否则一进他的详细界面就会崩。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control        → UI 控件基类
## signal xxx(a, b)       → 多参数信号
## Dictionary             → 等价于 Python dict
## Array                  → 等价于 Python list
## ScrollContainer        → 可滚动容器（技能编程行数多时需要）
## String.left(n)         → 取前 n 个字符，等价于 Python 的 s[:n]
## "　".join(arr)         → 用全角空格连接，等价于 Python 的 "".join()
## var x := {}            → 类型推导为 Dictionary
## =====================================================================
class_name UnitDetailPanel
extends Control

## 某个可点格子被激活。
##   kind  = "equip" / "skill" / "cond" / "del" / "add"
##   row   = 装备槽下标 或 策略行号
##   field = 条件格用 "cond1"/"cond2"，其余为空串
signal cell_activated(kind: String, row: int, field: String)

## 要显示的八项属性：数据键 → 中文名。
const ATTR_DEFS := [
	{ "key": "hp",  "label": "生命" },
	{ "key": "atk", "label": "物攻" },
	{ "key": "def", "label": "物防" },
	{ "key": "mag", "label": "魔攻" },
	{ "key": "mdf", "label": "魔防" },
	{ "key": "spd", "label": "先制" },
	{ "key": "acc", "label": "命中" },
	{ "key": "eva", "label": "回避" },
]

var _panel: Panel
var _scroll: ScrollContainer
var _body: VBoxContainer
var _foot: Label

var _unit: UnitModel = null
## 所有可点格子的扁平清单，W/S 就在这个清单上走。
## 每项 = { kind, row, field, node }
var _focus_items: Array = []
var _cursor: int = 0


func _init() -> void:
	name = "UnitDetailPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel",
		FormationSkin.box(Color(0.086, 0.070, 0.043, 0.99), FormationSkin.GOLD, 2, 10))
	FormationSkin.add_filling(self, _panel)

	_scroll = ScrollContainer.new()
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)

	_foot = FormationSkin.make_text(
		"W/S 选择格子　空格打开可选界面　ESC 返回队伍成员界面",
		FormationSkin.INK_DIM, 11)
	_panel.add_child(_foot)


func relayout() -> void:
	var pad := 12.0
	var foot_h := 26.0
	_scroll.position = Vector2(pad, pad)
	_scroll.size = Vector2(size.x - pad * 2.0, size.y - pad * 2.0 - foot_h)
	_body.custom_minimum_size = Vector2(_scroll.size.x, 0)
	_foot.position = Vector2(pad, size.y - pad - foot_h + 6.0)
	_foot.size = Vector2(size.x - pad * 2.0, foot_h)


func unit() -> UnitModel:
	return _unit


## 打开某个单位的详细界面。
func open(u: UnitModel) -> void:
	_unit = u
	_cursor = 0
	visible = true
	rebuild()


func close() -> void:
	visible = false
	_unit = null


## 重建全部内容。改完装备/技能后调用。
func rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_focus_items = []
	if _unit == null:
		return

	_build_header()
	_build_attrs()
	_build_equipment()
	_build_strategy()

	# 光标可能因为删行而越界
	_cursor = clampi(_cursor, 0, maxi(0, _focus_items.size() - 1))
	# 内容是 queue_free + 新建的，要等一帧节点就位后再上色。
	call_deferred("_paint")


# ---------------- 各段 ----------------

func _build_header() -> void:
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 64)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(head)

	var portrait := FormationSkin.make_portrait(_unit, 56.0)
	portrait.position = Vector2(2, 4)
	portrait.size = Vector2(56, 56)
	head.add_child(portrait)

	var n := FormationSkin.make_text(_unit.display_name(), FormationSkin.GOLD, 20)
	n.position = Vector2(68, 6)
	n.size = Vector2(400, 26)
	head.add_child(n)

	var sub := FormationSkin.make_text(
		"Lv.%d　%s　EXP %d/%d　AP %d　PP %d　规模 %d" % [
			_unit.level, _unit.class_label(), _unit.exp, _unit.exp_to_next(),
			_unit.ap, _unit.pp, _unit.size],
		FormationSkin.INK_DIM, 12)
	sub.position = Vector2(68, 34)
	sub.size = Vector2(460, 20)
	head.add_child(sub)


func _build_attrs() -> void:
	_body.add_child(_section_title("角色属性"))

	# ⚠️ 判空：角色 hermann 确实没有 base_stats 字段。
	var stats = _unit.char_data.get("base_stats", {})
	if typeof(stats) != TYPE_DICTIONARY:
		stats = {}

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)

	for d in ATTR_DEFS:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(0, 30)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_stylebox_override("panel",
			FormationSkin.box(Color(0, 0, 0, 0.22), FormationSkin.LINE, 1, 4))
		grid.add_child(cell)

		var k := FormationSkin.make_text(str(d.label), FormationSkin.INK_DIM, 11)
		k.position = Vector2(6, 2)
		k.size = Vector2(60, 13)
		cell.add_child(k)

		# 没有该项属性时显示 "—" 而不是 0，免得看起来像真的是 0。
		var raw = stats.get(str(d.key), null)
		var v := FormationSkin.make_text(
			"—" if raw == null else str(int(raw)), FormationSkin.INK, 14)
		v.position = Vector2(6, 14)
		v.size = Vector2(70, 16)
		cell.add_child(v)


func _build_equipment() -> void:
	_body.add_child(_section_title("装备栏　（点击更换 / 卸下）"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)

	for i in UnitModel.EQUIP_SLOTS.size():
		var sdef: Dictionary = UnitModel.EQUIP_SLOTS[i]
		var eid := _unit.equipped_id(str(sdef.key))
		var title := str(sdef.label)
		var desc := "空槽位"
		if not eid.is_empty():
			var e := FormationData.get_equipment(eid)
			desc = str(e.get("name_zh", eid))
		var cell := _make_clickable(title, desc, not eid.is_empty())
		grid.add_child(cell)
		_focus_items.append({ "kind": "equip", "row": i, "field": "", "node": cell })
		_connect_cell(cell, "equip", i, "")


func _build_strategy() -> void:
	_body.add_child(_section_title(
		"技能编程　（%d/%d 行　·　点技能或条件格更换）" % [
			_unit.strategy.size(), UnitModel.MAX_STRATEGY_ROWS]))

	for i in _unit.strategy.size():
		var row_data = _unit.strategy[i]
		if typeof(row_data) != TYPE_DICTIONARY:
			continue
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_theme_constant_override("separation", 5)
		_body.add_child(line)

		# --- 技能格（占 2 份宽）---
		var sk_id := str(row_data.get("skill", ""))
		var sk_name := "＋ 选择技能"
		var sk_desc := "尚未指定"
		if not sk_id.is_empty():
			var s := FormationData.get_skill(sk_id)
			sk_name = str(s.get("name_zh", sk_id))
			sk_desc = "AP %s　%s" % [
				str(s.get("ap_cost", 0)), str(s.get("description_zh", "")).left(18)]
		var c_sk := _make_clickable(sk_name, sk_desc, not sk_id.is_empty())
		c_sk.size_flags_stretch_ratio = 2.0
		line.add_child(c_sk)
		_focus_items.append({ "kind": "skill", "row": i, "field": "", "node": c_sk })
		_connect_cell(c_sk, "skill", i, "")

		# --- 两个条件格 ---
		for field in ["cond1", "cond2"]:
			var cid := str(row_data.get(field, ""))
			var cname := "＋ 条件" + ("一" if field == "cond1" else "二")
			var cdesc := "无条件"
			if not cid.is_empty():
				var cdata := FormationData.get_condition(cid)
				cname = str(cdata.get("name_zh", cid))
				cdesc = str(cdata.get("type", ""))
			var c_cd := _make_clickable(cname, cdesc, not cid.is_empty())
			c_cd.size_flags_stretch_ratio = 1.5
			line.add_child(c_cd)
			_focus_items.append({ "kind": "cond", "row": i, "field": field, "node": c_cd })
			_connect_cell(c_cd, "cond", i, field)

		# --- 删除本行 ---
		var c_del := _make_clickable("×", "删除本行", false)
		c_del.custom_minimum_size = Vector2(38, 44)
		c_del.size_flags_horizontal = Control.SIZE_SHRINK_END
		line.add_child(c_del)
		_focus_items.append({ "kind": "del", "row": i, "field": "", "node": c_del })
		_connect_cell(c_del, "del", i, "")

	# --- 新增一行 ---
	if _unit.strategy.size() < UnitModel.MAX_STRATEGY_ROWS:
		var c_add := _make_clickable("＋ 新增策略行", "先加一行，再给它选技能和条件", false)
		c_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(c_add)
		_focus_items.append({ "kind": "add", "row": -1, "field": "", "node": c_add })
		_connect_cell(c_add, "add", -1, "")


# ---------------- 小组件 ----------------

func _section_title(text: String) -> Label:
	var l := FormationSkin.make_text(text, FormationSkin.GOLD, 13)
	l.custom_minimum_size = Vector2(0, 20)
	return l


## 造一个可点格子（两行文字：标题 + 描述）。
func _make_clickable(title: String, desc: String, filled: bool) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 44)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Color(0.145, 0.114, 0.067) if filled else Color(0, 0, 0, 0.22)
	p.add_theme_stylebox_override("panel", FormationSkin.box(bg, FormationSkin.LINE, 1, 5))

	var t := FormationSkin.make_text(title, FormationSkin.INK if filled else FormationSkin.INK_DIM, 13)
	t.position = Vector2(8, 4)
	t.size = Vector2(220, 18)
	t.clip_text = true
	p.add_child(t)

	var d := FormationSkin.make_text(desc, FormationSkin.INK_DIM, 10)
	d.position = Vector2(8, 23)
	d.size = Vector2(220, 16)
	d.clip_text = true
	p.add_child(d)
	return p


## 给格子接上点击和悬停。
func _connect_cell(node: Panel, kind: String, row: int, field: String) -> void:
	# 闭包陷阱：这三个参数是函数形参（每次调用都是新的），所以可以直接捕获，
	# 不像 for 循环变量那样需要额外拷贝。
	node.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			cell_activated.emit(kind, row, field))
	node.mouse_entered.connect(func():
		for i in _focus_items.size():
			if _focus_items[i].node == node:
				_cursor = i
				break
		_paint())


# ---------------- 键盘 ----------------

## W/S 在扁平的可点格子清单上走，首尾循环。
func step(step_dir: int) -> void:
	if _focus_items.is_empty():
		return
	_cursor = posmod(_cursor + step_dir, _focus_items.size())
	_paint()
	var node = _focus_items[_cursor].node
	if node is Control:
		_scroll.ensure_control_visible(node)


## 空格确认当前格子。
func activate_cursor() -> void:
	if _cursor < 0 or _cursor >= _focus_items.size():
		return
	var it: Dictionary = _focus_items[_cursor]
	cell_activated.emit(str(it.kind), int(it.row), str(it.field))


## 高亮当前光标格。
func _paint() -> void:
	for i in _focus_items.size():
		var node = _focus_items[i].node
		if not (node is Panel) or not is_instance_valid(node):
			continue
		var sel := i == _cursor
		# 保持原来的填充色判断：有内容的格子底色亮一点。
		var kind := str(_focus_items[i].kind)
		var filled := kind == "equip" or kind == "skill" or kind == "cond"
		var bg := Color(0.145, 0.114, 0.067) if filled else Color(0, 0, 0, 0.22)
		if sel:
			bg = Color(0.196, 0.153, 0.086)
		node.add_theme_stylebox_override("panel", FormationSkin.box(
			bg, FormationSkin.GOLD if sel else FormationSkin.LINE, 2 if sel else 1, 5))
