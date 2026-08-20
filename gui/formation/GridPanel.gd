## =====================================================================
## GridPanel — 九宫格（readme：「队伍的九宫格信息，有九个锚点，用以放置单位」）
## =====================================================================
## 这是整个界面里**唯一有两种行为模式**的控件，所以单独成一个文件：
##
##   普通模式（焦点在队伍列表界面时）
##     点任意一格 → 把焦点交给队伍成员界面（readme 第 21 行）。
##     空格也算，整片九宫格都是可点区域，没有死角。
##
##   移动模式（成员操作菜单里选了「移动」之后）
##     焦点进入九宫格锚点，WSAD 循环移动一个**光标**，
##     空格/左键才真正提交：目标空 → 移过去；目标有人 → 两人互换。
##
##     ⚠️ readme 第 26 行「WSAD进行循环，如果目标是一个空栏位，则直接移动过去」
##     字面上像是「每按一次键就立即生效」。但那样光标走过有人的格子会瞬间互换，
##     用户没法反悔，得额外做撤销。这里实现成「光标 + 确认」两步，
##     ESC 取消不留任何痕迹，行为更可预期。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control        → 有位置尺寸的 UI 控件
## signal xxx(a)          → 信号（观察者）。本控件只负责「报告点了哪一格」，
##                          真正怎么处理由 FormationScreen 决定 —— 控件不做决策。
## gui_input              → 控件自己范围内的输入事件（区别于全局的 _unhandled_input）
## InputEventMouseButton  → 鼠标按键事件；.pressed 按下、.button_index 哪个键
## queue_free()           → 安全删除节点（下一帧才真删，比立即 free 安全）
## for c in get_children()→ 遍历子节点，等价于 Python 的 for c in children
## posmod(a, b)           → 取模且结果**恒为非负**（Python 的 % 本来就是这样，
##                          但 GDScript 的 % 对负数会返回负数，所以必须用 posmod）
## Callable.bind(x)       → 给回调预绑参数，等价于 functools.partial
## =====================================================================
class_name GridPanel
extends Control

## 某一格被点击（无论空格还是有人）。参数是格子编号 0..8。
signal cell_clicked(slot: int)

var _layout: FormationLayout
var _team: TeamModel = null

## 移动模式状态。_move_src < 0 表示当前不在移动模式。
var _move_src: int = -1
var _move_cursor: int = 0

## 9 个格子的 Panel，索引即 slot。
var _cells: Array = []


func setup(layout: FormationLayout) -> void:
	_layout = layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 自己不吃鼠标，让每个格子自己吃
	# 先把 9 个格子建出来，之后只改内容不重建节点。
	for i in TeamModel.MAX_UNITS:
		var cell := Panel.new()
		cell.name = "Cell%d" % i
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		# 闭包陷阱：必须先把循环变量拷进局部变量再 bind，
		# 否则所有格子的回调都会拿到循环结束后的同一个 i。
		var slot_copy := i
		cell.gui_input.connect(_on_cell_input.bind(slot_copy))
		add_child(cell)
		_cells.append(cell)


## 摆放 9 个格子的位置（窗口缩放时重调）。
func relayout() -> void:
	for i in _cells.size():
		var r: Rect2 = _layout.rect_grid_cell(i)
		var cell: Panel = _cells[i]
		cell.position = r.position
		cell.size = r.size
	refresh()


## 换一支队伍来显示。
func set_team(team: TeamModel) -> void:
	_team = team
	_move_src = -1
	refresh()


# ---------------- 移动模式 ----------------

func enter_move_mode(src_slot: int) -> void:
	_move_src = src_slot
	_move_cursor = src_slot   # 光标从源格开始，方便「原地取消」
	refresh()


func exit_move_mode() -> void:
	_move_src = -1
	refresh()


func is_moving() -> bool:
	return _move_src >= 0


func move_cursor() -> int:
	return _move_cursor


func move_source() -> int:
	return _move_src


## WSAD 循环移动光标。dx/dy 是列/行的增量。
## 行列各自独立 wrap（比如在最上一行按 W 会跳到最下一行的同一列）。
func step_cursor(dx: int, dy: int) -> void:
	if not is_moving():
		return
	var rc := TeamModel.slot_to_rc(_move_cursor)
	# posmod 保证负数取模也落在 0..2，GDScript 的 % 对负数会返回负数。
	var row := posmod(rc.x + dy, TeamModel.ROWS)
	var col := posmod(rc.y + dx, TeamModel.COLS)
	_move_cursor = TeamModel.rc_to_slot(row, col)
	refresh()


# ---------------- 渲染 ----------------

## 重绘全部格子。数据量很小（9 格），每次全量重建内容最省心也不卡。
func refresh() -> void:
	for i in _cells.size():
		_draw_cell(i)


func _draw_cell(slot: int) -> void:
	var cell: Panel = _cells[slot]
	# 清掉上一次的内容（保留 Panel 本身）
	for c in cell.get_children():
		c.queue_free()

	var unit: UnitModel = _team.unit_at(slot) if _team != null else null
	var is_src := is_moving() and slot == _move_src
	var is_cursor := is_moving() and slot == _move_cursor

	# ---- 格子底样式 ----
	var bg := Color(0.145, 0.114, 0.067) if unit != null else Color(0, 0, 0, 0.25)
	var edge := FormationSkin.LINE
	var edge_w := 1
	if is_cursor:
		# 移动模式的目标格：空格用绿色（可移入），有人用金色（会互换）
		edge = FormationSkin.GREEN if _team.unit_at(slot) == null else FormationSkin.GOLD
		edge_w = 3
	elif is_src:
		edge = FormationSkin.GOLD
		edge_w = 2
	cell.add_theme_stylebox_override("panel", FormationSkin.box(bg, edge, edge_w, 5))

	if unit == null:
		# 空格：移动模式下提示「移到这」，平时只画一个淡淡的点
		var hint := "移到这" if is_cursor else "·"
		var col := FormationSkin.GREEN if is_cursor else FormationSkin.INK_DIM
		var l := FormationSkin.make_text(hint, col, 12 if is_cursor else 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		FormationSkin.add_filling(cell, l)
		return

	# ---- 有人的格子：头像 + 名字，队长额外加皇冠 ----
	var side := minf(cell.size.x, cell.size.y)
	var pw := side * 0.52
	var portrait := FormationSkin.make_portrait(unit, pw)
	portrait.position = Vector2((cell.size.x - pw) * 0.5, side * 0.10)
	portrait.size = Vector2(pw, pw)
	cell.add_child(portrait)

	var nm := FormationSkin.make_text(unit.display_name(), FormationSkin.INK, 11)
	nm.position = Vector2(2.0, side * 0.10 + pw + 2.0)
	nm.size = Vector2(cell.size.x - 4.0, 16.0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true   # 名字太长就裁掉，不要撑破格子
	cell.add_child(nm)

	if _team != null and _team.captain == unit:
		var crown := FormationSkin.make_crown(side * 0.22)
		crown.position = Vector2(3.0, 3.0)
		cell.add_child(crown)


# ---------------- 输入 ----------------

## 格子被点击。本控件只把「点了第几格」报上去，不自己判断该干嘛 ——
## 该干嘛取决于当前处在哪个 Surface，那是 FormationScreen 的职责。
func _on_cell_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(slot)
