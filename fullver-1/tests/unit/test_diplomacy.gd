extends RefCounted
## =============================================================================
## 外交系统测试（docs/00-design.md §11）
## 规则口径迁移自 diplomacy 参考项目并数据化；断言失败 = push_error。
## =============================================================================


func _fail(template: String, ...args: Array) -> void:
	push_error("[test_diplomacy] " + template.format(args, "{}"))


## 造两个势力（玩家 + AI），各带资源与预期
func _make_pair() -> Array:
	var gs := GameState.new()
	var p := Faction.new()
	p.id = "player"; p.is_player = true
	p.resources = {"gold": 100, "food": 100, "wood": 50, "horse": 20}
	p.expectations = p.resources.duplicate()
	var ai := Faction.new()
	ai.id = "ai1"
	ai.resources = {"gold": 80, "food": 40, "wood": 30, "horse": 10}
	ai.expectations = {"gold": 100, "food": 120, "wood": 60, "horse": 20}
	gs.factions = [p, ai]
	# 军团：玩家 12 人（4 个满编 3 人？）——军力 = Σ 编队人数
	for i in range(4):
		var a := Army.new()
		a.id = "pa%d" % i; a.owner_faction_id = "player"; a.current_city_id = "roma"
		a.team = Team.new()
		for j in range(3):
			var u := Unit.new(); u.id = "pu%d_%d" % [i, j]; u.character_id = "alain"
			a.team.set_unit(j, u)
		gs.armies.append(a)
	var aa := Army.new()
	aa.id = "aa0"; aa.owner_faction_id = "ai1"; aa.current_city_id = "ragusa"
	aa.team = Team.new()
	var uu := Unit.new(); uu.id = "au0"; uu.character_id = "alain"
	aa.team.set_unit(6, uu)
	gs.armies.append(aa)
	return [gs, DiplomacySystem.new(gs)]


## 宣战：好感压平（30→-40）、双方交战、重复宣战/条约期内拒绝
func test_declare_war_rules() -> void:
	var pair: Array = _make_pair()
	var gs: GameState = pair[0]
	var dip: DiplomacySystem = pair[1]
	var p: Faction = gs.get_faction("player")
	var ai: Faction = gs.get_faction("ai1")
	dip.ensure_relation(p.id, ai.id).attitude = 30.0
	var r: Dictionary = dip.declare_war(p, ai)
	if not r.get("ok", false):
		_fail("首次宣战应成功: {}", r)
	if dip.ensure_relation(p.id, ai.id).attitude != -40.0:
		_fail("宣战后好感应从 30 压平到 -40，实际 {}", dip.ensure_relation(p.id, ai.id).attitude)
	if not dip.ensure_relation(p.id, ai.id).at_war or not dip.ensure_relation(ai.id, p.id).at_war:
		_fail("宣战后双方应处于交战")
	if dip.declare_war(p, ai).get("ok", false):
		_fail("重复宣战应拒绝")
	# 和平条约期内宣战拒绝（先交战再求和，才存在有效的和平条约）
	var pair2: Array = _make_pair()
	var dip2: DiplomacySystem = pair2[1]
	var gs2: GameState = pair2[0]
	var p2: Faction = gs2.get_faction("player")
	var ai2: Faction = gs2.get_faction("ai1")
	if not dip2.declare_war(p2, ai2).get("ok", false):
		_fail("前置宣战失败（配对状态异常）")
	if not dip2.make_peace(p2, ai2).get("ok", false):
		_fail("前置求和失败")
	if dip2.declare_war(p2, ai2).get("ok", false):
		_fail("和平条约期内宣战应拒绝")


## 求和：清交战 + 和平条约；非交战求和拒绝
func test_make_peace() -> void:
	var pair: Array = _make_pair()
	var gs: GameState = pair[0]
	var dip: DiplomacySystem = pair[1]
	var p: Faction = gs.get_faction("player")
	var ai: Faction = gs.get_faction("ai1")
	if not dip.declare_war(p, ai).get("ok", false):
		_fail("前置宣战失败")
		return
	if not dip.make_peace(p, ai).get("ok", false):
		_fail("交战中求和应成功")
	var rel: Relation = dip.ensure_relation(p.id, ai.id)
	if rel.at_war:
		_fail("求和后不应交战")
	if not rel.has_treaty("peace"):
		_fail("求和后应有和平条约")
	if dip.make_peace(p, ai).get("ok", false):
		_fail("未交战时求和应拒绝")


## 友谊/同盟阈值（40/60）：低于拒绝、达标成功并加好感；同盟有条约
func test_friendship_alliance_thresholds() -> void:
	var pair: Array = _make_pair()
	var gs: GameState = pair[0]
	var dip: DiplomacySystem = pair[1]
	var p: Faction = gs.get_faction("player")
	var ai: Faction = gs.get_faction("ai1")
	var rel: Relation = dip.ensure_relation(p.id, ai.id)
	rel.attitude = 35.0
	if dip.declare_friendship(p, ai).get("ok", false):
		_fail("好感 35 应拒绝友谊")
	rel.attitude = 45.0
	if not dip.declare_friendship(p, ai).get("ok", false):
		_fail("好感 45 应成功友谊")
	if rel.attitude != 55.0:
		_fail("友谊应 +10，实际 {}", rel.attitude)
	# 同盟：55 拒绝、65 成功
	rel.attitude = 55.0
	if dip.declare_alliance(p, ai).get("ok", false):
		_fail("好感 55 应拒绝同盟")
	rel.attitude = 65.0
	if not dip.declare_alliance(p, ai).get("ok", false):
		_fail("好感 65 应成功同盟")
	if not rel.has_treaty("alliance"):
		_fail("同盟后应有同盟条约")


## 贸易评分：缺口补齐 +1/份；对方给出低于预期 -2/份；总分≥0 接受、>0 加好感
func test_trade_score() -> void:
	var pair: Array = _make_pair()
	var gs: GameState = pair[0]
	var dip: DiplomacySystem = pair[1]
	var p: Faction = gs.get_faction("player")
	var ai: Faction = gs.get_faction("ai1")
	# ai 粮持有 40、预期 120（缺 80）；玩家给 20 粮 → 补齐 20 → +20 分
	# 索要 20 粮：ai 持有 40 ≤ 预期 120 → -40 分 → 总分 -20 → 拒绝
	var r1: Dictionary = dip.propose_trade(p, ai, {"food": 20}, {"food": 20})
	if r1.get("accepted", false):
		_fail("总分 -20 应拒绝: {}", r1)
	if int(r1.get("score", 0)) != -20:
		_fail("评分应为 -20，实际 {}", r1.get("score", 0))
	# 玩家给 20 粮、索 5 金：+20 -10 = +10 → 接受、好感 +10
	var rel: Relation = dip.ensure_relation(p.id, ai.id)
	var before: float = rel.attitude
	var r2: Dictionary = dip.propose_trade(p, ai, {"food": 20}, {"gold": 5})
	if not r2.get("accepted", false):
		_fail("总分 +10 应接受: {}", r2)
	if int(r2.get("score", 0)) != 10:
		_fail("评分应为 +10，实际 {}", r2.get("score", 0))
	if rel.attitude != before + 10.0:
		_fail("成交后好感应 +10")
	if p.resources["gold"] != 105 or ai.resources["food"] != 60:
		_fail("成交后资源转移不对: 玩家金 {} / AI 粮 {}", p.resources["gold"], ai.resources["food"])
	# 资源不足拒绝
	var r3: Dictionary = dip.propose_trade(p, ai, {"horse": 999}, {})
	if r3.get("ok", false):
		_fail("玩家资源不足应拒绝")


## 朝贡：军力严格 > 3 倍 + 关系 ≥ 0 + 非交战
func test_tribute() -> void:
	var pair: Array = _make_pair()
	var gs: GameState = pair[0]
	var dip: DiplomacySystem = pair[1]
	var p: Faction = gs.get_faction("player")
	var ai: Faction = gs.get_faction("ai1")
	# 玩家 12 人 vs AI 1 人：12 > 3×1=3 → 军力满足
	var r: Dictionary = dip.demand_tribute(p, ai)
	if not r.get("ok", false):
		_fail("军力碾压应可朝贡: {}", r)
	if p.resources["gold"] != 110:
		_fail("朝贡应获得 10 金（配置上限），实际 {}", p.resources["gold"])
	# 交战关系下拒绝
	dip.declare_war(p, ai)
	if dip.demand_tribute(p, ai).get("ok", false):
		_fail("交战中朝贡应拒绝")


## 回合推进：好感衰减 + 条约倒计时/过期清理
func test_tick_treaties() -> void:
	var pair: Array = _make_pair()
	var gs: GameState = pair[0]
	var dip: DiplomacySystem = pair[1]
	var p: Faction = gs.get_faction("player")
	var ai: Faction = gs.get_faction("ai1")
	var rel: Relation = dip.ensure_relation(p.id, ai.id)
	rel.attitude = 5.0
	dip.ensure_relation(p.id, ai.id)
	# 加一个 1 回合过期的条约
	var t := Treaty.new()
	t.type = "peace"; t.remaining_rounds = 1
	rel.treaties.append(t)
	dip.tick_treaties()
	if rel.attitude != 4.9:
		_fail("衰减应为 0.1，实际 {}", rel.attitude)
	if rel.has_treaty("peace"):
		_fail("1 回合条约应在推进后过期")
	# 小值直接归零
	rel.attitude = 0.05
	dip.tick_treaties()
	if rel.attitude != 0.0:
		_fail("|好感| ≤ 0.1 应直接归零")
