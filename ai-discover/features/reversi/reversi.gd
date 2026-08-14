extends Node2D
## =============================================================================
## 黑白棋 —— 8×8 夹子翻转（经典 Reversi/Othello）
## =============================================================================
## · 黑白轮流落子，落子必须夹住对方一条直线（横竖斜）并翻转；
## · 无合法步自动跳过；双方都无步 → 结束，按子数定胜负；
## · 【🔄 重开】。翻转/合法步判定为纯函数，可确定性测试。
## =============================================================================

const N := 8
const CELL := 74.0
const ORIGIN := Vector2(340, 60)
const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _board: Array = []      # [y][x] → 0 空 / 1 黑 / 2 白
var _turn := 1
var _over := false

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_new_game)
	_new_game()


func _new_game() -> void:
	_board = []
	for y in N:
		var row: Array = []
		for x in N:
			row.append(0)
		_board.append(row)
	_board[3][3] = 2
	_board[3][4] = 1
	_board[4][3] = 1
	_board[4][4] = 2
	_turn = 1
	_over = false
	_refresh_status()


## 在 pos 落子可翻的对方子总数（供测试与判定）
func _flip_count(b: Array, pos: Vector2i, player: int) -> int:
	if b[pos.y][pos.x] != 0:
		return 0
	var total := 0
	for d in DIRS8:
		var cur := pos + d
		var line := 0
		while cur.x >= 0 and cur.x < N and cur.y >= 0 and cur.y < N and int(b[cur.y][cur.x]) == 3 - player:
			line += 1
			cur += d
		if line > 0 and cur.x >= 0 and cur.x < N and cur.y >= 0 and cur.y < N \
				and int(b[cur.y][cur.x]) == player:
			total += line
	return total


## 玩家所有合法落点（供测试与 AI）
func _legal_moves(b: Array, player: int) -> Array:
	var out: Array = []
	for y in N:
		for x in N:
			if _flip_count(b, Vector2i(x, y), player) > 0:
				out.append(Vector2i(x, y))
	return out


## 落子并翻转（供输入与测试）
func _place(pos: Vector2i) -> bool:
	if _over or _flip_count(_board, pos, _turn) == 0:
		return false
	_board[pos.y][pos.x] = _turn
	for d in DIRS8:
		var cur := pos + d
		var line: Array = []
		while cur.x >= 0 and cur.x < N and cur.y >= 0 and cur.y < N and int(_board[cur.y][cur.x]) == 3 - _turn:
			line.append(cur)
			cur += d
		if not line.is_empty() and cur.x >= 0 and cur.x < N and cur.y >= 0 and cur.y < N \
				and int(_board[cur.y][cur.x]) == _turn:
			for c in line:
				_board[c.y][c.x] = _turn
	# 换手（无步则跳过）
	_turn = 3 - _turn
	if _legal_moves(_board, _turn).is_empty():
		_turn = 3 - _turn
		if _legal_moves(_board, _turn).is_empty():
			_over = true
	_refresh_status()
	queue_redraw()
	return true


func _count(p: int) -> int:
	var n := 0
	for y in N:
		for x in N:
			if int(_board[y][x]) == p:
				n += 1
	return n


func _refresh_status() -> void:
	if _over:
		var b := _count(1)
		var w := _count(2)
		status_label.text = "🏁 结束！黑 %d : 白 %d · %s" % [b, w, "黑胜" if b > w else ("白胜" if w > b else "平局")]
	else:
		status_label.text = "%s 落子（合法步 %d）" % [["⚫ 黑", "⚪ 白"][_turn - 1], _legal_moves(_board, _turn).size()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(
			int(floor((event.position.x - ORIGIN.x) / CELL)),
			int(floor((event.position.y - ORIGIN.y) / CELL)))
		if c.x >= 0 and c.x < N and c.y >= 0 and c.y < N:
			_place(c)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(ORIGIN - Vector2(8, 8), Vector2(N * CELL + 16, N * CELL + 16)), Color(0.22, 0.45, 0.28))
	for y in N:
		for x in N:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL, CELL))
			draw_rect(r, Color(0.1, 0.1, 0.12), false, 1.5)
			if int(_board[y][x]) != 0:
				var c := r.get_center()
				draw_circle(c, CELL * 0.4, Color(0.1, 0.1, 0.12) if int(_board[y][x]) == 1 else Color(0.95, 0.95, 0.92))
