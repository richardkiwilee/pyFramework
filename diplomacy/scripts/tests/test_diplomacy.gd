extends SceneTree
## =============================================================================
## test_diplomacy — AIState 规则冒烟测试（headless 运行）
## 运行：
##   Godot_v4.6.2-stable_win64_console.exe --headless -s res://scripts/tests/test_diplomacy.gd
## 覆盖：贸易评分（含跨界补齐）、宣战钳制、关系状态推导、逼迫条件、回合衰减、
##       交易执行、默认 AI 工厂。
## =============================================================================

var failed := 0


func _init() -> void:
	_test_trade_score()
	_test_apply_trade()
	_test_war_peace()
	_test_relation_state()
	_test_coerce()
	_test_decay()
	_test_factory()
	print("---------------------------------------------")
	print("结果：%s" % ("全部通过" if failed == 0 else "%d 项失败" % failed))
	quit(failed)


func check(cond: bool, name: String) -> void:
	if cond:
		print("PASS · %s" % name)
	else:
		print("FAIL · %s" % name)
		failed += 1


func _std_ai() -> AIState:
	var ai := AIState.new()
	ai.id = "test"
	ai.display_name = "测试"
	ai.military = 40
	ai.resources = {"food": 30, "gold": 60, "wood": 10, "horse": 5}
	ai.expectations = {"food": 50, "gold": 20, "wood": 10, "horse": 30}
	ai.relationship = 0.0
	return ai


func _test_trade_score() -> void:
	var ai := _std_ai()
	# 低于预期给出：food 30 < 50，给 5 → +5
	check(ai.trade_score({"food": 5}, {}) == 5, "低于预期给出每份 +1")
	# 高于预期给出：gold 60 > 20，给 10 → 0
	check(ai.trade_score({"gold": 10}, {}) == 0, "高于预期给出记 0 分")
	# 跨界补齐：food 30 < 50，给 40 → 只记补齐到预期的 20 份
	check(ai.trade_score({"food": 40}, {}) == 20, "跨界给出只记补齐部分")
	# 低于预期索取：food 30 < 50，要 5 → -10
	check(ai.trade_score({}, {"food": 5}) == -10, "低于预期索取每份 -2")
	# 高于预期索取：gold 60 > 20，要 5 → -5
	check(ai.trade_score({}, {"gold": 5}) == -5, "高于预期索取每份 -1")
	# 恰好等于预期索取：wood 10 = 10，要 2 → -4（原型口径：按将跌破预期处理）
	check(ai.trade_score({}, {"wood": 2}) == -4, "等于预期索取按 -2 计")
	# 混合：给 food 5 (+5)、要 gold 3 (-3) → +2
	check(ai.trade_score({"food": 5}, {"gold": 3}) == 2, "混合交易计分")
	# 临界 0 分：给马 2 (+2)、要马 1 (-2)
	check(ai.trade_score({"horse": 2}, {"horse": 1}) == 0, "临界 0 分仍接受")
	# 空白交易：0 分
	check(ai.trade_score({}, {}) == 0, "空白交易 0 分")


func _test_apply_trade() -> void:
	var ai := _std_ai()
	var player := {"food": 50, "gold": 50, "wood": 30, "horse": 15}
	ai.apply_trade({"food": 5}, {"gold": 3}, player, 2)
	check(int(player["food"]) == 45 and int(player["gold"]) == 53, "交易执行双向转移")
	check(int(ai.resources["food"]) == 35 and int(ai.resources["gold"]) == 57, "AI 库存同步变化")
	check(absf(ai.relationship - 2.0) < 0.001, "分数 >0 加到关系值")
	ai.apply_trade({"food": 5}, {}, player, 0)
	check(absf(ai.relationship - 2.0) < 0.001, "0 分不加关系")


func _test_war_peace() -> void:
	var a := _std_ai()
	a.relationship = 30.0
	a.declare_war()
	check(a.at_war and absf(a.relationship - (-40.0)) < 0.001, "宣战 30 → -40（-60 后压到 -40）")
	var b := _std_ai()
	b.relationship = 100.0
	b.declare_war()
	check(absf(b.relationship - (-40.0)) < 0.001, "宣战 100 → -40")
	var c := _std_ai()
	c.relationship = -30.0
	c.declare_war()
	check(absf(c.relationship - (-90.0)) < 0.001, "宣战 -30 → -90（已低于 -40 不压）")
	var d := _std_ai()
	d.relationship = -100.0
	d.declare_war()
	check(absf(d.relationship - (-100.0)) < 0.001, "宣战 -100 → 下限 -100")
	d.make_peace()
	check(not d.at_war and d.relation_state() == "敌视", "和平后解除交战但仍敌视")


func _test_relation_state() -> void:
	var ai := _std_ai()
	ai.relationship = -50.0
	check(ai.relation_state() == "敌视", "关系 -50 → 敌视")
	ai.relationship = -0.1
	check(ai.relation_state() == "敌视", "关系 -0.1 → 敌视")
	ai.relationship = 0.0
	check(ai.relation_state() == "和平", "关系 0 → 和平")
	ai.relationship = 39.9
	check(ai.relation_state() == "和平", "关系 39.9 → 和平")
	ai.relationship = 40.0
	check(ai.relation_state() == "友好", "关系 40 → 友好")
	ai.relationship = 59.9
	check(ai.relation_state() == "友好", "关系 59.9 → 友好")
	ai.relationship = 60.0
	check(ai.relation_state() == "同盟", "关系 60 → 同盟")
	ai.at_war = true
	ai.relationship = 80.0
	check(ai.relation_state() == "交战", "交战状态优先于关系值")


func _test_coerce() -> void:
	var ai := _std_ai()  # military 40
	ai.relationship = 0.0
	check(ai.can_coerce(121), "军力 121 > 3×40 → 可逼迫")
	check(not ai.can_coerce(120), "军力 120 不严格大于 3 倍 → 不可逼迫")
	ai.relationship = -1.0
	check(not ai.can_coerce(999), "敌视关系不可逼迫")
	ai.relationship = 0.0
	ai.at_war = true
	check(not ai.can_coerce(999), "交战状态不可逼迫")

	# 执行：索取量受库存上限约束，关系 -20
	var player := {"food": 0, "gold": 0, "wood": 0, "horse": 0}
	var ai2 := _std_ai()
	ai2.relationship = 30.0
	var gained := ai2.coerce(player)
	check(int(gained.get("food", 0)) == 10 and int(gained.get("wood", 0)) == 5
		and int(gained.get("horse", 0)) == 3, "逼迫获得量按上限截断（马 5 只取 3）")
	check(int(player["food"]) == 10 and int(ai2.resources["food"]) == 20, "逼迫后双方库存变化")
	check(absf(ai2.relationship - 10.0) < 0.001, "逼迫成功关系 -20")


func _test_decay() -> void:
	var ai := _std_ai()
	ai.relationship = 50.0
	ai.decay_toward_zero()
	check(absf(ai.relationship - 49.9) < 0.001, "正关系每回合 -0.1")
	ai.relationship = -3.0
	ai.decay_toward_zero()
	check(absf(ai.relationship - (-2.9)) < 0.001, "负关系每回合 +0.1")
	ai.relationship = 0.05
	ai.decay_toward_zero()
	check(ai.relationship == 0.0, "不足 0.1 直接归零")


func _test_factory() -> void:
	var ais := AIState.build_default_ais()
	check(ais.size() == 4, "默认 4 个 AI")
	var exps: Dictionary = {}
	for a: AIState in ais:
		exps[str(a.expectations)] = true
	check(exps.size() == 4, "4 个 AI 预期各不相同")
