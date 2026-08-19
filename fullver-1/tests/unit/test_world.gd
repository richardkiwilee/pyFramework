extends RefCounted
## =============================================================================
## 大地图模型测试（docs/00-design.md §8）
## 覆盖：寻路、邻接、移动校验（相邻/移动力）、占城、战斗触发与后果应用。
## 断言失败 = push_error（走引擎错误通道触发 FAIL，见 test_core.gd 头注释）。
## =============================================================================


func _fail(template: String, ...args: Array) -> void:
	push_error("[test_world] " + template.format(args, "{}"))


## 造状态：玩家 + 1 AI；城市从真实地图数据全量创建（22 座，邻接/寻路都真实）
## 归属覆盖：roma → 玩家，ragusa → ai1，其余保持地图数据归属
func _make_state() -> GameState:
	var gs := GameState.new()
	var p := Faction.new()
	p.id = "player"; p.is_player = true; p.resources = {"gold": 100}
	var ai := Faction.new()
	ai.id = "ai1"; ai.resources = {"gold": 100}
	gs.factions = [p, ai]
	for city_data in DataManager.get_map_cities():
		var c := City.new()
		c.id = city_data.get("id", "")
		c.name_zh = city_data.get("name_zh", "")
		c.name_en = city_data.get("name_en", "")
		c.x = float(city_data.get("x", 0.0))
		c.y = float(city_data.get("y", 0.0))
		c.type = city_data.get("type", "land")
		c.owner_faction_id = city_data.get("owner", "")
		gs.cities.append(c)
	# 测试专用归属覆盖（注意：ragusa 在地图数据里属 veneti，这里改给 ai1）
	gs.get_city("roma").owner_faction_id = "player"
	gs.get_city("ragusa").owner_faction_id = "ai1"
	return gs


## 造一个可移动军团（有编队）
func _make_army(gs: GameState, fid: String, city_id: String) -> Army:
	var a := Army.new()
	a.id = "army_%s_%s" % [fid, city_id]
	a.owner_faction_id = fid
	a.current_city_id = city_id
	a.max_move_points = 2
	a.move_points = 2
	a.team = Team.new()
	var u := Unit.new(); u.id = "u_%s_%s" % [fid, city_id]; u.character_id = "alain"
	a.team.set_unit(6, u)
	gs.armies.append(a)
	return a


## 邻接表：venezia 有 5 个邻接（v2 地图：aquileia/vindobona/roma/ragusa/constant）
func test_adjacency() -> void:
	var gs := _make_state()
	var model := WorldMapModel.new(gs)
	var neighbors: Array[String] = model.adjacent_city_ids("venezia")
	if neighbors.size() != 5:
		_fail("venezia 邻接数应为 5，实际 {}", neighbors)
	if "roma" not in model.adjacent_city_ids("ragusa"):
		_fail("roma-ragusa 应相邻")


## 寻路：roma → jerusalem 有路（途经链长度 > 2）；无路返回 []
func test_pathfinder() -> void:
	var gs := _make_state()
	# 完整地图数据下 roma→jerusalem 应可达
	var adj: Dictionary = {}
	var routes: Array = DataManager.get_map_data().get("routes", [])
	for r in routes:
		if not adj.has(r[0]): adj[r[0]] = []
		if not adj.has(r[1]): adj[r[1]] = []
		adj[r[0]].append(r[1])
		adj[r[1]].append(r[0])
	var pf := Pathfinder.new(adj)
	var path: Array[String] = pf.find_path("roma", "jerusalem")
	if path.is_empty() or path[0] != "roma" or path[path.size() - 1] != "jerusalem":
		_fail("roma→jerusalem 应可达，实际 {}", path)
	# 逐段校验：路径上相邻节点必须真的相邻
	for i in range(path.size() - 1):
		if path[i + 1] not in adj[path[i]]:
			_fail("路径段 {}-{} 不邻接", path[i], path[i + 1])
	# 不存在的城市：无路
	if not pf.find_path("roma", "narnia").is_empty():
		_fail("到不存在的城市应返回空路径")


## 移动：中立城占领 + 扣移动力 + 驻军更新
func test_move_into_neutral_city() -> void:
	var gs := _make_state()
	var model := WorldMapModel.new(gs)
	var army: Army = _make_army(gs, "player", "roma")
	var result: Dictionary = model.move_army(army, "venezia")
	if not result.get("ok", false):
		_fail("中立城移动应成功: {}", result)
	if army.current_city_id != "venezia" or army.move_points != 1:
		_fail("移动后应位于 venezia 且扣 1 移动力")
	var venezia: City = gs.get_city("venezia")
	if venezia.owner_faction_id != "player":
		_fail("中立城应被占领")
	if venezia.garrison_army_id != army.id:
		_fail("驻军应为移动军团")


## 移动校验：无移动力 / 不相邻 / 目标城有敌军 → 战斗请求
func test_move_validation_and_battle() -> void:
	var gs := _make_state()
	var model := WorldMapModel.new(gs)
	var my_army: Army = _make_army(gs, "player", "roma")
	# 不相邻（roma 与 nicosia 不相邻）→ 拒绝
	var bad: Dictionary = model.move_army(my_army, "nicosia")
	if bad.get("ok", true) or bad.get("reason", "") != "not_adjacent":
		_fail("不相邻城市应拒绝: {}", bad)
	# 无移动力 → 拒绝
	my_army.move_points = 0
	var no_mp: Dictionary = model.move_army(my_army, "venezia")
	if no_mp.get("ok", true):
		_fail("无移动力应拒绝")
	my_army.move_points = 2
	# 目标城有敌军：ragusa 放一个 AI 军团；玩家从 roma 直接到 ragusa（相邻）
	var enemy: Army = _make_army(gs, "ai1", "ragusa")
	var battle: Dictionary = model.move_army(my_army, "ragusa")
	if not battle.has("battle"):
		_fail("进入敌占城应返回战斗请求: {}", battle)
	if battle["battle"]["attacker_army_id"] != my_army.id or battle["battle"]["defender_army_id"] != enemy.id:
		_fail("战斗双方不对: {}", battle)
	# 战斗未发生前：不扣点、不移动
	if my_army.move_points != 2 or my_army.current_city_id != "roma":
		_fail("战斗前不应扣移动力/移动")


## 战斗后果：胜利 → 防守方解散 + 占城；失败 → 进攻方解散
func test_apply_battle_outcome() -> void:
	var gs := _make_state()
	var model := WorldMapModel.new(gs)
	var attacker: Army = _make_army(gs, "player", "roma")
	var defender: Army = _make_army(gs, "ai1", "ragusa")
	var battle := {"attacker_army_id": attacker.id, "defender_army_id": defender.id, "city_id": "ragusa"}
	# 胜利
	model.apply_battle_outcome(battle, {"result": "victory"})
	if gs.get_army(defender.id) != null:
		_fail("胜利后防守方应解散")
	if gs.get_city("ragusa").owner_faction_id != "player":
		_fail("胜利后应占领 ragusa")
	if attacker.current_city_id != "ragusa":
		_fail("胜利后进攻方应进驻 ragusa")
	# 再来一局测失败
	var gs2 := _make_state()
	var model2 := WorldMapModel.new(gs2)
	var a2: Army = _make_army(gs2, "player", "roma")
	var d2: Army = _make_army(gs2, "ai1", "ragusa")
	model2.apply_battle_outcome({"attacker_army_id": a2.id, "defender_army_id": d2.id, "city_id": "ragusa"}, {"result": "defeat"})
	if gs2.get_army(a2.id) != null:
		_fail("失败后进攻方应解散")
	if gs2.get_city("ragusa").owner_faction_id != "ai1":
		_fail("失败后城市归属不应变化")
	# 平局：双方保留
	var gs3 := _make_state()
	var model3 := WorldMapModel.new(gs3)
	var a3: Army = _make_army(gs3, "player", "roma")
	var d3: Army = _make_army(gs3, "ai1", "ragusa")
	model3.apply_battle_outcome({"attacker_army_id": a3.id, "defender_army_id": d3.id, "city_id": "ragusa"}, {"result": "draw"})
	if gs3.get_army(a3.id) == null or gs3.get_army(d3.id) == null:
		_fail("平局双方都应保留")


## 沿路径行军：多步移动直到移动力耗尽；途中遇敌返回战斗请求
func test_move_army_toward() -> void:
	var gs := _make_state()
	var model := WorldMapModel.new(gs)
	var army: Army = _make_army(gs, "player", "roma")
	# roma → salona 需要 2 步（roma→ragusa→salona）；移动力 2 → 走到终点
	army.max_move_points = 2
	army.move_points = 2
	var r: Dictionary = model.move_army_toward(army, "salona")
	if not r.get("ok", false):
		_fail("2 步内可达目标应成功: {}", str(r))
	if r.get("moves", []) != ["ragusa", "salona"]:
		# ⚠️ String.format 跳过 Array/Dictionary 值（占位符原样留下）——必须 str() 包裹
		_fail("行军路径应为 [ragusa, salona]，实际 {}", str(r.get("moves", [])))
	if army.move_points != 0:
		_fail("两步后移动力应为 0，实际 {}", army.move_points)
	# 移动力 1：只能走一步
	var gs2 := _make_state()
	var model2 := WorldMapModel.new(gs2)
	var army2: Army = _make_army(gs2, "player", "roma")
	army2.move_points = 1
	var r2: Dictionary = model2.move_army_toward(army2, "salona")
	if not r2.get("ok", false):
		_fail("部分行军也应返回 ok: {}", str(r2))
	if r2.get("moves", []) != ["ragusa"]:
		_fail("移动力 1 应只走一步到 ragusa，实际 {}", str(r2.get("moves", [])))
	# 途中遇敌：ragusa 有敌军 → 战斗请求，moves 为空（第一步就遇敌）
	var gs3 := _make_state()
	var model3 := WorldMapModel.new(gs3)
	var army3: Army = _make_army(gs3, "player", "roma")
	_make_army(gs3, "ai1", "ragusa")
	var r3: Dictionary = model3.move_army_toward(army3, "salona")
	if not r3.has("battle"):
		_fail("途中遇敌应返回战斗请求: {}", str(r3))
	if r3["battle"]["defender_army_id"] != "army_ai1_ragusa":
		_fail("战斗防守方不对: {}", str(r3))
	# 目标=当前城：already_there
	var r4: Dictionary = model3.move_army_toward(army3, "roma")
	if r4.get("reason", "") != "already_there":
		_fail("目标为当前城应返回 already_there: {}", str(r4))


## GameManager 集成：开局后 AI 回合真实执行移动（命令已接线）
func test_ai_move_integration() -> void:
	GameManager.new_game()
	var gs: GameState = GameManager.game_state
	if gs == null:
		_fail("new_game 失败")
		return
	# 记录 AI 军团初始位置
	var ai_positions: Dictionary = {}
	for a in gs.armies:
		if a.owner_faction_id != gs.player_faction().id:
			ai_positions[a.id] = a.current_city_id
	# 结束回合：AI 会移动（可能触发战斗——两种情况都合法）
	var result: Dictionary = GameManager.end_turn()
	if result.has("battle"):
		# 战斗中断：处理战斗结果（占城/解散）后续跑
		GameManager.resolve_battle_result({"result": "victory"})
	var moved_count := 0
	for a in gs.armies:
		if ai_positions.has(a.id) and a.current_city_id != ai_positions[a.id]:
			moved_count += 1
	# 至少一个 AI 军团动了（BasicAI 总是尝试向邻接目标移动）
	if moved_count == 0:
		_fail("结束回合后应有 AI 军团移动")
	if gs.turn < 2:
		_fail("回合应推进")
