## 部队：3x3 九宫格（对应 pydemo/game/army.py）。
## 队长领导力决定占用上限；九宫格行列决定攻击可达性；每单位恒占 1 格。
class_name Armies
extends RefCounted

const ROWS: Array[String] = ["front", "mid", "back"]
const ROW_CN: Dictionary = {"front": "前", "mid": "中", "back": "后"}
const GRID_SIZE := 9

static func row_of(slot: int) -> String:
	return ROWS[slot / 3]   # 0-2 前, 3-5 中, 6-8 后

static func col_of(slot: int) -> int:
	return slot % 3

class Army:
	var id: String
	var name: String
	var captain_id: String = ""
	var grid: Array = []        # 9 个槽：单位 id 或 null
	var owner: String = ""
	var node_id: String = ""
	var has_acted_this_turn: bool = false
	var supply: int = 10
	var supply_max: int = 10

	func _init(id_: String, name_: String, captain_id_: String = "",
			grid_: Array = [], owner_: String = "", node_id_: String = "",
			has_acted_this_turn_: bool = false, supply_: int = 10,
			supply_max_: int = 10) -> void:
		id = id_
		name = name_
		captain_id = captain_id_
		grid = []
		for i in range(GRID_SIZE):
			grid.append(null)
		if grid_.size() == GRID_SIZE:
			grid = grid_.duplicate()
		owner = owner_
		node_id = node_id_
		has_acted_this_turn = has_acted_this_turn_
		supply = supply_
		supply_max = supply_max_

	func units(unit_index: Dictionary) -> Array:
		var out: Array = []
		for uid in grid:
			if uid != null and unit_index.has(uid):
				out.append(unit_index[uid])
		return out

	## 部队当前占用的领导力总和。
	func occupy_total(unit_index: Dictionary) -> int:
		var s := 0
		for uid in grid:
			if uid != null and unit_index.has(uid):
				s += unit_index[uid].occupy()
		return s

	## 部队可承载占用上限 = 队长领导力。
	func max_leadership(unit_index: Dictionary) -> int:
		if captain_id != "" and unit_index.has(captain_id):
			return unit_index[captain_id].leadership()
		return 0

	func can_add(unit: Units.Unit, unit_index: Dictionary) -> bool:
		if not unit_index.has(unit.id):
			return false
		if not grid.has(null):
			return false
		if occupy_total(unit_index) + unit.occupy() > max_leadership(unit_index):
			return false
		return true

	## 按兵种角色挑槽位：近战趋前，远程/魔法趋后，其余居中。
	func _pick_slot(unit: Units.Unit) -> int:
		var pref: Array = []
		if unit.tags.has("melee"):
			pref = [0, 1, 2, 3, 4, 5, 6, 7, 8]
		elif unit.tags.has("ranged") or unit.tags.has("magic"):
			pref = [6, 7, 8, 3, 4, 5, 0, 1, 2]
		else:
			pref = [3, 4, 5, 0, 1, 2, 6, 7, 8]
		for s in pref:
			if grid[s] == null:
				return s
		return -1

	func add(unit: Units.Unit, unit_index: Dictionary, slot: int = -1) -> bool:
		if not can_add(unit, unit_index):
			return false
		if slot < 0:
			slot = _pick_slot(unit)
			if slot < 0:
				return false
		if grid[slot] != null:
			return false
		grid[slot] = unit.id
		unit.army_id = id
		return true

	func remove(unit_id: String) -> void:
		for i in range(GRID_SIZE):
			if grid[i] == unit_id:
				grid[i] = null

	func alive_units(unit_index: Dictionary) -> Array:
		var out: Array = []
		for u in units(unit_index):
			if u.alive:
				out.append(u)
		return out

	func is_wiped(unit_index: Dictionary) -> bool:
		return alive_units(unit_index).is_empty()

	func slot_of(unit_id: String) -> int:
		for i in range(GRID_SIZE):
			if grid[i] == unit_id:
				return i
		return -1

	func describe(unit_index: Dictionary) -> String:
		var cap := "无"
		if captain_id != "" and unit_index.has(captain_id):
			cap = unit_index[captain_id].name
		var lines: Array[String] = [
			"%s(队长:%s 占用:%d/%d 补给:%d)" % [
				name, cap, occupy_total(unit_index), max_leadership(unit_index), supply]]
		for r in range(3):
			var cells: Array[String] = []
			for c in range(3):
				var slot := r * 3 + c
				var uid = grid[slot]
				cells.append(unit_index[uid].name if uid != null and unit_index.has(uid) else "·")
			lines.append("%s排[%s]" % [ROW_CN[ROWS[r]], " ".join(cells)])
		return "\n  ".join(lines)

## 创建空部队。
static func empty_army(army_id: String, name: String, owner: String, node_id: String) -> Army:
	return Armies.Army.new(army_id, name, "", [], owner, node_id)
