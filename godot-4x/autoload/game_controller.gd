## 控制器：持有 Game 单例 + 回合编排 + 日志 + 存档（对应 pydemo/tui/controller.py）。
## 模块级单例是最轻的解耦方式：场景/图形组件直接访问 GameController.game。
extends Node

const SAVE_PATH := "user://save001.dat"

var game: Game = null
var log_messages: Array = []   # [[text, warn], ...] 环形缓冲

func _ready() -> void:
	pass

# ---- 生命周期 ----
func new_game() -> Game:
	game = Scenario.build_scenario()
	clear_log()
	push_log("新游戏开始:攻破 AI 首都即获胜")
	begin_player_turn()
	return game

func player() -> Faction.Faction_:
	return game.factions[game.player_id]

# ---- 回合编排 ----
## 玩家回合开始：经济结算 + 招募池刷新 + 事件触发。
func begin_player_turn() -> void:
	var g := game
	var p: Faction.Faction_ = g.factions[g.player_id]
	g.start_turn(p)
	g.maybe_trigger_event(p)

## 结束玩家回合：AI 行动 → 日历推进 → 复位行动标记 → 胜负判定。
func run_ai_and_advance() -> void:
	var g := game
	# 玩家未处理的事件自动选 0，避免卡住
	if g.pending_event != null:
		var msg := g.resolve_event(0)
		push_log("事件:%s" % msg)
	# AI 行动
	for fid in g.factions:
		var f: Faction.Faction_ = g.factions[fid]
		if fid == g.player_id or not f.alive:
			continue
		var actions := Ai.ai_take_turn(f, g)
		for action in actions:
			_exec_ai_action(fid, action)
			if g.is_over():
				break
		if g.is_over():
			break
	# 日历推进 + 标记复位 + 胜负
	g.end_turn_advance()
	for a in g.armies.values():
		a.has_acted_this_turn = false
	g.check_winner()
	if g.is_over():
		_log_winner()
		return
	begin_player_turn()

func _exec_ai_action(fid: String, payload: Dictionary) -> void:
	var g := game
	match payload.get("kind", ""):
		"build":
			push_log("AI 建造:%s" % g.action_build(fid, payload["stronghold"], payload["building"]))
		"recruit_hero":
			push_log("AI 招募:%s" % g.action_recruit_hero(fid, payload["stronghold"], payload["hero"]))
		"move_attack":
			push_log("AI 行动:%s" % g.action_move_attack(fid, payload["army"], payload["to"]))
		"deploy":
			push_log("AI 上场:%s" % g.action_deploy(fid, payload["army"], payload["unit"]))
		"new_army":
			var node_id: String = payload["stronghold"]
			var name: String = payload.get("name", "AI 部队")
			var army := g.create_army(fid, node_id, name)
			var hero: Variant = g.unit_index.get(payload["hero"])
			if hero == null or not g.set_captain(army, hero):
				g.disband_army(army)
				push_log("AI 新建部队:失败(%s)" % payload.get("hero", "?"))
			else:
				push_log("AI 新建部队:%s(队长 %s)" % [army.name, hero.name])
		"learn_tech":
			push_log("AI 研究科技:%s" % g.action_learn_tech(fid, payload["tech"]))
		"learn_culture":
			push_log("AI 研究文化:%s" % g.action_learn_culture(fid, payload["culture"]))
		"recruit_unit":
			push_log("AI 招兵:%s" % g.action_recruit_unit(fid, payload["unit"]))

func _log_winner() -> void:
	var w := game.winner
	if w != "" and game.factions.has(w):
		push_log("游戏结束！胜者:%s" % game.factions[w].name, true)
	else:
		push_log("游戏结束(无胜者)", true)

# ---- 存档 ----
func save() -> String:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return "保存失败:%s" % FileAccess.get_open_error()
	f.store_string(JSON.stringify(game.snapshot()))
	return "已保存(第 %d 天)" % game.calendar.day

func load() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return "无存档(开始新游戏)"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data == null or not (data is Dictionary):
		return "读取失败:存档损坏"
	game = Game.restore(data)
	return "已读取(第 %d 天)" % game.calendar.day

# ---- 日志（对应 pydemo/tui/log.py） ----
const LOG_MAX := 50

func clear_log() -> void:
	log_messages.clear()

## 追加一条日志；warn=true 为错误/警告（"失败:..."）。
func push_log(msg: String, warn: bool = false) -> void:
	if msg == "":
		return
	log_messages.append([msg, warn])
	if log_messages.size() > LOG_MAX:
		log_messages.pop_front()

## 最近 n 条 [[text, warn], ...]。
func recent_log(n: int = 3) -> Array:
	if n <= 0:
		return []
	var start := maxi(0, log_messages.size() - n)
	var out: Array = []
	for i in range(start, log_messages.size()):
		out.append(log_messages[i])
	return out

## 执行动作并记日志（UI 便捷入口）。
func do_action(fn: Callable) -> void:
	var msg: String = fn.call()
	if msg != "":
		push_log(msg, msg.begins_with("失败"))
