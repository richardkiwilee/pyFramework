class_name Unit
extends RefCounted
## =============================================================================
## Unit — 单位（战术层的角色实例）
## =============================================================================
## 领域术语见 CONTEXT.md：编队（Team）中的一格就是一个单位。
## 单位 = 角色数据（characters.json 的 character_id）+ 运行期状态（等级/经验/装备/技能）。
##
## 职责边界（docs/00-design.md §6）：
##   - 本类只保存战略层持久状态，不计算战斗属性。
##   - 战斗属性（HP/攻/防/速……）由战斗引擎在开战时根据
##     character 数据 + 装备 + 等级现场推导（scripts/battle/ 的职责）。
##   - 禁止持有任何 Node/UI 引用。
##
## 类比 Python：
##   相当于一个 dataclass：纯数据 + 少量行为，没有游戏引擎依赖，
##   可以脱离 Godot 场景树在测试里直接 new 出来用。
## =============================================================================

## 唯一 ID（运行期生成，如 "unit_1"）
var id: String = ""

## 角色数据 ID（对应 data/characters.json 的 id，如 "alain"）
var character_id: String = ""

## 等级（默认 1；属性成长由战斗引擎按等级计算）
var level: int = 1

## 经验值
var exp: int = 0

## 装备：槽位名 → 装备 ID（data/equipment.json 的 id）
## 简化版编成界面只编辑这个字典；槽位名如 "weapon" / "shield"
var equipment: Dictionary = {}

## 行动策略：最多 8 行 [{skill: 技能id, cond1: 条件id, cond2: 条件id}]
## （demo-1 的"行动策略面板"结构：[技能 | 条件1 | 条件2]，最多 8 行）
## 空数组 = 战斗引擎按角色数据自动配默认技能（demo-1 行为）
var strategy: Array = []


## 战斗技能 ID 列表（策略行按序提取；引擎读这个）
## 条件 cond1/cond2 目前只存储与展示，战斗引擎暂不消费（文档已声明）
func battle_skill_ids() -> Array:
	var result: Array = []
	for row in strategy:
		var sk: String = row.get("skill", "")
		if sk != "":
			result.append(sk)
	return result


## ---------------------------------------------------------------------------
## to_dict() / from_dict() — 序列化（存档用）
## ---------------------------------------------------------------------------
## 所有领域类都提供这对方法，GameState 把它们组合成整档 JSON。
## 类比 Python 的 __dict__ 序列化，但字段是显式列出的（可控、防漏）。
## ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"id": id,
		"character_id": character_id,
		"level": level,
		"exp": exp,
		"equipment": equipment,
		"strategy": strategy,
	}


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = d.get("id", "")
	u.character_id = d.get("character_id", "")
	u.level = int(d.get("level", 1))
	u.exp = int(d.get("exp", 0))
	# Dictionary 是引用类型：存档读入是新字典，直接赋值即可（不会污染其他对象）
	u.equipment = d.get("equipment", {})
	# 兼容旧存档：无 strategy 键则回退旧的 skills 数组（技能 id 列表）
	if d.has("strategy"):
		u.strategy = d.get("strategy", [])
	else:
		for sk_id in d.get("skills", []):
			u.strategy.append({"skill": sk_id, "cond1": "", "cond2": ""})
	return u


## 便捷：给单位装一件装备（槽位覆盖写入）
func equip(slot_key: String, eq_id: String) -> void:
	equipment[slot_key] = eq_id


## 便捷：卸下一件装备
func unequip(slot_key: String) -> void:
	equipment.erase(slot_key)
