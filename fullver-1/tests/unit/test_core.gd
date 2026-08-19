extends RefCounted
## =============================================================================
## 领域层测试（docs/00-design.md §16）
## 覆盖：Team 槽位与战斗站位映射、队长回退、GameState 序列化往返、
##       Faction 资源收支、TurnManager 回合流程与战斗打断点。
##
## gdtest 约定（zfoo/gdtest/UnitTest.gd）：
##   - 测试方法名（小写后）以 test 开头或结尾，且不能有参数
##   - 断言失败 = push_error(...) —— ⚠️ 不能用 Log.error！
##     实测：zfoo 的 Log.error 只调 printerr，不触发 gdf.events.log_error；
##     只有走引擎错误通道的 push_error / 脚本错误会被 LoggerHelper 捕获，
##     进而置 error_occurred → 测试 FAIL → gdf.quit(1)。
##
## GDScript 闭包陷阱（本文件实测踩过）：
##   lambda 捕获变量是"按值"的——标量 += 1 改的是副本，外层看不到！
##   需要共享可变状态时用 Dictionary 包一层（引用类型，捕获的是引用）。
## =============================================================================


## 断言失败：走引擎错误通道，触发测试框架 FAIL + quit(1)
## template 用 {} 占位符，args 顺序替换（同 zfoo Log 风格）
func _fail(template: String, ...args: Array) -> void:
	push_error("[test_core] " + template.format(args, "{}"))


# ------------------------------------------------------------------ 辅助工厂

## 造一个最小的 GameState（1 玩家 + 2 AI、3 城）
func _make_state() -> GameState:
	var gs := GameState.new()
	var p := Faction.new()
	p.id = "player"; p.name_zh = "玩家"; p.is_player = true
	p.resources = {"gold": 100, "food": 100}
	var ai1 := Faction.new()
	ai1.id = "ai1"; ai1.name_zh = "AI1"
	var ai2 := Faction.new()
	ai2.id = "ai2"; ai2.name_zh = "AI2"
	gs.factions = [p, ai1, ai2]
	for i in range(3):
		var c := City.new()
		c.id = "city_%d" % i
		c.name_zh = "城%d" % i
		c.owner_faction_id = "player"
		gs.cities.append(c)
	return gs


# ------------------------------------------------------------------ Team 测试

## 槽位 → 战斗站位映射：前排（row2, slot 6-8）→ position 0-2，
## 后排（row0, slot 0-2）→ position 6-8（修正 demo-1 摆位不影响战斗的缺陷）
func test_slot_to_battle_position() -> void:
	if Team.slot_to_battle_position(6) != 0:
		_fail("前排左槽 slot6 应映射 position 0，实际 {}", Team.slot_to_battle_position(6))
	if Team.slot_to_battle_position(7) != 1:
		_fail("前排中槽 slot7 应映射 position 1")
	if Team.slot_to_battle_position(8) != 2:
		_fail("前排右槽 slot8 应映射 position 2")
	if Team.slot_to_battle_position(4) != 4:
		_fail("中排中槽 slot4 应映射 position 4")
	if Team.slot_to_battle_position(0) != 6:
		_fail("后排左槽 slot0 应映射 position 6")
	# 往返映射一致
	for slot in range(9):
		if Team.battle_position_to_slot(Team.slot_to_battle_position(slot)) != slot:
			_fail("槽位映射往返不一致: slot {}", slot)


## 编队操作：放置/移除/队长回退
func test_team_operations() -> void:
	var t := Team.new()
	var u1 := Unit.new(); u1.id = "u1"
	var u2 := Unit.new(); u2.id = "u2"
	var u3 := Unit.new(); u3.id = "u3"
	# 放置：第一个单位自动成为队长
	if not t.set_unit(0, u1):
		_fail("set_unit(0) 应成功")
	if t.captain != u1:
		_fail("首个单位应自动成为队长")
	# 占位槽拒绝覆盖
	if t.set_unit(0, u2):
		_fail("已占用槽位应拒绝放置")
	# 移动单位到空槽
	if not t.move_unit(0, 5):
		_fail("move_unit 到空槽应成功")
	if t.get_unit_at(0) != null or t.get_unit_at(5) != u1:
		_fail("move_unit 后槽位内容不对")
	# 移除队长 → 回退到第一个存活单位
	t.set_unit(1, u2)
	t.set_unit(2, u3)
	var removed: Unit = t.remove_unit_at(5)  # 移除的是队长 u1
	if removed != u1:
		_fail("remove_unit_at 应返回被移除单位")
	if t.captain != u2:
		_fail("队长被移除后应回退到第一个存活单位")
	if t.unit_count() != 2:
		_fail("unit_count 应为 2，实际 {}", t.unit_count())


# ------------------------------------------------------------------ Faction 测试

## 资源收支：原子扣除（任一不足则全不动）
func test_faction_resources() -> void:
	var f := Faction.new()
	f.resources = {"gold": 10, "food": 5}
	f.add_resources({"gold": 5, "wood": 3})
	if f.resources["gold"] != 15 or f.resources["wood"] != 3:
		_fail("add_resources 结果不对: {}", f.resources)
	# 支付成功
	if not f.pay({"gold": 6, "food": 2}):
		_fail("足够资源应支付成功")
	# 原子性：gold 不够时 food 也不能被扣
	if f.can_afford({"gold": 999, "food": 1}):
		_fail("资源不足应 can_afford=false")
	if f.pay({"gold": 999, "food": 1}):
		_fail("资源不足应支付失败")
	if f.resources["food"] != 3:
		_fail("支付失败后 food 不应被扣（原子性破坏）")


# ------------------------------------------------------------------ 序列化测试

## GameState → dict → GameState 往返：字段逐一核对
func test_game_state_roundtrip() -> void:
	var gs := _make_state()
	# 造一个带编队的军团
	var army: Army = gs.new_army("player", "city_0")
	var u1: Unit = gs.new_unit("alain", 3)
	u1.equipment = {"weapon": "eq_test", "acc1": "eq_acc"}
	u1.strategy = [
		{"skill": "skill_001", "cond1": "cond_001", "cond2": ""},
		{"skill": "skill_002", "cond1": "", "cond2": "cond_002"},
	]
	var u2: Unit = gs.new_unit("scarlett", 2)
	army.team.set_unit(6, u1)
	army.team.set_unit(7, u2)
	# 双边关系 + 条约
	var r := Relation.new()
	r.faction_a = "player"; r.faction_b = "ai1"
	r.attitude = 55.0; r.at_war = false
	var t := Treaty.new()
	t.type = "alliance"; t.remaining_rounds = 12
	r.treaties.append(t)
	gs.relations.append(r)
	gs.add_event("turn_start", {})
	gs.turn = 7

	# 序列化往返
	var d: Dictionary = gs.to_dict()
	var gs2: GameState = GameState.from_dict(d)
	if gs2 == null:
		_fail("from_dict 返回 null（版本不符？）")
		return
	if gs2.turn != 7:
		_fail("turn 往返不一致: {}", gs2.turn)
	if gs2.factions.size() != 3 or gs2.cities.size() != 3 or gs2.armies.size() != 1:
		_fail("对象数量往返不一致")
	var a2: Army = gs2.get_army(army.id)
	if a2 == null:
		_fail("军团未还原")
		return
	if a2.team.unit_count() != 2:
		_fail("编队单位数往返不一致: {}", a2.team.unit_count())
	var slot6: Unit = a2.team.get_unit_at(6)
	if slot6 == null or slot6.character_id != "alain" or slot6.level != 3:
		_fail("单位数据往返不一致")
	if slot6.equipment.get("weapon", "") != "eq_test":
		_fail("单位装备往返不一致")
	# 策略行往返（4 装备槽 + 8 策略栏的存储结构）
	if slot6.strategy.size() != 2:
		_fail("策略行数量往返不一致: {}", str(slot6.strategy))
	if slot6.strategy[0].get("skill", "") != "skill_001" or slot6.strategy[0].get("cond1", "") != "cond_001":
		_fail("策略行内容往返不一致: {}", str(slot6.strategy))
	if slot6.battle_skill_ids() != ["skill_001", "skill_002"]:
		_fail("battle_skill_ids 应按序提取策略行技能: {}", str(slot6.battle_skill_ids()))
	if a2.team.captain == null or a2.team.captain.id != u1.id:
		_fail("队长引用往返不一致")
	var r2: Relation = gs2.get_relation("player", "ai1")
	if r2 == null or r2.attitude != 55.0 or not r2.has_treaty("alliance"):
		_fail("关系/条约往返不一致")
	if gs2.event_log.size() != 1:
		_fail("事件日志往返不一致")
	# 新对象 ID 计数器延续（不重号）
	var u3: Unit = gs2.new_unit("alain")
	if u3.id == u1.id or u3.id == u2.id:
		_fail("ID 计数器未延续，出现重号")


# ------------------------------------------------------------------ TurnManager 测试

## 正常回合推进：AI 依序行动 → 结算 → 回合+1
func test_turn_advance() -> void:
	var gs := _make_state()
	var ai_log: Array = []
	# ⚠️ 闭包陷阱：标量按值捕获，+= 改的是副本。计数器用 Dictionary 包一层
	# （Dictionary 是引用类型，捕获的是引用，修改能传到外层）
	var counters := {"settled": 0, "advanced": 0}
	var tm := TurnManager.new(
		gs,
		func(faction: Faction) -> Dictionary:
			ai_log.append(faction.id)
			return {},
		func() -> Dictionary:
			counters["settled"] += 1
			return {},
		func() -> void:
			counters["advanced"] += 1
	)
	var result: Dictionary = tm.run_player_end_turn()
	if not result.has("advance"):
		_fail("应正常推进回合，实际返回 {}", result)
	if ai_log != ["ai1", "ai2"]:
		_fail("AI 行动顺序不对: {}", ai_log)
	if counters["settled"] != 1 or counters["advanced"] != 1:
		_fail("结算/收尾回调次数不对: {}", counters)
	if gs.turn != 2:
		_fail("回合数应为 2，实际 {}", gs.turn)


## 战斗打断点：AI2 行动引发战斗 → 挂起 → resume 后续跑
func test_turn_battle_interrupt() -> void:
	var gs := _make_state()
	var ai_log: Array = []
	var counters := {"advanced": 0}
	var battle_req := {"attacker_army_id": "army_x", "defender_army_id": "army_y", "city_id": "city_1"}
	var tm := TurnManager.new(
		gs,
		func(faction: Faction) -> Dictionary:
			ai_log.append(faction.id)
			if faction.id == "ai2":
				return {"battle": battle_req}   # ai2 的行动引发战斗
			return {},
		func() -> Dictionary: return {},
		func() -> void: counters["advanced"] += 1
	)
	var result: Dictionary = tm.run_player_end_turn()
	if not result.has("battle"):
		_fail("应返回战斗请求，实际 {}", result)
		return
	if ai_log != ["ai1", "ai2"]:
		_fail("战斗打断前 AI 顺序不对: {}", ai_log)
	if gs.turn != 1:
		_fail("战斗未结束前回合不应推进")
	if not tm.is_awaiting_battle():
		_fail("应处于等待战斗状态")
	# 战斗结束续跑：剩余 AI（无）→ 结算 → 推进
	var resumed: Dictionary = tm.resume_after_battle({"result": "victory"})
	if not resumed.has("advance") or gs.turn != 2:
		_fail("战斗后应推进回合，实际 {}", resumed)
	if counters["advanced"] != 1:
		_fail("战斗后收尾回调应执行一次，实际 {}", counters["advanced"])
	if tm.is_awaiting_battle():
		_fail("战斗后应清除挂起状态")


## 连续战斗打断：两个 AI 都引发战斗
func test_turn_double_battle() -> void:
	var gs := _make_state()
	var tm := TurnManager.new(
		gs,
		func(faction: Faction) -> Dictionary:
			return {"battle": {"attacker_army_id": "a_%s" % faction.id}},
		func() -> Dictionary: return {},
		func() -> void: pass
	)
	var r1: Dictionary = tm.run_player_end_turn()
	if not r1.has("battle"):
		_fail("第一场战斗应打断")
		return
	var r2: Dictionary = tm.resume_after_battle({"result": "victory"})
	if not r2.has("battle"):
		_fail("第二场战斗应继续打断，实际 {}", r2)
		return
	var r3: Dictionary = tm.resume_after_battle({"result": "defeat"})
	if not r3.has("advance") or gs.turn != 2:
		_fail("两场战斗后应推进回合")
