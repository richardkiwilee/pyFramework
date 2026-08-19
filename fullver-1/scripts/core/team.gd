class_name Team
extends RefCounted
## =============================================================================
## Team — 编队（3×3 最多 9 个单位）
## =============================================================================
## 领域术语见 CONTEXT.md：编队隶属于军团（Army），格子排布决定战斗站位。
##
## 槽位约定（移植 demo-1 TeamManager 的语义）：
##   slot = row * 3 + col（0~8）
##   row 0 = 后排（棋盘顶部，离敌人远）
##   row 2 = 前排（棋盘底部，离敌人近）
##
## ⭐ 本项目修正 demo-1 的缺陷（"棋盘摆位不影响战斗"）：
##   槽位与战斗站位显式映射：前排（row 2）→ 战斗 position 0-2，
##   中排 → 3-5，后排（row 0）→ 6-8。战斗引擎按此映射布阵，
##   玩家在编成界面的摆放真实影响战斗（docs/00-design.md §9.1）。
##
## 类比 Python：
##   相当于一个定长 list（9 格）+ 队长的组合，空位是 None。
## =============================================================================

const ROWS := 3
const COLS := 3
const MAX_UNITS := 9

## 槽位数组：长度固定 9，空位为 null（GDScript 类型化数组允许 null 元素）
## slot = row * 3 + col
var units: Array[Unit] = [null, null, null, null, null, null, null, null, null]

## 队长：指向 units 中某个单位的引用（为空编队时是 null）
var captain: Unit


## ---------------------------------------------------------------------------
## 槽位操作
## ---------------------------------------------------------------------------

## 取某个槽位的单位（空位返回 null）
func get_unit_at(slot: int) -> Unit:
	if slot < 0 or slot >= MAX_UNITS:
		return null
	return units[slot]


## 放一个单位到指定槽位。目标槽位非空则返回 false（先移走再放）。
func set_unit(slot: int, unit: Unit) -> bool:
	if slot < 0 or slot >= MAX_UNITS:
		return false
	if units[slot] != null:
		return false
	units[slot] = unit
	if captain == null:
		captain = unit
	return true


## 移除槽位上的单位（空位返回 null）。队长被移除时自动回退到第一个存活单位。
func remove_unit_at(slot: int) -> Unit:
	var u := get_unit_at(slot)
	if u == null:
		return null
	units[slot] = null
	if captain == u:
		captain = _first_unit()
	return u


## 把一个槽位的单位移动到另一个空槽位（换位用）
func move_unit(from_slot: int, to_slot: int) -> bool:
	if to_slot < 0 or to_slot >= MAX_UNITS or units[to_slot] != null:
		return false
	var u := get_unit_at(from_slot)
	if u == null:
		return false
	units[to_slot] = u
	units[from_slot] = null
	return true


## 存活单位数量（编队里非空槽位数）
func unit_count() -> int:
	var n := 0
	for u in units:
		if u != null:
			n += 1
	return n


## 编队是否为空
func is_empty() -> bool:
	return unit_count() == 0


## ---------------------------------------------------------------------------
## 战斗站位映射（docs/00-design.md §9.1）
## ---------------------------------------------------------------------------

## 槽位 → 战斗 position（0-8）
## 映射规则：前排（row 2）→ 0-2，中排（row 1）→ 3-5，后排（row 0）→ 6-8
## 公式：position = (2 - row) * 3 + col
## 战斗引擎里 position < 3 = 前排（与 demo-1 口径一致）
static func slot_to_battle_position(slot: int) -> int:
	var row := slot / 3
	var col := slot % 3
	return (2 - row) * 3 + col


## 战斗 position → 槽位（反向映射，用于显示"战斗中谁在哪个格子"）
static func battle_position_to_slot(position: int) -> int:
	var row := 2 - position / 3
	var col := position % 3
	return row * 3 + col


## 取队长（可能为 null）
func get_captain() -> Unit:
	return captain


## 队长设为指定单位（该单位必须在编队内，否则拒绝）
func set_captain(unit: Unit) -> bool:
	if unit == null or unit not in units:
		return false
	captain = unit
	return true


## ---------------------------------------------------------------------------
## 序列化（存档用）
## ---------------------------------------------------------------------------
## 设计决策：units 槽位直接内嵌完整 Unit 字典（空位存空串），
## 存档自包含——读档时不需要跨表 id 查找，Unit 数据跟着编队走。
## 缺点：单位数据不共享（本框架里单位本来就唯一归属一个编队，无共享需求）。
## ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var unit_slots: Array = []
	for u in units:
		unit_slots.append(u.to_dict() if u != null else "")
	return {
		"units": unit_slots,
		"captain": captain.id if captain != null else "",
	}


static func from_dict(d: Dictionary) -> Team:
	var t := Team.new()
	var slots: Array = d.get("units", [])
	# 槽位字典 → Unit 对象（空串/缺失 = 空位）
	for i in range(MAX_UNITS):
		if i >= slots.size():
			break
		var slot: Variant = slots[i]
		if slot is Dictionary:
			t.units[i] = Unit.from_dict(slot)
	# 按 id 找回队长（队长必须是编队内成员）
	var cap_id: String = d.get("captain", "")
	for u in t.units:
		if u != null and u.id == cap_id:
			t.captain = u
			break
	return t


## 内部：找第一个非空单位（队长回退用）
func _first_unit() -> Unit:
	for u in units:
		if u != null:
			return u
	return null
