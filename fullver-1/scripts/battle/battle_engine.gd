class_name BattleEngine
extends RefCounted
## =============================================================================
## BattleEngine — 战斗引擎（纯逻辑，先算后播）
## =============================================================================
## 移植自 demo-1 的 battle_manager.gd（1864 行，ADR-0001 的既定方案），
## 按本项目设计（docs/00-design.md §9）改造：
##
## 改造点（相对 demo-1）：
##   1. 战斗单位从裸 Dictionary 改为强类型 BattleUnit 类（无 UI 引用）
##   2. 9v9：position 0-8（前排 = position < 3），编队 3×3 槽位经
##      Team.slot_to_battle_position() 显式映射战斗站位
##      （修正 demo-1"棋盘摆位不影响战斗"的缺陷）
##   3. 双方都是真实军团编队（demo-1 是玩家队 vs 自动生成的敌军）
##   4. 装备来自战略层 Unit.equipment（demo-1 是每场随机配装）
##   5. 补齐 demo-1 数据有但引擎缺失的效果 heal_on_kill（击杀回血）
##   6. 修复 demo-1 的重复掩护 bug（_compute_unit_action 与 _resolve_attack
##      各找一次掩护者，可能双扣 PP）——掩护只在 _resolve_attack 结算
##   7. 被动时点映射表统一走 EffectRegistry（与数据校验共用单一来源）
##
## 核心设计不变（demo-1 已验证）：
##   - "先算后播"：回合开始一次性预计算全部行动（伤害即时生效），
##     next_action() 逐个弹出播放；取出时做存活检查跳过失效行动
##   - 信号 + 轮询驱动 UI：battle_started / round_started / battle_ended
##     / battle_action（skipped 即时通知）
##   - 被攻击判定链：掩护 → 防御被动（必闪/格挡）→ 自然闪避 → 自然格挡 → 伤害
##
## 类比 Python：
##   相当于一个纯逻辑的模拟器类：状态机 + 队列 + 公式，无任何渲染。
## =============================================================================

# ==================================================================
#  信号定义（UI 层订阅；skipped 行动经 battle_action 即时通知）
# ==================================================================

signal battle_started()
## result: "victory" / "defeat" / "draw"
signal battle_ended(result: String)
signal round_started(round_num: int)
signal battle_action(action: Dictionary)

# ==================================================================
#  战斗状态
# ==================================================================

## 玩家方单位（BattleUnit 列表）
var player_units: Array[BattleUnit] = []
## 敌方单位
var enemy_units: Array[BattleUnit] = []
## 当前回合数（从 1 开始）
var round_num: int = 0
## 战斗是否进行中
var battle_active: bool = false

## 交战双方军团 ID（战斗结果应用时 GameManager 使用）
var attacker_army_id: String = ""
var defender_army_id: String = ""

# ---------------- 行动队列 ----------------
## 待播放行动队列（先算后播的核心）
var _pending_actions: Array = []
## 本回合行动顺序（按 spd 降序）
var _turn_order: Array[BattleUnit] = []
## 回合是否已处理完
var _round_done: bool = true
## 全体待机平局标记（延迟到队列耗尽时发出）
var _pending_draw: bool = false


# ==================================================================
#  战斗单位工厂
# ==================================================================

## ---------------------------------------------------------------------------
## start_battle() — 从两个军团初始化战斗
## ---------------------------------------------------------------------------
## 把双方编队实例化为 BattleUnit：
##   - 站位：编队槽位 → Team.slot_to_battle_position()（前排槽 6/7/8 → position 0-2）
##   - 属性：角色 base_stats（回退 level_50_stats）+ 已装备装备加成
##   - 等级成长：框架阶段不做等级缩放（demo-1 口径），接口预留注释
## 只做数据准备；begin_combat() 由战斗场景在 UI 就绪后调用。
## ---------------------------------------------------------------------------
func start_battle(attacker_army: Army, defender_army: Army) -> void:
	battle_active = true
	round_num = 0
	_pending_actions.clear()
	_turn_order.clear()
	_pending_draw = false
	attacker_army_id = attacker_army.id
	defender_army_id = defender_army.id

	# 玩家方 = 进攻方（后续若要"守城方视角"可在此换边）
	player_units.clear()
	for slot in range(Team.MAX_UNITS):
		var strategic_unit: Unit = attacker_army.team.get_unit_at(slot)
		if strategic_unit == null:
			continue
		var bu := _create_battle_unit(strategic_unit, false)
		bu.position = Team.slot_to_battle_position(slot)
		bu.source_slot = slot
		player_units.append(bu)

	enemy_units.clear()
	for slot in range(Team.MAX_UNITS):
		var strategic_unit: Unit = defender_army.team.get_unit_at(slot)
		if strategic_unit == null:
			continue
		var bu := _create_battle_unit(strategic_unit, true)
		bu.position = Team.slot_to_battle_position(slot)
		bu.source_slot = slot
		enemy_units.append(bu)


## ---------------------------------------------------------------------------
## _create_battle_unit() — 战略层 Unit → BattleUnit（属性现场推导）
## ---------------------------------------------------------------------------
## 属性来源优先级（demo-1 口径，数据字段名不一致的兼容链）：
##   base_stats（缩写键 hp/atk/def/...）> level_50_stats（全称键）> 硬编码默认值
## 之后叠加装备 stats 加成（战略层已装备的，不是随机配装）。
## ---------------------------------------------------------------------------
func _create_battle_unit(strategic_unit: Unit, is_enemy: bool) -> BattleUnit:
	var char_data: Dictionary = DataManager.get_character(strategic_unit.character_id)
	var class_id := DataManager.get_class_id_by_character(char_data)
	var class_data: Dictionary = DataManager.get_class_data(class_id)

	var bu := BattleUnit.new()
	bu.char_id = strategic_unit.character_id
	bu.name_zh = char_data.get("name_zh", strategic_unit.character_id)
	bu.name_en = char_data.get("name_en", strategic_unit.character_id)
	bu.class_zh = char_data.get("class_zh", "")
	bu.is_enemy = is_enemy

	# 属性提取（字段名不一致兼容链——demo-1 实测坑，见 §17 坑清单）
	var base: Dictionary = char_data.get("base_stats", {})
	var lv50: Dictionary = char_data.get("level_50_stats", {})
	if base == null: base = {}
	if lv50 == null: lv50 = {}
	bu.max_hp = _safe_int(_stat(base, lv50, "hp", "HP", 80), 80)
	bu.hp = bu.max_hp
	bu.atk = _safe_int(_stat(base, lv50, "atk", "Physical Attack", 30), 30)
	bu.def = _safe_int(_stat(base, lv50, "def", "Physical Defense", 20), 20)
	bu.mag = _safe_int(_stat(base, lv50, "mag", "Magic Attack", 30), 30)
	bu.mdf = _safe_int(_stat(base, lv50, "mdf", "Magic Defense", 20), 20)
	bu.spd = _safe_int(_stat(base, lv50, "spd", "Initiative", 30), 30)
	bu.acc = _safe_int(_stat(base, lv50, "acc", "Accuracy", 100), 100)
	bu.eva = _safe_int(_stat(base, lv50, "eva", "Evasion", 20), 20)
	bu.crit = _safe_int(lv50.get("Critical Rate", 10), 10)
	bu.guard = _safe_int(lv50.get("Guard Rate", 10), 10)

	# 等级成长：框架阶段不做缩放（demo-1 口径）。
	# 未来扩展：属性 × (1 + 0.03 × (level-1))，公式数据化后在此接入。

	# AP/PP 来自职业数据（base_ap/base_pp）
	bu.max_ap = int(class_data.get("base_ap", 2))
	bu.ap = bu.max_ap
	bu.max_pp = int(class_data.get("base_pp", 1))
	bu.pp = bu.max_pp

	# 技能：策略栏显式选择的技能优先，否则按角色数据解析（demo-1 _match_skill 逻辑）
	bu.skills = _resolve_unit_skills(char_data, strategic_unit.battle_skill_ids())

	# 装备：已装备的加成折算进属性（demo-1 的 equip_random 逻辑，改为读装备表）
	bu.equipment = strategic_unit.equipment
	_apply_equipment(bu, strategic_unit.equipment)
	return bu


## 取属性：base 优先，回退 lv50（两套字段名）
func _stat(base: Dictionary, lv50: Dictionary, short_key: String, full_key: String, fallback: int):
	if base.has(short_key):
		return base[short_key]
	if lv50.has(full_key):
		return lv50[full_key]
	return fallback


## 装备属性直接叠加（demo-1 口径：折算进基础属性，不追踪来源）
func _apply_equipment(bu: BattleUnit, equipment: Dictionary) -> void:
	for slot_key in equipment:
		var eq_data: Dictionary = DataManager.get_equipment(equipment[slot_key])
		if eq_data.is_empty():
			continue
		var st: Dictionary = eq_data.get("stats", {})
		if st == null:
			continue
		bu.atk += _safe_int(st.get("atk", 0), 0)
		bu.mag += _safe_int(st.get("mag", 0), 0)
		bu.def += _safe_int(st.get("def", 0), 0)
		bu.mdf += _safe_int(st.get("mdf", 0), 0)
		bu.spd += _safe_int(st.get("spd", 0), 0)
		var hp_bonus: int = _safe_int(st.get("hp", 0), 0)
		bu.hp += hp_bonus
		bu.max_hp += hp_bonus


## 解析角色技能：战略层已选技能直接用 id 查表；否则按角色数据内嵌技能
## 按 name_en 匹配 skills.json（demo-1 _match_skill 口径，未命中造默认技能）
func _resolve_unit_skills(char_data: Dictionary, chosen_skills: Array) -> Array:
	var result: Array = []
	if not chosen_skills.is_empty():
		for sk_id in chosen_skills:
			var sk: Dictionary = DataManager.get_skill(sk_id)
			if not sk.is_empty():
				result.append(_normalize_skill(sk, "active"))
		return result
	for embedded in char_data.get("skills", []):
		result.append(_match_skill(embedded))
	return result


func _match_skill(embedded: Dictionary) -> Dictionary:
	var name := String(embedded.get("name", ""))
	for sk_id in DataManager.skills:
		var sk: Dictionary = DataManager.skills[sk_id]
		if String(sk.get("name_en", "")).to_lower() == name.to_lower():
			var full: Dictionary = sk.duplicate()
			full["type"] = embedded.get("type", full.get("type", "active"))
			return _normalize_skill(full, full.get("type", "active"))
	# 未匹配：默认技能（数据缺口显式降级，不静默）
	return {
		"name_zh": embedded.get("name", "???"),
		"name_en": embedded.get("name", ""),
		"type": embedded.get("type", "active"),
		"ap_cost": 1, "pp_cost": 0,
		"power": 80, "hits": 1,
		"target_type": "single", "damage_type": "physical",
		"effects": [],
	}


## 技能统一化：主动技能至少消耗 1 AP（demo-1 口径）
func _normalize_skill(sk: Dictionary, type: String) -> Dictionary:
	sk["type"] = type
	if type == "active" and int(sk.get("ap_cost", 0)) < 1:
		sk["ap_cost"] = 1
	return sk


# ==================================================================
#  战斗流程控制（start_battle → begin_combat → next_action 循环）
# ==================================================================

## 正式开始战斗（战斗场景 UI 就绪后调用）
func begin_combat() -> void:
	# 【时点：战斗开始】先制/先手类被动
	for u in player_units + enemy_units:
		_dispatch_passives("battle_start", u, {})
	battle_started.emit()
	_start_next_round()


## 开始下一回合：状态结算 → 回合开始被动 → 速度排序 → 预计算全部行动
func _start_next_round() -> void:
	if not battle_active:
		return
	round_num += 1
	round_started.emit(round_num)

	# 清残余队列（在状态结算之前）
	_pending_actions.clear()

	# DoT 结算（中毒/燃烧，回合开始触发）
	_tick_statuses()

	# 回合开始被动（低HP回PP、再生）
	for u in player_units + enemy_units:
		if u.is_alive:
			_dispatch_passives("round_start", u, {})

	# 行动顺序：速度降序
	_turn_order.clear()
	var all_units: Array[BattleUnit] = player_units + enemy_units
	all_units.sort_custom(func(a, b): return a.spd > b.spd)
	for u in all_units:
		if u.is_alive:
			_turn_order.append(u)

	# 预计算所有行动（伤害即时生效；响应行动移到行动者自己的行动之后）
	for u in _turn_order:
		if not u.is_alive:
			continue
		var pre_len := _pending_actions.size()
		var action: Dictionary = _compute_unit_action(u)
		if not action.is_empty():
			_pending_actions.append(action)
		var tail: Array = _pending_actions.slice(pre_len)
		if tail.size() > 0:
			_pending_actions.resize(pre_len)
			if not action.is_empty():
				var u_action: Dictionary = tail.pop_back()
				_pending_actions.append(u_action)
			for a in tail:
				_pending_actions.append(a)

	# 全员待机 → 延迟平局
	var all_waited := true
	for a in _pending_actions:
		if a.get("kind", "") != "wait":
			all_waited = false
			break
	if all_waited:
		_pending_draw = true

	_round_done = false


## 取出下一个待播放行动（UI Timer 轮询；空 {} = 本拍无行动）
func next_action() -> Dictionary:
	if not battle_active:
		return {}
	while _pending_actions.size() > 0:
		var action: Dictionary = _pending_actions.pop_front()
		# 死亡行动永远播放
		if action.get("kind", "") == "death":
			return action
		var actor: BattleUnit = _find_unit(action.get("actor_name", ""))
		if actor != null and actor.is_alive:
			return action
		# 行动者已死 → skipped 通知
		battle_action.emit({
			"kind": "skipped",
			"actor_name": action.get("actor_name", ""),
			"actor_side": action.get("actor_side", ""),
			"target_name": "",
			"target_side": "",
			"damage": 0,
			"skill_name": "行动取消(已阵亡)",
			"target_hp": 0, "target_max_hp": 0, "target_alive": false,
			"actor_hp": 0, "actor_max_hp": 0,
			"actor_ap": 0, "actor_max_ap": 0,
		})
	# 队列空 → 回合结束检测
	if not _round_done:
		_round_done = true
		_check_battle_end()
		if not battle_active:
			return {}
		if _pending_draw:
			battle_active = false
			battle_ended.emit("draw")
			return {}
		_start_next_round()
		if _pending_actions.size() > 0:
			return _pending_actions.pop_front()
	return {}


## 按中文名查战斗单位（名字在数据内唯一；找不到返回 null）
func _find_unit(name: String) -> BattleUnit:
	for u in player_units + enemy_units:
		if u.name_zh == name:
			return u
	return null


## 战斗是否已结束（battle_ended 信号发出后为 true）
func is_over() -> bool:
	return not battle_active


# ==================================================================
#  行动计算（战斗 AI 决策 + 目标选取 + 效果应用）
# ==================================================================

## 计算单位本回合的行动（预计算阶段调用，直接应用效果）
func _compute_unit_action(unit: BattleUnit) -> Dictionary:
	# 眩晕/冰冻：跳过行动（状态回合递减）
	for st in unit.statuses:
		var stype: String = String(st.get("type", ""))
		if stype in ["stun", "freeze"]:
			st.turns = int(st.turns) - 1
			if int(st.turns) <= 0:
				unit.statuses.erase(st)
			return {
				"kind": "wait",
				"actor_name": unit.name_zh,
				"actor_side": unit.side_label(),
				"reason": stype,
			}

	# 付得起的主动技能（AP 足够）
	var affordable: Array = []
	for sk in unit.skills:
		if sk.get("type", "") == "active" and int(sk.get("ap_cost", 1)) <= unit.ap:
			affordable.append(sk)
	if affordable.is_empty():
		return {
			"kind": "wait",
			"actor_name": unit.name_zh,
			"actor_side": unit.side_label(),
		}

	var skill: Dictionary = affordable[randi() % affordable.size()]
	var ap_cost: int = max(1, int(skill.get("ap_cost", 1)))
	unit.ap -= ap_cost

	# 行动前被动（攻击强化类）
	_dispatch_passives("before_action", unit, {})

	# 目标池（敌我）
	var foes: Array[BattleUnit] = enemy_units if not unit.is_enemy else player_units
	var allies: Array[BattleUnit] = player_units if not unit.is_enemy else enemy_units
	var alive_foes: Array[BattleUnit] = []
	for t in foes:
		if t.is_alive: alive_foes.append(t)
	var alive_allies: Array[BattleUnit] = []
	for t in allies:
		if t.is_alive: alive_allies.append(t)

	# 按 target_type 选取目标（demo-1 全类型：single/row/column/all/multi/self/ally/ally_row）
	var target_type: String = skill.get("target_type", "single")
	var targets: Array[BattleUnit] = []
	match target_type:
		"single", "":
			if alive_foes.size() > 0:
				targets = [alive_foes[randi() % alive_foes.size()]]
		"row":
			var row_idx := randi() % 2
			for t in alive_foes:
				var is_front: bool = t.position < 3
				if (row_idx == 0 and is_front) or (row_idx == 1 and not is_front):
					targets.append(t)
			if targets.is_empty() and alive_foes.size() > 0:
				targets = [alive_foes[0]]
		"column":
			var col_idx := randi() % 3
			for t in alive_foes:
				if t.position % 3 == col_idx:
					targets.append(t)
			if targets.is_empty() and alive_foes.size() > 0:
				targets = [alive_foes[0]]
		"all_enemies", "aoe":
			targets = alive_foes.duplicate()
		"multi":
			var pool: Array[BattleUnit] = alive_foes.duplicate()
			pool.shuffle()
			targets = pool.slice(0, min(2, pool.size()))
		"self":
			targets = [unit]
		"ally", "ally_single":
			if alive_allies.size() > 0:
				alive_allies.sort_custom(func(a, b): return a.hp < b.hp)
				targets = [alive_allies[0]]
			else:
				targets = [unit]
		"ally_row":
			var ally_row_idx := randi() % 2
			for t in alive_allies:
				var is_front: bool = t.position < 3
				if (ally_row_idx == 0 and is_front) or (ally_row_idx == 1 and not is_front):
					targets.append(t)
			if targets.is_empty():
				targets = [unit]
		_:
			if alive_foes.size() > 0:
				targets = [alive_foes[randi() % alive_foes.size()]]

	if targets.is_empty():
		return {
			"kind": "wait",
			"actor_name": unit.name_zh,
			"actor_side": unit.side_label(),
		}

	# 结算每个目标的伤害/治疗
	var damage_type: String = skill.get("damage_type", "physical")
	var power: float = float(skill.get("power", 80))
	var hits: int = max(1, int(skill.get("hits", 1)))
	var total_dmg := 0
	var total_heal := 0
	var results: Array = []

	for t in targets:
		var t_dmg := 0
		var t_heal := 0
		if damage_type == "heal":
			t_heal = _calc_heal(unit, power) * hits
			_apply_heal(t, t_heal)
			total_heal += t_heal
			results.append({
				"name": t.name_zh, "side": t.side_label(),
				"damage": 0, "heal": t_heal,
				"hp": t.hp, "max_hp": t.max_hp, "alive": t.is_alive,
			})
		elif damage_type in ["buff", "shield", "debuff", "utility", "special", "summon"]:
			# 非伤害技能：记录展示条目（效果明细由被动/状态系统处理）
			results.append({
				"name": t.name_zh, "side": t.side_label(),
				"damage": 0, "heal": 0,
				"hp": t.hp, "max_hp": t.max_hp, "alive": t.is_alive,
			})
		else:
			# 被攻击判定链（掩护/必闪/格挡/自然闪避在 _resolve_attack 内结算）
			# ⭐ 修复 demo-1 重复掩护：掩护只在 _resolve_attack 内结算一次
			var t_guarded := false
			var covered_by := ""
			for _h in range(hits):
				var res: Dictionary = _resolve_attack(unit, t, power, damage_type, skill.get("name_zh", "技能"))
				t_dmg += res.damage
				if res.guarded:
					t_guarded = true
				if res.covered:
					covered_by = res.target.name_zh
				if res.dodged:
					continue
				total_dmg += res.damage
				if res.damage > 0:
					# 【时点：命中】吸血类被动
					_dispatch_passives("on_hit", unit, {"target": res.target, "damage": res.damage})
					# 技能附加状态（中毒/燃烧/眩晕/冰冻，30%）
					_try_apply_skill_statuses(skill, res.target)
					# 【时点：受击后】反击类被动
					_dispatch_passives("after_hit", res.target, {"attacker": unit, "damage": res.damage})
				if res.killed:
					# 【时点：击杀】击杀奖励/追击/击杀回血（本项目补齐）
					_dispatch_passives("on_kill", unit, {"target": res.target})
			var result_entry := {
				"name": t.name_zh, "side": t.side_label(),
				"damage": t_dmg, "heal": 0,
				"hp": res_target_hp(t, t_dmg), "max_hp": t.max_hp, "alive": t.is_alive,
				"guarded": t_guarded,
			}
			if covered_by != "":
				result_entry["covered_by"] = covered_by
			results.append(result_entry)

	# 行动结束，清临时 buff（demo-1 口径：临时 buff 只持续一次行动）
	unit.buffs.clear()

	if results.is_empty():
		return {"kind": "wait", "actor_name": unit.name_zh, "actor_side": unit.side_label()}

	var primary: Dictionary = results[0]
	return {
		"kind": "attack",
		"actor_name": unit.name_zh,
		"actor_side": unit.side_label(),
		"skill_name": skill.get("name_zh", skill.get("name_en", "技能")),
		"skill_name_en": skill.get("name_en", ""),
		"ap_cost": ap_cost,
		"pp_cost": 0,
		"passive_name": "",
		"damage_type": damage_type,
		"hits": hits,
		"target_name": primary.name,
		"target_side": primary.side,
		"damage": total_dmg,
		"heal": total_heal,
		"target_hp": primary.hp,
		"target_max_hp": primary.max_hp,
		"target_alive": primary.alive,
		"targets": results,
		"actor_hp": unit.hp,
		"actor_max_hp": unit.max_hp,
		"actor_ap": unit.ap,
		"actor_max_ap": unit.max_ap,
	}


## 结果条目里的 hp 取当前值（伤害已在结算中应用）
func res_target_hp(t: BattleUnit, _dmg: int) -> int:
	return t.hp


# ==================================================================
#  伤害公式与结算链
# ==================================================================

## 伤害公式（demo-1 口径）：
##   base = max(1, power/100 × 攻 - 防×0.4) × (0.85~1.15) ；暴击 ×1.5
## 物理/魔法/混合按 damage_type 选攻防属性；buff 修正 atk/def/crit/power
func _calc_damage(attacker: BattleUnit, defender: BattleUnit, power: float,
		damage_type: String = "physical") -> int:
	var atk_val: float
	var def_val: float
	match damage_type:
		"magical":
			atk_val = attacker.mag
			def_val = defender.mdf
		"mixed":
			atk_val = (attacker.atk + attacker.mag) / 2.0
			def_val = (defender.def + defender.mdf) / 2.0
		_:
			atk_val = attacker.atk
			def_val = defender.def
	atk_val *= float(attacker.buffs.get("atk", 1.0))
	def_val *= float(defender.buffs.get("def", 1.0))
	var base: float = max(1.0, power / 100.0 * atk_val - def_val * 0.4)
	base *= 0.85 + randf() * 0.3
	var crit_chance: float = float(attacker.crit) * float(attacker.buffs.get("crit", 1.0))
	if randi() % 100 < int(crit_chance):
		base *= 1.5
	return max(1, int(base))


## 治疗量 = power% × 施法者 mag，浮动 85%~115%
func _calc_heal(caster: BattleUnit, power: float) -> int:
	var base: float = power / 100.0 * caster.mag
	base *= 0.85 + randf() * 0.3
	return max(1, int(base))


func _apply_heal(target: BattleUnit, amount: int) -> void:
	target.hp = min(target.max_hp, target.hp + amount)


## 应用伤害：扣血 + 统计 + 死亡检测（survive_fatal 一次挺过 → death 行动）
func _apply_damage(attacker: BattleUnit, target: BattleUnit, damage: int) -> void:
	target.hp = max(0, target.hp - damage)
	target.damage_taken += damage
	attacker.damage_dealt += damage
	if target.hp <= 0:
		if not target.survived_fatal and _has_passive_effect(target, "survive_fatal"):
			target.hp = 1
			target.survived_fatal = true
			_queue_heal_action(target, target, 0, "survive")
			return
		target.is_alive = false
		_queue_death_action(target)


## ---------------------------------------------------------------------------
## _resolve_attack() — 单次攻击的完整结算（被攻击判定链）
## ---------------------------------------------------------------------------
## 顺序（demo-1 口径）：
##   1. 友方掩护（cover_ally，目标转移到掩护者，掩护者耗 PP）
##   2. 防御被动（evade_once 必闪 / guard_medium 中格挡，耗 PP）
##   3. 自然闪避（acc - eva，clamp 50~95；truestrike 必中）
##   4. 自然格挡（guard 属性，伤害减半）
##   5. 伤害计算 + 应用
## ---------------------------------------------------------------------------
func _resolve_attack(attacker: BattleUnit, target: BattleUnit, power: float,
		damage_type: String, skill_name: String) -> Dictionary:
	var result := {
		"target": target, "covered": false, "dodged": false,
		"guarded": false, "damage": 0, "killed": false,
	}
	# --- 1. 掩护（只此一处结算，修复 demo-1 双扣 PP 的 bug）---
	var coverer: BattleUnit = _find_coverer(target)
	if coverer != null:
		coverer.pp -= 1
		target = coverer
		result.target = target
		result.covered = true
		_pending_actions.append({
			"kind": "cover",
			"actor_name": coverer.name_zh,
			"actor_side": coverer.side_label(),
			"target_name": attacker.name_zh,
			"target_side": attacker.side_label(),
		})
	# --- 2. 防御被动 ---
	for sk in target.skills:
		if sk.get("type", "") != "passive":
			continue
		var pp_cost: int = max(1, int(sk.get("pp_cost", 1)))
		if target.pp < pp_cost:
			continue
		for ef in sk.get("effects", []):
			var et: String = String(ef.get("effect_type", ""))
			if et == "evade_once":
				target.pp -= pp_cost
				result.dodged = true
				_pending_actions.append({
					"kind": "dodge",
					"actor_name": target.name_zh,
					"actor_side": target.side_label(),
					"target_name": attacker.name_zh,
					"target_side": attacker.side_label(),
				})
				return result
			elif et == "guard_medium":
				target.pp -= pp_cost
				result.guarded = true
				break
		if result.guarded:
			break
	# --- 3. 自然闪避 ---
	var hit_chance: int = clamp(int(attacker.acc) - int(target.eva), 50, 95)
	if int(attacker.buffs.get("truestrike", 0)) == 1:
		hit_chance = 100
	if randi() % 100 >= hit_chance:
		result.dodged = true
		_pending_actions.append({
			"kind": "dodge",
			"actor_name": target.name_zh,
			"actor_side": target.side_label(),
			"target_name": attacker.name_zh,
			"target_side": attacker.side_label(),
		})
		return result
	# --- 4. 自然格挡 ---
	if randi() % 100 < int(target.guard):
		result.guarded = true
	# --- 5. 伤害 ---
	var eff_power: float = power + float(attacker.buffs.get("power", 0.0))
	var dmg: int = _calc_damage(attacker, target, eff_power, damage_type)
	if result.guarded:
		dmg = max(1, int(dmg * 0.5))
	_apply_damage(attacker, target, dmg)
	result.damage = dmg
	result.killed = not target.is_alive
	return result


# ==================================================================
#  时点分派系统（映射表统一来自 EffectRegistry）
# ==================================================================

## 在指定时点触发 subject 的全部匹配被动（消耗 PP，一个技能每时点触发一个效果）
func _dispatch_passives(trigger: String, subject: BattleUnit, context: Dictionary) -> void:
	if not subject.is_alive:
		return
	for sk in subject.skills:
		if sk.get("type", "") != "passive":
			continue
		var pp_cost: int = int(sk.get("pp_cost", 1))
		if pp_cost > 0 and subject.pp < pp_cost:
			continue
		for ef in sk.get("effects", []):
			var et: String = String(ef.get("effect_type", ""))
			if EffectRegistry.trigger_for(et) == trigger:
				if pp_cost > 0:
					subject.pp -= pp_cost
				_execute_passive_effect(subject, ef, context)
				break  # 一个技能本时点只触发一个效果


## 被动效果实现（demo-1 全集 + 本项目补齐的 heal_on_kill）
func _execute_passive_effect(subject: BattleUnit, ef: Dictionary, context: Dictionary) -> void:
	var et: String = String(ef.get("effect_type", ""))
	var value = ef.get("value", 0)
	match et:
		"initiative_up":
			subject.spd += _int_value(value, 20)
		"first_strike":
			subject.spd += 999  # 先手：临时速度大幅提升确保先动
		"pp_on_low_hp":
			if subject.hp <= subject.max_hp / 2:
				subject.pp = min(subject.max_pp, subject.pp + _int_value(value, 1))
				_queue_heal_action(subject, subject, 0, "pp")
		"regen":
			var regen_amt: int = max(1, int(subject.max_hp * 0.10))
			_apply_heal(subject, regen_amt)
			_queue_heal_action(subject, subject, regen_amt, "regen")
		"attack_up":
			subject.buffs["atk"] = 1.0 + _pct_value(value, 0.3)
		"power_boost":
			if subject.hp == subject.max_hp:
				subject.buffs["power"] = float(_int_value(value, 50))
		"truestrike", "truestrike_once":
			subject.buffs["truestrike"] = 1
		"accuracy_up":
			subject.buffs["acc"] = 1.0 + _pct_value(value, 0.2)
		"crit_up":
			subject.buffs["crit"] = 1.0 + _pct_value(value, 0.5)
		"heal_on_hit":
			var dmg_hit: int = int(context.get("damage", 0))
			var heal_amt: int = max(1, int(dmg_hit * _pct_value(value, 0.25)))
			_apply_heal(subject, heal_amt)
			_queue_heal_action(subject, subject, heal_amt, "lifesteal")
		"lifesteal":
			var dmg_ls: int = int(context.get("damage", 0))
			var ls_amt: int = max(1, int(dmg_ls * _pct_value(value, 0.5)))
			_apply_heal(subject, ls_amt)
			_queue_heal_action(subject, subject, ls_amt, "lifesteal")
		"pp_on_hit":
			subject.pp = min(subject.max_pp, subject.pp + _int_value(value, 1))
		"ap_on_kill":
			subject.ap = min(subject.max_ap, subject.ap + _int_value(value, 1))
			_queue_heal_action(subject, subject, 0, "ap")
		"pp_on_kill":
			subject.pp = min(subject.max_pp, subject.pp + _int_value(value, 1))
			_queue_heal_action(subject, subject, 0, "pp")
		"attack_up_on_kill":
			subject.buffs["atk"] = 1.0 + _pct_value(value, 0.5)
		"heal_on_kill":
			# ⭐ 本项目补齐：demo-1 数据有（skill_001 等）但引擎没实现的效果。
			# 击杀后回复 最大HP × value%（value 形如 "25%"）
			var hok_amt: int = max(1, int(subject.max_hp * _pct_value(value, 0.25)))
			_apply_heal(subject, hok_amt)
			_queue_heal_action(subject, subject, hok_amt, "heal_on_kill")
		"follow_up":
			# 追击：对随机敌人追加一次攻击
			var foes: Array[BattleUnit] = enemy_units if not subject.is_enemy else player_units
			var alive_f: Array[BattleUnit] = []
			for t in foes:
				if t.is_alive: alive_f.append(t)
			if alive_f.size() > 0:
				var ft: BattleUnit = alive_f[randi() % alive_f.size()]
				var fdmg: int = _calc_damage(subject, ft, 100.0)
				_apply_damage(subject, ft, fdmg)
				_queue_attack_action(subject, ft, fdmg, "追击")
		"counter":
			var atk: BattleUnit = context.get("attacker") as BattleUnit
			if atk != null and atk.is_alive:
				var cdmg: int = _calc_damage(subject, atk, 100.0)
				_apply_damage(subject, atk, cdmg)
				_queue_attack_action(subject, atk, cdmg, "反击")
		"ally_defense_up":
			var defender: BattleUnit = context.get("defender") as BattleUnit
			if defender != null:
				defender.buffs["def"] = 1.0 + _pct_value(value, 0.2)
		"end_of_battle_heal":
			var eoh: int = max(1, int(subject.max_hp * _pct_value(value, 0.25)))
			_apply_heal(subject, eoh)
		_:
			# 未实现效果：显式记录（数据校验在启动时已告警，这里不再静默）
			pass


## 单位是否拥有指定效果类型的被动
func _has_passive_effect(unit: BattleUnit, effect_type: String) -> bool:
	for sk in unit.skills:
		if sk.get("type", "") != "passive":
			continue
		for ef in sk.get("effects", []):
			if String(ef.get("effect_type", "")) == effect_type:
				return true
	return false


## 在目标的友方中寻找可发动 cover_ally 的掩护者
func _find_coverer(target: BattleUnit) -> BattleUnit:
	var allies: Array[BattleUnit] = player_units if not target.is_enemy else enemy_units
	for ally in allies:
		if not ally.is_alive or ally == target:
			continue
		for sk in ally.skills:
			if sk.get("type", "") != "passive":
				continue
			var pp_cost: int = max(1, int(sk.get("pp_cost", 1)))
			if ally.pp < pp_cost:
				continue
			for ef in sk.get("effects", []):
				if String(ef.get("effect_type", "")) == "cover_ally":
					return ally
	return null


# ==================================================================
#  状态效果系统（demo-1 口径）
# ==================================================================

## 附加状态（已存在同类型则刷新回合数）
func _apply_status(target: BattleUnit, status_type: String, turns: int = 2) -> void:
	for st in target.statuses:
		if st.get("type") == status_type:
			st.turns = max(int(st.turns), turns)
			return
	target.statuses.append({"type": status_type, "turns": turns})
	_pending_actions.append({
		"kind": "status",
		"actor_name": target.name_zh,
		"actor_side": target.side_label(),
		"status_type": status_type,
	})


## 技能命中后尝试附加状态（30% 概率）
func _try_apply_skill_statuses(skill: Dictionary, target: BattleUnit) -> void:
	for ef in skill.get("effects", []):
		var et: String = String(ef.get("effect_type", ""))
		if et in ["poison", "burn", "stun", "freeze"] and randi() % 100 < 30:
			_apply_status(target, et)


## 回合开始的状态结算（DoT 伤害 + 回合递减）
func _tick_statuses() -> void:
	for u in player_units + enemy_units:
		if not u.is_alive:
			continue
		for st in u.statuses.duplicate():
			var stype: String = String(st.get("type", ""))
			if stype == "poison":
				_take_dot_damage(u, max(1, int(u.max_hp * 0.10)), "中毒")
			elif stype == "burn":
				_take_dot_damage(u, max(1, int(u.max_hp * 0.08)), "燃烧")
			st.turns = int(st.turns) - 1
			if int(st.turns) <= 0:
				u.statuses.erase(st)


## DoT 伤害（不计攻击者统计）
func _take_dot_damage(target: BattleUnit, amount: int, source_name: String) -> void:
	if not target.is_alive:
		return
	target.hp = max(0, target.hp - amount)
	target.damage_taken += amount
	_pending_actions.append({
		"kind": "dot",
		"actor_name": target.name_zh,
		"actor_side": target.side_label(),
		"dot_type": source_name,
		"damage": amount,
		"target_hp": target.hp,
		"target_max_hp": target.max_hp,
		"target_alive": target.is_alive,
	})
	if target.hp <= 0:
		target.is_alive = false
		_queue_death_action(target)


# ==================================================================
#  战斗结束判定与统计
# ==================================================================

func _check_battle_end() -> void:
	var player_alive := false
	for u in player_units:
		if u.is_alive:
			player_alive = true
			break
	var enemy_alive := false
	for u in enemy_units:
		if u.is_alive:
			enemy_alive = true
			break
	if not player_alive:
		battle_active = false
		for u in player_units:
			if u.is_alive:
				_dispatch_passives("battle_end", u, {})
		battle_ended.emit("defeat")
	elif not enemy_alive:
		battle_active = false
		for u in player_units:
			if u.is_alive:
				_dispatch_passives("battle_end", u, {})
		battle_ended.emit("victory")


## 战后统计（结果界面展示用；口径同 demo-1）
func get_stats_summary() -> Dictionary:
	var player_stats := {"total_damage_dealt": 0, "total_damage_taken": 0, "units": []}
	var enemy_stats := {"total_damage_dealt": 0, "total_damage_taken": 0, "units": []}
	for u in player_units:
		player_stats.total_damage_dealt += u.damage_dealt
		player_stats.total_damage_taken += u.damage_taken
		player_stats.units.append(_unit_stats(u))
	for u in enemy_units:
		enemy_stats.total_damage_dealt += u.damage_dealt
		enemy_stats.total_damage_taken += u.damage_taken
		enemy_stats.units.append(_unit_stats(u))
	return {"player": player_stats, "enemy": enemy_stats, "rounds": round_num}


func _unit_stats(u: BattleUnit) -> Dictionary:
	return {
		"name": u.name_zh,
		"class": u.class_zh,
		"hp": u.hp, "max_hp": u.max_hp,
		"damage_dealt": u.damage_dealt,
		"damage_taken": u.damage_taken,
		"alive": u.is_alive,
	}


# ==================================================================
#  队列辅助
# ==================================================================

func _queue_attack_action(attacker: BattleUnit, target: BattleUnit, dmg: int, label: String) -> void:
	_pending_actions.append({
		"kind": "attack",
		"actor_name": attacker.name_zh,
		"actor_side": attacker.side_label(),
		"skill_name": label,
		"skill_name_en": "",
		"ap_cost": 0, "pp_cost": 0, "passive_name": "",
		"damage_type": "physical", "hits": 1,
		"target_name": target.name_zh,
		"target_side": target.side_label(),
		"damage": dmg, "heal": 0,
		"target_hp": target.hp, "target_max_hp": target.max_hp, "target_alive": target.is_alive,
		"targets": [{
			"name": target.name_zh, "side": target.side_label(),
			"damage": dmg, "heal": 0,
			"hp": target.hp, "max_hp": target.max_hp, "alive": target.is_alive,
		}],
		"actor_hp": attacker.hp, "actor_max_hp": attacker.max_hp,
		"actor_ap": attacker.ap, "actor_max_ap": attacker.max_ap,
	})


func _queue_heal_action(healer: BattleUnit, target: BattleUnit, amount: int, source: String) -> void:
	if amount > 0 or source in ["ap", "pp", "survive"]:
		_pending_actions.append({
			"kind": "heal",
			"actor_name": healer.name_zh,
			"actor_side": healer.side_label(),
			"target_name": target.name_zh,
			"target_side": target.side_label(),
			"heal": amount,
			"heal_source": source,
			"target_hp": target.hp,
			"target_max_hp": target.max_hp,
			"actor_hp": healer.hp,
			"actor_max_hp": healer.max_hp,
			"actor_ap": healer.ap,
			"actor_max_ap": healer.max_ap,
			"actor_pp": healer.pp,
			"actor_max_pp": healer.max_pp,
		})


func _queue_death_action(target: BattleUnit) -> void:
	_pending_actions.append({
		"kind": "death",
		"actor_name": target.name_zh,
		"actor_side": target.side_label(),
		"target_name": "",
		"target_side": "",
		"damage": 0,
		"skill_name": "",
		"target_hp": 0,
		"target_max_hp": target.max_hp,
		"target_alive": false,
		"actor_hp": target.hp,
		"actor_max_hp": target.max_hp,
		"actor_ap": 0,
		"actor_max_ap": 0,
	})


# ==================================================================
#  数值解析工具（demo-1 口径）
# ==================================================================

## 安全转 int（JSON 值可能是 "120" 字符串）
func _safe_int(val, fallback: int = 10) -> int:
	if val is int or val is float:
		return int(val)
	if val is String:
		var digits := ""
		for c in val:
			if c in "0123456789":
				digits += c
		if digits != "":
			return int(digits)
	return fallback


## 解析 "30%" / "50%HP" 为 0.30 浮点
func _pct_value(val, default: float) -> float:
	if val is String:
		var digits := ""
		for ch in val:
			if ch in "0123456789.":
				digits += ch
		if digits != "":
			return float(digits) / 100.0
	if val is int or val is float:
		return float(val) / 100.0
	return default


## 解析值为整数（兼容 "AP-1" / 50 / "2"）
func _int_value(val, default: int) -> int:
	if val is int or val is float:
		return int(val)
	if val is String:
		var digits := ""
		for ch in val:
			if ch in "0123456789":
				digits += ch
		if digits != "":
			return int(digits)
	return default
