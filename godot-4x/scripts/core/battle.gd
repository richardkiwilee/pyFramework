## Tick 驱动的自动战斗引擎（对应 pydemo/game/battle.py）。
## 默认 200 Tick；行动条达 100 出手；同 Tick 多单位：防守方优先、前排优先。
## 未分胜负：防守方留守、进攻方退回。统一命中/格挡/闪避/暴击/意志管道。
class_name Battle
extends RefCounted

const BATTLE_TICKS := 200
const ATB_THRESHOLD := 100.0
const ATB_RATE := 30.0
const BLOCK_EVA_ENABLED := true
const BLOCK_DMG_FACTOR := 0.5

class BattleSide:
	var army: Armies.Army
	var is_attacker: bool
	var home_node: String = ""
	var units: Array = []

	func _init(army_: Armies.Army, is_attacker_: bool, home_node_: String = "",
			units_: Array = []) -> void:
		army = army_
		is_attacker = is_attacker_
		home_node = home_node_
		units = units_

class BattleResult:
	var attacker_wiped: bool = false
	var defender_wiped: bool = false
	var log: Array = []
	var occupier_side: String = ""   # "attacker" | "defender" | ""
	var casualties: Array = []

class StrikeResult:
	var hit: bool = true
	var blocked: bool = false
	var evaded: bool = false
	var crit: bool = false
	var dmg: int = 0
	var kind: String = ""

class BattleContext:
	var attacker_side: BattleSide
	var defender_side: BattleSide
	var strategies: Dictionary = {}
	var eff_map: Dictionary = {}
	var skill_defs: Dictionary = {}
	var result: BattleResult
	var log_detail: bool = false
	var rng: RandomNumberGenerator
	var block_eva_enabled: bool = BLOCK_EVA_ENABLED
	var trigger_fired_this_attack: Dictionary = {}
	var survived_this_battle: Dictionary = {}
	var player_faction_id: String = ""
	var resolve_strike: Callable = Callable()   # 由 run_battle 挂接，避免循环依赖

	func _init(attacker_side_: BattleSide, defender_side_: BattleSide,
			strategies_: Dictionary, eff_map_: Dictionary, skill_defs_: Dictionary,
			result_: BattleResult, log_detail_: bool, rng_: RandomNumberGenerator,
			block_eva_enabled_: bool, survived_this_battle_: Dictionary,
			player_faction_id_: String) -> void:
		attacker_side = attacker_side_
		defender_side = defender_side_
		strategies = strategies_
		eff_map = eff_map_
		skill_defs = skill_defs_
		result = result_
		log_detail = log_detail_
		rng = rng_
		block_eva_enabled = block_eva_enabled_
		survived_this_battle = survived_this_battle_
		player_faction_id = player_faction_id_

## 计算单位有效属性（基础 + 修正管道）。
static func effective_attrs(unit: Units.Unit, mods: Array) -> Dictionary:
	var eff: Dictionary = {}
	for attr in unit.base:
		var bounds: Array = Units.ATTR_BOUNDS.get(attr, [0.0, 99999.0])
		eff[attr] = Modifier.compute_attribute(float(unit.base[attr]), mods, attr,
			float(bounds[0]), float(bounds[1]))
	var bounds2: Array = Units.ATTR_BOUNDS.get("mana_regen", [0.0, 999.0])
	eff["mana_regen"] = Modifier.compute_attribute(0.0, mods, "mana_regen",
		float(bounds2[0]), float(bounds2[1]))
	return eff

# ---------------------------------------------------------------------------
# 命中/格挡/闪避/暴击/意志统一管道
# ---------------------------------------------------------------------------

static func _unit_side(ctx: BattleContext, u) -> BattleSide:
	if ctx.attacker_side.units.has(u):
		return ctx.attacker_side
	return ctx.defender_side

static func _unit_side_faction(ctx: BattleContext, u) -> String:
	return _unit_side(ctx, u).army.owner

static func resolve_strike(ctx: BattleContext, attacker, target,
		kind: String, flat_dmg: int = -1) -> StrikeResult:
	var ueff: Dictionary = ctx.eff_map.get(attacker.id, {})
	var teff: Dictionary = ctx.eff_map.get(target.id, {})
	var res := StrikeResult.new()
	res.kind = kind
	# 闪避/格挡掷骰
	if ctx.block_eva_enabled:
		if ctx.rng.randf() < float(teff.get("eva", 0)) / 100.0:
			res.evaded = true
			res.hit = false
			res.dmg = 0
			dispatch_trigger(ctx, Triggers.TriggerPoint.ON_EVA, attacker, target)
			return res
		if ctx.rng.randf() < float(teff.get("block", 0)) / 100.0:
			res.blocked = true
	# 基础伤害
	var dmg: int
	if flat_dmg < 0:
		var base: float
		if kind == "magic":
			base = float(ueff.get("m_atk", 0)) - float(teff.get("m_def", 0))
		else:
			base = float(ueff.get("p_atk", 0)) - float(teff.get("p_def", 0))
		dmg = maxi(1, floori(base))
	else:
		dmg = maxi(1, flat_dmg)
	if res.blocked:
		dmg = floori(dmg * BLOCK_DMG_FACTOR)
	# 暴击
	if ctx.rng.randf() < float(ueff.get("crit", 0)) / 100.0:
		res.crit = true
		dmg = floori(dmg * 1.5)
	res.dmg = maxi(0, dmg) if res.evaded else maxi(1, dmg)
	# 意志生还（仅真人玩家；HP>1 将致死；每场每单位 1 次）
	if Units.WILL_SURVIVAL_ENABLED and res.dmg > 0:
		var new_hp := float(target.cur_hp) - res.dmg
		if (new_hp <= 0 and target.cur_hp > 1
				and not ctx.survived_this_battle.has(target.id)
				and _unit_side_faction(ctx, target) == ctx.player_faction_id):
			var will := float(ctx.eff_map.get(target.id, {}).get("will", 0))
			if will > 0 and ctx.rng.randf() < will / 100.0:
				res.dmg = maxi(0, int(target.cur_hp) - 1)
				ctx.survived_this_battle[target.id] = true
				ctx.result.log.append("意志生还:%s 保留 1 HP" % target.name)
	target.cur_hp -= res.dmg
	# 受击消耗（冻结破冰）
	Triggers.consume_on_self_hit(target)
	# 格挡时点
	if res.blocked:
		dispatch_trigger(ctx, Triggers.TriggerPoint.ON_BLOCK, attacker, target)
	# after_phys / after_magic
	var tp := Triggers.TriggerPoint.AFTER_PHYS if kind == "physical" else Triggers.TriggerPoint.AFTER_MAGIC
	dispatch_trigger(ctx, tp, attacker, target)
	return res

# ---------------------------------------------------------------------------
# 主动技能可释放判定
# ---------------------------------------------------------------------------

static func _can_fire_active(ctx: BattleContext, u, row) -> Variant:
	var sd: Dictionary = ctx.skill_defs.get(row.skill_id, {})
	if sd.is_empty() or Effects.skill_kind(sd) != Effects.SKILL_ACTIVE:
		return null
	var effs := Effects.build_skill_effects(sd)
	var total_ap := 0
	var total_mana := 0
	for e in effs:
		if e.trigger == "active":
			total_ap += e.ap_cost
			total_mana += e.mana_cost
	if u.cur_ap < total_ap or u.cur_mana < total_mana:
		return null
	# 无目标型必要条件 gate 释放
	for cond in row.necessary:
		var t: String = cond.get("type", "")
		if t in ["self_hp_le", "ally_avg_hp_le", "row_count_ge"]:
			if not Triggers.eval_necessary(cond, ctx, u):
				return null
	# 返回首个 active 效果
	for e in effs:
		if e.trigger == "active" and e.effect_type in ["ap_damage", "apply_status"]:
			return e
	return null

# ---------------------------------------------------------------------------
# 被动时点调度（每时点最多 1 单位响应，速度降序）
# ---------------------------------------------------------------------------

static func _passive_candidates(ctx: BattleContext, tp: int, actor, target) -> Array:
	var all_units: Array = []
	all_units.append_array(ctx.attacker_side.units)
	all_units.append_array(ctx.defender_side.units)
	var alive: Array = []
	for u in all_units:
		if u.alive:
			alive.append(u)
	var cand: Array = []
	if tp in [Triggers.TriggerPoint.ALLY_ATTACKED_START, Triggers.TriggerPoint.ALLY_ATTACKED_END]:
		if target == null:
			return []
		var side := _unit_side(ctx, target)
		for u in side.units:
			if u.alive and u.id != target.id:
				cand.append(u)
	elif tp in [Triggers.TriggerPoint.SELF_ATTACK_START, Triggers.TriggerPoint.SELF_ATTACK_END]:
		if actor == null:
			return []
		cand = [actor] if actor.alive else []
	else:
		cand = alive
	# 只保留有匹配 trigger_point 被动行的单位
	var cands: Array = []
	for u in cand:
		var strat: Variant = ctx.strategies.get(u.id)
		if strat == null:
			continue
		var has_row := false
		for prow in strat.passive_rows:
			if prow.trigger_point == Triggers.TRIGGER_POINTS[tp]:
				has_row = true
				break
		if has_row:
			cands.append(u)
	# 按当前速度降序
	cands.sort_custom(func(a, b):
		var sa := float(ctx.eff_map.get(a.id, {}).get("speed", 1))
		var sb := float(ctx.eff_map.get(b.id, {}).get("speed", 1))
		return sa > sb)
	return cands

static func dispatch_trigger(ctx: BattleContext, tp: int,
		actor = null, target = null) -> void:
	# 防同一时点重复触发（本轮攻击内）
	if ctx.trigger_fired_this_attack.has(tp):
		return
	ctx.trigger_fired_this_attack[tp] = true

	var cands := _passive_candidates(ctx, tp, actor, target)
	for u in cands:
		if not u.alive:
			continue
		var strat: Variant = ctx.strategies.get(u.id)
		if strat == null:
			continue
		for prow in strat.passive_rows:
			if prow.trigger_point != Triggers.TRIGGER_POINTS[tp]:
				continue
			var sd: Dictionary = ctx.skill_defs.get(prow.skill_id, {})
			if sd.is_empty() or Effects.skill_kind(sd) != Effects.SKILL_PASSIVE:
				continue
			var effs := Effects.build_skill_effects(sd)
			# 必要条件 gate
			var ok := true
			for cond in prow.necessary:
				if not Triggers.eval_necessary(cond, ctx, u, target):
					ok = false
					break
			if not ok:
				continue
			# PP 成本（取 passive 效果总 pp_cost）
			var total_pp := 0
			for e in effs:
				if e.trigger == "passive":
					total_pp += e.pp_cost
			if u.cur_pp < total_pp:
				continue
			# 判定满足即扣 PP（响应前）
			u.cur_pp -= total_pp
			# 执行被动效果
			var eff: Variant = null
			for e in effs:
				if e.trigger == "passive" and e.effect_type in ["ap_damage", "apply_status"]:
					eff = e
					break
			if eff != null:
				var resp_target = target if (target != null and target.alive) else actor
				if resp_target != null and resp_target.alive:
					var r: Dictionary = Effects.execute_passive_effect(eff, ctx, u, resp_target)
					if ctx.log_detail:
						var line := "  [被动 %s] %s 响应(%s)" % [
							Triggers.TRIGGER_POINTS[tp], u.name, prow.skill_id]
						if int(r.get("dmg", 0)) > 0:
							line += " 伤害%d" % r["dmg"]
						var sa: Array = r.get("status_applied", [])
						if not sa.is_empty():
							line += " 施加%s" % ",".join(sa)
						ctx.result.log.append(line)
					# 死亡检查（被动追击可能致死）
					if resp_target.cur_hp <= 0 and resp_target.alive:
						resp_target.alive = false
						resp_target.cur_hp = 0
						if not ctx.result.casualties.has(resp_target.id):
							ctx.result.casualties.append(resp_target.id)
			# 结束该时点（按时点各自计）
			return

# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------

static func run_battle(attacker: BattleSide, defender: BattleSide,
		strategies: Dictionary, extra_mods: Array, log_detail: bool = false,
		rng: RandomNumberGenerator = null, skill_defs: Dictionary = {},
		player_faction_id: String = "") -> BattleResult:
	var result := BattleResult.new()
	var all_units: Array = []
	all_units.append_array(attacker.units)
	all_units.append_array(defender.units)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# 有效属性
	var eff_map: Dictionary = {}
	for u in all_units:
		var umods: Array = []
		for m in extra_mods:
			if m.target == u.id:
				umods.append(m)
		eff_map[u.id] = effective_attrs(u, umods)

	# 初始化战斗内状态
	for u in all_units:
		u.cur_ap = float(eff_map[u.id].get("ap", 0))
		u.cur_pp = float(eff_map[u.id].get("pp", 0))
		var mana_cap := float(eff_map[u.id].get("mana", 0))
		u.cur_mana = mana_cap if u.cur_mana <= 0 else minf(u.cur_mana, mana_cap)
		u.atb = 0.0
		u.alive = true
		var eff_hp := float(eff_map[u.id].get("hp", u.base.get("hp", 1)))
		u.cur_hp = eff_hp if u.cur_hp <= 0 else minf(u.cur_hp, eff_hp)
		Triggers.clear_statuses(u)

	var ctx := BattleContext.new(attacker, defender, strategies, eff_map,
		skill_defs, result, log_detail, rng, BLOCK_EVA_ENABLED, {}, player_faction_id)
	ctx.resolve_strike = resolve_strike   # 挂接到 ctx，供 effects 调用

	var side_slots := func(side: BattleSide) -> Array:
		var slots: Array = []
		for i in range(side.army.grid.size()):
			var uid = side.army.grid[i]
			if uid == null:
				continue
			for x in side.units:
				if x.id == uid and x.alive:
					slots.append([i, x])
					break
		return slots

	var side_alive := func(side: BattleSide) -> Array:
		var out: Array = []
		for u in side.units:
			if u.alive:
				out.append(u)
		return out

	# battle_start 一次性
	dispatch_trigger(ctx, Triggers.TriggerPoint.BATTLE_START)

	var tick := 0
	while tick < BATTLE_TICKS:
		# 累加行动条
		for u in all_units:
			if u.alive:
				u.atb += float(eff_map[u.id].get("speed", 1)) / ATB_RATE
		var ready: Array = []
		for u in all_units:
			if u.alive and u.atb >= ATB_THRESHOLD:
				ready.append(u)
		if ready.is_empty():
			tick += 1
			continue
		ready.sort_custom(func(a, b):
			var in_a := attacker.units.has(a)
			var side_a := 1 if in_a else 0
			var slot_a := attacker.army.slot_of(a.id) if in_a else defender.army.slot_of(a.id)
			var row_a := Armies.row_of(slot_a) if slot_a >= 0 else "back"
			var row_rank_a: int = {"front": 0, "mid": 1, "back": 2}.get(row_a, 3)
			var in_b := attacker.units.has(b)
			var side_b := 1 if in_b else 0
			var slot_b := attacker.army.slot_of(b.id) if in_b else defender.army.slot_of(b.id)
			var row_b := Armies.row_of(slot_b) if slot_b >= 0 else "back"
			var row_rank_b: int = {"front": 0, "mid": 1, "back": 2}.get(row_b, 3)
			if side_a != side_b:
				return side_a < side_b
			if row_rank_a != row_rank_b:
				return row_rank_a < row_rank_b
			return a.atb > b.atb)

		for u in ready:
			if not u.alive:
				continue
			u.atb -= ATB_THRESHOLD
			# 冻结：跳过出手 + 消耗
			if Triggers.is_frozen(u):
				if log_detail:
					result.log.append("[T%d] %s 冰封,无法行动" % [tick, u.name])
				Triggers.consume_on_self_attack(u)
				continue
			var in_att := attacker.units.has(u)
			var my_side: BattleSide = attacker if in_att else defender
			var foe_side: BattleSide = defender if in_att else attacker
			var foes: Array = side_slots.call(foe_side)
			var strat: Variant = strategies.get(u.id)
			if strat == null:
				continue
			var my_slot := my_side.army.slot_of(u.id)
			ctx.trigger_fired_this_attack.clear()

			# 主动区按行序检测
			var fired := false
			for row in strat.active_rows:
				var eff: Variant = _can_fire_active(ctx, u, row)
				if eff == null:
					continue
				var target := Formation.choose_target_with_slots(
					maxi(my_slot, 0), u.tags, foes, strat, ctx.rng,
					row.necessary, row.priority, eff_map, ctx, u)
				if target.is_empty():
					continue
				var t_unit = target[1]
				dispatch_trigger(ctx, Triggers.TriggerPoint.SELF_ATTACK_START, u, t_unit)
				dispatch_trigger(ctx, Triggers.TriggerPoint.ALLY_ATTACKED_START, u, t_unit)
				var sd: Dictionary = ctx.skill_defs.get(row.skill_id, {})
				var sum_dmg := 0
				var sum_kind := ""
				var sum_status: Array = []
				for e in Effects.build_skill_effects(sd):
					if e.trigger != "active":
						continue
					if e.effect_type in ["ap_damage", "apply_status"]:
						var r: Dictionary = Effects.execute_active_effect(e, ctx, u, t_unit)
						sum_dmg += int(r.get("dmg", 0))
						if r.get("kind", "") != "":
							sum_kind = r["kind"]
						sum_status.append_array(r.get("status_applied", []))
				# 扣 AP/Mana（总成本）
				var total_ap := 0
				var total_mana := 0
				for e in Effects.build_skill_effects(sd):
					if e.trigger == "active":
						total_ap += e.ap_cost
						total_mana += e.mana_cost
				u.cur_ap -= total_ap
				u.cur_mana -= total_mana
				if log_detail:
					var line := "[T%d] %s 释放 %s→%s" % [tick, u.name, row.skill_id, t_unit.name]
					if sum_dmg > 0:
						line += " 伤害%d(%s)" % [sum_dmg, sum_kind]
					if not sum_status.is_empty():
						line += " 施加%s" % ",".join(sum_status)
					line += " 余%d" % maxi(0, int(t_unit.cur_hp))
					result.log.append(line)
				if t_unit.cur_hp <= 0 and t_unit.alive:
					t_unit.alive = false
					t_unit.cur_hp = 0
					if not result.casualties.has(t_unit.id):
						result.casualties.append(t_unit.id)
					if log_detail:
						result.log.append("  %s 阵亡" % t_unit.name)
				dispatch_trigger(ctx, Triggers.TriggerPoint.ALLY_ATTACKED_END, u, t_unit)
				dispatch_trigger(ctx, Triggers.TriggerPoint.SELF_ATTACK_END, u, t_unit)
				Triggers.consume_on_self_attack(u)
				fired = true
				break   # 首个可释放主动即出手

			if not fired:
				# 普通攻击
				var target := Formation.choose_target_with_slots(
					maxi(my_slot, 0), u.tags, foes, strat, ctx.rng,
					[], [], eff_map, ctx, u)
				if target.is_empty():
					if log_detail:
						result.log.append("[T%d] %s 无可打目标" % [tick, u.name])
					Triggers.consume_on_self_attack(u)
					continue
				var t_unit = target[1]
				var ueff: Dictionary = eff_map[u.id]
				var is_magic: bool = u.tags.has("magic") and float(ueff.get("m_atk", 0)) > float(ueff.get("p_atk", 0))
				var kind := "magic" if is_magic else "physical"
				dispatch_trigger(ctx, Triggers.TriggerPoint.SELF_ATTACK_START, u, t_unit)
				dispatch_trigger(ctx, Triggers.TriggerPoint.ALLY_ATTACKED_START, u, t_unit)
				var sres := resolve_strike(ctx, u, t_unit, kind)
				var kind_cn := "魔攻" if is_magic else "物攻"
				if log_detail:
					if sres.evaded:
						result.log.append("[T%d] %s %s→%s 闪避 余%d" % [
							tick, u.name, kind_cn, t_unit.name, maxi(0, int(t_unit.cur_hp))])
					else:
						var line := "[T%d] %s %s→%s 伤害%d" % [
							tick, u.name, kind_cn, t_unit.name, sres.dmg]
						if sres.blocked:
							line += "(格挡)"
						if sres.crit:
							line += "(暴击)"
						line += " 余%d" % maxi(0, int(t_unit.cur_hp))
						result.log.append(line)
				if t_unit.cur_hp <= 0 and t_unit.alive:
					t_unit.alive = false
					t_unit.cur_hp = 0
					if not result.casualties.has(t_unit.id):
						result.casualties.append(t_unit.id)
					if log_detail:
						result.log.append("  %s 阵亡(Lv%d)" % [t_unit.name, t_unit.level])
				dispatch_trigger(ctx, Triggers.TriggerPoint.ALLY_ATTACKED_END, u, t_unit)
				dispatch_trigger(ctx, Triggers.TriggerPoint.SELF_ATTACK_END, u, t_unit)
				Triggers.consume_on_self_attack(u)

			tick += 1
			if side_alive.call(attacker).is_empty():
				result.attacker_wiped = true
				break
			if side_alive.call(defender).is_empty():
				result.defender_wiped = true
				break

	# battle_end + 状态清场
	dispatch_trigger(ctx, Triggers.TriggerPoint.BATTLE_END)
	for u in all_units:
		Triggers.clear_statuses(u)

	# 结局
	if result.defender_wiped and not result.attacker_wiped:
		result.occupier_side = "attacker"
	elif result.attacker_wiped and not result.defender_wiped:
		result.occupier_side = "defender"
	return result
