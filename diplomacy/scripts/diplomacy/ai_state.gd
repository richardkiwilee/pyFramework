class_name AIState
extends RefCounted
## =============================================================================
## AIState — 单个 AI 外交方的数据与规则（4X 外交系统雏形）
## =============================================================================
## 数据：资源库存、每种资源的"预期"（期望持有量）、军力、关系值、交战标记。
## 规则口径（原型暂定，与界面提示一致）：
##   · 关系状态由 (交战标记, 关系值) 推导：
##       交战(宣战中) > 敌视(关系<0) > 和平(0..40) > 友好(40..60) > 同盟(>=60)
##   · 每回合关系向 0 靠拢 0.1
##   · 贸易评分见 trade_score()：>=0 接受、<0 拒绝，分数 >0 加到关系值
##   · 逼迫：我方军力严格 > 对方 3 倍，且关系在和平或以上；成功关系 -20
##   · 宣战：关系先 -60，若未到 -40 则继续压到 -40；和平仅解除交战标记
##   · 宣布友谊(+40 可用)/同盟(+60 可用)：一次性 +10 关系
## =============================================================================

## 资源枚举顺序（界面与测试遍历顺序）
const RESOURCE_ORDER: Array[String] = ["food", "gold", "wood", "horse"]

## 逼迫成功时的固定索取量（规则未限定数值，原型暂定）
const TRIBUTE: Dictionary = {"food": 10, "gold": 10, "wood": 5, "horse": 3}

var id: String = ""
var display_name: String = ""
var military: int = 0
var resources: Dictionary = {}     # 资源名 -> 持有量
var expectations: Dictionary = {}  # 资源名 -> 预期（期望持有量）
var relationship: float = 0.0      # -100 .. +100
var at_war: bool = false
var friendship_declared: bool = false
var alliance_declared: bool = false


# ==================================================================
#  关系状态
# ==================================================================

## 关系状态推导：交战优先，其余按关系值分段
func relation_state() -> String:
	if at_war:
		return "交战"
	if relationship < 0.0:
		return "敌视"
	if relationship < 40.0:
		return "和平"
	if relationship < 60.0:
		return "友好"
	return "同盟"


## 每回合：关系向 0 靠拢 0.1（不足 0.1 直接归零）
func decay_toward_zero() -> void:
	if absf(relationship) <= 0.1:
		relationship = 0.0
	elif relationship > 0.0:
		relationship -= 0.1
	else:
		relationship += 0.1
	relationship = clampf(relationship, -100.0, 100.0)


# ==================================================================
#  贸易评分与执行
# ==================================================================

## 贸易评分（AI 视角）：
##   我方给出某资源：持有低于预期时，补齐到预期的部分每份 +1；超出部分与
##   持有高于预期时的给出均记 0 分。
##   AI 给出某资源：持有低于预期（或恰好等于，给出会跌破预期）时每份 -2；
##   高于预期时每份 -1。
## 返回总分：>=0 接受，<0 拒绝。
func trade_score(give_to_ai: Dictionary, ask_from_ai: Dictionary) -> int:
	var score := 0
	for res: String in RESOURCE_ORDER:
		var holding: int = int(resources.get(res, 0))
		var expected: int = int(expectations.get(res, 0))
		var give: int = int(give_to_ai.get(res, 0))
		var ask: int = int(ask_from_ai.get(res, 0))
		if holding < expected:
			score += mini(give, expected - holding)
		if ask > 0:
			var per_unit := 2 if holding <= expected else 1
			score -= ask * per_unit
	return score


## 执行交易：双向转移资源；分数 >0 时加到关系值（上限 100）
func apply_trade(give_to_ai: Dictionary, ask_from_ai: Dictionary, player_res: Dictionary, score: int) -> void:
	for res: String in RESOURCE_ORDER:
		var give: int = int(give_to_ai.get(res, 0))
		var ask: int = int(ask_from_ai.get(res, 0))
		var mine: int = int(player_res.get(res, 0))
		var holding: int = int(resources.get(res, 0))
		player_res[res] = mine - give + ask
		resources[res] = holding - ask + give
	if score > 0:
		relationship = clampf(relationship + float(score), -100.0, 100.0)


# ==================================================================
#  逼迫
# ==================================================================

## 逼迫可行性：我方军力需严格超过对方 3 倍，且关系在和平或以上（关系 >= 0）
func can_coerce(player_military: int) -> bool:
	if at_war:
		return false
	if player_military <= military * 3:
		return false
	return relationship >= 0.0


## 执行逼迫（调用前需 can_coerce）：按 TRIBUTE 索取，以对方库存为上限；关系 -20。
## 返回实际获得的 {资源名: 数量}
func coerce(player_res: Dictionary) -> Dictionary:
	var gained: Dictionary = {}
	for res: String in RESOURCE_ORDER:
		var holding: int = int(resources.get(res, 0))
		var take: int = mini(int(TRIBUTE.get(res, 0)), holding)
		if take > 0:
			gained[res] = take
			resources[res] = holding - take
			player_res[res] = int(player_res.get(res, 0)) + take
	relationship = clampf(relationship - 20.0, -100.0, 100.0)
	return gained


# ==================================================================
#  宣战 / 和平 / 宣布
# ==================================================================

## 宣战：关系先 -60，若扣除后未达到 -40 则继续压到 -40
func declare_war() -> void:
	at_war = true
	relationship = clampf(minf(relationship - 60.0, -40.0), -100.0, 100.0)


## 和平：仅解除交战标记，关系值保持（仍会落在敌视段）
func make_peace() -> void:
	at_war = false


## 宣布友谊（阈值 +40 由界面校验）：一次性 +10
func declare_friendship() -> void:
	friendship_declared = true
	relationship = clampf(relationship + 10.0, -100.0, 100.0)


## 宣布同盟（阈值 +60 由界面校验）：一次性 +10
func declare_alliance() -> void:
	alliance_declared = true
	relationship = clampf(relationship + 10.0, -100.0, 100.0)


# ==================================================================
#  默认 AI 工厂
# ==================================================================

## 4 个默认 AI：对每种资源的预期各不相同
##   沙漠商盟：爱金银马（gold/horse 预期高）
##   北境农庄：爱粮木（food 预期极高）
##   铁蹄汗国：爱马木（horse 预期极高，军力最强）
##   河谷联邦：四维均衡（各 40）
static func build_default_ais() -> Array[AIState]:
	var ais: Array[AIState] = []
	ais.append(_make("trader", "沙漠商盟", 25, -10.0,
		{"food": 40, "gold": 20, "wood": 30, "horse": 10},
		{"food": 15, "gold": 60, "wood": 10, "horse": 30}))
	ais.append(_make("farmer", "北境农庄", 50, 15.0,
		{"food": 30, "gold": 15, "wood": 15, "horse": 8},
		{"food": 80, "gold": 8, "wood": 20, "horse": 4}))
	ais.append(_make("khan", "铁蹄汗国", 140, -55.0,
		{"food": 25, "gold": 30, "wood": 20, "horse": 25},
		{"food": 30, "gold": 25, "wood": 40, "horse": 70}))
	ais.append(_make("federal", "河谷联邦", 80, 30.0,
		{"food": 30, "gold": 45, "wood": 20, "horse": 12},
		{"food": 40, "gold": 40, "wood": 40, "horse": 40}))
	return ais


static func _make(p_id: String, p_name: String, p_military: int, p_rel: float,
		p_res: Dictionary, p_exp: Dictionary) -> AIState:
	var ai := AIState.new()
	ai.id = p_id
	ai.display_name = p_name
	ai.military = p_military
	ai.relationship = p_rel
	ai.resources = p_res.duplicate()
	ai.expectations = p_exp.duplicate()
	return ai
