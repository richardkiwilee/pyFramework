class_name MatchState
extends RefCounted
## =============================================================================
## MatchState — 对局级状态：筹码（钱即血量）、底注、连局、先手轮换
## =============================================================================
## 整场对局共用一副牌（跨回合记牌是本作技巧的一部分），抽空自动洗回。
## 纯逻辑，不依赖场景树；主机权威时只在主机上驱动本类。
## =============================================================================

const START_CHIPS := 100
const ANTE := 10

var deck: Deck
var rng: RandomNumberGenerator
var chips: Array[int] = [START_CHIPS, START_CHIPS]
var pot: int = 0
var round_number: int = 0
var round: RoundEngine
var round_antes: Array[int] = [0, 0]
var first_random: int = 0
var match_over: bool = false
var match_winner: int = -1


func _init(p_rng: RandomNumberGenerator) -> void:
	rng = p_rng
	deck = Deck.new()
	deck.shuffle(rng)
	first_random = rng.randi_range(0, 1)


## 开始新回合（双方下底注，不足则全押）。对局已结束或一方无筹码时返回 false。
func start_round() -> bool:
	if match_over:
		return false
	if chips[0] <= 0 or chips[1] <= 0:
		match_over = true
		match_winner = 1 if chips[0] <= 0 else 0
		return false
	for i in 2:
		round_antes[i] = mini(chips[i], ANTE)
		chips[i] -= round_antes[i]
	pot = round_antes[0] + round_antes[1]
	var first := (first_random + round_number) % 2
	round = RoundEngine.new(deck, rng, first)
	round_number += 1
	return true


## 结算当前回合：手牌进弃牌堆、赢家拿底池、push 退注；一方归零则对局结束。
func settle_round() -> void:
	if round == null or not round.is_over():
		return
	for i in 2:
		for c in round.hands[i].cards:
			deck.discard(c)
	if round.winner >= 0:
		chips[round.winner] += pot
	else:
		# push：各自退回本局底注
		chips[0] += round_antes[0]
		chips[1] += round_antes[1]
	pot = 0
	round = null
	if chips[0] <= 0 or chips[1] <= 0:
		match_over = true
		if chips[0] <= 0:
			match_winner = 1
		else:
			match_winner = 0


## 全量快照（联机广播共用；round 为 null 时该键为 {})
func snapshot() -> Dictionary:
	var rs: Dictionary = {}
	if round != null:
		rs = round.snapshot()
	return {
		"chips": chips.duplicate(),
		"pot": pot,
		"round_number": round_number,
		"match_over": match_over,
		"match_winner": match_winner,
		"round": rs,
	}
