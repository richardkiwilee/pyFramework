class_name Hand
extends RefCounted
## =============================================================================
## Hand — 一名玩家的手牌与 21 点点数计算（纯逻辑）
## =============================================================================

var cards: Array[CardData] = []


func add_card(c: CardData) -> void:
	cards.append(c)


func size() -> int:
	return cards.size()


func is_empty() -> bool:
	return cards.is_empty()


## ≤21 的最大点数；A 先按 1 计，再尽量升级为 11（软 A）
func best_total() -> int:
	var total := 0
	var aces := 0
	for c in cards:
		if c.rank == CardData.Rank.ACE:
			aces += 1
			total += 1
		else:
			total += c.value()
	for i in aces:
		if total + 10 <= 21:
			total += 10
	return total


func is_bust() -> bool:
	return best_total() > 21


## 自然黑杰克：恰好 2 张、A + 10 点牌
func is_natural_blackjack() -> bool:
	if cards.size() != 2:
		return false
	var has_ace := false
	var has_ten := false
	for c in cards:
		if c.rank == CardData.Rank.ACE:
			has_ace = true
		if c.is_ten_value():
			has_ten = true
	return has_ace and has_ten


## 同点决胜用：单张最大牌；A 视为 14（最大）
func max_rank() -> int:
	var m := 0
	for c in cards:
		var v := (14 if c.rank == CardData.Rank.ACE else c.rank)
		if v > m:
			m = v
	return m
