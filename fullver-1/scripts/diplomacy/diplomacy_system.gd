class_name DiplomacySystem
extends RefCounted
## =============================================================================
## DiplomacySystem — 外交系统（纯逻辑，模型层校验）
## =============================================================================
## 规则口径迁移自 diplomacy 参考项目（docs/00-design.md §11），并修正其缺陷：
##   1. 参数全数据化（data/diplomacy.json）——参考项目规则数字散落三处
##   2. 双边 Relation 对象（A 对 B 与 B 对 A 独立）——参考项目只有单侧视角
##   3. 条约是带持续回合的对象——参考项目只有 bool
##   4. 模型层校验——参考项目"UI 校验、模型裸奔"（模型方法可被误调用）
##   5. 玩家也是 Faction 对象——参考项目玩家是裸字典
##
## 所有行动返回 {"ok": bool, ...} 结构，事件通过 state.add_event 记录。
## 类比 Python：service 层——校验 → 变更 → 记录 → 返回结果。
## =============================================================================

## 游戏状态（构造时注入）
var state: GameState

## 外交参数（data/diplomacy.json）
var config: Dictionary


func _init(gs: GameState) -> void:
	state = gs
	config = DataManager.get_diplomacy_config()


# ==================================================================
#  关系管理
# ==================================================================

## 获取（不存在则创建）A 对 B 的关系记录
func ensure_relation(faction_a: String, faction_b: String) -> Relation:
	var rel := state.get_relation(faction_a, faction_b)
	if rel == null:
		rel = Relation.new()
		rel.faction_a = faction_a
		rel.faction_b = faction_b
		state.relations.append(rel)
	return rel


## 态度等级（委托 Relation.attitude_level，阈值从配置传入）
func attitude_level(rel: Relation) -> String:
	return rel.attitude_level(config.get("thresholds", {}))


## 好感度变更（统一收口 clamp 到配置范围）
func _change_attitude(rel: Relation, delta: float) -> void:
	var bounds: Dictionary = config.get("relationship", {})
	rel.attitude = clampf(rel.attitude + delta,
		float(bounds.get("min", -100.0)), float(bounds.get("max", 100.0)))


## 势力军力（军团 × 编队人数总和）——朝贡的军力比判定用
func military_score(faction: Faction) -> int:
	var total := 0
	for army in state.armies_of(faction.id):
		total += army.team.unit_count()
	return total


# ==================================================================
#  外交行动（全部模型层校验）
# ==================================================================

## 宣战。校验：不能重复宣战；和平/同盟条约未过期时拒绝（背约需先等条约到期）。
func declare_war(a: Faction, b: Faction) -> Dictionary:
	var rel := ensure_relation(a.id, b.id)
	if rel.at_war:
		return {"ok": false, "reason": "already_at_war"}
	if rel.has_treaty("peace") or rel.has_treaty("alliance"):
		return {"ok": false, "reason": "treaty_active"}
	rel.at_war = true
	# 好感大幅下降并压到 war_floor（口径同参考项目：minf(-60, 压到-40)）
	var rules: Dictionary = config.get("relationship", {})
	rel.attitude = clampf(minf(rel.attitude - float(rules.get("war_penalty", 60.0)),
		float(rules.get("war_floor", -40.0))),
		float(rules.get("min", -100.0)), float(rules.get("max", 100.0)))
	# 战争废止一切合作条约
	rel.treaties.clear()
	# 对方视角：b 对 a 也进入战争（战争是对称状态，好感变化不对称）
	var rel_back := ensure_relation(b.id, a.id)
	rel_back.at_war = true
	state.add_event("war_declared", {"a": a.name_zh, "b": b.name_zh})
	return {"ok": true}


## 求和。需处于交战；缔结持续 peace_rounds 的和平条约。
func make_peace(a: Faction, b: Faction) -> Dictionary:
	var rel := ensure_relation(a.id, b.id)
	if not rel.at_war:
		return {"ok": false, "reason": "not_at_war"}
	rel.at_war = false
	var rel_back := ensure_relation(b.id, a.id)
	rel_back.at_war = false
	var rounds: int = int(config.get("treaties", {}).get("peace_rounds", 10))
	_add_treaty(rel, "peace", rounds)
	_add_treaty(rel_back, "peace", rounds)
	state.add_event("peace_signed", {"a": a.name_zh, "b": b.name_zh})
	return {"ok": true}


## 缔结友谊：好感 ≥ friendly 阈值，一次性 +friendship_bonus（同向双方）
func declare_friendship(a: Faction, b: Faction) -> Dictionary:
	var rel := ensure_relation(a.id, b.id)
	if rel.at_war:
		return {"ok": false, "reason": "at_war"}
	if rel.has_treaty("alliance"):
		return {"ok": false, "reason": "already_allied"}
	var friendly: float = float(config.get("thresholds", {}).get("friendly", 40.0))
	if rel.attitude < friendly:
		return {"ok": false, "reason": "below_threshold"}
	_change_attitude(rel, float(config.get("friendship_bonus", 10.0)))
	_change_attitude(ensure_relation(b.id, a.id), float(config.get("friendship_bonus", 10.0)))
	return {"ok": true}


## 缔结同盟：好感 ≥ alliance 阈值；缔结持续 alliance_rounds 的同盟条约
func declare_alliance(a: Faction, b: Faction) -> Dictionary:
	var rel := ensure_relation(a.id, b.id)
	if rel.at_war:
		return {"ok": false, "reason": "at_war"}
	if rel.has_treaty("alliance"):
		return {"ok": false, "reason": "already_allied"}
	var threshold: float = float(config.get("thresholds", {}).get("alliance", 60.0))
	if rel.attitude < threshold:
		return {"ok": false, "reason": "below_threshold"}
	_change_attitude(rel, float(config.get("alliance_bonus", 10.0)))
	_change_attitude(ensure_relation(b.id, a.id), float(config.get("alliance_bonus", 10.0)))
	var rounds: int = int(config.get("treaties", {}).get("alliance_rounds", 20))
	_add_treaty(rel, "alliance", rounds)
	_add_treaty(ensure_relation(b.id, a.id), "alliance", rounds)
	state.add_event("alliance", {"a": a.name_zh, "b": b.name_zh})
	return {"ok": true}


## ---------------------------------------------------------------------------
## 贸易（评分口径同参考项目，参数数据化）
## ---------------------------------------------------------------------------
## 评分规则（config.trade）：
##   我方给出 give：对方持有低于预期 → 补齐部分每份 +deficit_fill_gain（超出部分不计）
##   对方给出 ask：对方持有 ≤ 预期 → 每份 -give_below_expectation_penalty
##                 高于预期 → 每份 -give_above_expectation_penalty
##   总分 ≥ accept_threshold(0) → 接受；分数 > 0 → 加好感
## ---------------------------------------------------------------------------
func propose_trade(a: Faction, b: Faction, give: Dictionary, ask: Dictionary) -> Dictionary:
	var rel := ensure_relation(a.id, b.id)
	if rel.at_war:
		return {"ok": false, "reason": "at_war", "accepted": false}
	# 资源存在性/足额校验（交易物必须双方都真的持有）
	if not a.can_afford(give) or not b.can_afford(ask):
		return {"ok": false, "reason": "insufficient", "accepted": false}
	var trade_cfg: Dictionary = config.get("trade", {})
	var score := _trade_score(give, ask, b, trade_cfg)
	if score < int(trade_cfg.get("accept_threshold", 0)):
		return {"ok": true, "accepted": false, "score": score, "reason": "rejected"}
	# 成交：转移资源
	a.pay(give)
	b.pay(ask)
	a.add_resources(ask)
	b.add_resources(give)
	if score > 0:
		_change_attitude(rel, float(score))
	state.add_event("trade", {"a": a.name_zh, "b": b.name_zh})
	return {"ok": true, "accepted": true, "score": score}


## 贸易评分（口径：参考项目 trade_score）
func _trade_score(give: Dictionary, ask: Dictionary, b: Faction, cfg: Dictionary) -> int:
	var score := 0
	# 我方给出：只记"对方缺口补齐部分"
	for res_id in give:
		var amount: int = int(give[res_id])
		var held: int = int(b.resources.get(res_id, 0))
		var expect: int = int(b.expectations.get(res_id, 0))
		var deficit: int = max(0, expect - held)
		var fills: int = min(amount, deficit)
		score += fills * int(cfg.get("deficit_fill_gain", 1))
	# 对方给出：低于预期每份高惩罚，高于预期低惩罚
	for res_id in ask:
		var amount: int = int(ask[res_id])
		var held: int = int(b.resources.get(res_id, 0))
		var expect: int = int(b.expectations.get(res_id, 0))
		var per_unit := int(cfg.get("give_above_expectation_penalty", 1))
		if held <= expect:
			per_unit = int(cfg.get("give_below_expectation_penalty", 2))
		score -= amount * per_unit
	return score


## 逼迫朝贡：军力严格 > 3 倍、非交战、好感 ≥ relation_floor；索取量受库存与配置上限约束
func demand_tribute(a: Faction, b: Faction) -> Dictionary:
	var rel := ensure_relation(a.id, b.id)
	if rel.at_war:
		return {"ok": false, "reason": "at_war"}
	var tcfg: Dictionary = config.get("tribute", {})
	if float(rel.attitude) < float(tcfg.get("relation_floor", 0.0)):
		return {"ok": false, "reason": "relation_too_low"}
	# 严格大于（参考项目口径：121 可、120 不可）
	if military_score(a) <= military_score(b) * int(tcfg.get("military_ratio_required", 3)):
		return {"ok": false, "reason": "military_not_dominant"}
	var amounts: Dictionary = tcfg.get("amounts", {})
	var taken: Dictionary = {}
	for res_id in amounts:
		var take: int = min(int(amounts[res_id]), int(b.resources.get(res_id, 0)))
		if take > 0:
			taken[res_id] = take
	b.pay(taken)
	a.add_resources(taken)
	_change_attitude(rel, -float(tcfg.get("relation_penalty", 20.0)))
	state.add_event("trade", {"a": a.name_zh, "b": b.name_zh})
	return {"ok": true, "taken": taken}


## ---------------------------------------------------------------------------
## 回合推进（每回合结束调用）
## ---------------------------------------------------------------------------

## 好感衰减（向 0 靠拢 decay_per_turn） + 条约倒计时 + 过期清理
func tick_treaties() -> void:
	var decay: float = float(config.get("relationship", {}).get("decay_per_turn", 0.1))
	for rel in state.relations:
		# 衰减：|x| ≤ decay 直接归零，否则向 0 移动 decay（口径同参考项目）
		if absf(rel.attitude) <= decay:
			rel.attitude = 0.0
		else:
			rel.attitude -= decay * signf(rel.attitude)
		# 条约倒计时与清理
		for treaty in rel.treaties:
			treaty.tick()
		rel.purge_expired()


# ==================================================================
#  AI 指令处理器（AIContext 注册表约定：func(params, ctx) -> Dictionary）
# ==================================================================

func ai_declare_war_command(params: Dictionary, ctx: AIContext) -> Dictionary:
	var target: Faction = state.get_faction(params.get("target_faction_id", ""))
	if target == null or target.id == ctx.faction.id:
		return {"ok": false, "reason": "bad_target"}
	return declare_war(ctx.faction, target)


func ai_propose_trade_command(params: Dictionary, ctx: AIContext) -> Dictionary:
	var target: Faction = state.get_faction(params.get("target_faction_id", ""))
	if target == null:
		return {"ok": false, "reason": "bad_target"}
	return propose_trade(ctx.faction, target, params.get("give", {}), params.get("ask", {}))


func ai_demand_tribute_command(params: Dictionary, ctx: AIContext) -> Dictionary:
	var target: Faction = state.get_faction(params.get("target_faction_id", ""))
	if target == null:
		return {"ok": false, "reason": "bad_target"}
	return demand_tribute(ctx.faction, target)


# ==================================================================
#  内部辅助
# ==================================================================

## 追加条约（同类型未过期的先替换——续约语义）
func _add_treaty(rel: Relation, type: String, rounds: int) -> void:
	for t in rel.treaties:
		if t.type == type:
			t.remaining_rounds = rounds
			return
	var treaty := Treaty.new()
	treaty.type = type
	treaty.remaining_rounds = rounds
	rel.treaties.append(treaty)
