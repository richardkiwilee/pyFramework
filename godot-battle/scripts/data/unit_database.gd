# unit_database.gd
# Autoload — 单位数据库
# 提供所有单位模板的预定义数据
extends Node

const UNIT_TEMPLATES: Dictionary = {
	"knight_blue": {
		"id": "knight_blue",
		"name": "亚瑟",
		"class_name": "knight",
		"class_display": "骑士",
		"team": "blue",
		"level": 10,
		"tags": ["cavalry", "infantry"],
		"base_stats": {
			"hp": 150, "atk": 35, "def": 25, "matk": 10, "mdef": 15,
			"hit": 90, "evasion": 10, "crit_rate": 10, "guard_rate": 25, "guard_reduction": 25,
			"speed": 20, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["heavy_slash", "wide_slash"],
		"passive_skills": ["guard"],
		"tactics": [
			{"priority": 1, "skill_id": "wide_slash", "condition_1": {"type": "armored", "mode": "only"}, "condition_2": {}},
			{"priority": 2, "skill_id": "heavy_slash", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}},
			{"priority": 3, "skill_id": "heavy_slash", "condition_1": {}, "condition_2": {}}
		]
	},
	"mage_blue": {
		"id": "mage_blue",
		"name": "梅林",
		"class_name": "mage",
		"class_display": "法师",
		"team": "blue",
		"level": 10,
		"tags": ["caster", "infantry"],
		"base_stats": {
			"hp": 100, "atk": 8, "def": 10, "matk": 42, "mdef": 30,
			"hit": 95, "evasion": 12, "crit_rate": 8, "guard_rate": 0, "guard_reduction": 0,
			"speed": 18, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["fireball", "icebolt"],
		"passive_skills": [],
		"tactics": [
			{"priority": 1, "skill_id": "icebolt", "condition_1": {"type": "speed_fastest", "mode": "priority"}, "condition_2": {}},
			{"priority": 2, "skill_id": "fireball", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}},
			{"priority": 3, "skill_id": "fireball", "condition_1": {}, "condition_2": {}}
		]
	},
	"archer_blue": {
		"id": "archer_blue",
		"name": "罗宾",
		"class_name": "archer",
		"class_display": "弓手",
		"team": "blue",
		"level": 10,
		"tags": ["infantry"],
		"base_stats": {
			"hp": 120, "atk": 30, "def": 15, "matk": 10, "mdef": 12,
			"hit": 100, "evasion": 18, "crit_rate": 15, "guard_rate": 0, "guard_reduction": 0,
			"speed": 25, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["precise_shot", "poison_slash"],
		"passive_skills": [],
		"tactics": [
			{"priority": 1, "skill_id": "precise_shot", "condition_1": {"type": "flying", "mode": "only"}, "condition_2": {"type": "hp_lowest", "mode": "priority"}},
			{"priority": 2, "skill_id": "poison_slash", "condition_1": {"type": "armored", "mode": "only"}, "condition_2": {}},
			{"priority": 3, "skill_id": "precise_shot", "condition_1": {}, "condition_2": {}}
		]
	},
	"cleric_blue": {
		"id": "cleric_blue",
		"name": "玛利亚",
		"class_name": "cleric",
		"class_display": "牧师",
		"team": "blue",
		"level": 10,
		"tags": ["healer", "infantry"],
		"base_stats": {
			"hp": 110, "atk": 10, "def": 12, "matk": 32, "mdef": 35,
			"hit": 95, "evasion": 10, "crit_rate": 5, "guard_rate": 0, "guard_reduction": 0,
			"speed": 16, "ap_max": 3, "pp_max": 3
		},
		"active_skills": ["heal", "group_heal"],
		"passive_skills": [],
		"tactics": [
			{"priority": 1, "skill_id": "heal", "condition_1": {"type": "hp_below_50", "mode": "only"}, "condition_2": {"type": "hp_lowest", "mode": "priority"}},
			{"priority": 2, "skill_id": "group_heal", "condition_1": {}, "condition_2": {}},
			{"priority": 3, "skill_id": "heal", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}}
		]
	},
	"thief_blue": {
		"id": "thief_blue",
		"name": "影",
		"class_name": "thief",
		"class_display": "盗贼",
		"team": "blue",
		"level": 10,
		"tags": ["scout", "infantry"],
		"base_stats": {
			"hp": 100, "atk": 28, "def": 8, "matk": 5, "mdef": 8,
			"hit": 95, "evasion": 35, "crit_rate": 20, "guard_rate": 0, "guard_reduction": 0,
			"speed": 35, "ap_max": 3, "pp_max": 3
		},
		"active_skills": ["shadow_strike"],
		"passive_skills": ["evade"],
		"tactics": [
			{"priority": 1, "skill_id": "shadow_strike", "condition_1": {"type": "hp_below_50", "mode": "priority"}, "condition_2": {}},
			{"priority": 2, "skill_id": "shadow_strike", "condition_1": {}, "condition_2": {}}
		]
	},
	"tank_blue": {
		"id": "tank_blue",
		"name": "铁壁",
		"class_name": "tank",
		"class_display": "重甲",
		"team": "blue",
		"level": 10,
		"tags": ["armored", "infantry"],
		"base_stats": {
			"hp": 200, "atk": 22, "def": 45, "matk": 5, "mdef": 20,
			"hit": 85, "evasion": 0, "crit_rate": 5, "guard_rate": 50, "guard_reduction": 50,
			"speed": 10, "ap_max": 2, "pp_max": 3
		},
		"active_skills": ["shield_bash"],
		"passive_skills": ["heavy_cover"],
		"tactics": [
			{"priority": 1, "skill_id": "shield_bash", "condition_1": {"type": "speed_fastest", "mode": "priority"}, "condition_2": {}},
			{"priority": 2, "skill_id": "shield_bash", "condition_1": {}, "condition_2": {}}
		]
	},
	"soldier_blue": {
		"id": "soldier_blue",
		"name": "兰斯",
		"class_name": "soldier",
		"class_display": "枪兵",
		"team": "blue",
		"level": 10,
		"tags": ["infantry"],
		"base_stats": {
			"hp": 140, "atk": 30, "def": 20, "matk": 8, "mdef": 12,
			"hit": 90, "evasion": 14, "crit_rate": 10, "guard_rate": 15, "guard_reduction": 15,
			"speed": 22, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["pierce", "heavy_slash"],
		"passive_skills": [],
		"tactics": [
			{"priority": 1, "skill_id": "pierce", "condition_1": {"type": "back_row", "mode": "priority"}, "condition_2": {}},
			{"priority": 2, "skill_id": "heavy_slash", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}},
			{"priority": 3, "skill_id": "heavy_slash", "condition_1": {}, "condition_2": {}}
		]
	},
	"knight_red": {
		"id": "knight_red",
		"name": "暗黑骑士",
		"class_name": "dark_knight",
		"class_display": "暗骑",
		"team": "red",
		"level": 10,
		"tags": ["cavalry", "infantry"],
		"base_stats": {
			"hp": 140, "atk": 38, "def": 20, "matk": 12, "mdef": 15,
			"hit": 90, "evasion": 12, "crit_rate": 12, "guard_rate": 20, "guard_reduction": 20,
			"speed": 22, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["dark_slash", "drain_blade"],
		"passive_skills": ["counter"],
		"tactics": [
			{"priority": 1, "skill_id": "dark_slash", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {"type": "caster", "mode": "priority"}},
			{"priority": 2, "skill_id": "dark_slash", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}},
			{"priority": 3, "skill_id": "drain_blade", "condition_1": {}, "condition_2": {}}
		]
	},
	"mage_red": {
		"id": "mage_red",
		"name": "火焰魔导",
		"class_name": "mage",
		"class_display": "法师",
		"team": "red",
		"level": 10,
		"tags": ["caster", "infantry"],
		"base_stats": {
			"hp": 95, "atk": 6, "def": 8, "matk": 45, "mdef": 28,
			"hit": 95, "evasion": 10, "crit_rate": 8, "guard_rate": 0, "guard_reduction": 0,
			"speed": 18, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["flame_storm", "fireball"],
		"passive_skills": [],
		"tactics": [
			{"priority": 1, "skill_id": "flame_storm", "condition_1": {"type": "armored", "mode": "only"}, "condition_2": {}},
			{"priority": 2, "skill_id": "fireball", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}},
			{"priority": 3, "skill_id": "fireball", "condition_1": {}, "condition_2": {}}
		]
	},
	"archer_red": {
		"id": "archer_red",
		"name": "暗影弓手",
		"class_name": "archer",
		"class_display": "弓手",
		"team": "red",
		"level": 10,
		"tags": ["infantry"],
		"base_stats": {
			"hp": 115, "atk": 32, "def": 14, "matk": 8, "mdef": 10,
			"hit": 98, "evasion": 16, "crit_rate": 14, "guard_rate": 0, "guard_reduction": 0,
			"speed": 26, "ap_max": 3, "pp_max": 2
		},
		"active_skills": ["phantom_arrow", "paralyze_arrow"],
		"passive_skills": [],
		"tactics": [
			{"priority": 1, "skill_id": "paralyze_arrow", "condition_1": {"type": "cavalry", "mode": "only"}, "condition_2": {}},
			{"priority": 2, "skill_id": "phantom_arrow", "condition_1": {"type": "hp_lowest", "mode": "priority"}, "condition_2": {}},
			{"priority": 3, "skill_id": "phantom_arrow", "condition_1": {}, "condition_2": {}}
		]
	}
}


func get_unit_template(id: String) -> Dictionary:
	if UNIT_TEMPLATES.has(id):
		return UNIT_TEMPLATES[id].duplicate(true)
	push_error("UnitDatabase: Unknown unit template id: " + id)
	return {}


func get_all_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in UNIT_TEMPLATES:
		result.append(UNIT_TEMPLATES[key].duplicate(true))
	return result


func get_blue_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in UNIT_TEMPLATES:
		if UNIT_TEMPLATES[key].team == "blue":
			result.append(UNIT_TEMPLATES[key].duplicate(true))
	return result


func get_red_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in UNIT_TEMPLATES:
		if UNIT_TEMPLATES[key].team == "red":
			result.append(UNIT_TEMPLATES[key].duplicate(true))
	return result


## 从模板创建一个深拷贝的战斗单位数据
func create_unit_from_template(template_id: String) -> Dictionary:
	var template = get_unit_template(template_id)
	if template.is_empty():
		return {}

	var unit: Dictionary = {
		"id": template.id,
		"name": template.name,
		"class_name": template.class_name,
		"class_display": template.class_display,
		"team": template.team,
		"level": template.level,
		"tags": template.tags.duplicate(),
		"active_skills": template.active_skills.duplicate(),
		"passive_skills": template.passive_skills.duplicate(),
		"tactics": template.tactics.duplicate(true),
		"equipment": {
			"weapon": null,
			"offhand": null,
			"accessory1": null,
			"accessory2": null
		},
		"status_effects": [],
		"buffs": {},
		"is_alive": true,
		"row": 0,   # 0=前排, 1=后排
		"col": 0,   # 0-2
	}

	# 复制基础属性
	for stat in template.base_stats:
		unit[stat] = template.base_stats[stat]

	# 运行时属性
	unit["hp_current"] = template.base_stats["hp"]
	unit["ap_current"] = template.base_stats["ap_max"]
	unit["pp_current"] = template.base_stats["pp_max"]

	return unit
