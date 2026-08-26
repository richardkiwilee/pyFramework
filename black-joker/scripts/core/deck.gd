class_name Deck
extends RefCounted
## =============================================================================
## Deck — 52 张牌堆（含弃牌堆；抽空时自动把弃牌堆洗回）
## =============================================================================
## 牌堆顶牌（draw_pile 末元素）是牌背观察玩法的核心对象：它的牌背
## 对双方可见，能读出花色与点数。
## =============================================================================

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []


func _init() -> void:
	draw_pile = CardData.all_cards()


## Fisher-Yates 洗牌（传入种子 RNG 即可复现）
func shuffle(rng: RandomNumberGenerator) -> void:
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: CardData = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp


## 牌堆顶牌（不取出）。空堆返回 null。
func peek_top() -> CardData:
	if draw_pile.is_empty():
		return null
	return draw_pile[draw_pile.size() - 1]


## 抽顶牌；牌堆空时先把弃牌堆洗回。仍空（理论不可能）返回 null。
func draw(rng: RandomNumberGenerator) -> CardData:
	if draw_pile.is_empty():
		_recycle(rng)
	if draw_pile.is_empty():
		return null
	return draw_pile.pop_back()


func discard(c: CardData) -> void:
	discard_pile.append(c)


func remaining() -> int:
	return draw_pile.size()


func _recycle(rng: RandomNumberGenerator) -> void:
	draw_pile.assign(discard_pile)
	discard_pile.clear()
	shuffle(rng)
