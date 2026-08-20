## =====================================================================
## MemberPanel — 队伍成员界面（屏幕右半边）
## =====================================================================
## readme 第 18-25 行：
##   · 均分为 9 个栏位，表示最多可以上场 9 个单位
##   · WS 或鼠标悬停在成员上进行切换
##   · 空格或鼠标左键点击一个成员，弹出操作选项
##   · 虽然单位在九宫格内都有位置，但**所有的角色栏位是从上往下紧密排列**，
##     第一个空栏位中间显示一个加号，表示添加成员
##
## ⚠️ 「紧密排列」是这个面板最容易做错的地方：
##   九宫格里的单位可能散布在 0/4/8 三格，但成员界面必须显示成
##   第 0 行、第 1 行、第 2 行连续三行，第 3 行才是加号。
##   所以本文件维护一个 _members 数组（= team.members() 的顺序），
##   行号和格子号是**两套编号**，要靠 _members[row] 互相换算，不能混用。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control      → UI 控件基类
## signal xxx(i)        → 信号
## Array                → 等价于 Python list
## for i in n:          → 等价于 for i in range(n)
## clampi(v, lo, hi)    → 整数版 clamp，把 v 夹在 [lo, hi] 之间
## posmod(a, b)         → 结果恒非负的取模（用来做首尾循环）
## is_instance_valid(o) → 判断对象是否还活着（节点被 queue_free 后就无效了）
## =====================================================================
class_name MemberPanel
extends Control

## 光标移动到第 row 行（0..8）。
signal cursor_changed(row: int)
## 第 row 行被「确认」（空格或左键）。
signal row_activated(row: int)

var _layout: FormationLayout
var _title: Label
var _rows: Array = []          # 9 个 MemberRow，索引 = 行号
var _team: TeamModel = null
var _members: Array = []       # 当前队伍的成员，顺序 = 从上往下的显示顺序
var _cursor: int = 0           # 光标所在行号


func setup(layout: FormationLayout) -> void:
	_layout = layout
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title = FormationSkin.make_title("队伍成员")
	add_child(_title)

	for i in FormationLayout.MEMBER_ROWS:
		var row := MemberRow.new()
		row.name = "Row%d" % i
		# 闭包陷阱：循环变量必须先拷进局部变量，否则所有行的回调都拿到同一个 i。
		var row_copy := i
		row.clicked.connect(func(): row_activated.emit(row_copy))
		row.hovered.connect(func(): _on_row_hovered(row_copy))
		add_child(row)
		_rows.append(row)


func relayout() -> void:
	position = Vector2.ZERO
	size = _layout.zone_right.size

	var rt: Rect2 = _layout.rect_right_title()
	_title.position = rt.position
	_title.size = rt.size

	for i in _rows.size():
		var r: Rect2 = _layout.rect_member_row(i)
		var row: MemberRow = _rows[i]
		row.position = r.position
		row.size = r.size
		row.relayout()


## 换队伍 / 数据变了，整体刷新。
## keep_cursor = true 时尽量保持光标位置（比如换完装备回来）。
func refresh(team: TeamModel, keep_cursor: bool = true) -> void:
	_team = team
	# team.members() 已经按格子顺序（0..8）返回非空单位，
	# 直接拿来当「从上往下紧密排列」的显示顺序。
	_members = team.members() if team != null else []

	if not keep_cursor:
		_cursor = 0
	# 光标不能超出「成员数 + 1（加号行）」的范围
	_cursor = clampi(_cursor, 0, maxi(0, mini(_members.size(), FormationLayout.MEMBER_ROWS - 1)))

	if team != null:
		_title.text = "队伍成员　%d/9" % _members.size()
	else:
		_title.text = "队伍成员"

	# 第一个空栏位的行号 = 成员数（因为成员是紧密排列的）。
	# 满 9 人时没有加号行。
	var add_row := _members.size() if _members.size() < FormationLayout.MEMBER_ROWS else -1

	for i in _rows.size():
		var u: UnitModel = _members[i] if i < _members.size() else null
		var is_cap := u != null and team != null and team.captain == u
		_rows[i].set_data(u, i == add_row, i == _cursor, is_cap)


# ---------------- 光标 ----------------

func cursor() -> int:
	return _cursor


## 光标所在行对应的单位；加号行或空行返回 null。
func cursor_unit() -> UnitModel:
	if _cursor >= 0 and _cursor < _members.size():
		return _members[_cursor]
	return null


## 光标所在行是不是「加号行」。
func cursor_is_add_row() -> bool:
	return _cursor == _members.size() and _members.size() < FormationLayout.MEMBER_ROWS


## 可用行数 = 成员数 + 加号行（如果有）。光标只在这个范围里循环。
func _usable_rows() -> int:
	var n := _members.size()
	if n < FormationLayout.MEMBER_ROWS:
		n += 1   # 加号行
	return maxi(n, 1)


## W/S 移动光标。step = -1 上 / +1 下。首尾循环。
func step_cursor(step: int) -> void:
	_cursor = posmod(_cursor + step, _usable_rows())
	_apply_cursor()
	cursor_changed.emit(_cursor)


## 鼠标悬停切换（readme：鼠标悬停在成员直接进行切换）。
## 悬停到没有内容的空行时忽略，避免光标乱跳。
func _on_row_hovered(row: int) -> void:
	if row >= _usable_rows():
		return
	if row == _cursor:
		return
	_cursor = row
	_apply_cursor()
	cursor_changed.emit(_cursor)


## 只更新选中态，不重建整行内容（比 refresh 便宜）。
func _apply_cursor() -> void:
	var add_row := _members.size() if _members.size() < FormationLayout.MEMBER_ROWS else -1
	for i in _rows.size():
		var u: UnitModel = _members[i] if i < _members.size() else null
		var is_cap := u != null and _team != null and _team.captain == u
		_rows[i].set_data(u, i == add_row, i == _cursor, is_cap)


## 取第 row 行的屏幕矩形，用来把操作菜单弹在它旁边。
## 返回的是**相对本面板**的坐标。
func row_rect(row: int) -> Rect2:
	if row < 0 or row >= _rows.size():
		return Rect2()
	var r: MemberRow = _rows[row]
	return Rect2(r.position, r.size)
