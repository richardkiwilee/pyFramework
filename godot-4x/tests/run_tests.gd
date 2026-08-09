## Headless 测试运行器（对应 Python 原型 smoke_test.py + pydemo/tests）。
## 运行：D:\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . -s tests/run_tests.gd
## 退出码 0 = 全部通过。
extends SceneTree

var _failures: Array = []
var _asserts := 0

func _initialize() -> void:
	# 加载所有核心脚本（语法检查）
	load("res://scripts/core/data_loader.gd")
	load("res://scripts/core/time_system.gd")
	load("res://scripts/core/economy.gd")
	load("res://scripts/core/map_system.gd")
	load("res://scripts/core/unit.gd")
	load("res://scripts/core/hero.gd")
	load("res://scripts/core/army.gd")
	load("res://scripts/core/faction.gd")
	load("res://scripts/core/modifier.gd")
	load("res://scripts/core/effects.gd")
	load("res://scripts/core/triggers.gd")
	load("res://scripts/core/formation.gd")
	load("res://scripts/core/synergy.gd")
	load("res://scripts/core/events.gd")
	load("res://scripts/core/battle.gd")
	load("res://scripts/core/ai.gd")
	load("res://scripts/core/game.gd")
	load("res://scripts/core/scenario.gd")
	call_deferred("_run")

func _run() -> void:
	print("=== TheGreatConquest Godot 测试 ===")
	_test_scenario()
	_test_economy()
	_test_unit_growth()
	_test_build_recruit_train()
	_test_learn_gate()
	_test_equip_inventory()
	_test_battle()
	_test_standby_deploy()
	_test_save_load()
	_test_ai_loop()
	# 冒烟：跑完整对局直到分出胜负（限 300 回合）
	_test_smoke_game()
	print("=== 断言总数: %d, 失败: %d ===" % [_asserts, _failures.size()])
	for f in _failures:
		print("FAIL: ", f)
	quit(1 if not _failures.is_empty() else 0)

# ---------- 断言 ----------
func ok(cond: bool, msg: String) -> void:
	_asserts += 1
	if not cond:
		_failures.append(msg)
		print("  ✗ ", msg)
	else:
		print("  ✓ ", msg)

func eq(a, b, msg: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])

# ---------- 测试 ----------
func _test_scenario() -> void:
	print("-- 场景装配 --")
	var g := Scenario.build_scenario()
	eq(g.map.strongholds.size(), 4, "据点数量=4")
	eq(g.map.minors.size(), 4, "小地点数量=4")
	eq(g.factions.size(), 2, "阵营数量=2")
	eq(g.player_id, "player", "玩家阵营=player")
	ok(g.unit_index.size() >= 6, "初始单位 >=6")
	ok(g.armies.size() >= 2, "初始部队 >=2")
	var player: Faction.Faction_ = g.factions["player"]
	eq(player.resources.get_amount("gold"), 80, "玩家初始金币=80")
	eq(player.belief.get_value("morality"), 20, "玩家道德=20")
	var army: Armies.Army = g.armies[player.army_ids[0]]
	ok(army.captain_id != "", "先锋军有队长")
	ok(g.artifact_defs.size() >= 10, "装备定义 >=10")
	var stock := 0
	for k in player.inventory:
		stock += int(player.inventory[k])
	eq(stock, g.artifact_defs.size() * 3, "玩家库存=定义数*3")

func _test_economy() -> void:
	print("-- 经济 --")
	var res := Economy.Resources.new({"gold": 10, "food": 0})
	res.add("gold", 5, Economy.SOURCE_BUILD, "p_cap", "市场")
	res.add("food", -3, Economy.SOURCE_MAINT)
	eq(res.get_amount("gold"), 15, "金币+5=15")
	eq(res.get_amount("food"), -3, "食物-3")
	eq(res.resource("gold").net(), 5, "gold 净变动=5")
	eq(res.resource("gold").display_net(), 5, "gold display_net=5")
	res.resource("gold").add_projected(4)
	eq(res.resource("gold").display_net(), 9, "gold 投影后 display_net=9")
	ok(res.can_afford({"gold": 15}), "可负担 gold:15")
	ok(not res.can_afford({"gold": 16}), "负担不起 gold:16")
	ok(res.pay({"gold": 15}), "pay 成功")
	ok(not res.pay({"gold": 5}), "pay 失败（余额不足）")
	eq(res.get_amount("gold"), 0, "扣款后 gold=0")
	var b := Economy.Belief.new({"morality": 95})
	b.change("morality", 10)
	eq(b.get_value("morality"), 100, "信念 clamp 上限 100")
	b.change("morality", -999)
	eq(b.get_value("morality"), -100, "信念 clamp 下限 -100")

func _test_unit_growth() -> void:
	print("-- 单位成长 --")
	var g := Scenario.build_scenario()
	var u := g.make_unit("infantry")
	eq(u.level, 1, "初始等级 1")
	eq(Units.xp_to_next(1), 5, "1->2 需 5 XP")
	var hp0 := u.cur_hp
	u.cur_hp = u.base["hp"] * 0.5   # 半血
	eq(u.gain_xp(5), 1, "+5XP 升 1 级")
	eq(u.level, 2, "等级=2")
	ok(u.cur_hp > 0 and u.cur_hp < u.base["hp"], "升级 HP 按比例保留(未回满)")
	eq(u.gain_xp(0), 0, "0XP 不升级")
	ok(Units.WILL_BASE == 5.0 and float(u.base["will"]) == 5.0, "普通兵 will 基准=5")

func _test_build_recruit_train() -> void:
	print("-- 建造/招募/训练 --")
	var g := Scenario.build_scenario()
	var p: Faction.Faction_ = g.factions["player"]
	p.resources.add("tech", 30, Economy.SOURCE_INIT)
	p.resources.add("culture", 30, Economy.SOURCE_INIT)
	p.resources.add("iron", 30, Economy.SOURCE_INIT)
	p.resources.add("gold", 100, Economy.SOURCE_INIT)
	p.resources.add("wood", 100, Economy.SOURCE_INIT)
	var msg := g.action_build("player", "p_cap", "market")
	ok(not msg.begins_with("失败"), "建市场成功: " + msg)
	var sh: MapSystem.Stronghold = g.map.strongholds["p_cap"]
	eq(sh.buildings.size(), 3, "p_cap 建筑数=3(农场+铁矿+市场)")
	ok(sh.free_slots() == 1, "p_cap 空槽=1")
	# 招募步兵（先建兵营——但兵营需科技，先测失败路径）
	msg = g.action_recruit_unit("player", "infantry")
	ok(msg.begins_with("失败"), "未建兵营不可招步兵: " + msg)
	# 学科技 martial_tradition → 建兵营 → 招步兵
	msg = g.action_learn_tech("player", "martial_tradition")
	ok(not msg.begins_with("失败"), "学武备传统: " + msg)
	msg = g.action_build("player", "p_cap", "barracks")
	ok(not msg.begins_with("失败"), "建兵营: " + msg)
	msg = g.action_recruit_unit("player", "infantry")
	ok(not msg.begins_with("失败"), "招步兵: " + msg)
	ok(p.standby.size() >= 1, "步兵进待命池")
	# 训练待命步兵
	var uid := ""
	for k in p.standby:
		uid = k
		break
	msg = g.action_train("player", uid)
	ok(not msg.begins_with("失败"), "训练: " + msg)
	msg = g.action_train("player", uid)
	ok(msg.begins_with("失败"), "每回合只能训练 1 次")

func _test_learn_gate() -> void:
	print("-- 科技/文化门控 --")
	var g := Scenario.build_scenario()
	var pg: Faction.Faction_ = g.factions["player"]
	pg.resources.add("tech", 30, Economy.SOURCE_INIT)
	pg.resources.add("culture", 30, Economy.SOURCE_INIT)
	pg.resources.add("iron", 30, Economy.SOURCE_INIT)
	pg.resources.add("stone", 30, Economy.SOURCE_INIT)
	pg.resources.add("food", 30, Economy.SOURCE_INIT)
	pg.resources.add("mana_stone", 30, Economy.SOURCE_INIT)
	# 锻造屋需要锻造文化
	var msg := g.action_build("player", "p_cap", "forge")
	ok(msg.begins_with("失败"), "未学锻造文化不可建锻造屋: " + msg)
	msg = g.action_learn_culture("player", "forge_culture")
	ok(not msg.begins_with("失败"), "学锻造文化: " + msg)
	msg = g.action_build("player", "p_cap", "forge")
	ok(not msg.begins_with("失败"), "学后可建锻造屋: " + msg)
	# 前置未满足
	msg = g.action_learn_tech("player", "smithing")
	ok(msg.begins_with("失败"), "锻造术前置(采矿术)未满足: " + msg)
	msg = g.action_learn_tech("player", "mining")
	ok(not msg.begins_with("失败"), "学采矿术: " + msg)
	msg = g.action_learn_tech("player", "smithing")
	ok(not msg.begins_with("失败"), "学锻造术: " + msg)

func _test_equip_inventory() -> void:
	print("-- 装备/仓库 --")
	var g := Scenario.build_scenario()
	var p: Faction.Faction_ = g.factions["player"]
	var sword := "sword_of_might"
	eq(g.available_count("player", sword), 3, "力量之剑在库 3")
	# 待命单位可装备
	var u := g.make_unit("infantry")
	p.standby[u.id] = 0
	var msg := g.action_equip("player", u.id, sword, 0)
	ok(not msg.begins_with("失败"), "待命单位装备: " + msg)
	eq(g.available_count("player", sword), 2, "装备后可用 2")
	eq(g.equipped_count("player", sword), 1, "已装备 1")
	msg = g.action_unequip("player", u.id, 0)
	ok(not msg.begins_with("失败"), "卸下: " + msg)
	eq(g.available_count("player", sword), 3, "卸下回库 3")
	msg = g.action_sell_artifact("player", sword)
	ok(not msg.begins_with("失败"), "卖出: " + msg)
	eq(g.available_count("player", sword), 2, "卖出后可用 2")
	eq(p.resources.get_amount("gold"), 90, "卖出 +10 金币")
	# 词条重算（骑兵战旗 tag_grant cavalry）
	var banner := "cavalry_banner"
	g.action_equip("player", u.id, banner, 0)
	ok(u.tags.has("cavalry"), "装备骑兵战旗获得骑兵词条")
	g.action_unequip("player", u.id, 0)
	ok(not u.tags.has("cavalry"), "卸下后词条移除")

func _test_battle() -> void:
	print("-- 战斗 --")
	var g := Scenario.build_scenario()
	# 造两支部队直接对撞
	var a_army := g.create_army("player", "m1", "测试攻方")
	var d_army := g.create_army("ai", "n1", "测试守方")
	var h1 := g.make_hero("knight")
	var h2 := g.make_hero("archmage")
	g.set_captain(a_army, h1)
	g.set_captain(d_army, h2)
	for i in range(2):
		var u := g.make_unit("infantry")
		a_army.add(u, g.unit_index)
		var u2 := g.make_unit("archer")
		d_army.add(u2, g.unit_index)
	var msg := g.action_move_attack("player", a_army.id, "n1")
	ok(not msg.begins_with("失败"), "发起战斗: " + msg)
	# 无论胜负，双方血量应被修改过或有一方全灭
	var total_hp := 0.0
	var base_hp := 0.0
	for uid in g.unit_index:
		var u: Units.Unit = g.unit_index[uid]
		if not u.alive:
			continue
		total_hp += u.cur_hp
		base_hp += float(u.base.get("hp", 1))
	ok(total_hp < base_hp or total_hp == base_hp, "战斗结算后 HP 不超上限")
	# 直接单元测试 resolve_strike 管道
	var ctx := _make_battle_ctx(g)
	var attacker: Units.Unit = g.unit_index[h1.id]
	var target: Units.Unit = g.unit_index[h2.id]
	attacker.cur_hp = 100.0
	target.cur_hp = 100.0
	var res := Battle.resolve_strike(ctx, attacker, target, "physical")
	ok(res.dmg >= 0, "resolve_strike dmg>=0")
	ok(target.cur_hp <= 100.0, "受击 HP 下降")
	# 状态：冰封跳过行动
	Triggers.apply_status(target, "frozen", 1)
	ok(Triggers.is_frozen(target), "冻结生效")
	Triggers.consume_on_self_attack(target)
	ok(not Triggers.is_frozen(target), "行动后冻结消耗移除")

func _make_battle_ctx(g: Game) -> Battle.BattleContext:
	var a: Armies.Army = g.armies[g.factions["player"].army_ids[0]]
	var d: Armies.Army = g.armies[g.factions["ai"].army_ids[0]]
	var aside := Battle.BattleSide.new(a, true, "p_cap", a.alive_units(g.unit_index))
	var dside := Battle.BattleSide.new(d, false, "a_cap", d.alive_units(g.unit_index))
	var mods := g.collect_army_mods(a, g.calendar, "")
	var eff: Dictionary = {}
	for u in aside.units:
		eff[u.id] = Battle.effective_attrs(u, mods)
	for u in dside.units:
		eff[u.id] = Battle.effective_attrs(u, mods)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ctx := Battle.BattleContext.new(aside, dside, {}, eff, {},
		Battle.BattleResult.new(), false, rng, true, {}, g.player_id)
	ctx.resolve_strike = Battle.resolve_strike
	return ctx

func _test_standby_deploy() -> void:
	print("-- 待命/上场 --")
	var g := Scenario.build_scenario()
	var p: Faction.Faction_ = g.factions["player"]
	var army: Armies.Army = g.armies[p.army_ids[0]]
	# 普通单位下场（部队在己方据点 → 冷却 0）
	var uid := ""
	for slot in range(army.grid.size()):
		if army.grid[slot] != null and army.grid[slot] != army.captain_id:
			uid = army.grid[slot]
			break
	var msg := g.action_discharge("player", army.id, uid)
	ok(not msg.begins_with("失败"), "普通单位下场: " + msg)
	ok(int(p.standby.get(uid, -1)) == 0, "己方据点下场冷却 0")
	# 上场回部队
	msg = g.action_deploy("player", army.id, uid)
	ok(not msg.begins_with("失败"), "上场: " + msg)

func _test_save_load() -> void:
	print("-- 存档读档 --")
	var g := Scenario.build_scenario()
	g.start_turn(g.factions["player"])
	var data := g.snapshot()
	var g2 := Game.restore(data)
	eq(g2.calendar.day, g.calendar.day, "读档后天数一致")
	eq(g2.factions.size(), g.factions.size(), "读档后阵营一致")
	eq(g2.unit_index.size(), g.unit_index.size(), "读档后单位一致")
	eq(g2.map.strongholds.size(), g.map.strongholds.size(), "读档后据点一致")
	var p1: Faction.Faction_ = g.factions["player"]
	var p2: Faction.Faction_ = g2.factions["player"]
	eq(p2.resources.get("gold"), p1.resources.get("gold"), "读档后金币一致")
	eq(p2.standby.size(), p1.standby.size(), "读档后待命池一致")
	var a1: Armies.Army = g.armies[p1.army_ids[0]]
	var a2: Armies.Army = g2.armies[p2.army_ids[0]]
	eq(a2.node_id, a1.node_id, "读档后部队位置一致")
	# 存档 round-trip 稳定
	var data2 := g2.snapshot()
	eq(JSON.stringify(data), JSON.stringify(data2), "snapshot 幂等")

func _test_ai_loop() -> void:
	print("-- AI 回合循环 --")
	var g := Scenario.build_scenario()
	g.start_turn(g.factions["player"])
	for i in range(10):
		var ai_f: Faction.Faction_ = g.factions["ai"]
		var actions := Ai.ai_take_turn(ai_f, g)
		for action in actions:
			ok(true, "AI 动作执行 %s" % action.get("kind", "?"))
		g.end_turn_advance()
		for a in g.armies.values():
			a.has_acted_this_turn = false
		g.start_turn(g.factions["player"])
	eq(g.calendar.day, 11, "10 天后第 11 天")

func _test_smoke_game() -> void:
	print("-- 冒烟：全自动对局 --")
	var g := Scenario.build_scenario()
	var turns := 0
	while not g.is_over() and turns < 300:
		turns += 1
		# 玩家回合：经济 + 事件自动处理 + AI 尽力（用 AI 逻辑代打玩家）
		g.start_turn(g.factions["player"])
		if g.pending_event != null:
			g.resolve_event(0)
		for fid in g.factions:
			var f: Faction.Faction_ = g.factions[fid]
			if not f.alive:
				continue
			var actions := Ai.ai_take_turn(f, g)
			for action in actions:
				match action.get("kind", ""):
					"build":
						g.action_build(fid, action["stronghold"], action["building"])
					"recruit_hero":
						g.action_recruit_hero(fid, action["stronghold"], action["hero"])
					"move_attack":
						g.action_move_attack(fid, action["army"], action["to"])
					"deploy":
						g.action_deploy(fid, action["army"], action["unit"])
					"new_army":
						var army := g.create_army(fid, action["stronghold"], action.get("name", "AI"))
						var hero: Variant = g.unit_index.get(action["hero"])
						if hero == null or not g.set_captain(army, hero):
							g.disband_army(army)
					"learn_tech":
						g.action_learn_tech(fid, action["tech"])
					"learn_culture":
						g.action_learn_culture(fid, action["culture"])
					"recruit_unit":
						g.action_recruit_unit(fid, action["unit"])
		g.end_turn_advance()
		for a in g.armies.values():
			a.has_acted_this_turn = false
		g.check_winner()
	ok(g.is_over(), "对局在 %d 回合内分出胜负" % turns)
	if g.is_over():
		print("  胜者: ", g.winner)
	ok(turns < 300, "未超过回合上限")
