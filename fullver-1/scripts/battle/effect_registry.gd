class_name EffectRegistry
## =============================================================================
## EffectRegistry — 效果注册表（战斗被动时点体系的唯一权威来源）
## =============================================================================
## 作用：把「效果类型 → 触发时点」的映射集中在一处，供两个消费方使用：
##   1. BattleEngine — 被动分派时查表（_dispatch_passives 的 EFFECT_TRIGGERS）
##   2. DataManager.validate_effect_coverage() — 数据校验（防效果静默丢失）
##
## 完整移植自 demo-1 battle_manager.gd 的 EFFECT_TRIGGERS（20 个时点映射），
## 并补上 demo-1 数据里有但引擎没实现的 heal_on_kill（demo-1 的已知缺陷，
## 本项目在引擎中补齐实现）。
##
## 类比 Python：
##   相当于一个常量模块 EFFECT_TRIGGERS = {...}，全部 static 方法，
##   不产生实例（GDScript 里 static func 就是类方法）。
## =============================================================================

# ==================================================================
#  被动效果 → 触发时点 映射表
# ==================================================================
# 时点含义（与 demo-1 口径一致）：
#   battle_start  — 战斗开始（先制、提速类被动）
#   round_start   — 每回合开始（低血量回 PP、再生）
#   before_action — 行动前（攻击提升、必中、暴击率提升）
#   on_hit        — 命中时（命中吸血、命中回 PP）
#   on_kill       — 击杀时（击杀回 AP/PP、追击）
#   after_hit     — 受击后（反击、掩护队友加防）
#   battle_end    — 战斗结束（战后治疗）
# ==================================================================
const PASSIVE_TRIGGERS: Dictionary = {
	"initiative_up": "battle_start",
	"first_strike": "battle_start",
	"pp_on_low_hp": "round_start",
	"regen": "round_start",
	"attack_up": "before_action",
	"power_boost": "before_action",
	"truestrike_once": "before_action",
	"truestrike": "before_action",
	"accuracy_up": "before_action",
	"crit_up": "before_action",
	"heal_on_hit": "on_hit",
	"lifesteal": "on_hit",
	"pp_on_hit": "on_hit",
	"ap_on_kill": "on_kill",
	"pp_on_kill": "on_kill",
	"follow_up": "on_kill",
	"attack_up_on_kill": "on_kill",
	"counter": "after_hit",
	"ally_defense_up": "after_hit",
	"end_of_battle_heal": "battle_end",
	# --- 本项目补齐（demo-1 数据中有、引擎遗漏）---
	"heal_on_kill": "on_kill",
}

# ==================================================================
#  上下文效果集 (Contextual Effects)
# ==================================================================
# 不走时点分派的被动效果——在攻击结算链内部被引擎直接消费
# （demo-1 的 _resolve_attack / 被攻击判定链里处理）：
#   cover_ally      — 掩护队友
#   evade_once      — 单次闪避
#   guard_medium    — 中型格挡
#   guard_seal      — 封印格挡
#   counter         — 已在时点表（after_hit）
# 本项目引擎（P6）移植并校验后，此列表与 BattleEngine 实际消费集合保持一致。
# ==================================================================
const CONTEXTUAL_EFFECTS: Array[String] = [
	"cover_ally",
	"evade_once",
	"guard_medium",
	"guard_seal",
	"damage_reduce",
	"damage_taken_down",
	"crit_down",
	"evade_buff",
	"defense_up",
	"mag_def_up",
	"def_up",
	"debuff_negate",
]


## 获取被动时点映射表（供引擎与校验共用）
static func get_passive_triggers() -> Dictionary:
	return PASSIVE_TRIGGERS


## 获取上下文效果集（供数据校验用）
static func get_contextual_effects() -> Array[String]:
	return CONTEXTUAL_EFFECTS


## 查询某个效果类型对应的触发时点。未注册返回空串。
static func trigger_for(effect_type: String) -> String:
	return PASSIVE_TRIGGERS.get(effect_type, "")


## 判断某个效果类型是否已注册（时点表或上下文集）
static func is_registered(effect_type: String) -> bool:
	return PASSIVE_TRIGGERS.has(effect_type) or (effect_type in CONTEXTUAL_EFFECTS)
