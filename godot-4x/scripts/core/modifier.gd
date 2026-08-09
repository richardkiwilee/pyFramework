## 统一修正管道（对应 pydemo/game/modifier.py，ADR-0002）。
## 所有修正源经同一条管道收集，按固定顺序计算：flat → pct → clamp，每阶段 floor。
class_name Modifier
extends RefCounted

enum Source {
	MOON = 0, DAY_NIGHT, TAG, SYNERGY, BELIEF, SKILL, ARTIFACT, TERRAIN, LANDMARK,
}

class Mod_:
	var source: int = Source.MOON
	var source_id: String = ""
	var target: String = ""
	var attr: String = ""
	var value: float = 0.0
	var op: String = "flat"   # "flat" | "pct"（pct 以小数表示，+10% = 0.1）

	func _init(source_: int = Source.MOON, source_id_: String = "", target_: String = "",
			attr_: String = "", value_: float = 0.0, op_: String = "flat") -> void:
		source = source_
		source_id = source_id_
		target = target_
		attr = attr_
		value = value_
		op = op_

## 按固定顺序计算：flat → pct → clamp，每阶段向下取整。
static func compute_attribute(base: float, mods: Array, attr: String,
		lo: float = -INF, hi: float = INF) -> float:
	var flat := 0.0
	var pct := 0.0
	for m in mods:
		if m.attr != attr:
			continue
		if m.op == "flat":
			flat += m.value
		elif m.op == "pct":
			pct += m.value
	var result := floorf(base + flat)
	result = floorf(result * (1.0 + pct))
	if lo > -INF:
		result = maxf(lo, result)
	if hi < INF:
		result = minf(hi, result)
	return floorf(result)
