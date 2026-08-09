# battle_manager.gd
# Autoload — 战斗管理器
# 管理战斗回合流程、状态效果、战斗日志
extends Node

# 信号
signal battle_started()
signal turn_started(unit_data: Dictionary)
signal turn_ended(unit_data: Dictionary)
signal skill_used(caster: Dictionary, skill: Dictionary, target: Dictionary, result: Dictionary)
signal passive_triggered(unit: Dictionary, skill: Dictionary, target: Dictionary, result: Dictionary)
signal damage_dealt(target: Dictionary, damage: int)
signal unit_died(unit: Dictionary)
signal battle_ended(winner: String, stats: Dictionary)
signal log_message(msg: String, color: Color)

# 战斗状态
var team_blue: Array[Dictionary] = []
var team_red: Array[Dictionary] = []
var battle_log: Array[String] = []
var current_round: int = 0
var current_unit_index: int = 0
var turn_order: Array[Dictionary] = []
var battle_active: bool = false
var paused: bool = false
var battle_speed: float = 1.0
var total_damage_blue: int = 0
var total_damage_red: int = 0
var chain_count: int = 0  # 技能连锁计数（上限2）
var max_chain: int = 2

# 内部引用
var _battle_scene: Node = null
var _timer: Timer = null
var _evaluator: ConditionEvaluator = null
var _calculator: DamageCalculator = null


func _ready() -> void:
	_evaluator = ConditionEvaluator.new()
	_calculator = DamageCalculator.new()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


func start_battle(scene: Node) -> void:
	_battle_scene = scene
	team_blue = BattleData.team_blue
	team_red = BattleData.team_red
	battle_log.clear()
	current_round = 0
	current_unit_index = 0
	total_damage_blue = 0
	total_damage_red = 0
	chain_count = 0
	battle_active = true
	paused = false
	battle_speed = 1.0

	# 初始化单位位置 (前排 0-2, 后排 0-2)
	_init_positions(team_blue)
	_init_positions(team_red)

	battle_started.emit()
	_emit_log("════ 战斗开始 ════", Color.WHITE)
	_emit_log("蓝方 %d 人  VS  红方 %d 人" % [team_blue.size(), team_red.size()], Color("#aaaaaa"))

	# 触发开场被动
	_trigger_start_battle_passives()

	# 开始第一回合
	await get_tree().create_timer(1.0 / battle_speed).timeout
	if battle_active:
		_start_new_round()


func _init_positions(team: Array[Dictionary]) -> void:
	# 前3人放前排，其余放后排
	for i in range(team.size()):
		if i < 3:
			team[i]["row"] = 0
			team[i]["col"] = i
		else:
			team[i]["row"] = 1
			team[i]["col"] = i - 3


func _start_new_round() -> void:
	if not battle_active:
		return

	current_round += 1
	current_unit_index = 0
	_emit_log("── 第 %d 回合 ──" % current_round, Color("#888888"))

	# 回合开始效果处理
	_process_round_start_effects()

	# 收集所有存活单位并按速度排序
	turn_order = _get_alive_units_sorted()
	current_unit_index = 0

	if turn_order.is_empty():
		_end_battle()
		return

	_process_next_unit()


func _get_alive_units_sorted() -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for u in team_blue:
		if u.get("is_alive", false):
			units.append(u)
	for u in team_red:
		if u.get("is_alive", false):
			units.append(u)

	# 按速度降序，速度相同按ID排序（确定性）
	units.sort_custom(func(a, b):
		var spd_a = a.get("speed", 0) + a.get("buffs", {}).get("speed", 0)
		var spd_b = b.get("speed", 0) + b.get("buffs", {}).get("speed", 0)
		if spd_a != spd_b:
			return spd_a > spd_b
		return a.get("id", "") > b.get("id", "")
	)
	return units


func _process_next_unit() -> void:
	if not battle_active:
		return

	if paused:
		_timer.start(0.1)
		return

	# 跳过已死亡或AP为0的单位
	while current_unit_index < turn_order.size():
		var unit = turn_order[current_unit_index]
		if unit.get("is_alive", false) and unit.get("ap_current", 0) > 0:
			break
		current_unit_index += 1

	if current_unit_index >= turn_order.size():
		# 所有单位已行动，进入回合结束
		_process_round_end()
		return

	var unit = turn_order[current_unit_index]

	# 检查是否被控制（冰冻/眩晕）
	if _has_status(unit, "freeze") or _has_status(unit, "stun"):
		_emit_log("❄ %s 被控制，无法行动！" % unit.get("name", "???"), Color("#66aaff"))
		turn_started.emit(unit)
		await get_tree().create_timer(0.5 / battle_speed).timeout
		turn_ended.emit(unit)
		current_unit_index += 1
		_process_next_unit()
		return

	turn_started.emit(unit)
	_emit_log("▶ %s 开始行动 [AP:%d/%d]" % [unit.get("name", "???"), unit.get("ap_current", 0), unit.get("ap_max", 3)], Color.WHITE)
	await get_tree().create_timer(0.3 / battle_speed).timeout

	# 执行单位回合
	await _execute_unit_turn(unit)

	turn_ended.emit(unit)
	current_unit_index += 1

	await get_tree().create_timer(0.8 / battle_speed).timeout

	# 检查战斗是否结束
	if _check_battle_end():
		return

	_process_next_unit()


func _execute_unit_turn(unit: Dictionary) -> void:
	var tactics: Array = unit.get("tactics", [])
	if tactics.is_empty():
		_emit_log("  %s 没有配置策略，待命" % unit.get("name", "???"), Color("#888888"))
		return

	# 收集潜在目标
	var all_enemies = _get_enemies_of(unit)
	var all_allies = _get_allies_of(unit)

	# 遍历策略（优先级1→N）
	for tactic in tactics:
		if not battle_active:
			return
		if unit.get("ap_current", 0) <= 0:
			break

		var skill_id = tactic.get("skill_id", "")
		if skill_id == "":
			continue

		var skill = SkillDatabase.get_skill(skill_id)
		if skill.is_empty():
			continue
		if skill.type != "active":
			continue
		if skill.get("cost", 1) > unit.get("ap_current", 0):
			continue

		var c1 = tactic.get("condition_1", {})
		var c2 = tactic.get("condition_2", {})

		# 根据技能目标类型确定潜在目标池
		var target_pool: Array[Dictionary]
		if skill.target_type in ["single_ally", "row_ally", "all_ally"]:
			target_pool = all_allies.duplicate()
		else:
			target_pool = all_enemies.duplicate()

		# 过滤存活目标
		var alive_targets: Array[Dictionary] = []
		for t in target_pool:
			if t.get("is_alive", false) or skill.damage_type == "heal":
				alive_targets.append(t)

		if alive_targets.is_empty():
			continue

		# 评估条件
		var valid_targets = _evaluator.evaluate_dual(c1, c2, unit, alive_targets, all_enemies + all_allies)

		# 检查"仅"条件
		if (not c1.is_empty() and c1.get("mode", "") == "only") or (not c2.is_empty() and c2.get("mode", "") == "only"):
			# 有"仅"条件，不满足则跳过
			var only_met = true
			if not c1.is_empty() and c1.get("mode", "") == "only":
				only_met = _evaluator.is_only_condition_met(c1, unit, alive_targets, all_enemies + all_allies)
			if only_met and not c2.is_empty() and c2.get("mode", "") == "only":
				only_met = _evaluator.is_only_condition_met(c2, unit, alive_targets, all_enemies + all_allies)
			if not only_met:
				continue

		if valid_targets.is_empty():
			continue

		# 选择第一个（最佳）目标
		var target = valid_targets[0]
		if target == null:
			continue

		# 扣除AP并释放技能
		unit["ap_current"] -= skill.get("cost", 1)
		await _execute_skill(unit, skill, target)

		# 技能释放后检查结束
		if _check_battle_end():
			return

	# AP耗尽
	if unit.get("ap_current", 0) <= 0:
		_emit_log("  %s AP耗尽" % unit.get("name", "???"), Color("#888888"))


func _execute_skill(caster: Dictionary, skill: Dictionary, target: Dictionary) -> void:
	var caster_name = caster.get("name", "???")
	var skill_name = skill.get("name", "???")
	var target_name = target.get("name", "???")

	# 治疗技能特殊处理
	if skill.damage_type == "heal":
		var result = _calculator.calculate(caster, target, skill)
		var heal_amount = result.damage
		target["hp_current"] = min(target.get("hp", 100), target.get("hp_current", 0) + heal_amount)
		_emit_log("💚 %s 使用「%s」→ %s 恢复 %d HP" % [caster_name, skill_name, target_name, heal_amount], Color("#44ff44"))
		skill_used.emit(caster, skill, target, result)
		return

	_emit_log("⚔ %s 使用「%s」→ %s" % [caster_name, skill_name, target_name], Color("#ffcc00"))
	await get_tree().create_timer(0.3 / battle_speed).timeout

	# 计算伤害
	var result = _calculator.calculate(caster, target, skill)

	if not result.hit:
		_emit_log("  MISS! %s" % result.message, Color("#888888"))
		skill_used.emit(caster, skill, target, result)
		return

	# 闪避被动检查 (在伤害前触发)
	if _try_trigger_passive(target, "evade", caster, skill, result):
		_emit_log("  ✨ %s 触发「闪避」！躲开了攻击！" % target_name, Color("#88ccff"))
		skill_used.emit(caster, skill, target, result)
		return

	# 格挡被动检查 (在伤害前触发)
	var guard_triggered = false
	if skill.damage_type == "physical" and not result.guard:
		guard_triggered = _try_trigger_passive(target, "guard", caster, skill, result)

	# 掩护被动检查 (友方掩护)
	var cover_unit = _find_cover_ally(target)
	if cover_unit != null:
		var cover_result = _calculator.calculate(caster, cover_unit, skill)
		if cover_result.hit:
			cover_result.damage = int(cover_result.damage * 0.5)  # 掩护减免50%
			_apply_damage(cover_unit, cover_result.damage, caster)
			_emit_log("  🛡 %s 掩护 %s！代替承受 %d 伤害" % [cover_unit.get("name", "???"), target_name, cover_result.damage], Color("#ffdd44"))
			passive_triggered.emit(cover_unit, SkillDatabase.get_skill("heavy_cover"), target, cover_result)
			skill_used.emit(caster, skill, target, result)
			return

	# 应用伤害
	_apply_damage(target, result.damage, caster)
	_emit_log("  %s" % result.message, Color("#ff6644") if not result.crit else Color("#ffd700"))

	# 吸血
	if result.drain_heal > 0:
		caster["hp_current"] = min(caster.get("hp", 100), caster.get("hp_current", 0) + result.drain_heal)
		_emit_log("  🩸 %s 吸取 %d HP" % [caster_name, result.drain_heal], Color("#ff4444"))

	skill_used.emit(caster, skill, target, result)
	damage_dealt.emit(target, result.damage)

	# 应用技能效果（中毒/灼烧/冰冻等）
	_apply_skill_effects(target, skill)

	# 触发被攻击单位的反击被动
	if target.get("is_alive", false):
		_try_trigger_passive(target, "counter", caster, skill, result)

	# 触发施法者友方的追击被动
	for ally in _get_allies_of(caster):
		if ally.get("is_alive", false):
			_try_trigger_passive(ally, "follow_slash", target, skill, result)

	# 检查死亡
	if not target.get("is_alive", false):
		_emit_log("💀 %s 被击败！" % target_name, Color("#ff2222"))
		unit_died.emit(target)


func _apply_damage(target: Dictionary, damage: int, source: Dictionary) -> void:
	target["hp_current"] = max(0, target.get("hp_current", 0) - damage)
	if target.team == "blue":
		total_damage_red += damage
	else:
		total_damage_blue += damage
	if target["hp_current"] <= 0:
		target["hp_current"] = 0
		target["is_alive"] = false


func _try_trigger_passive(unit: Dictionary, passive_type: String, trigger_unit: Dictionary, skill: Dictionary, result: Dictionary) -> bool:
	if not unit.get("is_alive", false):
		return false
	if unit.get("pp_current", 0) <= 0:
		return false
	if chain_count >= max_chain:
		return false

	# 查找匹配的被动技能
	var passive_skill_id = ""
	for ps_id in unit.get("passive_skills", []):
		var ps = SkillDatabase.get_skill(ps_id)
		if ps.is_empty():
			continue
		var trigger = ps.get("trigger", "")
		match passive_type:
			"evade":
				if ps_id == "evade" and ps.trigger == "before_take_damage":
					passive_skill_id = ps_id
					break
			"guard":
				if ps_id == "guard" and ps.trigger == "before_take_damage":
					passive_skill_id = ps_id
					break
			"counter":
				if ps_id == "counter" and ps.trigger == "after_take_damage":
					passive_skill_id = ps_id
					break
			"follow_slash":
				if ps_id == "follow_slash" and ps.trigger == "ally_attacked":
					passive_skill_id = ps_id
					break

	if passive_skill_id == "":
		return false

	var ps = SkillDatabase.get_skill(passive_skill_id)
	if ps.is_empty():
		return false

	unit["pp_current"] -= ps.get("cost", 1)
	chain_count += 1

	if passive_type == "evade":
		return true  # 特殊处理：闪避不造成伤害

	if passive_type == "guard":
		result.guard = true
		result.damage = int(result.damage * 0.5)
		_emit_log("  🛡 %s 触发「格挡」！伤害减半" % unit.get("name", "???"), Color("#ffdd44"))
	elif passive_type == "counter":
		var counter_result = _calculator.calculate(unit, trigger_unit, ps)
		if counter_result.hit:
			_apply_damage(trigger_unit, counter_result.damage, unit)
			_emit_log("  ↩ %s 触发「反击」→ %s 造成 %d 伤害" % [unit.get("name", "???"), trigger_unit.get("name", "???"), counter_result.damage], Color("#ff8866"))
			passive_triggered.emit(unit, ps, trigger_unit, counter_result)
	elif passive_type == "follow_slash":
		var follow_result = _calculator.calculate(unit, trigger_unit, ps)
		if follow_result.hit:
			_apply_damage(trigger_unit, follow_result.damage, unit)
			_emit_log("  ➤ %s 触发「追击」→ %s 造成 %d 伤害" % [unit.get("name", "???"), trigger_unit.get("name", "???"), follow_result.damage], Color("#ff8866"))
			passive_triggered.emit(unit, ps, trigger_unit, follow_result)

	return true


func _find_cover_ally(target: Dictionary) -> Variant:
	for ally in _get_allies_of(target):
		if not ally.get("is_alive", false):
			continue
		if ally.get("pp_current", 0) <= 0:
			continue
		if "heavy_cover" in ally.get("passive_skills", []):
			# 只有前排可以掩护后排（同一列）
			if ally.get("row", 0) == 0 and target.get("row", 0) == 1:
				if ally.get("col", -1) == target.get("col", -1):
					ally["pp_current"] -= 1
					return ally
	return null


func _apply_skill_effects(target: Dictionary, skill: Dictionary) -> void:
	for effect in skill.get("effects", []):
		var effect_type = effect.get("type", "")
		var duration = effect.get("duration", 1)

		# 检查免疫
		var immunities: Array = []
		var equipment = target.get("equipment", {})
		for slot_key in equipment:
			var eq_id = equipment[slot_key]
			if eq_id == null or eq_id == "":
				continue
			var eq = EquipmentDatabase.get_equipment(eq_id)
			if not eq.is_empty():
				immunities.append_array(eq.get("immunities", []))

		if effect_type in immunities:
			_emit_log("  ⛔ %s 免疫%s效果" % [target.get("name", "???"), _status_name(effect_type)], Color("#aaaaaa"))
			continue

		# 添加或刷新状态
		_remove_status(target, effect_type)  # 先移除旧的
		target["status_effects"].append({
			"type": effect_type,
			"duration": duration,
			"source": skill.get("id", "")
		})
		_emit_log("  🔔 %s 受到%s效果(%d回合)" % [target.get("name", "???"), _status_name(effect_type), duration], _status_color(effect_type))


func _process_round_start_effects() -> void:
	# 回合开始时处理灼烧伤害
	var all_units = _get_alive_units_sorted()
	for unit in all_units:
		for se in unit.get("status_effects", []):
			if se.type == "burn":
				var burn_dmg = int(unit.get("hp", 100) * 0.1)
				unit["hp_current"] = max(0, unit.get("hp_current", 0) - burn_dmg)
				_emit_log("🔥 %s 受到灼烧伤害 %d" % [unit.get("name", "???"), burn_dmg], Color("#ff6622"))
				if unit["hp_current"] <= 0:
					unit["is_alive"] = false
					_emit_log("💀 %s 被灼烧击败！" % unit.get("name", "???"), Color("#ff2222"))
					unit_died.emit(unit)
			elif se.type == "poison":
				var poison_dmg = int(unit.get("hp", 100) * 0.3)
				unit["hp_current"] = max(0, unit.get("hp_current", 0) - poison_dmg)
				_emit_log("☠ %s 受到中毒伤害 %d" % [unit.get("name", "???"), poison_dmg], Color("#8844cc"))
				if unit["hp_current"] <= 0:
					unit["is_alive"] = false
					_emit_log("💀 %s 被毒击败！" % unit.get("name", "???"), Color("#ff2222"))
					unit_died.emit(unit)


func _process_round_end() -> void:
	_emit_log("── 第 %d 回合结束 ──" % current_round, Color("#888888"))

	# 减少状态持续时间
	var all_units = _get_alive_units_sorted()
	for unit in all_units:
		var new_effects: Array = []
		for se in unit.get("status_effects", []):
			se["duration"] -= 1
			if se["duration"] > 0:
				new_effects.append(se)
			else:
				_emit_log("🔔 %s 的%s效果解除" % [unit.get("name", "???"), _status_name(se.type)], Color("#aaaaaa"))
		unit["status_effects"] = new_effects

	# 重置技能连锁计数
	chain_count = 0

	if _check_battle_end():
		return

	await get_tree().create_timer(0.5 / battle_speed).timeout
	_start_new_round()


func _trigger_start_battle_passives() -> void:
	# 触发所有"战斗开始时"的被动
	# 当前系统中此类被动技能暂不实现，预留接口
	pass


func _check_battle_end() -> bool:
	if not battle_active:
		return true

	var blue_alive = 0
	var red_alive = 0
	for u in team_blue:
		if u.get("is_alive", false):
			blue_alive += 1
	for u in team_red:
		if u.get("is_alive", false):
			red_alive += 1

	if blue_alive == 0 or red_alive == 0:
		_end_battle()
		return true

	# 检查是否所有单位AP耗尽
	var all_ap_depleted = true
	for u in _get_alive_units_sorted():
		if u.get("ap_current", 0) > 0:
			all_ap_depleted = false
			break

	if all_ap_depleted:
		_end_battle()
		return true

	return false


func _end_battle() -> void:
	battle_active = false
	paused = false

	var blue_alive = 0
	var red_alive = 0
	var blue_hp_lost = 0
	var red_hp_lost = 0

	for u in team_blue:
		if u.get("is_alive", false):
			blue_alive += 1
		blue_hp_lost += max(0, u.get("hp", 100) - u.get("hp_current", 0))
	for u in team_red:
		if u.get("is_alive", false):
			red_alive += 1
		red_hp_lost += max(0, u.get("hp", 100) - u.get("hp_current", 0))

	_emit_log("════ 战斗结束 ════", Color.WHITE)

	var winner: String
	if blue_alive == 0 and red_alive == 0:
		winner = "draw"
		_emit_log("⚡ 双方全灭！平局！", Color("#ffd700"))
	elif blue_alive == 0:
		winner = "red"
		_emit_log("⚡ 红方胜利！", Color("#ff4444"))
	elif red_alive == 0:
		winner = "blue"
		_emit_log("⚡ 蓝方胜利！", Color("#4488ff"))
	else:
		# AP耗尽 → HP损失更多的一方失败
		_emit_log("双方AP耗尽，按HP损失判定...", Color("#aaaaaa"))
		if blue_hp_lost > red_hp_lost:
			winner = "red"
			_emit_log("⚡ 蓝方HP损失更多(%d > %d)，红方胜利！" % [blue_hp_lost, red_hp_lost], Color("#ff4444"))
		elif red_hp_lost > blue_hp_lost:
			winner = "blue"
			_emit_log("⚡ 红方HP损失更多(%d > %d)，蓝方胜利！" % [red_hp_lost, blue_hp_lost], Color("#4488ff"))
		else:
			winner = "draw"
			_emit_log("⚡ HP损失相同，平局！", Color("#ffd700"))

	var stats = {
		"blue_alive": blue_alive,
		"red_alive": red_alive,
		"blue_total": team_blue.size(),
		"red_total": team_red.size(),
		"total_damage_blue": total_damage_blue,
		"total_damage_red": total_damage_red,
		"rounds": current_round,
		"blue_hp_lost": blue_hp_lost,
		"red_hp_lost": red_hp_lost,
	}

	BattleData.battle_result = {"winner": winner, "stats": stats}
	battle_ended.emit(winner, stats)


func _get_enemies_of(unit: Dictionary) -> Array[Dictionary]:
	var enemy_team = team_blue if unit.team == "red" else team_red
	var result: Array[Dictionary] = []
	for u in enemy_team:
		if u.get("is_alive", false):
			result.append(u)
	return result


func _get_allies_of(unit: Dictionary) -> Array[Dictionary]:
	var ally_team = team_blue if unit.team == "blue" else team_red
	var result: Array[Dictionary] = []
	for u in ally_team:
		if u != unit and u.get("is_alive", false):
			result.append(u)
	return result


func _has_status(unit: Dictionary, status_type: String) -> bool:
	for se in unit.get("status_effects", []):
		if se.get("type", "") == status_type:
			return true
	return false


func _remove_status(unit: Dictionary, status_type: String) -> void:
	var new_effects: Array = []
	for se in unit.get("status_effects", []):
		if se.get("type", "") != status_type:
			new_effects.append(se)
	unit["status_effects"] = new_effects


func _status_name(status_type: String) -> String:
	match status_type:
		"poison": return "中毒"
		"burn": return "灼烧"
		"freeze": return "冰冻"
		"stun": return "眩晕"
		"darkness": return "黑暗"
		_: return status_type


func _status_color(status_type: String) -> Color:
	match status_type:
		"poison": return Color("#8844cc")
		"burn": return Color("#ff6622")
		"freeze": return Color("#66aaff")
		"stun": return Color("#ffcc00")
		_: return Color.WHITE


func _emit_log(msg: String, color: Color) -> void:
	battle_log.append(msg)
	log_message.emit(msg, color)


func toggle_pause() -> void:
	paused = not paused
	if not paused:
		_process_next_unit()


func set_speed(multiplier: float) -> void:
	battle_speed = multiplier


func _on_timer_timeout() -> void:
	if paused and battle_active:
		_timer.start(0.1)


func get_unit_icon_texture(unit: Dictionary) -> ImageTexture:
	return PlaceholderAssets.get_unit_portrait(unit.get("class_name", "knight"), unit.get("team", "blue"))
