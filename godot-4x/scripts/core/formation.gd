## 战斗策略（Formation）：预设优先级表（对应 pydemo/game/formation.py，ADR-0011）。
## 策略表 ≤8 行，分主动区 + 被动区；条件分必要（硬筛）/ 优先（软排）两型。
class_name Formation
extends RefCounted

const STRATEGY_ROW_CAP := 8

class StrategyRow:
	var skill_id: String
	var trigger_point: String = ""
	var necessary: Array = []
	var priority: Array = []

	func _init(skill_id_: String, trigger_point_: String = "",
			necessary_: Array = [], priority_: Array = []) -> void:
		skill_id = skill_id_
		trigger_point = trigger_point_
		necessary = necessary_
		priority = priority_

class UnitStrategy:
	var unit_id: String
	var active_rows: Array = []
	var passive_rows: Array = []
	var target_pref: String = "low_hp"
	var skill_order: Array = []
	var hold_position: bool = false

	func _init(unit_id_: String, active_rows_: Array = [], passive_rows_: Array = [],
			target_pref_: String = "low_hp", skill_order_: Array = [],
			hold_position_: bool = false) -> void:
		unit_id = unit_id_
		active_rows = active_rows_
		passive_rows = passive_rows_
		target_pref = target_pref_
		skill_order = skill_order_
		hold_position = hold_position_

	func total_rows() -> int:
		return active_rows.size() + passive_rows.size()

## 从被动技能定义读 trigger_point（第一个带 trigger_point 的 passive effect）。
static func _trigger_point_of_passive(skill_def: Dictionary) -> String:
	for e in skill_def.get("effects", []):
		var tp: String = e.get("trigger_point", "")
		if tp != "":
			return tp
	return ""

## 根据单位词条与技能定义给默认策略。
static func default_strategy(unit: Units.Unit, skill_defs: Dictionary) -> UnitStrategy:
	var pref := "low_hp"
	if unit.tags.has("melee"):
		pref = "front"
	var active_rows: Array = []
	var passive_rows: Array = []
	for sid in unit.effective_skills():
		if not skill_defs.has(sid):
			continue
		var sd: Dictionary = skill_defs[sid]
		match Effects.skill_kind(sd):
			Effects.SKILL_ACTIVE:
				var nec: Array = []
				if unit.tags.has("melee"):
					nec = [{"type": "target_pref_front"}]
				else:
					nec = [{"type": "target_pref_low_hp"}]
				active_rows.append(StrategyRow.new(sid, "", nec, []))
			Effects.SKILL_PASSIVE:
				passive_rows.append(StrategyRow.new(sid, _trigger_point_of_passive(sd), [], []))
	return UnitStrategy.new(unit.id, active_rows, passive_rows, pref, unit.skills.duplicate())

## 为部队每个活着的单位生成默认策略。
static func build_default_formation(army: Armies.Army, unit_index: Dictionary,
		skill_defs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for u in army.alive_units(unit_index):
		out[u.id] = default_strategy(u, skill_defs)
	return out

## 带敌方槽位的可达性 + 策略选目标。返回 [slot, unit] 或 null。
static func choose_target_with_slots(attacker_slot: int, attacker_tags: Array,
		enemy_slots: Array, strat: UnitStrategy, rng: RandomNumberGenerator,
		necessary: Array = [], priority: Array = [],
		eff_map: Dictionary = {}, ctx = null, attacker = null) -> Array:
	var is_melee := attacker_tags.has("melee")
	var alive: Array = []
	for su in enemy_slots:
		if su[1].alive:
			alive.append(su)
	if alive.is_empty():
		return []
	var pool: Array = []
	if is_melee:
		for row in Armies.ROWS:
			var row_units: Array = []
			for su in alive:
				if Armies.row_of(su[0]) == row:
					row_units.append(su)
			if not row_units.is_empty():
				pool = row_units
				break
		if pool.is_empty():
			return []
	else:
		pool = alive
	var reachable: Array = pool.duplicate()

	# 必要条件过滤（目标型）
	if not necessary.is_empty():
		var filtered: Array = []
		for su in pool:
			var ok := true
			for cond in necessary:
				var t: String = cond.get("type", "")
				if t in ["self_hp_le", "ally_avg_hp_le", "row_count_ge"]:
					continue   # gate 释放，不在此筛
				var c: Dictionary = cond.duplicate()
				c["_target_slot"] = su[0]
				if not Triggers.eval_necessary(c, ctx, attacker, su[1]):
					ok = false
					break
			if ok:
				filtered.append(su)
		if not filtered.is_empty():
			pool = filtered
		else:
			pool = reachable   # 池空回退可达性池，不软锁

	# 优先条件稳定排序
	if not priority.is_empty():
		var sort_key := func(su):
			var keys: Array = []
			for cond in priority:
				keys.append_array(Triggers.priority_key(cond, ctx, su[1], su[0]))
			keys.append(su[1].id)
			return keys
		pool.sort_custom(func(a, b):
			return _cmp_arrays(sort_key.call(a), sort_key.call(b)) < 0)
		return pool[0]

	# 旧 target_pref fallback
	var tp := strat.target_pref if strat != null else "low_hp"
	if tp == "low_hp":
		pool.sort_custom(func(a, b): return a[1].cur_hp < b[1].cur_hp)
		return pool[0]
	if tp == "front":
		var front: Array = []
		for su in pool:
			if Armies.row_of(su[0]) == "front":
				front.append(su)
		return (front if not front.is_empty() else pool)[0]
	return pool[rng.randi() % pool.size()]

static func _cmp_arrays(a: Array, b: Array) -> int:
	for i in range(mini(a.size(), b.size())):
		var av: Variant = a[i]
		var bv: Variant = b[i]
		if av is float and bv is float:
			if av < bv:
				return -1
			if av > bv:
				return 1
		elif av != bv:
			return -1 if str(av) < str(bv) else 1
	return 0
