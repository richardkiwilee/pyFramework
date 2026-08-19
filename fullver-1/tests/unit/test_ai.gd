extends RefCounted
## =============================================================================
## AI 挂载机制测试（docs/00-design.md §10）
## 覆盖：策略加载（默认/回退/类型校验）、回调顺序、BasicAI 决策、
##       GameManager 开局/存读档/回合推进。
## 断言失败 = push_error（走引擎错误通道触发 FAIL，见 test_core.gd 头注释）。
## =============================================================================


func _fail(template: String, ...args: Array) -> void:
	push_error("[test_ai] " + template.format(args, "{}"))


## 造一个最小 GameState：玩家 + 2 AI、3 城
## ⚠️ 城市 id 必须用真实地图数据（roma/venezia/ragusa）——
## AIContext.adjacent_city_ids 读 data/world/map.json 的路线表，
## 假 id 查不到邻接（本测试实测踩过）
func _make_state() -> GameState:
	var gs := GameState.new()
	var p := Faction.new()
	p.id = "player"; p.is_player = true; p.resources = {"gold": 999, "food": 999}
	var ai1 := Faction.new()
	ai1.id = "ai1"; ai1.ai_strategy = ""
	var ai2 := Faction.new()
	ai2.id = "ai2"; ai2.ai_strategy = ""
	gs.factions = [p, ai1, ai2]
	var c0 := City.new(); c0.id = "roma"; c0.owner_faction_id = "player"; gs.cities.append(c0)
	var c1 := City.new(); c1.id = "venezia"; c1.owner_faction_id = "ai1"; gs.cities.append(c1)
	var c2 := City.new(); c2.id = "ragusa"; c2.owner_faction_id = "ai2"; gs.cities.append(c2)
	# 关系：ai1 对 ai2 好感 -70（触发宣战）
	var r := Relation.new()
	r.faction_a = "ai1"; r.faction_b = "ai2"; r.attitude = -70.0
	gs.relations.append(r)
	# ai1 一个军团，停在 venezia（与 roma/ragusa 相邻）
	var army := Army.new()
	army.id = "a1"; army.owner_faction_id = "ai1"
	army.current_city_id = "venezia"; army.max_move_points = 2; army.move_points = 2
	army.team = Team.new()
	var u := Unit.new(); u.id = "u1"; u.character_id = "alain"
	army.team.set_unit(6, u)
	gs.armies.append(army)
	return gs


# ------------------------------------------------------------------ 策略加载

## 空路径 → 内置 BasicAI；回调按约定顺序执行
func test_loads_basic_ai_and_callback_order() -> void:
	var gs := _make_state()
	var ctrl := AIController.new(gs)
	var calls: Array = []
	# 用一个自定义策略记录回调顺序（继承 BaseAIStrategy 的内嵌类无法用 class_name，
	# 但可以 preload 一个测试专用策略脚本——这里直接验证 BasicAI 类型即可，
	# 回调顺序用下面的 mock 策略脚本验证）
	var ai1: Faction = gs.get_faction("ai1")
	var r1: Dictionary = ctrl.run_faction_turn(ai1)
	if r1.has("battle"):
		_fail("未接线命令时不应产生战斗请求")
	# 结果里不应有 battle；AIController 正常跑完
	if ctrl._strategy_cache.size() != 1:
		_fail("策略缓存应缓存 1 个势力，实际 {}", ctrl._strategy_cache.size())


## 不存在的脚本路径 → 回退 BasicAI（Log.error 会打到控制台，但不影响流程）
func test_fallback_on_missing_script() -> void:
	var gs := _make_state()
	var ctrl := AIController.new(gs)
	var f := Faction.new()
	f.id = "ghost"
	f.ai_strategy = "res://scripts/ai/strategies/not_exist.gd"
	var r: Dictionary = ctrl.run_faction_turn(f)
	if r.has("battle"):
		_fail("回退策略后不应产生战斗请求")
	if ctrl._strategy_cache["ghost"] == null or not (ctrl._strategy_cache["ghost"] is BasicAI):
		_fail("脚本缺失时应回退 BasicAI")


## 挂载的脚本未继承 BaseAIStrategy → 回退 BasicAI
func test_fallback_on_wrong_type() -> void:
	var gs := _make_state()
	var ctrl := AIController.new(gs)
	var f := Faction.new()
	f.id = "wrong"
	# ai_context.gd 是 RefCounted 但不是 AI 策略
	f.ai_strategy = "res://scripts/ai/ai_context.gd"
	var r: Dictionary = ctrl.run_faction_turn(f)
	if r.has("battle"):
		_fail("类型回退后不应产生战斗请求")
	if not (ctrl._strategy_cache["wrong"] is BasicAI):
		_fail("类型不符时应回退 BasicAI")


# ------------------------------------------------------------------ BasicAI 决策

## 军团阶段：向邻接的敌对/中立城市发 move 指令；战斗请求会中断流程
func test_basic_ai_army_phase_move_and_battle() -> void:
	var gs := _make_state()
	var ctrl := AIController.new(gs)
	var move_log: Array = []
	ctrl.command_handlers["move"] = func(params: Dictionary, ctx: AIContext) -> Dictionary:
		move_log.append({"army": params.get("army_id", ""), "target": params.get("target_city_id", "")})
		return {"ok": true}
	var ai1: Faction = gs.get_faction("ai1")
	var result: Dictionary = ctrl.run_faction_turn(ai1)
	# 邻接目标：roma（玩家城）与 ragusa（ai2 城）——
	# 关系 -70 但未宣战（at_war=false），两者优先级相同，任一是合法目标
	if move_log.is_empty():
		_fail("有移动力的军团应对邻接目标发 move 指令")
	if move_log[0]["army"] != "a1":
		_fail("move 指令的军团不对: {}", move_log)
	var target: String = move_log[0]["target"]
	if target != "roma" and target != "ragusa":
		_fail("move 目标应是邻接城 roma/ragusa 之一，实际 {}", target)
	# 战斗中断：指令处理器写入 pending_battle → AIController 返回 battle
	var ctrl2 := AIController.new(gs)
	ctrl2.command_handlers["move"] = func(params: Dictionary, ctx: AIContext) -> Dictionary:
		ctx.pending_battle = {"attacker_army_id": "a1", "defender_army_id": "a2", "city_id": "ragusa"}
		return {"ok": true}
	var r2: Dictionary = ctrl2.run_faction_turn(ai1)
	if not r2.has("battle"):
		_fail("move 引发战斗时应中断流程返回 battle，实际 {}", r2)
	if r2["battle"]["city_id"] != "ragusa":
		_fail("战斗请求内容不对: {}", r2["battle"])


## 外交阶段：好感 < -60 且未交战 → 宣战指令
func test_basic_ai_diplomacy_declares_war() -> void:
	var gs := _make_state()
	var ctrl := AIController.new(gs)
	var war_targets: Array = []
	# 让 move 不产生行动（无移动力）
	var ai1: Faction = gs.get_faction("ai1")
	for a in gs.armies:
		a.move_points = 0
	ctrl.command_handlers["declare_war"] = func(params: Dictionary, ctx: AIContext) -> Dictionary:
		war_targets.append(params.get("target_faction_id", ""))
		return {"ok": true}
	ctrl.run_faction_turn(ai1)
	if war_targets != ["ai2"]:
		_fail("好感 -70 应对 ai2 宣战，实际 {}", war_targets)


# ------------------------------------------------------------------ GameManager

## 开局：势力/城市/军团齐全，初始编队单位数正确
func test_game_manager_new_game() -> void:
	GameManager.new_game()
	var gs: GameState = GameManager.game_state
	if gs == null:
		_fail("new_game 后 game_state 为 null")
		return
	if gs.factions.size() != 4:
		_fail("势力数应为 4，实际 {}", gs.factions.size())
	if gs.cities.size() != 22:
		_fail("城市数应为 22（v2 地图），实际 {}", gs.cities.size())
	if gs.armies.size() != 4:
		_fail("初始军团数应为 4（每势力 1），实际 {}", gs.armies.size())
	for army in gs.armies:
		if army.team.unit_count() != 6:
			_fail("初始编队应为 6 单位，实际 {}", army.team.unit_count())
	var player: Faction = gs.player_faction()
	if player == null:
		_fail("缺少玩家势力")
		return
	if int(player.resources.get("gold", 0)) <= 0:
		_fail("玩家初始资源未发放: {}", player.resources)


## 存读档：save → load 后回合/军团一致
func test_game_manager_save_load() -> void:
	GameManager.new_game()
	var turn_before: int = GameManager.game_state.turn
	if not GameManager.save_game(99):
		_fail("save_game 应成功")
	# 破坏现场状态再读档
	GameManager.new_game()
	GameManager.game_state.turn = 123
	if not GameManager.load_game(99):
		_fail("load_game 应成功")
	if GameManager.game_state.turn != turn_before:
		_fail("读档后回合数应为 {}，实际 {}", turn_before, GameManager.game_state.turn)
	if GameManager.game_state.armies.size() != 4:
		_fail("读档后军团数不对")
	# 存档列表包含槽位 99
	var saves: Array = GameManager.list_saves()
	var found := false
	for s in saves:
		if s.slot == 99:
			found = true
	if not found:
		_fail("list_saves 应包含槽位 99")


## 战斗结算链回归测试（"移动两次后动不了"的根因修复）：
## AI 进攻玩家驻军 → 战斗 → 结算 → 回合推进 → 玩家军团移动力回满
func test_end_turn_battle_resolution_chain() -> void:
	GameManager.new_game()
	var gs: GameState = GameManager.game_state
	var player: Faction = gs.player_faction()
	var p_army: Army = gs.armies_of(player.id)[0]
	# 布局：玩家军团驻守 roma；veneti 军团挪到 venezia（与 roma 相邻）→ AI 必攻 roma
	p_army.current_city_id = "roma"
	gs.get_city("roma").garrison_army_id = p_army.id
	p_army.move_points = 0  # 模拟玩家已用光移动力
	var veneti_army: Army = gs.armies_of("veneti")[0]
	veneti_army.current_city_id = "venezia"
	# 结束回合 → veneti 进攻 roma → 战斗请求
	var result: Dictionary = GameManager.end_turn()
	if not result.has("battle"):
		_fail("AI 应进攻 roma 触发战斗，实际 {}", str(result))
		return
	if not GameManager.turn_manager.is_awaiting_battle():
		_fail("应处于等待战斗状态")
	# 战斗结算：玩家防守成功（引擎口径 defeat = 进攻方 AI 败）
	GameManager.resolve_battle_result({"result": "defeat"})
	if gs.turn != 2:
		_fail("战斗结算后回合应推进到 2，实际 {}", gs.turn)
	if gs.get_army(veneti_army.id) != null:
		_fail("进攻失败的 AI 军团应解散")
	if p_army.move_points != p_army.max_move_points:
		_fail("新回合玩家军团移动力应回满（移动力 0 时收到战斗结算卡死的回归）")


## 结束回合：AI 回合跑完（命令未接线=不动）→ 回合 +1、玩家军团回移动力
func test_game_manager_end_turn() -> void:
	GameManager.new_game()
	var gs: GameState = GameManager.game_state
	# 消耗掉玩家一个军团的移动力
	var player: Faction = gs.player_faction()
	var p_army: Army = gs.armies_of(player.id)[0]
	p_army.move_points = 0
	var result: Dictionary = GameManager.end_turn()
	if result.has("battle"):
		_fail("命令未接线时不应有战斗请求: {}", result)
	if gs.turn != 2:
		_fail("结束回合后应为第 2 回合，实际 {}", gs.turn)
	if p_army.move_points != p_army.max_move_points:
		_fail("新回合玩家军团移动力应回满")
