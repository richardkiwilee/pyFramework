## 阵营（对应 pydemo/game/faction.py）。
## 持有资源、信念、据点、部队、英雄、招募池、待命池、装备库存、已学科技/文化。
class_name Faction
extends RefCounted

class Faction_:
	var id: String
	var name: String
	var is_ai: bool = false
	var resources: Economy.Resources
	var belief: Economy.Belief
	var capital_id: String = ""
	var army_ids: Array = []
	var hero_ids: Array = []
	var stronghold_ids: Array = []
	var standby: Dictionary = {}    # unit_id -> cooldown（0=可用，>0=不可用）
	var inventory: Dictionary = {}  # def_id -> 库存数（含在库 + 已装备）
	var recruitment_pools: Dictionary = {}   # stronghold_id -> RecruitmentPool
	var tech_learned: Array = []
	var culture_learned: Array = []
	var alive: bool = true

	func _init(id_: String, name_: String, is_ai_: bool = false) -> void:
		id = id_
		name = name_
		is_ai = is_ai_
		resources = Economy.Resources.new()
		belief = Economy.Belief.new()

	## 待命·可用的单位 id（冷却 <= 0）。
	func standby_available_ids() -> Array:
		var out: Array = []
		for uid in standby:
			if int(standby[uid]) <= 0:
				out.append(uid)
		return out

	func describe() -> String:
		return "%s(%s) %s 首都:%s 据点:%d 部队:%d 英雄:%d 待命:%d" % [
			name, id, "[AI]" if is_ai else "[玩家]", capital_id,
			stronghold_ids.size(), army_ids.size(), hero_ids.size(), standby.size()]
