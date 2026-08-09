## 羁绊（Synergy）：部队中凑齐复数个相同词条触发（对应 pydemo/game/synergy.py）。
## tag_flat：拥有者每人 +per_unit_value*(count-1)；tier_bonus：按数量取最高档给持有者。
class_name Synergies
extends RefCounted

class SynergyDef:
	var id: String
	var tag: String
	var kind: String = "tag_flat"
	var attr: String = ""
	var per_unit_value: float = 0.0
	var tiers: Array = []

	func _init(id_: String, tag_: String, kind_: String = "tag_flat",
			attr_: String = "", per_unit_value_: float = 0.0, tiers_: Array = []) -> void:
		id = id_
		tag = tag_
		kind = kind_
		attr = attr_
		per_unit_value = per_unit_value_
		tiers = tiers_

static func load_synergies(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for sid in d:
		var s: Dictionary = d[sid]
		out[sid] = SynergyDef.new(sid, s["tag"], s.get("kind", "tag_flat"),
			s.get("attr", ""), float(s.get("per_unit_value", 0)), s.get("tiers", []))
	return out

## 根据部队各词条数量生成作用于每个单位的修正（count >= 2 触发）。
static func collect_synergy_mods(army_tags_count: Dictionary,
		army_units: Array, synergy_defs: Dictionary) -> Array:
	var mods: Array = []
	for syn in synergy_defs.values():
		var count := int(army_tags_count.get(syn.tag, 0))
		if count < 2:
			continue
		var holders: Array = []
		for u in army_units:
			if u.tags.has(syn.tag):
				holders.append(u)
		if syn.kind == "tag_flat":
			var val: float = syn.per_unit_value * (count - 1)
			for u in holders:
				mods.append(Modifier.Mod_.new(Modifier.Source.SYNERGY, syn.id, u.id,
					syn.attr, val, "flat"))
		elif syn.kind == "tier_bonus":
			var best: Dictionary = {}
			for t in syn.tiers:
				if count >= int(t["count"]):
					best = t
			if not best.is_empty():
				for u in holders:
					mods.append(Modifier.Mod_.new(Modifier.Source.SYNERGY, syn.id, u.id,
						best["attr"], float(best["value"]), best.get("op", "flat")))
	return mods
