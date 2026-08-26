class_name LocalGame
extends Node
## =============================================================================
## LocalGame — 本地对局驱动器（单机 AI / 本地双人）
## =============================================================================
## 持有 MatchState（权威状态），把操作意图转成状态变化，统一以
## state_changed(snapshot) 信号对外广播。牌桌 UI 只认快照，因此联机模式
## （阶段5 的 NetGame）可以无缝替换本类。
## =============================================================================

signal state_changed(snap: Dictionary)

var ms: MatchState
var ai_players: Array[bool] = [false, false]  # 默认双方都是人；单机模式由 table 显式设 [true, false]
var difficulty: String = "easy"

var settle_delay: float = 2.0
var ai_delay: float = 0.9

var _pending_settle := false
var _ai_guard := 0


func start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	ms = MatchState.new(rng)
	ms.start_round()
	_emit()
	_schedule_ai_if_needed()


## 玩家 p 提交动作；非 p 的回合或非法动作会被忽略
func submit_action(p: int, action: String) -> void:
	if ms == null or ms.match_over:
		return
	var round := ms.round
	if round == null or not round.can_act(p):
		return
	if action == "hit":
		round.hit()
	elif action == "stand":
		round.stand()
	else:
		return
	_emit()
	if round.is_over():
		_schedule_settle()
	else:
		_schedule_ai_if_needed()


func snapshot() -> Dictionary:
	return ms.snapshot()


## 回合结束 → 停顿 → 结算 → 开新回合（或对局结束）
func _schedule_settle() -> void:
	if _pending_settle:
		return
	_pending_settle = true
	await get_tree().create_timer(settle_delay).timeout
	_pending_settle = false
	ms.settle_round()
	_emit()
	if ms.match_over:
		return
	ms.start_round()
	_emit()
	_schedule_ai_if_needed()


## 轮到 AI 座位时延时出牌（延时让玩家看清局势）
func _schedule_ai_if_needed() -> void:
	if ms == null or ms.match_over or ms.round == null:
		return
	var p := ms.round.active_player()
	if not ai_players[p]:
		return
	_ai_guard += 1
	var guard := _ai_guard
	await get_tree().create_timer(ai_delay).timeout
	if guard != _ai_guard:
		return
	var decision := AIPlayer.decide(ms.round.snapshot(), difficulty)
	submit_action(p, decision)


func _emit() -> void:
	state_changed.emit(snapshot())
