## =====================================================================
## TeamModel — 一支队伍（九宫格 + 队长 + 队名）
## =====================================================================
## 九宫格用一个长度固定为 9 的数组表示，slot = row * 3 + col：
##       col0  col1  col2
##  row0   0     1     2      ← 后排（离敌人远）
##  row1   3     4     5
##  row2   6     7     8      ← 前排（离敌人近）
## 空格子存 null。这套编号沿用 fullver-1 scripts/core/team.gd 的约定。
##
## 本文件最重要的东西是 is_valid() —— readme 第 30 行那条退出校验规则。
## 规则以后要改，只动那一个函数。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends RefCounted      → 纯数据对象，不进场景树（同 UnitModel）
## Array                   → 等价于 Python list。这里刻意**不用** Array[UnitModel] 这种
##                           类型化数组：GDScript 的类型化数组在跨文件返回时容易出兼容问题，
##                           而且它不允许存 null，而我们的空格子就是 null。
## null                    → 等价于 Python 的 None
## for i in 9:             → 等价于 Python 的 for i in range(9)
## range(a, b)             → 和 Python 一样
## == / !=                 → 对象比较的是引用（同一个实例），类似 Python 的 is
## Array 返回多个值        → GDScript 没有元组，要返回多个值就返回 Array 或 Dictionary
## push_warning(msg)       → 输出警告到 Godot 控制台（不中断执行）
## =====================================================================
class_name TeamModel
extends RefCounted

const ROWS := 3
const COLS := 3
const MAX_UNITS := 9

## 退出校验的结果码。用字符串常量而不是 enum，方便直接塞进提示文本里。
const OK := "OK"                    # 合法，可以退出
const VOID := "VOID"                # 空队 → 允许退出，但队伍作废、自动删除
const NO_CAPTAIN := "NO_CAPTAIN"    # 有人但没队长 → 拒绝退出
const OVERLOAD := "OVERLOAD"        # 队长领导力不足 → 拒绝退出

var id: String = ""
var team_name: String = "新队伍"
## 9 个格子，元素是 UnitModel 或 null。
var cells: Array = [null, null, null, null, null, null, null, null, null]
## 队长。必须是本队成员之一；不是队长时为 null。
var captain: UnitModel = null


func _init(p_id: String = "", p_name: String = "新队伍") -> void:
	id = p_id
	team_name = p_name
	# 注意：这里必须重新建一个数组。上面 var cells := [...] 的字面量如果直接用，
	# 所有 TeamModel 实例会共享同一个数组（Array 是引用类型）——这是 GDScript
	# 相当于 Python「可变默认参数」的经典坑。
	cells = [null, null, null, null, null, null, null, null, null]


# ---------------- 格子读写 ----------------

## 行列 → 格子编号。
static func rc_to_slot(row: int, col: int) -> int:
	return row * COLS + col


## 格子编号 → 行列（返回 Vector2i(row, col)）。
static func slot_to_rc(slot: int) -> Vector2i:
	return Vector2i(slot / COLS, slot % COLS)


## 取某格的单位；空格返回 null。越界也返回 null。
func unit_at(slot: int) -> UnitModel:
	if slot < 0 or slot >= MAX_UNITS:
		return null
	return cells[slot]


## 往某格放单位。该格已有人时返回 false（调用方应该先判空或走 move_unit 走互换）。
func set_unit(slot: int, unit: UnitModel) -> bool:
	if slot < 0 or slot >= MAX_UNITS:
		return false
	if cells[slot] != null:
		return false
	cells[slot] = unit
	# 第一个进队的人自动成为队长，省得空队没队长。
	if captain == null:
		captain = unit
	return true


## 找第一个空格子，没有空格返回 -1。
## 顺序是 0..8，也就是从后排往前排填。
func first_empty_slot() -> int:
	for i in MAX_UNITS:
		if cells[i] == null:
			return i
	return -1


## 把某格的单位拿走并返回它。空格返回 null。
## 如果拿走的是队长，队长自动改派给剩下的第一个人（没人了就是 null）。
func remove_at(slot: int) -> UnitModel:
	if slot < 0 or slot >= MAX_UNITS:
		return null
	var u: UnitModel = cells[slot]
	if u == null:
		return null
	cells[slot] = null
	if captain == u:
		captain = null
		for c in cells:
			if c != null:
				captain = c
				break
	return u


## 移动 / 互换。
##   目标格为空 → 直接移过去
##   目标格有人 → 两人交换位置
## 源格为空或首尾同格时什么也不做。
func move_unit(from_slot: int, to_slot: int) -> void:
	if from_slot < 0 or from_slot >= MAX_UNITS:
		return
	if to_slot < 0 or to_slot >= MAX_UNITS:
		return
	if from_slot == to_slot:
		return
	if cells[from_slot] == null:
		return
	# 一行搞定「移动」和「互换」两种情况：目标为 null 时，交换后源格自然变成 null。
	var tmp = cells[to_slot]
	cells[to_slot] = cells[from_slot]
	cells[from_slot] = tmp


## 找某个单位在第几格；不在本队返回 -1。
func slot_of(unit: UnitModel) -> int:
	if unit == null:
		return -1
	for i in MAX_UNITS:
		if cells[i] == unit:
			return i
	return -1


## 按格子顺序返回所有非空单位（从上到下、从左到右）。
## 队伍成员界面就是用这个顺序做「从上往下紧密排列」的。
func members() -> Array:
	var out: Array = []
	for c in cells:
		if c != null:
			out.append(c)
	return out


func unit_count() -> int:
	return members().size()


func is_empty() -> bool:
	return unit_count() == 0


## 全队规模之和。用来和队长领导力比。
func total_size() -> int:
	var sum := 0
	for c in cells:
		if c != null:
			sum += c.size
	return sum


## 设队长。必须是本队成员，否则拒绝并返回 false。
## readme 说「设为队长，直接设为队长，将合法性检查留到退出界面」——
## 所以这里只检查「是不是本队的人」，不检查领导力够不够。
func set_captain(unit: UnitModel) -> bool:
	if unit == null or slot_of(unit) < 0:
		return false
	captain = unit
	return true


# ---------------- 退出校验（readme 第 30 行，本功能的核心）----------------

## 返回 [结果码, 给用户看的说明]。
##
## ⚠️ 关于 readme 的一处自相矛盾（实现时必须挑一边）：
## 第 30 行写的是「如果没有队长（即没有任何一个单位）」，把「没队长」和「没人」
## 当成了同一件事。但第 27 行的「下场」可以把队长本人移走，会留下
## **有人却没队长** 的队伍。所以这里以**人数**为准：
##     0 人      → VOID，允许退出但队伍作废、自动删除
##     有人无队长 → NO_CAPTAIN，拒绝退出，要求先指定队长
## 这样两条规则都能自洽。
func is_valid() -> Array:
	if unit_count() == 0:
		return [VOID, "队伍没有任何单位，将被自动解散"]
	if captain == null:
		return [NO_CAPTAIN, "队伍没有队长，请先设为队长"]
	var used := total_size()
	var cap := captain.leadership
	if used > cap:
		return [OVERLOAD, "队长「%s」领导力 %d，不足以容纳全队规模 %d（还缺 %d）" \
			% [captain.display_name(), cap, used, used - cap]]
	return [OK, ""]


## 保存成功时改名：readme 要求用「<队长名>队」。
func rename_by_captain() -> void:
	if captain != null:
		team_name = "%s队" % captain.display_name()
