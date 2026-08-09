## 数据驱动的技能/被动效果解释器（对应 pydemo/game/effects.py，ADR-0001）。
## 技能 = 数据描述（效果类型 + 参数）+ 统一解释器；新增技能只改数据，不重编译。
class_name Effects
extends RefCounted

const SKILL_ACTIVE := "active"
const SKILL_PASSIVE := "passive"
const SKILL_PERK := "perk"

class Effect:
	var effect_type: String
	var params: Dictionary = {}
	var trigger: String = "passive"
	var ap_cost: int = 0
	var pp_cost: int = 0
	var mana_cost: int = 0
	var trigger_point: String = ""

	func _init(effect_type_: String, params_: Dictionary = {}, trigger_: String = "passive",
			ap_cost_: int = 0, pp_cost_: int = 0, mana_cost_: int = 0,
			trigger_point_: String = "") -> void:
		effect_type = effect_type_
		params = params_
		trigger = trigger_
		ap_cost = ap_cost_
		pp_cost = pp_cost_
		mana_cost = mana_cost_
		trigger_point = trigger_point_

## 从技能数据定义构造 Effect 列表。
static func build_skill_effects(skill_def: Dictionary) -> Array:
	var out: Array = []
	for e in skill_def.get("effects", []):
		out.append(Effect.new(e.get("type", ""), e.get("params", {}),
			e.get("trigger", "passive"), int(e.get("ap_cost", 0)),
			int(e.get("pp_cost", 0)), int(e.get("mana_cost", 0)),
			e.get("trigger_point", "")))
	return out

## 技能 kind，缺省 perk（兼容旧无 kind 字段的被动修正技能）。
static func skill_kind(skill_def: Dictionary) -> String:
	if skill_def.is_empty():
		return SKILL_PERK
	return skill_def.get("kind", SKILL_PERK)

## 把一组被动效果展开为修正（作用于 owner_id）。tag_grant/skill_grant 不产出修正。
static func collect_passive_modifiers(effects: Array, owner_id: String,
		owner_tags: Array, army_tags_count: Dictionary,
		source: int, source_id: String) -> Array:
	var mods: Array = []
	for eff in effects:
		if eff.trigger != "passive":
			continue
		var p: Dictionary = eff.params
		match eff.effect_type:
			"flat_attr":
				mods.append(Modifier.Mod_.new(source, source_id, owner_id,
					p["attr"], float(p["value"]), "flat"))
			"pct_attr":
				mods.append(Modifier.Mod_.new(source, source_id, owner_id,
					p["attr"], float(p["value"]), "pct"))
			"tag_bonus":
				if owner_tags.has(p["tag"]):
					mods.append(Modifier.Mod_.new(source, source_id, owner_id,
						p["attr"], float(p["value"]), p.get("op", "flat")))
			"moon_regen":
				mods.append(Modifier.Mod_.new(source, source_id, owner_id,
					"mana_regen", float(p["scale"]), "pct"))
			"aura_flat":
				mods.append(Modifier.Mod_.new(source, source_id, owner_id,
					p["attr"], float(p["value"]), "flat"))
	return mods

## 施加状态（重施加取 max）；返回状态名。
static func apply_status_from_effect(eff: Effect, target) -> Array:
	var applied: Array = []
	var p: Dictionary = eff.params
	var st: String = p.get("status", "")
	if st == "":
		return applied
	var layers: Variant = p.get("duration")
	var name := Triggers.apply_status(target, st, layers)
	if name != "":
		applied.append(name)
	return applied

## 执行一条主动效果（ap_damage 走统一命中管道）。返回 {dmg, kind, status_applied}。
static func execute_active_effect(eff: Effect, ctx, attacker, target) -> Dictionary:
	var p: Dictionary = eff.params
	var et := eff.effect_type
	if et == "ap_damage":
		var kind: String = p.get("kind", "physical")
		var value := int(p.get("value", 0))
		var res = ctx.resolve_strike.call(ctx, attacker, target, kind, value)
		return {"dmg": res.dmg, "kind": res.kind, "status_applied": []}
	if et == "apply_status":
		return {"dmg": 0, "kind": "", "status_applied": apply_status_from_effect(eff, target)}
	return {"dmg": 0, "kind": "", "status_applied": []}

## 执行一条被动效果。返回同 execute_active_effect。
static func execute_passive_effect(eff: Effect, ctx, actor, target) -> Dictionary:
	var p: Dictionary = eff.params
	var et := eff.effect_type
	if et == "apply_status":
		return {"dmg": 0, "kind": "", "status_applied": apply_status_from_effect(eff, target)}
	if et == "ap_damage":
		var kind: String = p.get("kind", "physical")
		var value := int(p.get("value", 0))
		var res = ctx.resolve_strike.call(ctx, actor, target, kind, value)
		return {"dmg": res.dmg, "kind": res.kind, "status_applied": []}
	return {"dmg": 0, "kind": "", "status_applied": []}
