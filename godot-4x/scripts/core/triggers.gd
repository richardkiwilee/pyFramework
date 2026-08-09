## 触发时点 / 状态 / 策略条件（对应 pydemo/game/triggers.py，ADR-0010/0011）。
## 状态采用消费模型（无 tick 计时）：按消费方式耗层，归 0 解除，battle_end 清场。
class_name Triggers
extends RefCounted

enum TriggerPoint {
	BATTLE_START = 0, BATTLE_END,
	SELF_ATTACK_START, SELF_ATTACK_END,
	ALLY_ATTACKED_START, ALLY_ATTACKED_END,
	ON_BLOCK, ON_EVA, AFTER_PHYS, AFTER_MAGIC,
}

const TRIGGER_POINTS: Array = ["battle_start", "battle_end",
	"self_attack_start", "self_attack_end",
	"ally_attacked_start", "ally_attacked_end",
	"on_block", "on_eva", "after_phys", "after_magic"]

const STATUS_CN: Dictionary = {"frozen": "冰封", "debuff": "减益"}

enum StatusConsume { BATTLE_LONG = 0, ON_SELF_ATTACK, ON_SELF_HIT }

## 状态元数据：类型 -> [默认层数, 消费方式]
const STATUS_META: Dictionary = {
	"frozen": [1, StatusConsume.ON_SELF_ATTACK],
	"debuff": [2, StatusConsume.BATTLE_LONG],
}

# ---- 状态读写 ----
static func status_layers(u, status: String) -> int:
	return int(u.statuses.get(status, 0))

static func has_status(u, status: String) -> bool:
	return status_layers(u, status) > 0

static func apply_status(u, status: String, layers: Variant = null) -> String:
	if not STATUS_META.has(status):
		return ""
	var default_layers: int = STATUS_META[status][0]
	if layers == null:
		layers = default_layers
	var cur := status_layers(u, status)
	u.statuses[status] = maxi(cur, int(layers))
	return status

static func _consume(u, mode: int) -> Array:
	var removed: Array = []
	for st in STATUS_META:
		var meta: Array = STATUS_META[st]
		if meta[1] != mode:
			continue
		if not u.statuses.has(st) or int(u.statuses[st]) <= 0:
			continue
		u.statuses[st] = int(u.statuses[st]) - 1
		if int(u.statuses[st]) <= 0:
			u.statuses.erase(st)
			removed.append(st)
	return removed

static func consume_on_self_attack(u) -> Array:
	return _consume(u, StatusConsume.ON_SELF_ATTACK)

static func consume_on_self_hit(u) -> Array:
	return _consume(u, StatusConsume.ON_SELF_HIT)

static func clear_statuses(u) -> void:
	u.statuses.clear()

static func is_frozen(u) -> bool:
	return has_status(u, "frozen")

# ---- 条件求值 ----
static func _pct_cur_hp(u) -> float:
	var eff_max := float(u.base.get("hp", 1))
	if eff_max <= 0.0:
		eff_max = 1.0
	return 100.0 * float(u.cur_hp) / eff_max

static func _unit_side(ctx, u):
	if ctx.attacker_side.units.has(u):
		return ctx.attacker_side
	return ctx.defender_side

static func _side_allies_of(ctx, u) -> Array:
	var side = _unit_side(ctx, u)
	var out: Array = []
	for x in side.units:
		if x.alive:
			out.append(x)
	return out

static func _row_alive_count(ctx, u, row: String) -> int:
	var side = _unit_side(ctx, u)
	var count := 0
	for i in range(side.army.grid.size()):
		var uid = side.army.grid[i]
		if uid == null:
			continue
		if Armies.row_of(i) != row:
			continue
		for x in side.units:
			if x.id == uid and x.alive:
				count += 1
				break
	return count

## 必要条件求值（全满足才允许释放并筛目标）。
static func eval_necessary(cond: Dictionary, ctx, actor, target = null) -> bool:
	var t: String = cond.get("type", "")
	match t:
		"self_hp_le":
			return _pct_cur_hp(actor) <= float(cond.get("threshold", 0))
		"ally_avg_hp_le":
			var allies := _side_allies_of(ctx, actor)
			if allies.is_empty():
				return true
			var s := 0.0
			for a in allies:
				s += _pct_cur_hp(a)
			return s / allies.size() <= float(cond.get("threshold", 0))
		"row_count_ge":
			return _row_alive_count(ctx, actor, cond.get("row", "front")) >= int(cond.get("n", 0))
		"enemy_has_frozen":
			if target == null:
				return true   # 无目标上下文不卡释放，由 choose_target 过滤
			return has_status(target, "frozen")
		"target_pref_low_hp":
			return target == null or target.alive
		"target_pref_front":
			var slot: Variant = cond.get("_target_slot")
			if slot == null or target == null:
				return true
			return Armies.row_of(int(slot)) == "front"
		"target_pref_random":
			return true
	return false

## 优先条件排序键（越小越优先）。
static func priority_key(cond: Dictionary, ctx, target, target_slot: int = -1) -> Array:
	var t: String = cond.get("type", "")
	match t:
		"pref_enemy_frozen":
			return [0 if has_status(target, "frozen") else 1]
		"pref_enemy_debuffed":
			return [0 if has_status(target, "debuff") else 1]
		"pref_low_hp":
			return [float(target.cur_hp)]
		"pref_front":
			if target_slot < 0:
				return [1]
			return [0 if Armies.row_of(target_slot) == "front" else 1, 0]
		"pref_random":
			return [0]
	return [1]
