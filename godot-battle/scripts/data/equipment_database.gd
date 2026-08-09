# equipment_database.gd
# Autoload — 装备数据库
extends Node

const EQUIPMENT: Dictionary = {
	"steel_sword": {
		"id": "steel_sword",
		"name": "钢剑",
		"slot": "weapon",
		"stats": {"atk": 15},
		"granted_skill": "",
		"immunities": [],
		"description": "攻击+15"
	},
	"magic_staff": {
		"id": "magic_staff",
		"name": "魔法杖",
		"slot": "weapon",
		"stats": {"matk": 20},
		"granted_skill": "",
		"immunities": [],
		"description": "魔法攻击+20"
	},
	"iron_bow": {
		"id": "iron_bow",
		"name": "铁弓",
		"slot": "weapon",
		"stats": {"atk": 12, "hit": 10},
		"granted_skill": "",
		"immunities": [],
		"description": "攻击+12, 命中+10"
	},
	"great_shield": {
		"id": "great_shield",
		"name": "大盾",
		"slot": "offhand",
		"stats": {"def": 10, "guard_rate": 25},
		"granted_skill": "",
		"immunities": [],
		"description": "防御+10, 格挡率+25%"
	},
	"dagger": {
		"id": "dagger",
		"name": "匕首",
		"slot": "offhand",
		"stats": {"atk": 8, "speed": 5},
		"granted_skill": "",
		"immunities": [],
		"description": "攻击+8, 速度+5"
	},
	"hp_pendant": {
		"id": "hp_pendant",
		"name": "生命吊坠",
		"slot": "accessory",
		"stats": {"hp": 30},
		"granted_skill": "",
		"immunities": [],
		"description": "最大HP+30"
	},
	"ap_ring": {
		"id": "ap_ring",
		"name": "AP指环",
		"slot": "accessory",
		"stats": {"ap": 1},
		"granted_skill": "",
		"immunities": [],
		"description": "AP上限+1"
	},
	"pp_ring": {
		"id": "pp_ring",
		"name": "PP指环",
		"slot": "accessory",
		"stats": {"pp": 1},
		"granted_skill": "",
		"immunities": [],
		"description": "PP上限+1"
	},
	"flame_sword": {
		"id": "flame_sword",
		"name": "火焰之剑",
		"slot": "weapon",
		"stats": {"atk": 20, "crit_rate": 5},
		"granted_skill": "fireball",
		"immunities": ["burn"],
		"description": "攻击+20, 暴击+5%, 附带「火球术」, 免疫灼烧"
	},
	"ice_amulet": {
		"id": "ice_amulet",
		"name": "冰霜护符",
		"slot": "accessory",
		"stats": {"mdef": 10},
		"granted_skill": "",
		"immunities": ["freeze"],
		"description": "魔法防御+10, 免疫冰冻"
	},
	"cursed_blade": {
		"id": "cursed_blade",
		"name": "诅咒之刃",
		"slot": "weapon",
		"stats": {"atk": 25, "speed": -5},
		"granted_skill": "",
		"immunities": [],
		"description": "攻击+25, 速度-5"
	},
	"guardian_plate": {
		"id": "guardian_plate",
		"name": "守护铠甲",
		"slot": "offhand",
		"stats": {"def": 15, "hp": 20, "guard_rate": 10},
		"granted_skill": "",
		"immunities": [],
		"description": "防御+15, HP+20, 格挡率+10%"
	},
}


func get_equipment(id: String) -> Dictionary:
	if EQUIPMENT.has(id):
		return EQUIPMENT[id].duplicate(true)
	push_error("EquipmentDatabase: Unknown equipment id: " + id)
	return {}


func get_all_equipment() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in EQUIPMENT:
		result.append(EQUIPMENT[key].duplicate(true))
	return result


func get_equipment_for_slot(slot: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in EQUIPMENT:
		var eq = EQUIPMENT[key]
		if eq.slot == slot or (slot == "accessory" and eq.slot == "accessory"):
			result.append(eq.duplicate(true))
	return result
