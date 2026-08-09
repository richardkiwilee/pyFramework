## 事件系统（对应 pydemo/game/events.py）：回合开始随机触发的选择支。
class_name GameEvents
extends RefCounted

const EVENT_TRIGGER_CHANCE := 0.40   # maybe_trigger_event 触发概率，仅玩家

class EventOption:
	var label: String
	var effects: Dictionary = {}

	func _init(label_: String, effects_: Dictionary = {}) -> void:
		label = label_
		effects = effects_

class GameEvent:
	var id: String
	var title: String
	var text: String
	var options: Array = []

	func _init(id_: String, title_: String, text_: String, options_: Array = []) -> void:
		id = id_
		title = title_
		text = text_
		options = options_

static func load_events(event_defs: Dictionary) -> Array:
	var out: Array = []
	for eid in event_defs:
		var d: Dictionary = event_defs[eid]
		var opts: Array = []
		for o in d.get("options", []):
			opts.append(EventOption.new(o.get("label", ""), o.get("effects", {})))
		out.append(GameEvent.new(eid, d.get("title", ""), d.get("text", ""), opts))
	return out

## 应用选项效果，返回结果描述。
static func apply_option(opt: EventOption, resources: Economy.Resources,
		belief: Economy.Belief) -> String:
	var parts: Array[String] = []
	var eff: Dictionary = opt.effects
	for dim in eff.get("belief", {}):
		var delta := int(eff["belief"][dim])
		belief.change(dim, delta)
		parts.append("%s %+d" % [Economy.BELIEF_CN.get(dim, dim), delta])
	for k in eff.get("resources", {}):
		var v := int(eff["resources"][k])
		resources.add(k, v, Economy.SOURCE_EVENT)
		parts.append("%s %+d" % [Economy.RESOURCE_CN.get(k, k), v])
	return "、".join(parts) if not parts.is_empty() else "无变化"

static func random_event(events: Array, rng: RandomNumberGenerator) -> GameEvent:
	if events.is_empty():
		return null
	return events[rng.randi() % events.size()]
