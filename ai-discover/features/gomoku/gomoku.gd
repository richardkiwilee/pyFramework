extends Node2D
## =============================================================================
## 五子棋 —— 15×15 双人轮流落子，五连即胜
## =============================================================================
## · 点击交叉点落子（黑先白后交替），横/竖/斜任意五连获胜；
## · 获胜连线高亮 + 落子数显示；【🔄 重开】。
## 规则（_place/_check_win）为纯函数，可确定性测试。
## =============================================================================

const N := 15
const CELL := 40.0
const ORIGIN := Vector2(320, 60)

var _board: Dictionary = {}    # Vector2i → 1 黑 / 2 白
var _turn := 1
var _winner := 0
var _win_line: Array = []

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_reset)
	_reset()


func _reset() -> void:
	_board.clear()
	_turn = 1
	_winner = 0
	_win_line.clear()
	status_label.text = "⚫ 黑方落子"
	queue_redraw()


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < N and c.y >= 0 and c.y < N


## 落子（供输入与测试）
func _place(c: Vector2i) -> bool:
	if _winner != 0 or not _in_grid(c) or _board.has(c):
		return false
	_board[c] = _turn
	if _check_win(c):
		_winner = _turn
		status_label.text = "🏆 %s 获胜！（%d 手）" % [["⚫ 黑方", "⚪ 白方"][_turn - 1], _board.size()]
		return true
	_turn = 3 - _turn
	status_label.text = "%s 落子" % ["⚫ 黑方", "⚪ 白方"][_turn - 1]
	queue_redraw()
	return true


## 五连判定（供测试）
func _check_win(c: Vector2i) -> bool:
	var player: int = _board[c]
	for dir in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var line: Array = [c]
		for sign in [1, -1]:
			var p: Vector2i = c + dir * sign
			while _in_grid(p) and _board.get(p, 0) == player:
				line.append(p)
				p += dir * sign
		if line.size() >= 5:
			_win_line = line
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(
			int(round((event.position.x - ORIGIN.x) / CELL)),
			int(round((event.position.y - ORIGIN.y) / CELL)))
		_place(c)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 棋盘
	draw_rect(Rect2(ORIGIN - Vector2(26, 26), Vector2((N - 1) * CELL + 52, (N - 1) * CELL + 52)), Color(0.75, 0.58, 0.36))
	for i in N:
		draw_line(ORIGIN + Vector2(i * CELL, 0), ORIGIN + Vector2(i * CELL, (N - 1) * CELL), Color(0.2, 0.15, 0.1), 1.5)
		draw_line(ORIGIN + Vector2(0, i * CELL), ORIGIN + Vector2((N - 1) * CELL, i * CELL), Color(0.2, 0.15, 0.1), 1.5)
	# 星位
	for s in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 11), Vector2i(11, 11), Vector2i(7, 7)]:
		draw_circle(ORIGIN + Vector2(s) * CELL, 4, Color(0.2, 0.15, 0.1))
	# 棋子
	for c in _board.keys():
		var p := ORIGIN + Vector2(c) * CELL
		var col := Color(0.1, 0.1, 0.12) if int(_board[c]) == 1 else Color(0.95, 0.95, 0.92)
		draw_circle(p, CELL * 0.42, col)
		draw_circle(p + Vector2(-4, -5), 4, Color(1, 1, 1, 0.4))
	# 获胜连线
	if _winner != 0:
		var a := ORIGIN + Vector2(_win_line[0]) * CELL
		var b := ORIGIN + Vector2(_win_line[_win_line.size() - 1]) * CELL
		draw_line(a, b, Color(1, 0.3, 0.3), 6.0)
