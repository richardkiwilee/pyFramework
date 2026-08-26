class_name RoundEngine
extends RefCounted
## =============================================================================
## RoundEngine — 单回合 21 点对局状态机（纯逻辑，不依赖场景树）
## =============================================================================
## 流程（见 docs/00-design.md §2.2）：
##   双方手牌从空开始 → 先手方行动（要牌/停牌）→ 要牌抽牌堆顶（其牌背
##   在抽之前已对双方可见）→ 爆牌立即输 → 5 张自动停 → 对方已停则自己
##   可连续行动 → 双方都停后比大小。
## =============================================================================

enum Phase { WAITING, TURN, OVER }
enum ResultKind { NONE, BUST, BLACKJACK, POINTS, PUSH }

const MAX_CARDS := 5

var deck: Deck
var rng: RandomNumberGenerator
var hands: Array[Hand] = []
var turn: int = 0
var stood: Array[bool] = [false, false]
var phase: int = Phase.WAITING
var winner: int = -1      # -1 = 未定或平局
var result_kind: int = ResultKind.NONE
var busted: int = -1      # 爆牌方


func _init(p_deck: Deck, p_rng: RandomNumberGenerator, first_player: int) -> void:
	deck = p_deck
	rng = p_rng
	turn = first_player
	phase = Phase.TURN
	hands.append(Hand.new())
	hands.append(Hand.new())


func active_player() -> int:
	return turn


func is_over() -> bool:
	return phase == Phase.OVER


## 玩家 p 现在能否行动（要牌或停牌）
func can_act(p: int) -> bool:
	return phase == Phase.TURN and turn == p


## 牌堆顶牌——本作的核心观察对象（牌背对双方可见）
func top_card() -> CardData:
	return deck.peek_top()


## 当前行动方要牌。成功返回 true。
func hit() -> bool:
	if phase != Phase.TURN:
		return false
	if hands[turn].size() >= MAX_CARDS:
		return false
	var card := deck.draw(rng)
	if card == null:
		return false
	hands[turn].add_card(card)
	if hands[turn].is_bust():
		busted = turn
		winner = 1 - turn
		result_kind = ResultKind.BUST
		phase = Phase.OVER
		return true
	if hands[turn].size() >= MAX_CARDS:
		stood[turn] = true  # 5 张自动停
	_after_stand()
	return true


## 当前行动方停牌（至少须持有 1 张牌）。成功返回 true。
func stand() -> bool:
	if phase != Phase.TURN:
		return false
	if hands[turn].is_empty():
		return false
	stood[turn] = true
	_after_stand()
	return true


## 停牌后推进：双方都停则比大小；对方未停则轮转；对方已停则自己继续
func _after_stand() -> void:
	if stood[0] and stood[1]:
		_compare()
		return
	if not stood[1 - turn]:
		turn = 1 - turn


## 双方停牌后的胜负判定（优先级见 docs/00-design.md §2.3）
func _compare() -> void:
	phase = Phase.OVER
	var bj0 := hands[0].is_natural_blackjack()
	var bj1 := hands[1].is_natural_blackjack()
	if bj0 != bj1:
		winner = 0 if bj0 else 1
		result_kind = ResultKind.BLACKJACK
		return
	var t0 := hands[0].best_total()
	var t1 := hands[1].best_total()
	if t0 != t1:
		winner = 0 if t0 > t1 else 1
		result_kind = ResultKind.POINTS
		return
	var m0 := hands[0].max_rank()
	var m1 := hands[1].max_rank()
	if m0 != m1:
		winner = 0 if m0 > m1 else 1
		result_kind = ResultKind.POINTS
		return
	winner = -1
	result_kind = ResultKind.PUSH


## 全量状态快照（联机广播与测试断言共用）。
## top 只含牌堆顶牌的 (suit, rank)——这正是牌背公开携带的等价信息。
func snapshot() -> Dictionary:
	# hand_dicts 存的是"每人一个数组"（数组的数组），必须无类型，否则
	# append 数组到 Array[Dictionary] 会触发类型校验错误
	var hand_dicts = []
	for h in hands:
		var cards_out: Array[Dictionary] = []
		for c in h.cards:
			cards_out.append(c.to_dict())
		hand_dicts.append(cards_out)
	var top_dict: Dictionary = {}
	var t := deck.peek_top()
	if t != null:
		top_dict = t.to_dict()
	return {
		"phase": phase,
		"turn": turn,
		"hands": hand_dicts,
		"totals": [hands[0].best_total(), hands[1].best_total()],
		"stood": stood.duplicate(),
		"winner": winner,
		"result_kind": result_kind,
		"busted": busted,
		"deck_count": deck.remaining(),
		"discard": _discard_dicts(),
		"top": top_dict,
	}


func _discard_dicts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in deck.discard_pile:
		out.append(c.to_dict())
	return out
