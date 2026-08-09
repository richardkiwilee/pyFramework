## 单位与兵种词条（对应 pydemo/game/unit.py）。
## 17 项属性、等级 1~99、意志生还、装备 4 槽（def_id 库存模型）。
class_name Units
extends RefCounted

const MAJOR_TAGS: Array[String] = ["melee", "ranged", "magic"]
const TAG_CN: Dictionary = {
	"melee": "近战", "ranged": "远程", "magic": "魔法",
	"human": "人类", "cavalry": "骑兵", "archer": "弓兵",
}

const UNIT_ATTRS: Array[String] = [
	"occupy", "hp", "ap", "pp", "mana", "speed",
	"p_atk", "m_atk", "p_def", "m_def",
	"acc", "eva", "block", "crit", "luck", "will", "leadership",
]
const ATTR_BOUNDS: Dictionary = {
	"hp": [0, 99999], "ap": [0, 99], "pp": [0, 99], "mana": [0, 99], "speed": [1, 999],
	"occupy": [0, 99999], "p_atk": [0, 9999], "m_atk": [0, 9999],
	"p_def": [0, 9999], "m_def": [0, 9999],
	"acc": [0, 100], "eva": [0, 100], "block": [0, 100],
	"crit": [0, 100], "luck": [0, 100], "will": [0, 999], "leadership": [0, 99999],
	"mana_regen": [0, 999],
}
const ATTR_CN: Dictionary = {
	"hp": "生命", "ap": "行动点", "pp": "被动点", "mana": "魔力", "speed": "速度",
	"p_atk": "物攻", "m_atk": "魔攻", "p_def": "物防", "m_def": "魔防",
	"acc": "命中", "eva": "闪避", "block": "格挡", "crit": "暴击",
	"luck": "幸运", "will": "意志", "occupy": "占用", "leadership": "领导力",
	"mana_regen": "魔力恢复",
}

const LEVEL_CAP := 99
const ARTIFACT_SLOTS := 4   # 装备槽 0..3

# 意志生还：仅真人玩家有效；HP>1 将致死时 rng < will% 保留 1 HP；每场每单位 1 次。
const WILL_SURVIVAL_ENABLED := true
const WILL_BASE := 5.0
const WILL_GROWTH_NORMAL := 0.1
const WILL_GROWTH_HERO := 0.2

## 从 level 升到 level+1 所需经验（公差 5 等差数列）。
static func xp_to_next(level: int) -> int:
	return 5 * level

## 兵种定义（data/unit_types.json）。
class UnitType:
	var id: String
	var name: String
	var tags: Array = []           # 词条
	var recruit_cost: Dictionary = {}
	var base: Dictionary = {}
	var growth: Dictionary = {}
	var maintenance: Dictionary = {}
	var train_cost: Dictionary = {}
	var desc: String = ""

	func _init(id_: String, name_: String, tags_: Array, recruit_cost_: Dictionary = {},
			base_: Dictionary = {}, growth_: Dictionary = {},
			maintenance_: Dictionary = {}, train_cost_: Dictionary = {},
			desc_: String = "") -> void:
		id = id_
		name = name_
		tags = tags_.duplicate()
		recruit_cost = recruit_cost_
		base = base_
		growth = growth_
		maintenance = maintenance_
		train_cost = train_cost_
		desc = desc_

## 装备定义。
class Artifact:
	var id: String
	var name: String
	var effects: Array = []       # effect 原始 dict 列表
	var rarity: String = "common"

	func _init(id_: String, name_: String, effects_: Array = [],
			rarity_: String = "common") -> void:
		id = id_
		name = name_
		effects = effects_
		rarity = rarity_

## 单位实例。
class Unit:
	var id: String
	var type_id: String
	var name: String
	var tags: Array = []                  # 词条（本体 + 装备赋予）
	var base: Dictionary = {}             # 基础属性（含等级成长，不含情境修正）
	var artifacts: Array = []             # 装备 def_id 列表，槽位 0..3
	var is_hero: bool = false
	var skills: Array = []                # 习得技能 id
	var granted_skills: Array = []        # 装备赋予技能 id
	var cur_hp: float = 0
	var army_id: String = ""
	var cur_ap: float = 0
	var cur_pp: float = 0
	var cur_mana: float = 0
	var atb: float = 0
	var alive: bool = true
	var statuses: Dictionary = {}         # 状态类型 -> 剩余层数
	var node_id: String = ""
	var level: int = 1
	var xp: int = 0
	var growth: Dictionary = {}
	# 运行时标记（不入档）
	var _starved_this_turn: bool = false
	var _trained_this_turn: bool = false

	func _init(id_: String, type_id_: String, name_: String, tags_: Array,
			base_: Dictionary = {}, artifacts_: Array = [], is_hero_: bool = false,
			skills_: Array = [], granted_skills_: Array = [], cur_hp_: float = 0.0,
			army_id_: String = "", cur_ap_: float = 0.0, cur_pp_: float = 0.0,
			cur_mana_: float = 0.0, atb_: float = 0.0, alive_: bool = true,
			statuses_: Dictionary = {}, node_id_: String = "",
			level_: int = 1, xp_: int = 0, growth_: Dictionary = {}) -> void:
		id = id_
		type_id = type_id_
		name = name_
		tags = tags_.duplicate()
		base = base_
		artifacts = artifacts_.duplicate()
		is_hero = is_hero_
		skills = skills_.duplicate()
		granted_skills = granted_skills_.duplicate()
		cur_hp = cur_hp_
		if cur_hp <= 0:
			cur_hp = float(base.get("hp", 1))
		army_id = army_id_
		cur_ap = cur_ap_
		cur_pp = cur_pp_
		cur_mana = cur_mana_
		atb = atb_
		alive = alive_
		statuses = statuses_.duplicate()
		node_id = node_id_
		level = level_
		xp = xp_
		growth = growth_.duplicate()

	## 当前可用技能 = 习得 + 装备赋予。
	func effective_skills() -> Array:
		var out: Array = []
		out.append_array(skills)
		out.append_array(granted_skills)
		return out

	## 装备 tag_grant 词条合并进单位词条集合。
	func grant_tags_from_artifacts(artifact_defs: Dictionary) -> void:
		for def_id in artifacts:
			if def_id == null:
				continue
			var art: Variant = artifact_defs.get(def_id)
			if art == null:
				continue
			for e in art.effects:
				if e.get("type") == "tag_grant":
					if not tags.has(e["params"]["tag"]):
						tags.append(e["params"]["tag"])

	func occupy() -> int:
		return int(base.get("occupy", 1))

	func leadership() -> int:
		return int(base.get("leadership", 0))

	## 获得经验并升级；返回升了几级。升级时 HP 按比例保留。
	func gain_xp(amount: int) -> int:
		if level >= LEVEL_CAP:
			return 0
		xp += amount
		var levels_gained := 0
		while level < LEVEL_CAP and xp >= Units.xp_to_next(level):
			xp -= Units.xp_to_next(level)
			level += 1
			_apply_growth()
			levels_gained += 1
		return levels_gained

	func _apply_growth() -> void:
		var old_max := float(base.get("hp", 1))
		var old_cur := cur_hp
		for attr in growth:
			if attr == "occupy" or float(growth[attr]) == 0.0:
				continue
			var old_val := float(base.get(attr, 0.0))
			base[attr] = floorf(old_val + float(growth[attr]))
		var new_max := float(base.get("hp", old_max))
		if new_max > 0 and old_max > 0:
			cur_hp = floorf(new_max * old_cur / old_max)
		else:
			cur_hp = new_max

	func describe() -> String:
		var tagstr := ""
		for i in range(tags.size()):
			if i > 0:
				tagstr += "/"
			tagstr += TAG_CN.get(tags[i], tags[i])
		return "%s[%s] HP:%d/%d 速:%d 物攻:%d Lv%d" % [
			name, tagstr, int(cur_hp), int(base.get("hp", 1)),
			int(base.get("speed", 0)), int(base.get("p_atk", 0)), level]

static func load_unit_types(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for uid in d:
		var u: Dictionary = d[uid]
		out[uid] = UnitType.new(uid, u["name"], u.get("tags", []),
			u.get("recruit_cost", {}), u.get("base", {}), u.get("growth", {}),
			u.get("maintenance", {}), u.get("train_cost", {}), u.get("desc", ""))
	return out

static func load_artifacts(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for aid in d:
		var a: Dictionary = d[aid]
		out[aid] = Artifact.new(aid, a["name"], a.get("effects", []),
			a.get("rarity", "common"))
	return out
