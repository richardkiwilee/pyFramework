class_name Faction
extends RefCounted
## =============================================================================
## Faction — 势力（玩家或 AI 控制的一方可玩阵营）
## =============================================================================
## 领域术语见 CONTEXT.md。玩家与 AI 同构：同一份数据结构，
## 差别只在 is_player 标记与 ai_strategy 脚本挂载（docs/00-design.md §6，
## 修正 diplomacy 项目"玩家不是对象"的缺陷）。
##
## 类比 Python：dataclass + 资源收支方法，无引擎依赖。
## =============================================================================

## 势力 ID（data/factions.json 的 id）
var id: String = ""

## 显示名
var name_zh: String = ""
var name_en: String = ""

## 是否玩家控制的势力（factions.json 中 is_player=true 唯一）
var is_player: bool = false

## AI 策略脚本路径（res:// 开头，空串 = 内置 BasicAI）
## 只有 AI 势力读取此字段；玩家势力忽略
var ai_strategy: String = ""

## 资源持有量：资源ID → 数量（int）
## 如 {"gold": 100, "food": 120, "wood": 60, "horse": 20}
var resources: Dictionary = {}

## 资源预期量（外交贸易评分的基准：持有低于预期才计"缺口"）
## 开局 = factions.json 的 starting_resources 副本，随贸易变动由系统更新
var expectations: Dictionary = {}

## 是否已灭亡（所有城市被占且无军团）。灭亡势力跳过其 AI 回合。
var alive: bool = true


## ---------------------------------------------------------------------------
## 资源收支
## ---------------------------------------------------------------------------

## 增加资源（delta 为正）。负数会被截到 0 以下时按 0 处理。
func add_resources(delta: Dictionary) -> void:
	for res_id in delta:
		var cur: int = int(resources.get(res_id, 0))
		resources[res_id] = max(0, cur + int(delta[res_id]))


## 扣除资源。全部足够才扣并返回 true；任一不足则不动、返回 false
## （原子性：防止部分扣除后事务失败的状态撕裂）
func can_afford(cost: Dictionary) -> bool:
	for res_id in cost:
		if int(resources.get(res_id, 0)) < int(cost[res_id]):
			return false
	return true


## 支付（调用前先 can_afford）。返回是否成功。
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res_id in cost:
		resources[res_id] = int(resources.get(res_id, 0)) - int(cost[res_id])
	return true


## ---------------------------------------------------------------------------
## 序列化（存档用）
## ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name_zh": name_zh,
		"name_en": name_en,
		"is_player": is_player,
		"ai_strategy": ai_strategy,
		"resources": resources,
		"expectations": expectations,
		"alive": alive,
	}


static func from_dict(d: Dictionary) -> Faction:
	var f := Faction.new()
	f.id = d.get("id", "")
	f.name_zh = d.get("name_zh", "")
	f.name_en = d.get("name_en", "")
	f.is_player = bool(d.get("is_player", false))
	f.ai_strategy = d.get("ai_strategy", "")
	f.resources = d.get("resources", {})
	f.expectations = d.get("expectations", {})
	f.alive = bool(d.get("alive", true))
	return f
