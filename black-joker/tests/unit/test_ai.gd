extends TestBase
## AIPlayer 决策测试：构造快照断言 easy/hard 两档的 hit/stand 选择


func _snap(turn: int, totals: Array, stood: Array, top: Dictionary) -> Dictionary:
	return {"turn": turn, "totals": totals, "stood": stood, "top": top, "hands": [[], []]}


func test_easy_threshold() -> void:
	var snap := _snap(0, [16, 10], [false, false], {"suit": 0, "rank": 10})
	assert_eq(AIPlayer.decide(snap, "easy"), "hit", "16 点要牌")
	snap = _snap(0, [17, 10], [false, false], {"suit": 0, "rank": 10})
	assert_eq(AIPlayer.decide(snap, "easy"), "stand", "17 点停牌")


func test_hard_next_value() -> void:
	# 顶牌是 A：my=10 时贡献 11
	assert_eq(AIPlayer._next_value(_snap(0, [10, 0], [false, false], {"suit": 0, "rank": 1}), 10), 11, "A 按 11 计")
	# my=15 时 A 按 1 计（+11 会爆）
	assert_eq(AIPlayer._next_value(_snap(0, [15, 0], [false, false], {"suit": 0, "rank": 1}), 15), 1, "A 按 1 计")
	# 顶牌 K = 10
	assert_eq(AIPlayer._next_value(_snap(0, [10, 0], [false, false], {"suit": 0, "rank": 13}), 10), 10, "K 按 10 计")
	# 空顶牌 = -1
	assert_eq(AIPlayer._next_value(_snap(0, [10, 0], [false, false], {}), 10), -1, "无顶牌 -1")


func test_hard_known_bust_stands() -> void:
	# my=17，顶牌 5 → 必爆；对方未停 → 停
	var snap := _snap(0, [17, 10], [false, false], {"suit": 0, "rank": 5})
	assert_eq(AIPlayer.decide(snap, "hard"), "stand", "必爆且未输定 → 停")


func test_hard_known_bust_behind_gambles() -> void:
	# my=17，顶牌 5 → 必爆；但对方已停且领先 → 只能赌
	var snap := _snap(0, [17, 20], [false, true], {"suit": 0, "rank": 5})
	assert_eq(AIPlayer.decide(snap, "hard"), "hit", "站着必输 → 赌一把")


func test_hard_winning_stands() -> void:
	# 对方已停，我领先 → 停
	var snap := _snap(0, [17, 15], [false, true], {"suit": 0, "rank": 5})
	assert_eq(AIPlayer.decide(snap, "hard"), "stand", "领先且对方已停 → 停")


func test_hard_behind_chases_safe_card() -> void:
	# 对方已停 17，我 15，顶牌 2（安全）→ 追
	var snap := _snap(0, [15, 17], [false, true], {"suit": 0, "rank": 2})
	assert_eq(AIPlayer.decide(snap, "hard"), "hit", "落后追安全牌")


func test_hard_17_stands_vs_playing_opponent() -> void:
	var snap := _snap(0, [17, 10], [false, false], {"suit": 0, "rank": 3})
	assert_eq(AIPlayer.decide(snap, "hard"), "stand", "对方未停且我 17+ → 停")


func test_hard_low_hits_vs_playing_opponent() -> void:
	var snap := _snap(0, [12, 10], [false, false], {"suit": 0, "rank": 3})
	assert_eq(AIPlayer.decide(snap, "hard"), "hit", "我 12 且顶牌安全 → 要")


func test_hard_21_stands() -> void:
	var snap := _snap(0, [21, 10], [false, false], {"suit": 0, "rank": 2})
	assert_eq(AIPlayer.decide(snap, "hard"), "stand", "21 点必停")


func test_hard_empty_top_conservative() -> void:
	assert_eq(AIPlayer.decide(_snap(0, [11, 10], [false, false], {}), "hard"), "hit", "无顶牌 11 → 要")
	assert_eq(AIPlayer.decide(_snap(0, [12, 10], [false, false], {}), "hard"), "stand", "无顶牌 12 → 停")


func test_decide_accepts_real_round_snapshot() -> void:
	# 回归测试：AI 决策必须吃真实的 RoundEngine 回合快照（而非对局级快照）。
	# 曾出 bug：LocalGame 把 MatchState.snapshot() 传给 decide，顶层缺 turn 键，
	# 运行时错误 "Invalid access to property or key 'turn'"（本地测试用手工快照没抓到）。
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var deck := Deck.new()
	deck.shuffle(rng)
	var round := RoundEngine.new(deck, rng, 0)
	round.hit()  # P0 抽一张
	var decision := AIPlayer.decide(round.snapshot(), "hard")
	assert_true(decision == "hit" or decision == "stand", "真实回合快照能正常决策")
