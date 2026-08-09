## 资源与信念（对应 pydemo/game/economy.py）。
## 11 种全局资源 + 3 维信念（每维 [-100,+100]）。资源对象带本回合变动细项
## （DeltaItem），面板以"现存(净变动)"展示，悬停弹窗呈现细项（godot 迁移点）。
class_name Economy
extends RefCounted

# 资源来源类型（delta 溯源）
const SOURCE_BUILD := "build"
const SOURCE_MAINT := "maint"
const SOURCE_EVENT := "event"
const SOURCE_RECRUIT := "recruit"
const SOURCE_TRAIN := "train"
const SOURCE_SUPPLY := "supply"
const SOURCE_INIT := "init"
const SOURCE_UNKNOWN := "unknown"

const RESOURCE_TYPES: Array[String] = [
	"gold", "food", "wood", "stone", "iron", "mana_stone",
	"tech", "culture", "faith", "luxury", "decree",
]
const RESOURCE_CN: Dictionary = {
	"gold": "金币", "food": "食物", "wood": "木材", "stone": "石材",
	"iron": "铁矿", "mana_stone": "魔石", "tech": "科技", "culture": "文化",
	"faith": "信仰", "luxury": "奢侈品", "decree": "政令",
}

const BELIEF_DIMS: Array[String] = ["morality", "utility", "liberty"]
const BELIEF_CN: Dictionary = {"morality": "道德", "utility": "功利", "liberty": "自由"}
const BELIEF_BOUND := 100

## 一条资源变动细项。
class DeltaItem:
	var source: String = SOURCE_UNKNOWN
	var value: int = 0
	var stronghold: String = ""
	var building: String = ""
	func _init(source_: String = SOURCE_UNKNOWN, value_: int = 0,
			stronghold_: String = "", building_: String = "") -> void:
		source = source_
		value = value_
		stronghold = stronghold_
		building = building_

## 单个全局资源对象：存量 + 本回合变动细项 + 投影（下回合预估产出）。
class ResItem:
	var kind: String = "gold"
	var amount: int = 0
	var deltas: Array = []          # [DeltaItem]
	var _projected: int = 0

	func _init(kind_: String = "gold", amount_: int = 0) -> void:
		kind = kind_
		amount = amount_

	func add(v: int, source: String = SOURCE_UNKNOWN,
			stronghold: String = "", building: String = "") -> void:
		amount += v
		deltas.append(DeltaItem.new(source, v, stronghold, building))

	func add_projected(v: int) -> void:
		_projected += v

	func clear_projected() -> void:
		_projected = 0

	func net() -> int:
		var s := 0
		for d in deltas:
			s += d.value
		return s

	## 面板用净变动 = 本回合已结算净变动 + 下回合投影预估。
	func display_net() -> int:
		return net() + _projected

	func reset_turn() -> void:
		deltas.clear()
		_projected = 0

	## "20(+1)" 形式（含投影）。
	func output() -> String:
		var n := display_net()
		var sign := "+" if n >= 0 else ""
		return "%d(%s%d)" % [amount, sign, n]

## 阵营持有的全局资源容器。
class Resources:
	var amounts: Dictionary = {}     # kind -> int
	var _resources: Dictionary = {}  # kind -> Resource（懒建）

	func _init(amounts_: Dictionary = {}) -> void:
		if amounts_.is_empty():
			for k in RESOURCE_TYPES:
				amounts[k] = 0
		else:
			amounts = amounts_.duplicate()

	func _res(k: String) -> ResItem:
		if not _resources.has(k):
			_resources[k] = ResItem.new(k, amounts.get(k, 0))
		else:
			_resources[k].amount = amounts.get(k, 0)
		return _resources[k]

	func get_amount(k: String) -> int:
		return int(amounts.get(k, 0))

	func add(k: String, v: int, source: String = SOURCE_UNKNOWN,
			stronghold: String = "", building: String = "") -> void:
		amounts[k] = get_amount(k) + v
		_res(k).add(v, source, stronghold, building)

	func can_afford(costs: Dictionary) -> bool:
		for k in costs:
			if get_amount(k) < int(costs[k]):
				return false
		return true

	## 扣资源：任一不足则全失败（先整体校验）。
	func pay(costs: Dictionary, source: String = SOURCE_UNKNOWN,
			stronghold: String = "", building: String = "") -> bool:
		if not can_afford(costs):
			return false
		for k in costs:
			add(k, -int(costs[k]), source, stronghold, building)
		return true

	func reset_turn() -> void:
		for k in _resources:
			_resources[k].reset_turn()

	## 取某资源的对象视图（output/net/deltas）。
	func resource(k: String) -> ResItem:
		return _res(k)

	## 某资源本回合净变动细项（悬停弹窗用）。
	func deltas_of(k: String) -> Array:
		return _res(k).deltas

class Belief:
	var values: Dictionary = {}   # dim -> int

	func _init(values_: Dictionary = {}) -> void:
		if values_.is_empty():
			for d in BELIEF_DIMS:
				values[d] = 0
		else:
			values = values_.duplicate()

	func get_value(dim: String) -> int:
		return int(values.get(dim, 0))

	func change(dim: String, delta: int) -> void:
		var v: int = get_value(dim) + delta
		values[dim] = clampi(v, -BELIEF_BOUND, BELIEF_BOUND)

	func meets(dim: String, threshold: int) -> bool:
		return get_value(dim) >= threshold

	func describe() -> String:
		var parts: Array[String] = []
		for d in BELIEF_DIMS:
			parts.append("%s:%+d" % [BELIEF_CN.get(d, d), get_value(d)])
		return "  ".join(parts)
