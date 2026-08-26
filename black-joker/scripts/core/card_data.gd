class_name CardData
extends RefCounted
## =============================================================================
## CardData — 单张扑克牌数据（纯数据类，无场景依赖）
## =============================================================================
## 花色与点数均为 int（Suit/Rank 枚举）。牌背编码依赖 (suit, rank) 二元组，
## id() 给出唯一标识，作为牌背纹理缓存键。
## =============================================================================

enum Suit { SPADES, HEARTS, DIAMONDS, CLUBS }
enum Rank { ACE = 1, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, TEN, JACK, QUEEN, KING }

# 注意：const 数组不能用 := 推断（会推断成类型化数组，而 GDScript
# 不支持类型化数组常量，导致整类解析级联失败），必须无类型声明。
const RANK_NAMES = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUIT_SYMBOLS = ["♠", "♥", "♦", "♣"]
const SUIT_NAMES_CN = ["黑桃", "红桃", "方块", "梅花"]

var suit: int
var rank: int


func _init(p_suit: int, p_rank: int) -> void:
	suit = p_suit
	rank = p_rank


## 牌面点数：J/Q/K=10，A=1（软 11 由 Hand.best_total 计算）
func value() -> int:
	if rank >= Rank.JACK and rank <= Rank.KING:
		return 10
	return rank


func is_ten_value() -> bool:
	return rank >= Rank.TEN and rank <= Rank.KING


## 展示文本，如 "♠7"（符号字形仅作日志用，UI 用矢量绘制花色）
func display() -> String:
	var r: String = RANK_NAMES[rank]
	var s: String = SUIT_SYMBOLS[suit]
	return r + s


## 花色×点数的唯一标识（牌背纹理缓存键、联机快照键）
func id() -> String:
	return "%d-%d" % [suit, rank]


func _to_string() -> String:
	return display()


func to_dict() -> Dictionary:
	return {"suit": suit, "rank": rank}


static func from_dict(d: Dictionary) -> CardData:
	return CardData.new(int(d["suit"]), int(d["rank"]))


## 固定顺序的 52 张牌（花色外层、点数内层）
static func all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for s in Suit.values():
		for r in Rank.values():
			out.append(CardData.new(int(s), int(r)))
	return out
