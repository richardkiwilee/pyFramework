# skill_database.gd
# Autoload — 技能数据库
# 提供所有技能的预定义数据
extends Node

# 主动技能（红色，消耗AP）
const SKILLS: Dictionary = {
	# ===== 主动技能 =====
	"heavy_slash": {
		"id": "heavy_slash",
		"name": "重斩",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 150,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"effects": [],
		"description": "对单个敌人造成150%物理伤害"
	},
	"wide_slash": {
		"id": "wide_slash",
		"name": "横扫",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 120,
		"damage_type": "physical",
		"target_type": "row_enemy",
		"range": "melee",
		"effects": [],
		"description": "对一排敌人造成120%物理伤害"
	},
	"poison_slash": {
		"id": "poison_slash",
		"name": "毒刃",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 100,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"effects": [{"type": "poison", "duration": 3}],
		"description": "对单个敌人造成100%物理伤害，附加中毒(3回合)"
	},
	"pierce": {
		"id": "pierce",
		"name": "穿刺",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 150,
		"damage_type": "physical",
		"target_type": "column_enemy",
		"range": "melee",
		"effects": [],
		"description": "贯穿一列敌人，造成150%物理伤害"
	},
	"fireball": {
		"id": "fireball",
		"name": "火球术",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 130,
		"damage_type": "magical",
		"target_type": "single_enemy",
		"range": "any",
		"effects": [{"type": "burn", "duration": 3}],
		"description": "对单个敌人造成130%魔法伤害，附加灼烧(3回合)"
	},
	"icebolt": {
		"id": "icebolt",
		"name": "冰箭",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 110,
		"damage_type": "magical",
		"target_type": "single_enemy",
		"range": "any",
		"effects": [{"type": "freeze", "duration": 1}],
		"description": "对单个敌人造成110%魔法伤害，附加冰冻(1回合)"
	},
	"heal": {
		"id": "heal",
		"name": "治疗",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 120,
		"damage_type": "heal",
		"target_type": "single_ally",
		"range": "any",
		"effects": [],
		"description": "恢复单个友方单位HP（基于魔法攻击×120%）"
	},
	"group_heal": {
		"id": "group_heal",
		"name": "群体治疗",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 2,
		"power": 80,
		"damage_type": "heal",
		"target_type": "row_ally",
		"range": "any",
		"effects": [],
		"description": "恢复一排友方单位HP（基于魔法攻击×80%）"
	},
	"precise_shot": {
		"id": "precise_shot",
		"name": "精准射击",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 120,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "any",
		"effects": [],
		"sure_hit": true,
		"description": "必中的射击，造成120%物理伤害"
	},
	"shadow_strike": {
		"id": "shadow_strike",
		"name": "暗杀",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 180,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"effects": [],
		"hp_below_50_bonus": 50,  # 目标HP<50%时威力+50
		"description": "对单个敌人造成180%物理伤害，HP<50%时威力+50"
	},
	"dark_slash": {
		"id": "dark_slash",
		"name": "暗黑斩",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 150,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"effects": [],
		"description": "暗黑骑士的强力斩击，造成150%物理伤害"
	},
	"drain_blade": {
		"id": "drain_blade",
		"name": "吸血刃",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 120,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"effects": [],
		"drain": 50,  # 吸取50%伤害为HP
		"description": "造成120%物理伤害，恢复50%伤害量的HP"
	},
	"flame_storm": {
		"id": "flame_storm",
		"name": "烈焰风暴",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 2,
		"power": 120,
		"damage_type": "magical",
		"target_type": "row_enemy",
		"range": "any",
		"effects": [{"type": "burn", "duration": 2}],
		"description": "对一排敌人造成120%魔法伤害，附加灼烧"
	},
	"shield_bash": {
		"id": "shield_bash",
		"name": "盾击",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 100,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"effects": [{"type": "stun", "duration": 1}],
		"description": "造成100%物理伤害，附加眩晕(1回合)"
	},
	"phantom_arrow": {
		"id": "phantom_arrow",
		"name": "暗影箭",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 130,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "any",
		"effects": [],
		"description": "暗影弓手的箭矢，造成130%物理伤害"
	},
	"paralyze_arrow": {
		"id": "paralyze_arrow",
		"name": "麻醉箭",
		"type": "active",
		"color": "red",
		"cost_type": "AP",
		"cost": 1,
		"power": 80,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "any",
		"effects": [{"type": "stun", "duration": 1}],
		"description": "造成80%物理伤害，附加眩晕(1回合)"
	},

	# ===== 被动技能 =====
	"guard": {
		"id": "guard",
		"name": "格挡",
		"type": "passive",
		"color": "blue",
		"cost_type": "PP",
		"cost": 1,
		"power": 0,
		"damage_type": "none",
		"target_type": "self",
		"range": "self",
		"trigger": "before_take_damage",
		"effects": [{"type": "guard_boost", "guard_rate_bonus": 50, "guard_reduction": 50, "duration": 1}],
		"description": "受到物理攻击时，提升格挡率和格挡减伤"
	},
	"heavy_cover": {
		"id": "heavy_cover",
		"name": "重装掩护",
		"type": "passive",
		"color": "blue",
		"cost_type": "PP",
		"cost": 1,
		"power": 0,
		"damage_type": "none",
		"target_type": "single_ally",
		"range": "any",
		"trigger": "ally_attacked",
		"effects": [{"type": "cover", "damage_reduction": 50}],
		"description": "代替队友承受伤害，并减免50%"
	},
	"follow_slash": {
		"id": "follow_slash",
		"name": "追击",
		"type": "passive",
		"color": "blue",
		"cost_type": "PP",
		"cost": 1,
		"power": 75,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"trigger": "ally_attacked",
		"effects": [],
		"description": "友方被攻击时，对攻击者进行追击"
	},
	"counter": {
		"id": "counter",
		"name": "反击",
		"type": "passive",
		"color": "blue",
		"cost_type": "PP",
		"cost": 1,
		"power": 120,
		"damage_type": "physical",
		"target_type": "single_enemy",
		"range": "melee",
		"trigger": "after_take_damage",
		"effects": [],
		"description": "受到攻击后，对攻击者进行反击"
	},
	"evade": {
		"id": "evade",
		"name": "闪避",
		"type": "passive",
		"color": "blue",
		"cost_type": "PP",
		"cost": 1,
		"power": 0,
		"damage_type": "none",
		"target_type": "self",
		"range": "self",
		"trigger": "before_take_damage",
		"effects": [{"type": "evade_attack"}],
		"description": "闪避一次即将命中的攻击"
	},
}


## 获取技能数据
func get_skill(id: String) -> Dictionary:
	if SKILLS.has(id):
		return SKILLS[id].duplicate(true)
	push_error("SkillDatabase: Unknown skill id: " + id)
	return {}


## 获取所有技能ID
func get_all_skill_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in SKILLS:
		ids.append(key)
	return ids
