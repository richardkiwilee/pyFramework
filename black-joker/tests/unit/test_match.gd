extends TestBase
## MatchState 对局级测试：底注、底池、全押、push 退注、筹码归零结束、先手轮换
## 注意：变量名不能用 match（GDScript 保留关键字），统一用 ms。


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 777
	return r


## 直接把当前回合改成"胜者已定"，绕过抽牌流程
func _force_win(ms: MatchState, winner: int) -> void:
	ms.round.hands[0].add_card(CardData.new(0, 10))
	ms.round.hands[0].add_card(CardData.new(0, 7))
	ms.round.hands[1].add_card(CardData.new(1, 2))
	ms.round.hands[1].add_card(CardData.new(1, 3))
	ms.round.phase = RoundEngine.Phase.OVER
	ms.round.winner = winner


func _force_push(ms: MatchState) -> void:
	_force_win(ms, 0)
	ms.round.winner = -1


func test_ante_deduction_and_pot() -> void:
	var ms := MatchState.new(_rng())
	assert_true(ms.start_round(), "开始回合")
	assert_eq(ms.chips, [90, 90], "各扣 10 底注")
	assert_eq(ms.pot, 20, "底池 20")
	assert_eq(ms.round_number, 1, "第一回合")


func test_win_takes_pot() -> void:
	var ms := MatchState.new(_rng())
	ms.start_round()
	_force_win(ms, 0)
	ms.settle_round()
	assert_eq(ms.chips[0], 110, "赢家 100-10+20=110")
	assert_eq(ms.chips[1], 90, "输家 90")
	assert_false(ms.match_over, "对局未结束")


func test_push_refunds() -> void:
	var ms := MatchState.new(_rng())
	ms.start_round()
	_force_push(ms)
	ms.settle_round()
	assert_eq(ms.chips, [100, 100], "push 各退底注")
	assert_eq(ms.pot, 0, "底池清零")


func test_all_in_ante() -> void:
	var ms := MatchState.new(_rng())
	ms.chips[1] = 5
	ms.start_round()
	assert_eq(ms.round_antes, [10, 5], "P1 全押 5")
	assert_eq(ms.pot, 15, "底池 15")
	_force_win(ms, 1)
	ms.settle_round()
	assert_eq(ms.chips[1], 15, "P1 赢 0+15=15")
	assert_false(ms.match_over, "未结束（双方都还有筹码）")


func test_match_ends_when_broke() -> void:
	var ms := MatchState.new(_rng())
	ms.chips[1] = 10
	ms.start_round()
	_force_win(ms, 0)
	ms.settle_round()
	assert_true(ms.match_over, "P1 归零对局结束")
	assert_eq(ms.match_winner, 0, "P0 获胜")


func test_first_player_alternates() -> void:
	var ms := MatchState.new(_rng())
	ms.start_round()
	var first0: int = ms.round.turn
	_force_push(ms)
	ms.settle_round()
	ms.start_round()
	var first1: int = ms.round.turn
	assert_eq(first1, 1 - first0, "先手逐局轮换")
