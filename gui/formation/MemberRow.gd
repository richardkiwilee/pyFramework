## =====================================================================
## MemberRow — 队伍成员界面里的一个栏位（一行）
## =====================================================================
## readme 第 19-20 行：
##   「每个栏位分成 1：4：2，左侧是单位头像，中间部分是单位基本信息，
##     包括等级、经验值、AP/PP。右侧是单位的装备栏（仅展示）。」
##
##   ┌────┬──────────────────────────┬──────────────┐
##   │头像│ 亚连  领主               │ ⚔  🛡  💍  💍 │
##   │ 1  │ Lv.21  EXP 0/2100        │      2       │
##   │    │ AP 1  PP 1  规模 20      │              │
##   └────┴──────────────────────────┴──────────────┘
##        └──────────  4  ───────────┘
##
## 三种形态：
##   有人   —— 上面那样
##   空栏位 —— 全空，什么都不画
##   第一个空栏位 —— 正中显示一个加号，表示「添加成员」（readme 第 25 行）
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control        → UI 控件基类
## signal clicked()       → 无参数信号
## mouse_entered          → 鼠标进入控件范围时发出的内置信号（用来做悬停切换）
## get_children()         → 子节点列表
## queue_free()           → 安全删除节点
## Rect2 解构             → GDScript 没有 Python 的 a, b, c = ... 解构语法，
##                          只能 parts[0] / parts[1] 这样按下标取
## "%d/%d" % [a, b]      → 字符串格式化，和 Python 的 % 一致
## =====================================================================
class_name MemberRow
extends Control

## 本行被左键点击。
signal clicked
## 鼠标悬停到本行（readme：鼠标悬停在成员直接进行切换）。
signal hovered

## 本行内容区（除了背景之外的所有东西都塞这里，方便整体清空重建）。
var _content: Control

var _unit: UnitModel = null
var _is_add_row: bool = false
var _selected: bool = false
var _is_captain: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # 整行都可点、可悬停
	gui_input.connect(_on_input)
	mouse_entered.connect(func(): hovered.emit())

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 内容不吃鼠标，让整行统一处理
	FormationSkin.add_filling(self, _content)


## 设置本行要显示什么。
##   unit       该栏位的单位；null 表示空栏位
##   is_add_row 是不是「第一个空栏位」（要显示加号）
##   selected   是不是当前光标所在行
##   is_captain 是不是队长
func set_data(unit: UnitModel, is_add_row: bool, selected: bool, is_captain: bool) -> void:
	_unit = unit
	_is_add_row = is_add_row
	_selected = selected
	_is_captain = is_captain
	_rebuild()


func unit() -> UnitModel:
	return _unit


func is_add_row() -> bool:
	return _is_add_row


## 尺寸变化后要重建（因为 1:4:2 的分栏宽度依赖行宽）。
func relayout() -> void:
	_rebuild()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	if size.x <= 1.0 or size.y <= 1.0:
		return   # 还没排版，等 relayout 再画

	_draw_background()
	if _unit != null:
		_draw_unit()
	elif _is_add_row:
		_draw_add_hint()
	# 普通空栏位：什么都不画，只留背景


func _draw_background() -> void:
	var bg := Color(0, 0, 0, 0.18)
	var edge := FormationSkin.LINE
	var w := 1
	if _unit != null:
		bg = Color(0.129, 0.102, 0.059)
	if _selected:
		edge = FormationSkin.GOLD
		w = 2
		bg = Color(0.180, 0.141, 0.078) if _unit != null else Color(0.10, 0.09, 0.05, 0.35)
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", FormationSkin.box(bg, edge, w, 5))
	FormationSkin.add_filling(_content, p)


## 第一个空栏位：正中一个加号。
func _draw_add_hint() -> void:
	var l := FormationSkin.make_text("＋", FormationSkin.INK_DIM, int(minf(size.y * 0.5, 26.0)))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _selected:
		l.add_theme_color_override("font_color", FormationSkin.GOLD)
	FormationSkin.add_filling(_content, l)


func _draw_unit() -> void:
	# readme 的 1:4:2 分栏，具体比例定义在锚点文件里。
	var parts: Array = FormationLayout.split_member_row(size)
	var r_portrait: Rect2 = parts[0]
	var r_info: Rect2 = parts[1]
	var r_equip: Rect2 = parts[2]

	# ---------- 1 ：头像 ----------
	var px := minf(r_portrait.size.x, r_portrait.size.y) - 6.0
	var portrait := FormationSkin.make_portrait(_unit, px)
	portrait.position = r_portrait.position + Vector2(
		(r_portrait.size.x - px) * 0.5, (r_portrait.size.y - px) * 0.5)
	portrait.size = Vector2(px, px)
	_content.add_child(portrait)

	# 队长皇冠压在头像左上角
	if _is_captain:
		var crown := FormationSkin.make_crown(px * 0.42)
		crown.position = r_portrait.position + Vector2(2.0, 2.0)
		_content.add_child(crown)

	# ---------- 4 ：基本信息 ----------
	# 三行：名字+职业 / 等级+经验 / AP+PP+规模
	var line_h := r_info.size.y / 3.0
	var name_txt := _unit.display_name()
	if _is_captain:
		name_txt += "　（队长）"
	var l1 := FormationSkin.make_text(name_txt, FormationSkin.INK, 14)
	_place(l1, Rect2(r_info.position + Vector2(4, 0), Vector2(r_info.size.x - 8, line_h)))
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l1.clip_text = true
	_content.add_child(l1)

	var l2 := FormationSkin.make_text(
		"Lv.%d　EXP %d/%d　%s" % [_unit.level, _unit.exp, _unit.exp_to_next(), _unit.class_label()],
		FormationSkin.INK_DIM, 11)
	_place(l2, Rect2(r_info.position + Vector2(4, line_h), Vector2(r_info.size.x - 8, line_h)))
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l2.clip_text = true
	_content.add_child(l2)

	var l3 := FormationSkin.make_text(
		"AP %d　PP %d　规模 %d" % [_unit.ap, _unit.pp, _unit.size],
		FormationSkin.INK_DIM, 11)
	_place(l3, Rect2(r_info.position + Vector2(4, line_h * 2.0), Vector2(r_info.size.x - 8, line_h)))
	l3.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l3.clip_text = true
	_content.add_child(l3)

	# ---------- 2 ：装备栏（readme 注明「仅展示」，所以不接任何点击）----------
	var slots: Array = UnitModel.EQUIP_SLOTS
	var n := slots.size()
	var gap := 3.0
	var sw := (r_equip.size.x - gap * float(n - 1)) / float(n)
	var sh := minf(r_equip.size.y - 6.0, sw * 1.35)
	for i in n:
		var slot_def: Dictionary = slots[i]
		var eid := _unit.equipped_id(str(slot_def.key))
		var filled := not eid.is_empty()
		# 有装备就显示装备名，没有就显示槽位名（武器/盾牌/饰品一/饰品二）
		var label := str(slot_def.label)
		if filled:
			var edata := FormationData.get_equipment(eid)
			label = str(edata.get("name_zh", label))
		var cell := FormationSkin.make_equip_slot(label, filled)
		cell.position = r_equip.position + Vector2(
			float(i) * (sw + gap), (r_equip.size.y - sh) * 0.5)
		cell.size = Vector2(sw, sh)
		_content.add_child(cell)


func _place(c: Control, r: Rect2) -> void:
	c.position = r.position
	c.size = r.size


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
