extends TestBase
## CardData / Hand 单元测试：面值、软硬 A、爆牌、自然黑杰克、单张决胜


func _card(s: int, r: int) -> CardData:
	return CardData.new(s, r)


func _hand(cards: Array[CardData]) -> Hand:
	var h := Hand.new()
	for c in cards:
		h.add_card(c)
	return h


func test_card_values() -> void:
	assert_eq(_card(0, 1).value(), 1, "A 面值为 1")
	assert_eq(_card(0, 10).value(), 10, "10 面值为 10")
	assert_eq(_card(0, 11).value(), 10, "J 面值为 10")
	assert_eq(_card(0, 12).value(), 10, "Q 面值为 10")
	assert_eq(_card(0, 13).value(), 10, "K 面值为 10")
	assert_eq(_card(0, 7).value(), 7, "7 面值为 7")


func test_ten_value_flag() -> void:
	assert_false(_card(0, 9).is_ten_value(), "9 不是 10 点牌")
	assert_true(_card(0, 10).is_ten_value(), "10 是 10 点牌")
	assert_true(_card(0, 11).is_ten_value(), "J 是 10 点牌")
	assert_true(_card(0, 12).is_ten_value(), "Q 是 10 点牌")
	assert_true(_card(0, 13).is_ten_value(), "K 是 10 点牌")
	assert_false(_card(0, 1).is_ten_value(), "A 不是 10 点牌")


func test_all_cards_52_unique() -> void:
	var all := CardData.all_cards()
	assert_eq(all.size(), 52, "共 52 张")
	var seen := {}
	for c in all:
		seen[c.id()] = true
	assert_eq(seen.size(), 52, "52 张全部唯一")


func test_hand_best_total_soft_ace() -> void:
	assert_eq(_hand([_card(0, 1), _card(1, 10)]).best_total(), 21, "A+10 = 21")
	assert_eq(_hand([_card(0, 1), _card(0, 6)]).best_total(), 17, "A+6 = 17（A 作 11）")
	assert_eq(_hand([_card(0, 1), _card(0, 6), _card(0, 5)]).best_total(), 12, "A+6+5 = 12（A 作 1）")
	assert_eq(_hand([_card(0, 1), _card(0, 1), _card(0, 9)]).best_total(), 21, "A+A+9 = 21")


func test_hand_bust() -> void:
	assert_true(_hand([_card(0, 10), _card(0, 7), _card(0, 5)]).is_bust(), "10+7+5=22 爆牌")
	assert_false(_hand([_card(0, 1), _card(0, 10), _card(0, 10)]).is_bust(), "A+10+10=21 不爆")
	assert_false(_hand([_card(0, 1), _card(0, 5), _card(0, 8)]).is_bust(), "A+5+8=14 不爆")


func test_hand_natural_blackjack() -> void:
	assert_true(_hand([_card(0, 1), _card(0, 13)]).is_natural_blackjack(), "A+K 两张是 BJ")
	assert_true(_hand([_card(0, 1), _card(0, 10)]).is_natural_blackjack(), "A+10 两张是 BJ")
	assert_false(_hand([_card(0, 1), _card(0, 2), _card(0, 8)]).is_natural_blackjack(), "3 张 21 不是 BJ")
	assert_false(_hand([_card(0, 10), _card(0, 11)]).is_natural_blackjack(), "10+J 不是 BJ")


func test_hand_max_rank() -> void:
	assert_eq(_hand([_card(0, 1), _card(0, 7)]).max_rank(), 14, "A 视为 14 最大")
	assert_eq(_hand([_card(0, 13), _card(0, 12)]).max_rank(), 13, "K=13")
	assert_eq(_hand([_card(0, 9), _card(0, 3)]).max_rank(), 9, "9 最大")
