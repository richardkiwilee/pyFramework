class_name Relation
extends RefCounted
## =============================================================================
## Relation — 外交关系（两个势力之间的双边状态）
## =============================================================================
## 领域术语见 CONTEXT.md：好感度 -100~+100、战争状态、条约集合。
##
## 修正 diplomacy 项目的缺陷：
##   1. 双边记录：A 对 B 与 B 对 A 各有一份 Relation（态度可以不对称）
##   2. 条约是对象数组（有期限），不是三个 bool
##
## 类比 Python：dataclass + 状态推导方法，无引擎依赖。
## =============================================================================

## 关系主体（faction_a 对 faction_b 的态度）
var faction_a: String = ""
var faction_b: String = ""

## 好感度：-100（死敌）~ +100（亲密）。所有变更由 DiplomacySystem 收口 clamp。
var attitude: float = 0.0

## 是否交战中
var at_war: bool = false

## 双方当前有效的条约列表（对称条约在双方各存一份）
var treaties: Array[Treaty] = []


## ---------------------------------------------------------------------------
## 状态推导（diplomacy 项目的"推导式状态"模式）
## ---------------------------------------------------------------------------
## 态度等级不是存储字段，而是每次由 (at_war, attitude, treaties) 现推，
## 避免状态字段之间失同步。
## ---------------------------------------------------------------------------

## 态度等级："war"（交战）/ "hostile"（敌视）/ "peace"（和平）/
##            "friendly"（友好）/ "allied"（同盟）
## 阈值读 data/diplomacy.json，由调用方传入（本类不碰 DataManager，保持纯净）
func attitude_level(thresholds: Dictionary) -> String:
	if at_war:
		return "war"
	var friendly_threshold: float = float(thresholds.get("friendly", 40.0))
	var alliance_threshold: float = float(thresholds.get("alliance", 60.0))
	var hostile_below: float = float(thresholds.get("hostile_below", 0.0))
	if has_treaty("alliance"):
		return "allied"
	if attitude >= alliance_threshold:
		return "allied"
	if attitude >= friendly_threshold:
		return "friendly"
	if attitude < hostile_below:
		return "hostile"
	return "peace"


## 是否存在某类型且未过期的条约
func has_treaty(type: String) -> bool:
	for t in treaties:
		if t.type == type and not t.is_expired():
			return true
	return false


## 移除已过期的条约，返回移除数量
func purge_expired() -> int:
	var removed := 0
	var kept: Array[Treaty] = []
	for t in treaties:
		if t.is_expired():
			removed += 1
		else:
			kept.append(t)
	treaties = kept
	return removed


## ---------------------------------------------------------------------------
## 序列化（存档用）
## ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var treaty_dicts: Array = []
	for t in treaties:
		treaty_dicts.append(t.to_dict())
	return {
		"faction_a": faction_a,
		"faction_b": faction_b,
		"attitude": attitude,
		"at_war": at_war,
		"treaties": treaty_dicts,
	}


static func from_dict(d: Dictionary) -> Relation:
	var r := Relation.new()
	r.faction_a = d.get("faction_a", "")
	r.faction_b = d.get("faction_b", "")
	r.attitude = float(d.get("attitude", 0.0))
	r.at_war = bool(d.get("at_war", false))
	for t in d.get("treaties", []):
		r.treaties.append(Treaty.from_dict(t))
	return r
