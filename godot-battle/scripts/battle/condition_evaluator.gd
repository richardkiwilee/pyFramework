# condition_evaluator.gd
# 条件评估器 — 评估技能的策略条件，筛选/排序目标
# RefCounted 纯代码类，不依赖场景树
class_name ConditionEvaluator extends RefCounted


# 评估条件，返回筛选/排序后的目标列表
# condition: {"type": "...", "mode": "only"|"priority"}
# caster: 施法者数据字典
# targets: 潜在目标数据字典数组
# all_units: 所有单位（用于位置判断等）
func evaluate_single(condition: Dictionary, caster: Dictionary, targets: Array[Dictionary], all_units: Array[Dictionary]) -> Array[Dictionary]:
	if condition.is_empty() or not condition.has("type") or condition.type == "":
		return targets.duplicate()

	var result: Array[Dictionary]
	match condition.type:
		"hp_lowest":
			result = _sort_by(targets, "hp_current", true)
		"hp_highest":
			result = _sort_by(targets, "hp_current", false)
		"hp_below_50":
			result = _filter_hp_below(targets, 50)
		"hp_below_25":
			result = _filter_hp_below(targets, 25)
		"hp_full":
			result = _filter_hp_full(targets)
		"def_lowest":
			result = _sort_by(targets, "def", true)
		"atk_highest":
			result = _sort_by(targets, "atk", false)
		"speed_fastest":
			result = _sort_by(targets, "speed", false)
		"evasion_lowest":
			result = _sort_by(targets, "evasion", true)
		"infantry":
			result = _filter_by_tag(targets, "infantry")
		"cavalry":
			result = _filter_by_tag(targets, "cavalry")
		"flying":
			result = _filter_by_tag(targets, "flying")
		"armored":
			result = _filter_by_tag(targets, "armored")
		"scout":
			result = _filter_by_tag(targets, "scout")
		"caster":
			result = _filter_by_tag(targets, "caster")
		"healer":
			result = _filter_by_tag(targets, "healer")
		"front_row":
			result = _filter_by_row(targets, all_units, 0)
		"back_row":
			result = _filter_by_row(targets, all_units, 1)
		"poisoned":
			result = _filter_by_status(targets, "poison")
		"burning":
			result = _filter_by_status(targets, "burn")
		"frozen":
			result = _filter_by_status(targets, "freeze")
		_:
			result = targets.duplicate()

	return result


# 评估双条件组合（核心逻辑）
# 返回筛选并排序好的目标列表，第一个为最佳目标
func evaluate_dual(
	condition_1: Dictionary,
	condition_2: Dictionary,
	caster: Dictionary,
	targets: Array[Dictionary],
	all_units: Array[Dictionary]
) -> Array[Dictionary]:
	if targets.is_empty():
		return []

	var c1_empty = condition_1.is_empty() or not condition_1.has("type") or condition_1.type == ""
	var c2_empty = condition_2.is_empty() or not condition_2.has("type") or condition_2.type == ""

	# 两个都为空 → 返回默认目标（前排→后排→就近）
	if c1_empty and c2_empty:
		return _default_target_order(targets, all_units)

	var mode_1 = condition_1.get("mode", "priority") if not c1_empty else ""
	var mode_2 = condition_2.get("mode", "priority") if not c2_empty else ""

	# 情况 1: 仅+仅 → AND 逻辑，两个条件必须同时满足
	if mode_1 == "only" and mode_2 == "only":
		var r1 = evaluate_single(condition_1, caster, targets, all_units)
		var r2 = evaluate_single(condition_2, caster, targets, all_units)
		var intersection: Array[Dictionary] = []
		for t in r1:
			if r2.has(t):
				intersection.append(t)
		return intersection

	# 情况 2: 仅+优先 → "仅"限定范围，"优先"在范围内排序
	if mode_1 == "only" and mode_2 == "priority":
		var filtered = evaluate_single(condition_1, caster, targets, all_units)
		if filtered.is_empty():
			return []  # "仅"条件不满足，跳过技能
		return evaluate_single(condition_2, caster, filtered, all_units)

	if mode_1 == "priority" and mode_2 == "only":
		var filtered = evaluate_single(condition_2, caster, targets, all_units)
		if filtered.is_empty():
			return []
		return evaluate_single(condition_1, caster, filtered, all_units)

	# 情况 3: 优先+优先 → 按"前后排"优先级规则
	if mode_1 == "priority" and mode_2 == "priority":
		var c1_front = condition_1.type == "front_row"
		var c2_front = condition_2.type == "front_row"
		var c1_back = condition_1.type == "back_row"
		var c2_back = condition_2.type == "back_row"

		# 第1步: 同时满足两个条件的目标
		var r1_all = evaluate_single(condition_1, caster, targets, all_units)
		var r2_all = evaluate_single(condition_2, caster, targets, all_units)
		var both: Array[Dictionary] = []
		for t in r1_all:
			if r2_all.has(t):
				both.append(t)

		# 第2步: 仅满足条件2
		var only_c2: Array[Dictionary] = []
		for t in r2_all:
			if not both.has(t):
				only_c2.append(t)

		# 第3步: 仅满足条件1
		var only_c1: Array[Dictionary] = []
		for t in r1_all:
			if not both.has(t):
				only_c1.append(t)

		# 特殊处理: "优先前排"/"优先后排"优先级最高
		# 先返回前后排条件结果，再按正常顺序
		var result: Array[Dictionary] = []
		result.append_array(both)
		result.append_array(only_c2)
		result.append_array(only_c1)
		return result

	# 单条件
	if mode_1 == "only":
		return evaluate_single(condition_1, caster, targets, all_units)
	if mode_2 == "only":
		return evaluate_single(condition_2, caster, targets, all_units)

	return _default_target_order(targets, all_units)


# 检查一个"仅"条件是否被满足（用于判断技能是否该跳过）
func is_only_condition_met(condition: Dictionary, caster: Dictionary, targets: Array[Dictionary], all_units: Array[Dictionary]) -> bool:
	if condition.is_empty() or not condition.has("type") or condition.type == "":
		return true  # 无条件不限制
	var filtered = evaluate_single(condition, caster, targets, all_units)
	return not filtered.is_empty()


# 默认目标顺序: 前排→后排→就近
func _default_target_order(targets: Array[Dictionary], all_units: Array[Dictionary]) -> Array[Dictionary]:
	var front: Array[Dictionary] = []
	var back: Array[Dictionary] = []
	for t in targets:
		if not t.get("is_alive", false):
			continue
		if t.get("row", 0) == 0:
			front.append(t)
		else:
			back.append(t)
	var result: Array[Dictionary] = []
	result.append_array(front)
	result.append_array(back)
	return result


func _sort_by(targets: Array[Dictionary], stat: String, ascending: bool) -> Array[Dictionary]:
	var result = targets.duplicate()
	result.sort_custom(func(a, b): return a.get(stat, 0) < b.get(stat, 0) if ascending else a.get(stat, 0) > b.get(stat, 0))
	return result


func _filter_hp_below(targets: Array[Dictionary], pct: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in targets:
		var hp_max = t.get("hp", 1)
		var hp_cur = t.get("hp_current", 0)
		if hp_max > 0 and float(hp_cur) / float(hp_max) * 100.0 < pct:
			result.append(t)
	return result


func _filter_hp_full(targets: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in targets:
		if t.get("hp_current", 0) >= t.get("hp", 1):
			result.append(t)
	return result


func _filter_by_tag(targets: Array[Dictionary], tag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in targets:
		if t.get("tags", []).has(tag):
			result.append(t)
	return result


func _filter_by_row(targets: Array[Dictionary], all_units: Array[Dictionary], row: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in targets:
		if t.get("row", -1) == row:
			result.append(t)
	return result


func _filter_by_status(targets: Array[Dictionary], status: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in targets:
		for se in t.get("status_effects", []):
			if se.get("type", "") == status:
				result.append(t)
				break
	return result
