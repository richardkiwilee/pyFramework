class_name AIContext
extends RefCounted
## =============================================================================
## AIContext — AI 上下文（只读局面视图 + 经系统校验的指令集）
## =============================================================================
## 领域术语见 CONTEXT.md。每个 AI 势力回合开始时由 AIController 创建一份。
##
## 设计原则（docs/00-design.md §10.2）：
##   - 视图只读：返回的都是引用/副本，AI 只能看不能改
##   - 指令经系统校验：AI 通过 command() 行动，内部走与玩家相同的校验路径，
##     非法指令返回 {"ok": false, "reason": ...}
##   - 指令处理器由 GameManager 接线（P4 接移动、P5 接外交），
##     未接线的命令返回 command_not_wired——保证策略脚本在系统就绪前不崩
##
## 类比 Python：
##   相当于给策略脚本的"沙箱 API"——一个门面（facade）对象，
##   后面挂的处理器可以随时替换/测试注入。
## =============================================================================

## 游戏状态（只读使用）
var state: GameState

## 本 AI 所控制的势力
var faction: Faction

## 战斗请求挂起位：AI 的某条指令（如进攻敌军城市）引发战斗时，
## 由指令处理器写入。AIController 每阶段结束检查此字段，
## 非空即中断流程返回给 TurnManager。
var pending_battle: Dictionary = {}

## 指令处理器注册表：命令名 → Callable
## handler 签名约定：func(params: Dictionary, ctx: AIContext) -> Dictionary
var _handlers: Dictionary = {}


## 注册指令处理器（GameManager 在系统就绪后调用）
func register_command(cmd: String, handler: Callable) -> void:
	_handlers[cmd] = handler


## 执行指令。返回约定：{"ok": bool, ...}；未接线/未知命令 ok=false。
func command(cmd: String, params: Dictionary = {}) -> Dictionary:
	if not _handlers.has(cmd):
		return {"ok": false, "reason": "command_not_wired"}
	var handler: Callable = _handlers[cmd]
	var result: Variant = handler.call(params, self)
	return result if result is Dictionary else {"ok": false, "reason": "bad_handler_result"}


# ==================================================================
#  只读视图 (Read-only Views)
# ==================================================================

## 本势力的全部军团
func my_armies() -> Array[Army]:
	return state.armies_of(faction.id)


## 本势力的全部城市
func my_cities() -> Array[City]:
	return state.cities_of(faction.id)


## 全部城市（含中立与敌对）
func all_cities() -> Array[City]:
	return state.cities


## 全部敌方势力（非我、存活）
func enemy_factions() -> Array[Faction]:
	var result: Array[Faction] = []
	for f in state.factions:
		if f.id != faction.id and f.alive:
			result.append(f)
	return result


## 与我交战的敌方势力
func at_war_factions() -> Array[Faction]:
	var result: Array[Faction] = []
	for f in enemy_factions():
		var r := state.get_relation(faction.id, f.id)
		if r != null and r.at_war:
			result.append(f)
	return result


## 本势力对目标的双边关系（不存在返回 null）
func relation_to(target_faction_id: String) -> Relation:
	return state.get_relation(faction.id, target_faction_id)


## 某城市的归属势力 ID（"" = 中立）
func city_owner(city_id: String) -> String:
	var city := state.get_city(city_id)
	return city.owner_faction_id if city != null else ""


## 某城市当前的军团（任何势力的）
func armies_at_city(city_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a in state.armies:
		if a.current_city_id == city_id:
			result.append(a)
	return result


## 邻接城市 ID 列表（读静态地图数据，不涉及领域规则）
## 数据来源：data/world/map.json 的 routes（无向边）
func adjacent_city_ids(city_id: String) -> Array[String]:
	var result: Array[String] = []
	var routes: Array = DataManager.get_map_data().get("routes", [])
	for r in routes:
		if r[0] == city_id:
			result.append(r[1])
		elif r[1] == city_id:
			result.append(r[0])
	return result
