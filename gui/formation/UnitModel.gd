## =====================================================================
## UnitModel — 一个「运行期单位」（花名册里的一个人）
## =====================================================================
## 区分两种数据，这是本项目数据层的核心概念：
##   静态角色数据 char_data —— 来自 data/characters.json，只读、全局共享、永不修改。
##                             比如「亚连」这个角色的基础属性、职业、技能表。
##   运行期单位   UnitModel  —— 玩家实际拥有的那个人，有等级、经验、装备、策略。
##                             同一个角色理论上可以造出多个单位实例。
##
## 类比 Python：char_data 像是类定义/配置表的一行，UnitModel 像是它的一个实例。
##
## 装备槽固定 4 个（沿用 fullver-1 的设计）：weapon / shield / acc1 / acc2
## 技能编程 strategy 最多 8 行，每行 {skill, cond1, cond2}（FF12 gambit 那一套）。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## class_name UnitModel   → 注册全局类型名，别处可以写 var u: UnitModel
## extends RefCounted     → 引用计数对象。没有节点、不进场景树，纯数据。
##                          用 UnitModel.new() 创建，没人引用时自动回收（类似 Python 对象）。
## func _init(...)        → 构造函数，等价于 Python 的 __init__
## var x: int = 0         → 带类型注解的字段。GDScript 的类型是**运行时强制**的，
##                          比 Python 的 type hint 严格得多，类型不符会直接报错。
## Dictionary / Array     → 等价于 Python 的 dict / list
## d.duplicate(true)      → 深拷贝，等价于 copy.deepcopy()
##                          （不加 true 是浅拷贝。Dictionary 是引用类型，不拷贝会共享！）
## str(x)                 → 转字符串，等价于 Python 的 str()
## "%s" % [a]            → 字符串格式化，和 Python 的 % 用法一致
## =====================================================================
class_name UnitModel
extends RefCounted

## 4 个装备槽的定义。key 是存储用的英文键，label 是界面显示的中文。
## icon 是「资源锚点名」——有对应美术资源就用图，没有就回退显示这个 emoji。
const EQUIP_SLOTS := [
	{ "key": "weapon", "label": "武器", "icon": "⚔",  "subtypes": ["sword", "axe", "spear", "bow", "staff"] },
	{ "key": "shield", "label": "盾牌", "icon": "🛡", "subtypes": ["shield", "greatshield"] },
	{ "key": "acc1",   "label": "饰品一", "icon": "💍", "subtypes": ["accessory"] },
	{ "key": "acc2",   "label": "饰品二", "icon": "💍", "subtypes": ["accessory"] },
]

## 技能编程最多几行。
const MAX_STRATEGY_ROWS := 8

# ---------------- 存档字段（会被序列化的）----------------
var id: String = ""              # 运行期唯一 id，形如 "unit_3"
var character_id: String = ""    # 指向 characters.json 的 id，形如 "alain"
var level: int = 1               # 等级
var exp: int = 0                 # 当前经验值
var equipment: Dictionary = {}   # 槽位键 → 装备 id，例：{"weapon": "sword_bronze"}
var strategy: Array = []         # [{skill, cond1, cond2}, ...]，最多 8 行

# ---------------- 只读引用（不序列化，构造时注入）----------------
var char_data: Dictionary = {}   # characters.json 里那一条
var class_data: Dictionary = {}  # classes.json 里那一条；查不到时是空字典 {}

# ---------------- 派生属性（构造时算好，之后只读）----------------
var size: int = 20               # 规模：占多少队伍容量（注意：占格数永远是 1）
var leadership: int = 60         # 领导力：当队长时能容纳的全队规模上限
var ap: int = 1                  # 主动点
var pp: int = 1                  # 被动点


## 构造。char_data 必传；class_data 查不到时传 {} 即可（有 17/70 个角色确实查不到）。
func _init(p_id: String = "", p_char_data: Dictionary = {}, p_class_data: Dictionary = {}, p_level: int = 1) -> void:
	id = p_id
	char_data = p_char_data
	class_data = p_class_data
	character_id = str(char_data.get("id", ""))
	level = maxi(1, p_level)  # maxi = 整数版 max，防止传进来 0 或负数
	_refresh_derived()


## 重算派生属性。等级变化后需要重新调用（领导力随等级成长）。
func _refresh_derived() -> void:
	size = TeamRules.size_for(char_data)
	leadership = TeamRules.leadership_for(char_data, level)
	var ap_pp := TeamRules.ap_pp_for(class_data)
	ap = ap_pp.x
	pp = ap_pp.y


## 显示名。characters.json 里叫 name_zh；查不到就退回 id，再不行显示「未知单位」。
func display_name() -> String:
	var n := str(char_data.get("name_zh", ""))
	if not n.is_empty():
		return n
	return character_id if not character_id.is_empty() else "未知单位"


## 职业中文名，用于成员行的副标题。
## 注意没有起名叫 class_name_xxx —— class_name 是 GDScript 关键字，容易踩雷。
func class_label() -> String:
	var n := str(char_data.get("class_zh", ""))
	return n if not n.is_empty() else "无职业"


## 升到下一级所需经验。用最简单的线性公式——本界面只做展示，不做养成。
func exp_to_next() -> int:
	return level * 100


## 头像用的「资源锚点名」。有 res://assets/portrait_<character_id>.svg 就用图，
## 没有就由 UI 层回退成带首字的色块（见 FormationSkin.make_portrait）。
func portrait_asset() -> String:
	return "portrait_%s" % character_id


# ---------------- 装备 ----------------

## 取某个槽位上的装备 id；空槽返回空串。
func equipped_id(slot_key: String) -> String:
	return str(equipment.get(slot_key, ""))


## 装备到指定槽位。同一件装备若已在别的槽位上，先从那里卸下（保证一件只占一个槽）。
func equip(slot_key: String, equipment_id: String) -> void:
	for k in equipment.keys():
		if equipment[k] == equipment_id:
			equipment.erase(k)
	equipment[slot_key] = equipment_id


## 卸下指定槽位。
func unequip(slot_key: String) -> void:
	equipment.erase(slot_key)


# ---------------- 技能编程（gambit）----------------

## 新增一行策略。已达 8 行上限时返回 false。
func add_strategy_row() -> bool:
	if strategy.size() >= MAX_STRATEGY_ROWS:
		return false
	strategy.append({ "skill": "", "cond1": "", "cond2": "" })
	return true


## 删除第 idx 行策略。
func remove_strategy_row(idx: int) -> void:
	if idx >= 0 and idx < strategy.size():
		strategy.remove_at(idx)


## 设置第 idx 行的某一格（field ∈ "skill" / "cond1" / "cond2"）。
## value 传空串表示「卸下」。
func set_strategy_cell(idx: int, field: String, value: String) -> void:
	if idx < 0 or idx >= strategy.size():
		return
	var row = strategy[idx]
	if typeof(row) == TYPE_DICTIONARY:
		row[field] = value


# ---------------- 序列化（留给存档功能，本界面暂未用到）----------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"character_id": character_id,
		"level": level,
		"exp": exp,
		# 深拷贝：Dictionary/Array 是引用类型，不拷贝的话存档和运行期会共享同一份，
		# 之后改运行期数据会连存档一起改掉。这是 GDScript 相对 Python 更容易踩的坑。
		"equipment": equipment.duplicate(true),
		"strategy": strategy.duplicate(true),
	}
