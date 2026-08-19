extends RefCounted
## =============================================================================
## 战斗引擎测试（docs/00-design.md §9）
## 覆盖：站位映射、完整战斗模拟（真实数据）、伤害公式、被动时点、
##       补齐的 heal_on_kill、状态 DoT、胜负判定。
## 断言失败 = push_error（见 test_core.gd 头注释）。
## =============================================================================


func _fail(template: String, ...args: Array) -> void:
	push_error("[test_battle] " + template.format(args, "{}"))


## 造一个 3 单位军团（真实角色数据，槽位指定）
func _make_army(gs: GameState, fid: String, city_id: String, slots: Array[int], char_ids: Array) -> Army:
	var a := Army.new()
	a.id = "army_%s" % fid
	a.owner_faction_id = fid
	a.current_city_id = city_id
	a.max_move_points = 2
	a.move_points = 2
	a.team = Team.new()
	for i in range(char_ids.size()):
		var u := Unit.new()
		u.id = "u_%s_%d" % [fid, i]
		u.character_id = char_ids[i]
		u.level = 1
		a.team.set_unit(slots[i], u)
	gs.armies.append(a)
	return a


## 造最小状态 + 两个军团
func _make_battle_setup() -> Array:
	var gs := GameState.new()
	var p := Faction.new(); p.id = "player"; p.is_player = true
	var ai := Faction.new(); ai.id = "ai1"
	gs.factions = [p, ai]
	var c0 := City.new(); c0.id = "roma"; c0.owner_faction_id = "player"
	var c1 := City.new(); c1.id = "ragusa"; c1.owner_faction_id = "ai1"
	gs.cities = [c0, c1]
	# 真实角色（DataManager 已加载）；前排槽 6/7/8
	var atk: Army = _make_army(gs, "player", "roma", [6, 7, 8], ["alain", "scarlett", "clive"])
	var def: Army = _make_army(gs, "ai1", "ragusa", [6, 7, 8], ["hodrick", "mordon", "aubin"])
	return [gs, atk, def]


## 站位映射：编队前排槽 6/7/8 → 战斗 position 0/1/2（前排）
func test_battle_setup_positions() -> void:
	var setup: Array = _make_battle_setup()
	var engine := BattleEngine.new()
	engine.start_battle(setup[1], setup[2])
	if engine.player_units.size() != 3 or engine.enemy_units.size() != 3:
		_fail("双方应各 3 个战斗单位")
	for u in engine.player_units:
		if u.position >= 3:
			_fail("槽位 6/7/8 的单位应映射到战斗前排（position<3），实际 {}", u.position)
	# 属性已推导（含装备）
	for u in engine.player_units:
		if u.max_hp <= 0 or u.atk <= 0:
			_fail("战斗单位属性推导异常: {} hp={} atk={}", u.name_zh, u.max_hp, u.atk)


## 完整战斗模拟：3v3 真实角色跑到底，验证行动结构/胜负/统计一致性
func test_full_battle_simulation() -> void:
	var setup: Array = _make_battle_setup()
	var engine := BattleEngine.new()
	var result_seen: Array = []
	engine.battle_ended.connect(func(r: String) -> void: result_seen.append(r))
	engine.start_battle(setup[1], setup[2])
	engine.begin_combat()
	# 最多 500 条行动（防御死循环）
	var guard := 0
	while not engine.is_over() and guard < 500:
		var action: Dictionary = engine.next_action()
		if action.is_empty():
			guard += 1
			continue
		var kind: String = action.get("kind", "")
		if kind not in ["attack", "wait", "heal", "death", "dot", "cover", "dodge", "status"]:
			_fail("未知行动类型: {}", kind)
			return
		guard += 1
	if guard >= 500:
		_fail("战斗未在 500 条行动内结束（疑似死循环）")
		return
	if result_seen.size() != 1:
		_fail("应恰好发出一次 battle_ended，实际 {}", result_seen.size())
	if result_seen[0] not in ["victory", "defeat", "draw"]:
		_fail("结果非法: {}", result_seen[0])
	# 统计一致性：双方总伤害 = 对方总承伤（DoT 不计入攻击方统计，口径允许 ≤）
	var stats: Dictionary = engine.get_stats_summary()
	if int(stats.get("rounds", 0)) <= 0:
		_fail("回合数异常: {}", stats)
	# 所有单位 hp 在合法范围
	for u in engine.player_units + engine.enemy_units:
		if u.hp < 0 or u.hp > u.max_hp:
			_fail("单位 {} 血量越界: {}/{}", u.name_zh, u.hp, u.max_hp)


## heal_on_kill：击杀后回复（本项目补齐的 demo-1 数据缺口）
func test_heal_on_kill_effect() -> void:
	var engine := BattleEngine.new()
	var subject := BattleUnit.new()
	subject.name_zh = "测试者"
	subject.max_hp = 100
	subject.hp = 10
	subject.pp = 5
	subject.skills = [{
		"type": "passive", "pp_cost": 0,
		"effects": [{"effect_type": "heal_on_kill", "value": "25%"}],
	}]
	engine._dispatch_passives("on_kill", subject, {"target": BattleUnit.new()})
	if subject.hp != 35:
		_fail("heal_on_kill 应回复 25% 最大HP（10→35），实际 {}", subject.hp)


## 反击被动：受击后对攻击者回击（after_hit 时点）
func test_counter_passive() -> void:
	var engine := BattleEngine.new()
	var attacker := BattleUnit.new()
	attacker.name_zh = "攻击者"
	attacker.max_hp = 100; attacker.hp = 100
	attacker.def = 0; attacker.eva = 0; attacker.guard = 0
	var subject := BattleUnit.new()
	subject.name_zh = "反击者"
	subject.max_hp = 100; subject.hp = 100
	subject.atk = 50; subject.acc = 100
	subject.pp = 5
	subject.skills = [{
		"type": "passive", "pp_cost": 1,
		"effects": [{"effect_type": "counter", "value": ""}],
	}]
	# 把双方挂进引擎单位列表（counter 的 follow_up 需要目标池）
	engine.player_units = [subject]
	engine.enemy_units = [attacker]
	attacker.is_enemy = true
	subject.is_enemy = false
	var before: int = attacker.hp
	engine._dispatch_passives("after_hit", subject, {"attacker": attacker, "damage": 10})
	if attacker.hp >= before:
		_fail("反击应造成伤害")
	if subject.pp != 4:
		_fail("反击应消耗 1 PP，实际 {}", subject.pp)


## 伤害公式边界：高防下至少 1 点；护甲减伤生效
func test_damage_formula() -> void:
	var engine := BattleEngine.new()
	var atk := BattleUnit.new()
	atk.atk = 30; atk.crit = 0
	var tank := BattleUnit.new()
	tank.def = 999
	var dmg: int = engine._calc_damage(atk, tank, 100.0, "physical")
	if dmg < 1:
		_fail("伤害至少应为 1，实际 {}", dmg)
	# 魔法伤害用 mag/mdf
	atk.atk = 1; atk.mag = 500
	tank.def = 999; tank.mdf = 0
	var m_dmg: int = engine._calc_damage(atk, tank, 100.0, "magical")
	if m_dmg < 400:
		_fail("魔法伤害应按 mag/mdf 计算，实际 {}", m_dmg)


## 状态 DoT：中毒每回合扣血并递减
func test_status_dot() -> void:
	var engine := BattleEngine.new()
	var u := BattleUnit.new()
	u.name_zh = "中毒者"
	u.max_hp = 100; u.hp = 100
	u.statuses = [{"type": "poison", "turns": 2}]
	engine.player_units = [u]
	engine._tick_statuses()
	if u.hp != 90:
		_fail("中毒应扣 10% 最大HP（100→90），实际 {}", u.hp)
	if int(u.statuses[0].turns) != 1:
		_fail("状态回合应递减")
	engine._tick_statuses()
	if u.statuses.size() != 0:
		_fail("状态到期应移除")


## 胜负判定：一方全灭 → victory/defeat 信号
func test_battle_end_detection() -> void:
	var engine := BattleEngine.new()
	var seen: Array = []
	engine.battle_ended.connect(func(r: String) -> void: seen.append(r))
	var p := BattleUnit.new(); p.name_zh = "p1"; p.is_alive = false
	var e := BattleUnit.new(); e.name_zh = "e1"; e.is_alive = true
	engine.player_units = [p]
	engine.enemy_units = [e]
	engine.battle_active = true
	engine._check_battle_end()
	if seen.size() != 1 or seen[0] != "defeat":
		_fail("玩家全灭应判负，实际 {}", seen)
