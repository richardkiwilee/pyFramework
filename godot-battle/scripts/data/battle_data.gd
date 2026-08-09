# battle_data.gd
# Autoload — 场景间数据传递
# 在队伍编辑场景和战斗场景之间传递队伍配置
extends Node

# 队伍数据：Array[Dictionary]
var team_blue: Array[Dictionary] = []
var team_red: Array[Dictionary] = []

# 战斗结果
var battle_result: Dictionary = {}


## 重置数据
func reset() -> void:
	team_blue.clear()
	team_red.clear()
	battle_result.clear()


## 设置队伍数据
func set_teams(blue: Array[Dictionary], red: Array[Dictionary]) -> void:
	team_blue = blue.duplicate(true)
	team_red = red.duplicate(true)


## 计算单位装备后的实际属性
func calculate_effective_stats(unit: Dictionary) -> Dictionary:
	var stats = {
		"hp": unit.get("hp", 0),
		"atk": unit.get("atk", 0),
		"def": unit.get("def", 0),
		"matk": unit.get("matk", 0),
		"mdef": unit.get("mdef", 0),
		"hit": unit.get("hit", 0),
		"evasion": unit.get("evasion", 0),
		"crit_rate": unit.get("crit_rate", 0),
		"guard_rate": unit.get("guard_rate", 0),
		"guard_reduction": unit.get("guard_reduction", 0),
		"speed": unit.get("speed", 0),
		"ap_max": unit.get("ap_max", 0),
		"pp_max": unit.get("pp_max", 0),
	}

	# 应用装备加成
	var equipment = unit.get("equipment", {})
	for slot_key in equipment:
		var eq_id = equipment[slot_key]
		if eq_id == null or eq_id == "":
			continue
		var eq = EquipmentDatabase.get_equipment(eq_id)
		if eq.is_empty():
			continue
		for stat_key in eq.stats:
			if stats.has(stat_key):
				stats[stat_key] += eq.stats[stat_key]

	return stats
