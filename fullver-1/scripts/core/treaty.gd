class_name Treaty
extends RefCounted
## =============================================================================
## Treaty — 条约（有持续时间的双边约定）
## =============================================================================
## 领域术语见 CONTEXT.md：条约有持续回合数，到期自动失效。
## 修正 diplomacy 项目的缺陷：其"条约"只是三个 bool，无期限、无强度。
##
## 类比 Python：dataclass。
## =============================================================================

## 条约类型："peace"（和平）/ "alliance"（同盟）
## 后续可扩展："trade"（贸易协定）、"non_aggression"（互不侵犯）……
var type: String = ""

## 剩余回合数。每回合结束 tick_treaties 递减，减到 0 自动失效。
var remaining_rounds: int = 0

## 类型相关的额外参数（如贸易协定携带的资源交换明细）
var params: Dictionary = {}


## 是否已到期
func is_expired() -> bool:
	return remaining_rounds <= 0


## 推进一回合，返回是否刚到期
func tick() -> bool:
	if remaining_rounds > 0:
		remaining_rounds -= 1
	return is_expired()


## ---------------------------------------------------------------------------
## 序列化（存档用）
## ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"type": type,
		"remaining_rounds": remaining_rounds,
		"params": params,
	}


static func from_dict(d: Dictionary) -> Treaty:
	var t := Treaty.new()
	t.type = d.get("type", "")
	t.remaining_rounds = int(d.get("remaining_rounds", 0))
	t.params = d.get("params", {})
	return t
