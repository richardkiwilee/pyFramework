extends TestBase
## Table 场景接线回归测试（AI 模式）
## 曾出 bug：table._setup_local 把 AI 座位配置写反——玩家被 AI 调度器替打、
## 真 AI 不行动导致"对手永远行动中"卡死。本测试直接加载 table 场景验证：
##   1) ai_players 配置正确（座位0=AI、座位1=人）；
##   2) 轮到玩家时不会被自动操作；
##   3) 轮到 AI 时 AI 会行动并把回合推进到玩家。


func test_table_ai_mode_wiring() -> void:
	var tree: SceneTree = ctx["tree"]
	GameConfig.mode = GameConfig.Mode.AI
	GameConfig.difficulty = "hard"

	var table = load("res://scenes/table.tscn").instantiate()
	tree.root.add_child(table)
	await tree.process_frame
	await tree.process_frame
	var game = table.get("game")
	assert_true(game != null, "table 已创建 LocalGame")
	var ai_players: Array = game.ai_players
	assert_eq(ai_players, [true, false], "AI 模式座位0=AI、座位1=人")

	# 等玩家回合出现（玩家先手时状态静止无事件，必须轮询而非等信号；
	# AI 先手时 AI 应在 ~0.9s 内行动并把回合推进给玩家）
	var deadline: SceneTreeTimer = tree.create_timer(5.0)
	var saw_turn1 := false
	while deadline.time_left > 0.0:
		await tree.process_frame
		var r = game.ms.round
		if r != null and r.turn == 1:
			saw_turn1 = true
			break
	assert_true(saw_turn1, "轮到过玩家（AI 先手时会行动并轮转）")

	# 玩家回合：无人操作时不应被自动替打
	var ms = game.ms
	var round = ms.round
	if round != null and round.turn == 1:
		var before: int = round.hands[1].size()
		await tree.create_timer(1.8).timeout  # 超过 AI 调度延迟(0.9s)的观察窗
		assert_eq(ms.round.turn, 1, "玩家回合不被自动跳过")
		assert_eq(ms.round.hands[1].size(), before, "玩家手牌不被自动替抽")

	tree.root.remove_child(table)
	table.queue_free()
	await tree.process_frame
