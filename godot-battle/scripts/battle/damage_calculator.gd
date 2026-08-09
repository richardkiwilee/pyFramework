# damage_calculator.gd
# 伤害计算器 — 计算技能伤害
# RefCounted 纯代码类
class_name DamageCalculator extends RefCounted


# 命中率查表：hit - evasion → 实际命中率
static func hit_rate_table(diff: int) -> float:
	if diff >= 100:
		return 100.0
	elif diff >= 80:
		return 95.0
	elif diff >= 60:
		return 90.0
	elif diff >= 50:
		return 84.0
	elif diff >= 40:
		return 78.0
	elif diff >= 30:
		return 72.0
	elif diff >= 20:
		return 65.0
	elif diff >= 10:
		return 57.0
	elif diff >= 0:
		return 50.0
	elif diff >= -10:
		return 43.0
	elif diff >= -20:
		return 35.0
	elif diff >= -30:
		return 28.0
	elif diff >= -40:
		return 22.0
	elif diff >= -50:
		return 16.0
	elif diff >= -80:
		return 8.0
	else:
		return 0.0


# 检查属性克制（是否有克制标签交叉）
func is_class_counter(caster: Dictionary, target: Dictionary) -> bool:
	# 简化版属性克制：特定标签组合
	var caster_tags: Array = caster.get("tags", [])
	var target_tags: Array = target.get("tags", [])

	# 骑兵克制步兵（非枪兵）
	if caster_tags.has("cavalry") and target_tags.has("infantry") and not target_tags.has("cavalry"):
		# 枪兵反制骑兵
		if target.get("class_name", "") == "soldier":
			return false
		return true

	# 弓手克制飞行
	if caster.get("class_name", "") == "archer" and target_tags.has("flying"):
		return true

	# 法师克制重甲
	if caster_tags.has("caster") and target_tags.has("armored"):
		return true

	return false


# 计算伤害结果
func calculate(caster: Dictionary, target: Dictionary, skill: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"hit": false,
		"damage": 0,
		"crit": false,
		"guard": false,
		"killed": false,
		"drain_heal": 0,
		"message": ""
	}

	# 这个是治疗技能
	if skill.get("damage_type", "") == "heal":
		var heal_amount = int(caster.get("matk", 10) * skill.get("power", 100) / 100.0)
		heal_amount = max(1, heal_amount)
		result.hit = true
		result.damage = heal_amount
		result.message = "恢复 %d HP" % heal_amount
		return result

	# 黑暗状态 → 必定Miss
	if _has_status(target, "darkness"):
		result.message = "黑暗状态 — 攻击未命中！"
		return result

	# 闪避被动检查
	if skill.get("damage_type", "physical") != "heal" and _has_passive_ready(caster, target, "evade", skill):
		# 这里在battle_manager中处理，这里只是标记
		pass

	# 1. 命中判定
	var hit_diff = caster.get("hit", 90) - target.get("evasion", 10)
	# 近战攻击非枪兵单位 → 回避×2
	var is_melee = skill.get("range", "any") == "melee"
	var is_soldier = target.get("class_name", "") == "soldier"
	if is_melee and not is_soldier:
		hit_diff -= target.get("evasion", 10)

	# 眩晕/冰冻 → 回避=0
	if _has_status(target, "stun") or _has_status(target, "freeze"):
		hit_diff = caster.get("hit", 90)

	# 必中技能
	if skill.get("sure_hit", false):
		hit_diff = 999

	var hit_rate = hit_rate_table(hit_diff)
	if randf() * 100.0 > hit_rate:
		result.message = "未命中！"
		return result

	result.hit = true

	# 获取有效属性（含buff/debuff）
	var eff_atk = caster.get("atk", 10) + caster.get("buffs", {}).get("atk", 0)
	var eff_matk = caster.get("matk", 10) + caster.get("buffs", {}).get("matk", 0)
	var eff_def = target.get("def", 10) + target.get("buffs", {}).get("def", 0)
	var eff_mdef = target.get("mdef", 10) + target.get("buffs", {}).get("mdef", 0)

	# 2. 基础伤害
	var atk_stat = eff_atk if skill.get("damage_type", "physical") == "physical" else eff_matk
	var damage: float = atk_stat * skill.get("power", 100) / 100.0

	# 目标HP<50%加成（暗杀等技能）
	if skill.has("hp_below_50_bonus"):
		var hp_pct = float(target.get("hp_current", 0)) / float(max(1, target.get("hp", 1))) * 100.0
		if hp_pct < 50.0:
			damage += skill.hp_below_50_bonus

	# 3. 属性克制
	if is_class_counter(caster, target):
		damage *= 2.0
		result.message = "属性克制！"

	# 4. 暴击判定
	var crit_rate = caster.get("crit_rate", 5) + caster.get("buffs", {}).get("crit_rate", 0)
	if randf() * 100.0 < crit_rate:
		result.crit = true
		damage *= 1.5

	# 5. 防御/格挡（仅物理伤害）
	if skill.get("damage_type", "physical") == "physical":
		damage -= eff_def

		# 格挡封印
		if not _has_status(target, "guard_seal"):
			var guard_rate = target.get("guard_rate", 0) + target.get("buffs", {}).get("guard_rate", 0)
			if skill.get("damage_type", "physical") == "physical" and randf() * 100.0 < guard_rate:
				result.guard = true
				var guard_red = target.get("guard_reduction", 25) / 100.0
				damage *= (1.0 - guard_red)
	elif skill.get("damage_type", "physical") == "magical":
		damage -= eff_mdef

	damage = max(1, int(damage))
	result.damage = damage

	# 吸血
	if skill.has("drain"):
		result.drain_heal = int(damage * skill.drain / 100.0)

	# 构建消息
	if result.message == "":
		result.message = "造成 %d 伤害" % damage
	if result.crit:
		result.message = "暴击！" + result.message
	if result.guard:
		result.message = "格挡！" + result.message

	return result


func _has_status(unit: Dictionary, status_type: String) -> bool:
	for se in unit.get("status_effects", []):
		if se.get("type", "") == status_type:
			return true
	return false


func _has_passive_ready(caster: Dictionary, target: Dictionary, passive_type: String, skill: Dictionary) -> bool:
	return false  # 由 BattleManager 处理
