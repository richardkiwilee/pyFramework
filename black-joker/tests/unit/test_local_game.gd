extends TestBase
## LocalGame 集成测试：受控牌堆全 10 点牌，玩家（座位1）一直要 → 必爆，
## AI（座位0，困难）每回合获胜，对局以 200:0 结束。


func test_local_ai_full_match() -> void:
	# 直接协程形态（runner 对协程方法 await 完成 Signal）
	var tree: SceneTree = ctx["tree"]
	var game := LocalGame.new()
	game.ai_players = [true, false]  # 座位0 是 AI，座位1 是玩家
	game.difficulty = "hard"
	game.ai_delay = 0.02
	game.settle_delay = 0.02
	tree.root.add_child(game)
	game.start()
	assert_true(game.ms != null, "对局已建立")

	# 受控牌堆：全 10 点牌
	var deck := game.ms.deck
	deck.draw_pile.clear()
	for i in 80:
		deck.draw_pile.append(CardData.new(0, 10))

	var deadline: SceneTreeTimer = tree.create_timer(20.0)
	var guard := 0
	while guard < 3000 and not game.ms.match_over and deadline.time_left > 0.0:
		await tree.process_frame
		guard += 1
		var round := game.ms.round
		if round == null or round.is_over():
			continue
		# 玩家回合：一直要牌
		if round.turn == 1 and round.can_act(1):
			game.submit_action(1, "hit")

	assert_true(game.ms.match_over, "对局正常结束")
	assert_eq(game.ms.match_winner, 0, "AI 每回合获胜")
	assert_eq(game.ms.chips, [200, 0], "筹码 200:0")
	tree.root.remove_child(game)
	game.free()
