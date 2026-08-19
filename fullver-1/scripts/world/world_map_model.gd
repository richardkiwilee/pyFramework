class_name WorldMapModel
extends RefCounted
## =============================================================================
## WorldMapModel — 大地图模型（据点图 + 移动规则 + 战斗触发 + 后果应用）
## =============================================================================
## 纯逻辑、无 Node 依赖（docs/00-design.md §8，ADR-0002）：
##   - 邻接表与寻路（Pathfinder）
##   - 军团移动校验（相邻 + 移动力）与执行
##   - 敌对相遇判定 → 战斗请求
##   - 战斗后果应用（占城/解散军团）——玩家与 AI 共用同一套校验路径
##
## 移动规则（框架阶段的最简规则集）：
##   1. 一次行动只能沿一条路线移动到相邻城市（消耗 1 移动力）
##   2. 目标城有敌方军团 → 不移动、不扣点，返回战斗请求
##   3. 目标城无敌人 → 移动成功；若城市归属他人/中立 → 占领
##
## 类比 Python：
##   相当于游戏的 service 层：校验 + 变更状态 + 返回结构化结果字典。
## =============================================================================

## 游戏状态（构造时注入）
var state: GameState

## 邻接表（构造时从 data/world/map.json 构建）
var adjacency: Dictionary = {}

## 寻路器
var pathfinder: Pathfinder


func _init(gs: GameState) -> void:
	state = gs
	_build_adjacency()
	pathfinder = Pathfinder.new(adjacency)


## 从静态地图数据构建邻接表（无向边双向登记）
func _build_adjacency() -> void:
	var routes: Array = DataManager.get_map_data().get("routes", [])
	for r in routes:
		var a: String = r[0]
		var b: String = r[1]
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		if b not in adjacency[a]:
			adjacency[a].append(b)
		if a not in adjacency[b]:
			adjacency[b].append(a)


# ==================================================================
#  查询接口
# ==================================================================

## 邻接城市 ID 列表
## ⚠️ Dictionary.get 返回无类型 Array，直接 return 会触发
## "expected Array[String]" 运行时错误（本环境实测）——必须拷贝进类型化数组
func adjacent_city_ids(city_id: String) -> Array[String]:
	var result: Array[String] = []
	for nid in adjacency.get(city_id, []):
		result.append(nid)
	return result


## 两城最短路径（含起终点）；无路返回 []
func find_path(from_id: String, to_id: String) -> Array[String]:
	return pathfinder.find_path(from_id, to_id)


## 某城市当前驻扎的全部军团
func armies_at(city_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a in state.armies:
		if a.current_city_id == city_id:
			result.append(a)
	return result


## 某城市驻扎的"敌对势力"军团（对我方 faction_id 而言）
func enemy_armies_at(city_id: String, faction_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a in armies_at(city_id):
		if a.owner_faction_id != faction_id:
			result.append(a)
	return result


## 军团能否行动（有移动力且编队可战）
func can_army_move(army: Army) -> bool:
	return army != null and army.move_points > 0 and army.can_fight()


# ==================================================================
#  移动行动（玩家与 AI 共用的唯一入口）
# ==================================================================

## ---------------------------------------------------------------------------
## move_army() — 军团移动到相邻城市
## ---------------------------------------------------------------------------
## 返回：
##   {"ok": true}                                  — 移动成功（含占城）
##   {"ok": false, "reason": "..."}                — 校验失败（无路/无移动力/不可战）
##   {"ok": false, "battle": {...}}                — 目标城有敌军 → 战斗请求
##      battle = {"attacker_army_id", "defender_army_id", "city_id"}
##   （battle 出现时 ok 恒为 false——移动是否发生取决于战斗结果）
## ---------------------------------------------------------------------------
func move_army(army: Army, target_city_id: String) -> Dictionary:
	if army == null:
		return {"ok": false, "reason": "no_army"}
	if not can_army_move(army):
		return {"ok": false, "reason": "no_move_points"}
	if target_city_id not in adjacency.get(army.current_city_id, []):
		return {"ok": false, "reason": "not_adjacent"}
	var target_city := state.get_city(target_city_id)
	if target_city == null:
		return {"ok": false, "reason": "unknown_city"}

	# 目标城有敌方军团 → 战斗（移动与否由战斗结果决定，不在这里扣点）
	var enemies: Array[Army] = enemy_armies_at(target_city_id, army.owner_faction_id)
	if not enemies.is_empty():
		var battle := {
			"attacker_army_id": army.id,
			"defender_army_id": enemies[0].id,
			"city_id": target_city_id,
		}
		state.add_event("battle_pending", battle)
		return {"ok": false, "battle": battle}

	# 执行移动
	_do_move(army, target_city)
	return {"ok": true}


## ---------------------------------------------------------------------------
## move_army_toward() — 沿最短路径向目标行军（玩家点击地图城市时调用）
## ---------------------------------------------------------------------------
## 逐段执行单步移动，直到移动力耗尽或遭遇敌军。
## 返回：
##   {"ok": true, "moves": [city_id...]}              — moves 为实际走到的城市（不含起点）
##   {"ok": false, "battle": {...}, "moves": [...]}   — 途中遇敌（moves 为遇敌前已走段）
##   {"ok": false, "reason": "no_path"/"already_there"/...}
## ---------------------------------------------------------------------------
func move_army_toward(army: Army, target_city_id: String) -> Dictionary:
	if army == null:
		return {"ok": false, "reason": "no_army"}
	if army.current_city_id == target_city_id:
		return {"ok": false, "reason": "already_there"}
	var path: Array[String] = find_path(army.current_city_id, target_city_id)
	if path.is_empty() or path.size() < 2:
		return {"ok": false, "reason": "no_path"}
	var moves: Array = []
	for i in range(1, path.size()):
		if not can_army_move(army):
			break  # 移动力耗尽：走多少算多少
		var step_result: Dictionary = move_army(army, path[i])
		if step_result.has("battle"):
			return {"ok": false, "battle": step_result["battle"], "moves": moves}
		if not step_result.get("ok", false):
			break
		moves.append(path[i])
	return {"ok": true, "moves": moves}


## 实际执行移动（内部：扣点、更新城市驻军与归属）
func _do_move(army: Army, target_city: City) -> void:
	var from_city := state.get_city(army.current_city_id)
	if from_city != null and from_city.garrison_army_id == army.id:
		from_city.garrison_army_id = ""
	army.spend_move_point()
	army.current_city_id = target_city.id
	# 占领：城市归属变更（中立/他人城市）；事件广播
	if target_city.owner_faction_id != army.owner_faction_id:
		var was_neutral: bool = target_city.is_neutral()
		var prev_owner: String = target_city.owner_faction_id
		target_city.set_owner(army.owner_faction_id)
		# 城市沦陷：原主的驻军引用清理（驻军军团的 current_city_id 仍指向此城，
		# 但它的势力已失去该城——占领后该军团会成为城里的"敌军"，
		# 下一回合移动规则会自然处理：任何势力军团只能从自己当前城出发）
		state.add_event("city_captured" if not was_neutral else "city_neutral", {
			"city_id": target_city.id,
			"city_name": target_city.name_zh,
			"new_owner": army.owner_faction_id,
			"prev_owner": prev_owner,
		})
	target_city.garrison_army_id = army.id


# ==================================================================
#  战斗后果应用（GameManager 在战斗场景结算后调用）
# ==================================================================

## ---------------------------------------------------------------------------
## apply_battle_outcome() — 应用战斗结果
## ---------------------------------------------------------------------------
## battle：GameManager.pending_battle（{attacker_army_id, defender_army_id, city_id}）
## result：战斗引擎的结局 {"result": "victory"/"defeat"/"draw"}
## 规则：
##   victory — 防守方军团解散；进攻方进占城市（归属变更）
##   defeat  — 进攻方军团解散；防守方留在原地
##   draw    — 双方保留，城市不变
## ---------------------------------------------------------------------------
func apply_battle_outcome(battle: Dictionary, result: Dictionary) -> void:
	var attacker: Army = state.get_army(battle.get("attacker_army_id", ""))
	var defender: Army = state.get_army(battle.get("defender_army_id", ""))
	var city := state.get_city(battle.get("city_id", ""))
	var outcome: String = result.get("result", "draw")

	match outcome:
		"victory":
			state.add_event("battle_win", {
				"winner": attacker.owner_faction_id if attacker != null else "",
				"city_name": city.name_zh if city != null else "",
			})
			# 防守方解散
			state.remove_army(defender)
			# 进攻方进占（若还在原城）
			if attacker != null and city != null:
				var prev_owner: String = city.owner_faction_id
				city.set_owner(attacker.owner_faction_id)
				city.garrison_army_id = attacker.id
				attacker.current_city_id = city.id
				state.add_event("city_captured", {
					"city_id": city.id,
					"city_name": city.name_zh,
					"new_owner": attacker.owner_faction_id,
					"prev_owner": prev_owner,
				})
		"defeat":
			state.add_event("battle_lose", {
				"loser": attacker.owner_faction_id if attacker != null else "",
				"city_name": city.name_zh if city != null else "",
			})
			state.remove_army(attacker)
		_:
			pass  # 平局：无变化


## ---------------------------------------------------------------------------
## ai_move_command() — 给 AIContext 的 "move" 指令处理器
## ---------------------------------------------------------------------------
## 签名符合 AIContext.register_command 的约定：
##   func(params: Dictionary, ctx: AIContext) -> Dictionary
## 校验失败返回 {"ok": false, "reason": ...}（策略脚本自行决定是否重试）。
## ---------------------------------------------------------------------------
func ai_move_command(params: Dictionary, ctx: AIContext) -> Dictionary:
	var army: Army = state.get_army(params.get("army_id", ""))
	if army == null or army.owner_faction_id != ctx.faction.id:
		return {"ok": false, "reason": "not_your_army"}
	var result: Dictionary = move_army(army, params.get("target_city_id", ""))
	if result.has("battle"):
		# 战斗请求写入 ctx.pending_battle，AIController 会中断流程
		ctx.pending_battle = result["battle"]
	return result


## ---------------------------------------------------------------------------
## ai_battle_outcome_handler() — 给 GameManager 的战斗后果处理器
## ---------------------------------------------------------------------------
func ai_battle_outcome_handler(battle: Dictionary, result: Dictionary) -> void:
	apply_battle_outcome(battle, result)
