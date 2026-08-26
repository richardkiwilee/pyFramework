extends TestBase
## RoundEngine 单元测试：脚本化 hit/stand 序列 → 胜负判定断言
## 注意回合规则：要牌后对方未停则轮转；对方已停则自己连续行动。


func _c(s: int, r: int) -> CardData:
	return CardData.new(s, r)


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 999
	return r


## 构造指定抽牌顺序的牌堆（列表首元素先被抽到）
func _deck_with(cards: Array[CardData]) -> Deck:
	var deck := Deck.new()
	deck.draw_pile.clear()
	for i in range(cards.size() - 1, -1, -1):
		deck.draw_pile.append(cards[i])
	return deck


func test_bust_ends_round() -> void:
	# P0: 10+7=17 停；P1: 10+10+5=25 爆
	var deck := _deck_with([_c(0, 10), _c(1, 10), _c(0, 7), _c(2, 10), _c(3, 5)])
	var round := RoundEngine.new(deck, _rng(), 0)
	assert_true(round.hit(), "P0 要牌 10")
	assert_true(round.hit(), "P1 要牌 10")
	assert_true(round.hit(), "P0 要牌 7（17 点）")
	assert_true(round.hit(), "P1 要牌 10（20 点）")
	assert_true(round.stand(), "P0 停牌")
	assert_eq(round.turn, 1, "轮到 P1")
	assert_true(round.hit(), "P1 要牌 5（25 点爆牌）")
	assert_true(round.is_over(), "回合结束")
	assert_eq(round.winner, 0, "P0 获胜")
	assert_eq(round.result_kind, RoundEngine.ResultKind.BUST, "结果为爆牌")
	assert_eq(round.busted, 1, "爆牌方是 P1")


func test_points_comparison() -> void:
	# P0: 10+7=17 停；P1: 3+4+9=16 停 → P0 胜
	var deck := _deck_with([_c(0, 10), _c(1, 3), _c(0, 7), _c(1, 4), _c(1, 9)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()   # P0: 10
	round.hit()   # P1: 3
	round.hit()   # P0: 7 → 17
	round.hit()   # P1: 4 → 7
	round.stand() # P0 停
	round.hit()   # P1: 9 → 16（P0 已停，P1 连续）
	round.stand() # P1 停 → 比大小
	assert_true(round.is_over(), "双方都停后结束")
	assert_eq(round.winner, 0, "P0 17 点胜 P1 16 点")
	assert_eq(round.result_kind, RoundEngine.ResultKind.POINTS, "比点决胜")


func test_blackjack_beats_21() -> void:
	# P0: A+K 两张自然 BJ；P1: 5+10+6=21 三张 → BJ 压过 21
	var deck := _deck_with([_c(0, 1), _c(1, 5), _c(0, 13), _c(1, 10), _c(1, 6)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()   # P0: A
	round.hit()   # P1: 5
	round.hit()   # P0: K → 自然 BJ
	assert_true(round.hands[0].is_natural_blackjack(), "P0 已构成自然 BJ")
	round.hit()   # P1: 10 → 15
	round.stand() # P0 停
	round.hit()   # P1: 6 → 21
	round.stand() # P1 停
	assert_eq(round.hands[1].best_total(), 21, "P1 三张 21 点")
	assert_true(round.is_over(), "结束")
	assert_eq(round.winner, 0, "自然 BJ 压过 21")
	assert_eq(round.result_kind, RoundEngine.ResultKind.BLACKJACK, "BJ 结果类型")


func test_tie_higher_card_wins() -> void:
	# 都是 17：P0 是 10+7（最大 10），P1 是 9+8（最大 9）→ P0 胜
	var deck := _deck_with([_c(0, 10), _c(1, 9), _c(0, 7), _c(1, 8)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()   # P0: 10
	round.hit()   # P1: 9
	round.hit()   # P0: 7 → 17
	round.hit()   # P1: 8 → 17
	round.stand() # P0 停
	round.stand() # P1 停
	assert_true(round.is_over(), "结束")
	assert_eq(round.winner, 0, "同点比单张最大，P0 胜")
	assert_eq(round.result_kind, RoundEngine.ResultKind.POINTS, "比点结果")


func test_push_when_identical() -> void:
	# 都是 10+7=17、最大单张都是 10 → push
	var deck := _deck_with([_c(0, 10), _c(1, 10), _c(0, 7), _c(1, 7)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()
	round.hit()
	round.hit()
	round.hit()
	round.stand()
	round.stand()
	assert_true(round.is_over(), "结束")
	assert_eq(round.winner, -1, "无胜者")
	assert_eq(round.result_kind, RoundEngine.ResultKind.PUSH, "push")


func test_five_cards_auto_stand() -> void:
	# P1 先停（9 点），P0 连抽 5 张（A+2+2+3+3=21）自动停 → P0 胜
	var deck := _deck_with([_c(0, 1), _c(1, 9), _c(1, 2), _c(2, 2), _c(3, 3), _c(0, 3)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()   # P0: A
	round.hit()   # P1: 9
	round.hit()   # P0: 2 → 3
	round.stand() # P1 停（9 点）
	assert_eq(round.turn, 0, "回到 P0")
	assert_true(round.hit(), "P0 要牌 2")
	assert_true(round.hit(), "P0 要牌 3")
	assert_true(round.hit(), "P0 要牌 3（第 5 张）")
	assert_eq(round.hands[0].size(), 5, "P0 已 5 张")
	assert_true(round.stood[0], "P0 自动停牌")
	assert_true(round.is_over(), "双方停牌结束")
	assert_eq(round.winner, 0, "P0 五张 21 点获胜")
	assert_false(round.can_act(0), "P0 不能继续行动")


func test_stand_requires_card() -> void:
	var deck := _deck_with([_c(0, 5)])
	var round := RoundEngine.new(deck, _rng(), 0)
	assert_false(round.stand(), "空手不能停牌")
	assert_eq(round.turn, 0, "回合不变")


func test_opponent_stood_player_continues() -> void:
	# P1 停牌后 P0 连续行动，回合不轮转
	var deck := _deck_with([_c(0, 5), _c(0, 6), _c(1, 4), _c(0, 7)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()   # P0: 5
	round.hit()   # P1: 6
	round.hit()   # P0: 4 → 9
	round.stand() # P1 停
	assert_eq(round.turn, 0, "P1 停后回到 P0 回合")
	assert_true(round.hit(), "P0 可继续要牌")
	assert_eq(round.turn, 0, "P1 已停，P0 连续行动")


func test_actions_blocked_after_over() -> void:
	# P0: 10+7+5=22 爆（P1 穿插抽 2、3 后停不下来也不影响）
	var deck := _deck_with([_c(0, 10), _c(1, 2), _c(0, 7), _c(1, 3), _c(0, 5)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()  # P0: 10
	round.hit()  # P1: 2
	round.hit()  # P0: 7 → 17
	round.hit()  # P1: 3 → 5
	round.hit()  # P0: 5 → 22 爆，结束
	assert_true(round.is_over(), "结束")
	assert_false(round.hit(), "结束后不能要牌")
	assert_false(round.stand(), "结束后不能停牌")
	assert_false(round.can_act(0), "无人可行动")


func test_snapshot_shape() -> void:
	var deck := _deck_with([_c(0, 10), _c(1, 7), _c(2, 3)])
	var round := RoundEngine.new(deck, _rng(), 0)
	round.hit()  # P0 抽走 10，顶牌变为 7
	var snap := round.snapshot()
	assert_eq(snap["turn"], 1, "快照记录当前行动方")
	assert_eq(snap["deck_count"], 2, "牌堆剩 2 张")
	assert_eq(snap["top"], {"suit": 1, "rank": 7}, "快照含顶牌（供牌背渲染）")
	assert_eq(snap["totals"], [10, 0], "双方点数")
	assert_eq(snap["hands"][0], [{"suit": 0, "rank": 10}], "P0 手牌序列化")
