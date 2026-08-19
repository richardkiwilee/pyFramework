class_name BattleUnit
extends RefCounted
## =============================================================================
## BattleUnit — 战斗单位（战术层）
## =============================================================================
## 修正 demo-1 的缺陷：demo-1 的战斗单位是裸 Dictionary（无类型保护、
## UI 引用直接挂在数据上），本项目改为强类型类（docs/00-design.md §9.1）。
##
## 职责：承载一个单位在一场战斗中的全部状态。
## 与领域层 Unit 的区别：Unit 是战略层持久状态（存档），BattleUnit 是
## 战斗临时状态（属性现场推导、不存档、战斗结束即弃）。
##
## 类比 Python：
##   Unit（战略）≈ 数据库里的行；BattleUnit ≈ 每次战斗新建的运行时对象。
## =============================================================================

# ---------------- 身份 ----------------
## 角色数据 ID（data/characters.json）
var char_id: String = ""
var name_zh: String = ""
var name_en: String = ""
var class_zh: String = ""
## 是否敌方（false = 玩家方/进攻方）
var is_enemy: bool = false
## 战斗站位 position 0-8（position < 3 = 前排；由编队槽位映射而来）
var position: int = 0
## 来源编队槽位（调试/统计用，不参与战斗逻辑）
var source_slot: int = 0

# ---------------- 战斗属性 ----------------
var max_hp: int = 80
var hp: int = 80
var atk: int = 30
var def: int = 20
var mag: int = 30
var mdf: int = 20
var spd: int = 30
var acc: int = 100
var eva: int = 20
var crit: int = 10
var guard: int = 10

# ---------------- 资源 ----------------
## 行动点（主动技能消耗，每回合恢复满）
var ap: int = 2
var max_ap: int = 2
## 被动点（被动技能消耗，每回合恢复满）
var pp: int = 1
var max_pp: int = 1

# ---------------- 技能与状态 ----------------
## 已解析的技能列表（skills.json 完整数据字典）
var skills: Array = []
var is_alive: bool = true
## 装备映射 {"weapon": eq_id, "shield": eq_id}（属性已在创建时折算进基础属性）
var equipment: Dictionary = {}
## 异常状态 [{type: String, turns: int}]
var statuses: Array = []
## 临时属性修正 {"atk": 1.3, "def": 1.2, "crit": 1.5, "power": 50, "acc": 1.2, "truestrike": 1}
## 行动结束时清空（demo-1 口径：临时 buff 只持续一次行动）
var buffs: Dictionary = {}
## survive_fatal 是否已用（一次性被动）
var survived_fatal: bool = false

# ---------------- 统计 ----------------
var damage_dealt: int = 0
var damage_taken: int = 0


## 存活敌人池/友方池判断用：与 is_enemy 相反的阵营标记
func side_label() -> String:
	return "enemy" if is_enemy else "player"
