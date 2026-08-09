## 场景装配（对应 pydemo/cli/scenario.py）：双首都双路径小地图 + 玩家/AI 初始状态。
class_name Scenario
extends RefCounted

const SCENARIO_SEED := 20260804

static func build_scenario() -> Game:
	var game := Game.new({}, SCENARIO_SEED)

	# 据点（size 整数槽位；landmark 独立专用槽；首都 medium、中立 weak）
	var p_cap := MapSystem.Stronghold.new("p_cap", "玩家首都", 4, "player", true,
		_landmark(game, "lm_medium"), 0, 0)
	var a_cap := MapSystem.Stronghold.new("a_cap", "AI首都", 4, "ai", true,
		_landmark(game, "lm_medium"), 8, 0)
	var n1 := MapSystem.Stronghold.new("n1", "中央堡", 1, "", false,
		_landmark(game, "lm_weak"), 4, 0)
	var n2 := MapSystem.Stronghold.new("n2", "南境堡", 1, "", false,
		_landmark(game, "lm_weak"), 6, 2)
	for s in [p_cap, a_cap, n1, n2]:
		game.map.add_stronghold(s)

	# 小地点
	game.map.add_minor(MapSystem.MinorLocation.new("m1", "路口", "plains", 2, 0))
	game.map.add_minor(MapSystem.MinorLocation.new("m2", "隘口", "mountain", 6, 0))
	game.map.add_minor(MapSystem.MinorLocation.new("m3", "林道", "forest", 5, 1))
	game.map.add_minor(MapSystem.MinorLocation.new("m4", "南道", "plains", 7, 2))

	# 连边（双路径）
	var edges: Array = [
		["p_cap", "m1"], ["m1", "n1"], ["n1", "m2"], ["m2", "a_cap"],
		["n1", "m3"], ["m3", "n2"], ["n2", "m4"], ["m4", "a_cap"],
	]
	for e in edges:
		game.map.add_edge(e[0], e[1])
	# 道路（坐标对 + 曲线信息）：沿主路轻微起伏，南线反向弯曲以示区分
	var curves := [0.12, -0.10, 0.10, -0.12, 0.14, -0.12, 0.10, -0.10]
	for i in range(edges.size()):
		game.map.add_road(edges[i][0], edges[i][1], curves[i])

	# 阵营
	var player := game.add_faction("player", "玩家", false)
	var ai := game.add_faction("ai", "敌方AI", true)
	player.capital_id = "p_cap"
	ai.capital_id = "a_cap"
	player.stronghold_ids = ["p_cap"]
	ai.stronghold_ids = ["a_cap"]
	# 初始信念（使对应英雄可达招募门槛）
	player.belief.values = {"morality": 20, "utility": 0, "liberty": 0}
	ai.belief.values = {"morality": 0, "utility": 20, "liberty": 0}
	# 初始资源
	for fid in ["player", "ai"]:
		var f: Faction.Faction_ = game.factions[fid]
		f.resources = Economy.Resources.new({
			"gold": 80, "food": 30, "wood": 30, "stone": 10, "iron": 10,
			"mana_stone": 15, "tech": 0, "culture": 5, "faith": 0,
			"luxury": 0, "decree": 0,
		})
	# 初始建筑：首都各一个农场；玩家送铁矿井、AI 送魔石矿
	for cap_id in ["p_cap", "a_cap"]:
		var cap: MapSystem.Stronghold = game.map.strongholds[cap_id]
		cap.add_building(MapSystem.Building.new("b_farm_start", "farm", "农场", {"food": 5}))
	game.map.strongholds["p_cap"].add_building(
		MapSystem.Building.new("b_iron_start", "iron_mine", "铁矿井", {"iron": 5}))
	game.map.strongholds["a_cap"].add_building(
		MapSystem.Building.new("b_mana_start", "mana_mine", "魔石矿", {"mana_stone": 3}))
	# 初始装备库存：玩家每种 3 件（AI 不用装备）
	for def_id in game.artifact_defs:
		game.add_artifact_stock(def_id, "player", 3)
	game.log_msg("玩家仓库初始装备:%d 件" % (game.artifact_defs.size() * 3))

	# 玩家初始英雄 + 部队
	var hero := game.make_hero("knight")
	player.hero_ids.append(hero.id)
	var army := game.create_army("player", "p_cap", "先锋军")
	game.set_captain(army, hero)
	for i in range(2):
		var u := game.make_unit("infantry")
		u.node_id = "p_cap"
		army.add(u, game.unit_index)

	# AI 初始英雄 + 部队
	var ai_hero := game.make_hero("archmage")
	ai.hero_ids.append(ai_hero.id)
	var ai_army := game.create_army("ai", "a_cap", "AI守备军")
	game.set_captain(ai_army, ai_hero)
	for i in range(2):
		var u := game.make_unit("archer")
		u.node_id = "a_cap"
		ai_army.add(u, game.unit_index)

	# 招募池初始化
	for fid in game.factions:
		var f: Faction.Faction_ = game.factions[fid]
		for sid in f.stronghold_ids:
			var pool := Heroes.RecruitmentPool.new(sid)
			pool.refresh(game.hero_defs.keys(), game.calendar.day, 14, game.rng)
			f.recruitment_pools[sid] = pool

	game.log_msg("场景就绪:玩家首都 vs AI首都,中央堡/南境堡为中立据点")
	return game

static func _landmark(game: Game, type_id: String) -> MapSystem.Building:
	var bdef: Dictionary = game.building_defs.get(type_id, {})
	return MapSystem.Building.new("lm_%s" % type_id, type_id,
		Game.cn_building(bdef), {}, bdef.get("tier", "weak"))
