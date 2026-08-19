class_name TurnManager
extends RefCounted
## =============================================================================
## TurnManager — 回合流程编排（纯逻辑，无 Node 依赖）
## =============================================================================
## 职责：实现 docs/00-design.md §7 的结束回合流程，包括
##   「战斗打断点」——AI 回合中发生战斗时挂起流程，战斗结束后续跑。
##
## 流程：
##   run_player_end_turn()
##     ├─ 依次执行每个 AI 势力回合（ai_turn 回调）
##     │    └─ 若 AI 行动引发战斗 → 挂起（保存剩余 AI 列表）并返回战斗请求
##     ├─ 全部 AI 完成 → 经济结算 + 条约推进（settle 回调）
##     └─ turn += 1 → 收尾（advance 回调：回移动力/发事件/广播信号）
##   resume_after_battle(result)
##     └─ 继续跑剩余 AI → 结算 → advance
##
## 为什么用 Callable 注入而不是直接引用系统类：
##   经济/外交/AI 系统分属 P5/P3 阶段，GDScript 没有前向声明；
##   用回调缝合让本类现在就可用、可测，同时保持"深模块"的小接口——
##   外部只需理解三个回调的契约，不必知道系统内部。
##
## 类比 Python：
##   相当于把回调函数当依赖注入的编排器（类似 FastAPI 的依赖注入思路，
##   但更朴素——就是三个 callable）。
## =============================================================================

## 游戏状态（由 GameManager 传入，TurnManager 不持有所有权）
var state: GameState

# ------------------------------------------------------------------ 注入的回调
## ai_turn(faction: Faction) -> Dictionary
##   执行一个 AI 势力的回合。返回值约定：
##     {}                    — 无事发生
##     {"battle": {...}}     — AI 行动引发战斗（挂起流程，返回给 GameManager）
var ai_turn: Callable

## settle() -> Dictionary
##   经济结算 + 条约推进（EconomySystem + DiplomacySystem 的顺序由接线方决定）
var settle: Callable

## advance() -> void
##   turn += 1 之后的收尾：玩家军团回移动力、追加回合事件、广播信号
var advance: Callable

# ------------------------------------------------------------------ 挂起状态
## 还没跑完的 AI 势力队列
var _pending_ai: Array[Faction] = []

## 是否正等待战斗结果
var _awaiting_battle: bool = false

## 当前挂起的战斗请求（供 GameManager 查）
var active_battle: Dictionary = {}


func _init(gs: GameState, ai_turn_cb: Callable, settle_cb: Callable, advance_cb: Callable) -> void:
	state = gs
	ai_turn = ai_turn_cb
	settle = settle_cb
	advance = advance_cb


## ---------------------------------------------------------------------------
## run_player_end_turn() — 玩家点"结束回合"时调用
## ---------------------------------------------------------------------------
## 返回值约定（GameManager 按此编排场景）：
##   {"battle": {...}}   — 发生战斗：{attacker_army_id, defender_army_id, city_id}
##                         战斗结束后必须调用 resume_after_battle(result)
##   {"advance": true, "turn": n} — 回合正常推进
## ---------------------------------------------------------------------------
func run_player_end_turn() -> Dictionary:
	_pending_ai = state.ai_factions()
	_awaiting_battle = false
	return _run_ai_queue()


## ---------------------------------------------------------------------------
## resume_after_battle() — 战斗结束后续跑回合流程
## ---------------------------------------------------------------------------
## battle_result：{"result": "victory"/"defeat"/"draw", ...}
## 战斗胜负的**后果应用**（占领城市/解散军团）由 GameManager 在战斗场景结算时
## 用 WorldMapModel 完成——本类只负责"流程续跑"，不碰领域后果。
## ---------------------------------------------------------------------------
func resume_after_battle(battle_result: Dictionary) -> Dictionary:
	if not _awaiting_battle:
		# 防御：没有挂起的战斗时被调用（不应发生）
		Log.error("[TurnManager] resume_after_battle 被调用但无挂起战斗")
		return {"advance": true, "turn": state.turn}
	_awaiting_battle = false
	active_battle = {}
	return _run_ai_queue()


## 是否正在等待战斗结果（GameManager 查询，防止重复进入战斗）
func is_awaiting_battle() -> bool:
	return _awaiting_battle


## ---------------------------------------------------------------------------
## _run_ai_queue() — 顺序执行剩余 AI 回合
## ---------------------------------------------------------------------------
func _run_ai_queue() -> Dictionary:
	while not _pending_ai.is_empty():
		var faction: Faction = _pending_ai.pop_front()
		var result: Dictionary = ai_turn.call(faction)
		var battle_req: Dictionary = result.get("battle", {})
		if not battle_req.is_empty():
			# 挂起：保存战斗请求，等 resume_after_battle
			_awaiting_battle = true
			active_battle = battle_req
			return {"battle": battle_req}
	# 全部 AI 完成 → 结算 + 推进回合
	settle.call()
	state.turn += 1
	advance.call()
	return {"advance": true, "turn": state.turn}
