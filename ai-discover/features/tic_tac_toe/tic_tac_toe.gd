extends Node2D
## =============================================================================
## 井字棋 —— 玩家 X 对战 Minimax AI（AI 必胜/不败）
## =============================================================================
## · 3×3 棋盘：你执 X 先手，AI 执 O；胜负/平局判定 + 计分；
## · AI 用 Minimax 搜索（深度 = 剩余空格，3×3 全树秒算）；
## · 【🔄 重开】。胜负/最优步（_check_win/_best_move）为纯函数，可确定性测试。
## =============================================================================

const CELL := 130.0
const ORIGIN := Vector2(445, 110)
const LINES := [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6],
]

var _board: Array = []     # 0 空 / 1 X(玩家) / 2 O(AI)
var _score_x := 0
var _score_o := 0
var _over := false

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_reset)
	_reset()


func _reset() -> void:
	_board = []
	for i in 9:
		_board.append(0)
	_over = false
	status_label.text = "❌ 你执 X 先手 · 点击格子落子"


## 胜负判定（供测试）：p 是否连成一线
func _check_win(b: Array, p: int) -> bool:
	for line in LINES:
		if b[line[0]] == p and b[line[1]] == p and b[line[2]] == p:
			return true
	return false


## 平局判定
func _is_full(b: Array) -> bool:
	for v in b:
		if int(v) == 0:
			return false
	return true


## Minimax 评分：AI(O) 胜 +1，玩家(X) 胜 -1，平局 0
func _minimax(b: Array, is_ai: bool) -> int:
	if _check_win(b, 2):
		return 1
	if _check_win(b, 1):
		return -1
	if _is_full(b):
		return 0
	var best := -99 if is_ai else 99
	for i in 9:
		if int(b[i]) != 0:
			continue
		b[i] = 2 if is_ai else 1
		var score := _minimax(b, not is_ai)
		b[i] = 0
		if is_ai:
			best = maxi(best, score)
		else:
			best = mini(best, score)
	return best


## AI 最优落点（供测试与游戏）
func _best_move() -> int:
	var best_score := -99
	var best := -1
	for i in 9:
		if int(_board[i]) != 0:
			continue
		_board[i] = 2
		var score := _minimax(_board, false)
		_board[i] = 0
		if score > best_score:
			best_score = score
			best = i
	return best


## 玩家落子（供输入与测试）：返回后接 AI 回合
func _place(idx: int) -> void:
	if _over or int(_board[idx]) != 0:
		return
	_board[idx] = 1
	if _check_win(_board, 1):
		_over = true
		_score_x += 1
		status_label.text = "🎉 你赢了！X %d : %d O · 重开再来" % [_score_x, _score_o]
		return
	if _is_full(_board):
		_over = true
		status_label.text = "🤝 平局！重开再来"
		return
	# AI 回合
	var ai := _best_move()
	_board[ai] = 2
	if _check_win(_board, 2):
		_over = true
		_score_o += 1
		status_label.text = "🤖 AI 获胜！X %d : %d O · 重开再来" % [_score_x, _score_o]
	elif _is_full(_board):
		_over = true
		status_label.text = "🤝 平局！重开再来"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(
			int(floor((event.position.x - ORIGIN.x) / CELL)),
			int(floor((event.position.y - ORIGIN.y) / CELL)))
		if c.x >= 0 and c.x < 3 and c.y >= 0 and c.y < 3:
			_place(c.y * 3 + c.x)
			queue_redraw()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 网格
	for i in range(1, 3):
		draw_line(ORIGIN + Vector2(i * CELL, 0), ORIGIN + Vector2(i * CELL, CELL * 3), Color(0.7, 0.75, 0.9), 4.0)
		draw_line(ORIGIN + Vector2(0, i * CELL), ORIGIN + Vector2(CELL * 3, i * CELL), Color(0.7, 0.75, 0.9), 4.0)
	# 棋子
	for i in 9:
		if int(_board[i]) == 0:
			continue
		var c := ORIGIN + Vector2(i % 3 + 0.5, i / 3 + 0.5) * CELL
		if int(_board[i]) == 1:
			# X
			draw_line(c - Vector2(38, 38), c + Vector2(38, 38), Color(0.95, 0.4, 0.4), 8.0)
			draw_line(c - Vector2(38, -38), c + Vector2(38, -38), Color(0.95, 0.4, 0.4), 8.0)
		else:
			# O
			draw_circle(c, 40, Color(0.4, 0.7, 0.95), false, 8.0)
