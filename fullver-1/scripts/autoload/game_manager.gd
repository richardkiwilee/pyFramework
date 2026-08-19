extends Node
## =============================================================================
## GameManager — 自动加载(Autoload)单例，游戏流程编排
## =============================================================================
## 职责（docs/00-design.md §5.5）：
##   - 持有 GameState（跨场景数据桥，autoload 本身不存业务数据）
##   - 组装 TurnManager / AIController / 各系统，管理回合流程
##   - 存读档（user://saves/slot_N.json）
##   - 场景编排（SceneHelper 转场）与全局信号广播
##   - 战斗打断点的调度：AI/玩家行动引发战斗 → 发 battle_requested →
##     战斗场景结束后 resolve_battle_result() 续跑回合流程
##
## 注意：本类不做领域计算——移动校验在世界模型、外交规则在外交系统、
## 战斗结算在战斗引擎；GameManager 只做"接线与编排"。
##
## 类比 Python：
##   相当于应用的"组装根"（composition root）：依赖注入 + 生命周期编排。
## =============================================================================

# ------------------------------------------------------------------ 全局信号
## 新回合开始（玩家可操作）
signal turn_started(turn: int)
## 玩家结束了自己的回合（AI 回合开始前）
signal turn_ended(turn: int)
## 全局游戏事件（外交/战斗/经济等一切值得展示的事件）
signal game_event(kind: String, data: Dictionary)
## 新游戏或读档完成
signal game_started()
## 一场战斗被请求（携带 {attacker_army_id, defender_army_id, city_id}）
## 世界地图场景监听此信号切战斗场景
signal battle_requested(battle: Dictionary)

# ------------------------------------------------------------------ 运行时对象
## 当前游戏状态（null = 主菜单未开局）
var game_state: GameState = null

## 回合流程编排器（每次开局/读档重建）
var turn_manager: TurnManager = null

## AI 策略调度器（每次开局/读档重建）
var ai_controller: AIController = null

## 挂起中的战斗请求（resolve_battle_result 使用）
var pending_battle: Dictionary = {}

## 世界模型（P4 接线：移动规则/寻路/战斗后果）
var world_model: WorldMapModel = null

## 外交系统（P5）
var diplomacy_system: DiplomacySystem = null

## 经济系统（P5）
var economy_system: EconomySystem = null

## 城市管理/部队编辑场景的上下文（世界场景选择后跨场景传递）
var selected_city_id: String = ""

# ------------------------------------------------------------------ 系统接线位
## 战斗后果处理器：func(battle: Dictionary, result: Dictionary) -> void
## P4 由 WorldMapModel 接线（占城/解散军团），P8 由世界场景触发
var battle_outcome_handler: Callable = Callable()

## 结算处理器：func() -> Dictionary（P5 接线 EconomySystem + DiplomacySystem）
## P5 就绪前为空实现（回合照常推进，只是不结算经济/条约）
var settle_handler: Callable = Callable()


func _ready() -> void:
	# 开局/读档时才构建系统（见 _rebuild_systems）。
	# Autoload 启动时 game_state 为 null，什么都不做。
	pass


# ==================================================================
#  开局 / 存读档
# ==================================================================

## ---------------------------------------------------------------------------
## new_game() — 从数据构建全新游戏
## ---------------------------------------------------------------------------
## 构建内容（数据全部来自 data/*.json）：
##   1. 势力（含玩家，初始资源 = factions.json 的 starting_resources）
##   2. 城市（归属按 world/map.json 的 owner）
##   3. 每势力 1 个初始军团（6 单位随机编成 + 随机配装）
##   4. 全势力两两关系初始化为 0（DiplomacySystem 后续演进）
## ---------------------------------------------------------------------------
func new_game() -> void:
	var gs := GameState.new()
	gs.turn = 1

	# --- 1. 势力 ---
	for fid in DataManager.get_all_faction_ids():
		var fd: Dictionary = DataManager.get_faction(fid)
		var f := Faction.new()
		f.id = fid
		f.name_zh = fd.get("name_zh", fid)
		f.name_en = fd.get("name_en", fid)
		f.is_player = bool(fd.get("is_player", false))
		f.ai_strategy = fd.get("ai_strategy", "")
		# 初始资源（所有势力同一起跑线）；预期量 = 初始值（外交贸易评分基准）
		var start_res: Dictionary = DataManager.get_factions_config().get("starting_resources", {})
		for res_id in start_res:
			f.resources[res_id] = int(start_res[res_id])
			f.expectations[res_id] = int(start_res[res_id])
		gs.factions.append(f)

	# --- 2. 城市 ---
	for city_data in DataManager.get_map_cities():
		var c := City.new()
		c.id = city_data.get("id", "")
		c.name_zh = city_data.get("name_zh", "")
		c.name_en = city_data.get("name_en", "")
		c.x = float(city_data.get("x", 0.0))
		c.y = float(city_data.get("y", 0.0))
		c.type = city_data.get("type", "land")
		c.owner_faction_id = city_data.get("owner", "")
		c.level = 1
		gs.cities.append(c)

	# --- 3. 初始军团（复用经济系统的征募逻辑，免费）---
	var team_size: int = int(DataManager.get_factions_config().get("army_team_size", 6))
	for faction in gs.factions:
		var faction_cities: Array[City] = gs.cities_of(faction.id)
		if faction_cities.is_empty():
			continue
		var econ := EconomySystem.new(gs)
		econ.recruit_army(faction, faction_cities[0], team_size, true)

	# --- 4. 初始关系（两两中性）---
	var ids: Array[String] = []
	for f in gs.factions:
		ids.append(f.id)
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var r := Relation.new()
			r.faction_a = a
			r.faction_b = b
			gs.relations.append(r)

	# 接管状态并重建系统
	game_state = gs
	_rebuild_systems()
	gs.add_event("turn_start", {})
	game_started.emit()
	turn_started.emit(gs.turn)


## 从存档槽位读档。返回是否成功。
func load_game(slot: int) -> bool:
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		Log.info("[GameManager] 存档不存在: {}", path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		Log.error("[GameManager] 存档解析失败: {}", path)
		return false
	var gs: GameState = GameState.from_dict(json.get_data())
	if gs == null:
		Log.error("[GameManager] 存档版本不兼容: {}", path)
		return false
	game_state = gs
	_rebuild_systems()
	game_started.emit()
	turn_started.emit(gs.turn)
	return true


## 保存当前游戏到槽位。无进行中游戏或写盘失败返回 false。
func save_game(slot: int) -> bool:
	if game_state == null:
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(_save_path(slot), FileAccess.WRITE)
	if file == null:
		Log.error("[GameManager] 无法写入存档: {}", _save_path(slot))
		return false
	# JSON.stringify(value, indent) — indent "\t" 让存档可读
	file.store_string(JSON.stringify(game_state.to_dict(), "\t"))
	return true


## 扫描存档目录，返回 [{slot: int, turn: int}, ...]（按槽位号排序）
func list_saves() -> Array:
	var result: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("slot_") and file_name.ends_with(".json"):
			var slot: int = int(file_name.substr(5, file_name.length() - 10))
			var text := FileAccess.get_file_as_string(SAVE_DIR + "/" + file_name)
			var turn := 0
			var json := JSON.new()
			if json.parse(text) == OK:
				var data: Dictionary = json.get_data()
				turn = int(data.get("turn", 0))
			result.append({"slot": slot, "turn": turn})
		file_name = dir.get_next()
	result.sort_custom(func(a, b): return a.slot < b.slot)
	return result


## 是否有进行中的游戏（主菜单"继续"按钮用）
func has_current_game() -> bool:
	return game_state != null


# ==================================================================
#  回合流程（对接 TurnManager）
# ==================================================================

## 玩家点"结束回合"。返回 TurnManager 的结果（可能携带战斗请求）。
func end_turn() -> Dictionary:
	if game_state == null or turn_manager == null:
		return {}
	turn_ended.emit(game_state.turn)
	var result: Dictionary = turn_manager.run_player_end_turn()
	_handle_turn_result(result)
	return result


## 战斗场景结束后调用：应用战斗后果 → 续跑回合流程
func resolve_battle_result(battle_result: Dictionary) -> void:
	if game_state == null or turn_manager == null:
		return
	# 1. 后果应用（占城/解散军团等，P4 接线）
	if pending_battle.size() > 0 and battle_outcome_handler.is_valid():
		battle_outcome_handler.call(pending_battle, battle_result)
	pending_battle = {}
	# 2. 续跑（可能再请求一场战斗）
	var resumed: Dictionary = turn_manager.resume_after_battle(battle_result)
	_handle_turn_result(resumed)


## 处理 TurnManager 返回结果：战斗请求 → 挂起 + 广播
func _handle_turn_result(result: Dictionary) -> void:
	if result.has("battle"):
		pending_battle = result.get("battle", {})
		battle_requested.emit(pending_battle)


# ==================================================================
#  场景编排与事件
# ==================================================================

## 带转场切换场景（zfoo SceneHelper，默认淡入淡出）
## 调用方用 await GameManager.change_scene(...) 等待切换完成
func change_scene(scene_path: String) -> void:
	await SceneHelper.async_change_scene_to_file(scene_path)


## 追加游戏事件：写 GameState 日志 + 广播信号（UI 消息面板订阅）
func add_event(kind: String, data: Dictionary = {}) -> void:
	if game_state == null:
		return
	game_state.add_event(kind, data)
	game_event.emit(kind, data)


## 玩家新回合开始的默认收尾（TurnManager 的 advance 回调）：
## 玩家军团回满移动力 + 回合事件 + 信号
func _default_advance() -> void:
	if game_state == null:
		return
	var player := game_state.player_faction()
	if player != null:
		for army in game_state.armies_of(player.id):
			army.refresh_move_points()
	game_state.add_event("turn_start", {})
	turn_started.emit(game_state.turn)


## TurnManager 的 settle 回调（P5 前为空实现）
func _default_settle() -> Dictionary:
	# P5：EconomySystem.settle_turn(game_state) + DiplomacySystem.tick_treaties(game_state)
	return {}


# ==================================================================
#  内部：系统组装与辅助
# ==================================================================

const SAVE_DIR := "user://saves"


func _save_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


## 开局/读档后重建系统对象（TurnManager/AIController 持有旧状态引用，必须重建）
func _rebuild_systems() -> void:
	# 系统层实例（P4 世界 / P5 外交经济）
	world_model = WorldMapModel.new(game_state)
	diplomacy_system = DiplomacySystem.new(game_state)
	economy_system = EconomySystem.new(game_state)
	# AI 指令接线
	ai_controller = AIController.new(game_state)
	ai_controller.command_handlers["move"] = world_model.ai_move_command
	ai_controller.command_handlers["declare_war"] = diplomacy_system.ai_declare_war_command
	ai_controller.command_handlers["propose_trade"] = diplomacy_system.ai_propose_trade_command
	ai_controller.command_handlers["demand_tribute"] = diplomacy_system.ai_demand_tribute_command
	ai_controller.command_handlers["recruit"] = economy_system.ai_recruit_command
	battle_outcome_handler = world_model.ai_battle_outcome_handler
	turn_manager = TurnManager.new(
		game_state,
		ai_controller.run_faction_turn,
		_settle_turn,
		_default_advance
	)


## TurnManager 的 settle 回调（P5）：经济结算 → 条约推进
func _settle_turn() -> Dictionary:
	economy_system.settle_turn()
	diplomacy_system.tick_treaties()
	return {}


## 玩家移动军团（世界场景点击城市时调用）。
## 规则校验走 WorldMapModel；触发战斗时广播 battle_requested。
func player_move_army(army_id: String, target_city_id: String) -> Dictionary:
	if game_state == null or world_model == null:
		return {"ok": false, "reason": "no_game"}
	var army: Army = game_state.get_army(army_id)
	var result: Dictionary = world_model.move_army(army, target_city_id)
	if result.has("battle"):
		pending_battle = result["battle"]
		battle_requested.emit(pending_battle)
	return result


## 玩家沿路径行军（可多步，直到移动力耗尽或遇敌）。
## 返回 WorldMapModel.move_army_toward 的结果（含 moves 序列供动画播放）。
func player_move_army_toward(army_id: String, target_city_id: String) -> Dictionary:
	if game_state == null or world_model == null:
		return {"ok": false, "reason": "no_game"}
	var army: Army = game_state.get_army(army_id)
	var result: Dictionary = world_model.move_army_toward(army, target_city_id)
	if result.has("battle"):
		pending_battle = result["battle"]
		battle_requested.emit(pending_battle)
	return result


## 构建一个势力的初始军团（已废弃：统一走 EconomySystem.recruit_army，勿再调用）
func _build_starting_army(_gs: GameState, _faction: Faction, _city_id: String, _team_size: int) -> void:
	pass


## 按角色职业随机配一件武器（已废弃：随 _build_starting_army 迁入 EconomySystem）
func _assign_random_equipment(_unit: Unit) -> void:
	pass
