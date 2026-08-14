extends Node2D
## =============================================================================
## 俄罗斯方块 —— 七种方块旋转下落、消行计分、难度递增
## =============================================================================
## · 左右移动/下加速/上或空格旋转；消行得分，每 10 行升一级加速；
## · 顶部堆满 → 结束，R 重开；下一块预览。
## 核心逻辑（旋转/碰撞/消行）为纯函数，可确定性测试。
## =============================================================================

const W := 10
const H := 20
const CELL := 30.0
const ORIGIN := Vector2(390, 50)

## 方块定义：每种 4 个旋转态（坐标列表）
const PIECES: Array = [
	[[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]],                          # O
	[[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]],                          # I
	[[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(-1, 2)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	 [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(1, -2)]],                        # J
	[[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(2, 0)],
	 [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(1, -2)]],                        # L
	[[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	 [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 0), Vector2i(1, 1)]],                          # S
	[[Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 0)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)]],                          # Z
	[[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(-1, 1)],
	 [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, -1)],
	 [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1)]],                          # T
]
const PIECE_COLORS: Array[Color] = [
	Color(0.95, 0.85, 0.3), Color(0.3, 0.85, 0.95), Color(0.3, 0.5, 0.95),
	Color(0.95, 0.6, 0.2), Color(0.4, 0.9, 0.5), Color(0.9, 0.3, 0.3), Color(0.7, 0.4, 0.95),
]

var _grid: Array = []          # [y][x] → 颜色下标 or -1
var _cur: Dictionary = {}      # {type, rot, pos}
var _next_type := 0
var _fall_t := 0.0
var _fall_interval := 0.8
var _score := 0
var _lines := 0
var _over := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false
	_new_game()


func _new_game() -> void:
	_grid = []
	for y in H:
		var row: Array = []
		for x in W:
			row.append(-1)
		_grid.append(row)
	_score = 0
	_lines = 0
	_over = false
	_fall_interval = 0.8
	over_label.visible = false
	_next_type = randi() % PIECES.size()
	_spawn_piece()


func _spawn_piece() -> void:
	_cur = {"type": _next_type, "rot": 0, "pos": Vector2i(3, 0)}
	_next_type = randi() % PIECES.size()
	# 出生即碰撞 → 游戏结束
	if not _collides(_cur):
		return
	_over = true
	over_label.text = "💀 堆到顶了！得分 %d · R 重开" % _score
	over_label.visible = true


## 当前方块占格（供碰撞/绘制/测试）
func _cells_of(piece: Dictionary) -> Array:
	var cells: Array = []
	for c in PIECES[piece["type"]][piece["rot"]]:
		cells.append(piece["pos"] + c)
	return cells


## 是否与墙/底/已有方块碰撞
func _collides(piece: Dictionary) -> bool:
	for c in _cells_of(piece):
		if c.x < 0 or c.x >= W or c.y >= H:
			return true
		if c.y >= 0 and _grid[c.y][c.x] != -1:
			return true
	return false


## 移动（供输入与测试）：dx 平移 / 旋转
func _move(dx: int) -> bool:
	if _over:
		return false
	var test: Dictionary = {"type": _cur["type"], "rot": _cur["rot"], "pos": _cur["pos"] + Vector2i(dx, 0)}
	if not _collides(test):
		_cur["pos"] = test["pos"]
		return true
	return false


func _rotate() -> bool:
	if _over:
		return false
	var test: Dictionary = {"type": _cur["type"], "rot": (_cur["rot"] + 1) % PIECES[_cur["type"]].size(), "pos": _cur["pos"]}
	if not _collides(test):
		_cur["rot"] = test["rot"]
		return true
	return false


## 下落一格（供测试）：落定则固化并消行，返回是否落定
func _fall() -> bool:
	var test: Dictionary = {"type": _cur["type"], "rot": _cur["rot"], "pos": _cur["pos"] + Vector2i(0, 1)}
	if not _collides(test):
		_cur["pos"] = test["pos"]
		return false
	# 固化
	for c in _cells_of(_cur):
		if c.y >= 0:
			_grid[c.y][c.x] = _cur["type"]
	_clear_lines()
	_spawn_piece()
	return true


## 消行（供测试）：返回消除行数
func _clear_lines() -> int:
	var cleared := 0
	var y := H - 1
	while y >= 0:
		var full := true
		for x in W:
			if _grid[y][x] == -1:
				full = false
				break
		if full:
			_grid.remove_at(y)
			var new_row: Array = []
			for x in W:
				new_row.append(-1)
			_grid.insert(0, new_row)
			cleared += 1
		else:
			y -= 1
	if cleared > 0:
		_lines += cleared
		_score += [0, 100, 300, 500, 800][cleared]
		_fall_interval = maxf(0.15, 0.8 - _lines / 10 * 0.07)
		status_label.text = "🟦 得分 %d · 行 %d" % [_score, _lines]
	return cleared


func _process(delta: float) -> void:
	if _over:
		return
	_fall_t += delta
	if _fall_t >= _fall_interval:
		_fall_t = 0.0
		_fall()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_new_game()
		return
	if event.is_action_pressed("ui_left"):
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_fall()
		_fall_t = 0.0
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_rotate()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 棋盘
	draw_rect(Rect2(ORIGIN - Vector2(4, 4), Vector2(W * CELL + 8, H * CELL + 8)), Color(0.08, 0.09, 0.13))
	for y in H:
		for x in W:
			var v: int = _grid[y][x]
			if v >= 0:
				draw_rect(Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 2, CELL - 2)), PIECE_COLORS[v])
				draw_rect(Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 2, CELL - 2)), Color(1, 1, 1, 0.25), false, 2.0)
	# 当前方块
	if not _over:
		for c in _cells_of(_cur):
			if c.y >= 0:
				draw_rect(Rect2(ORIGIN + Vector2(c) * CELL, Vector2(CELL - 2, CELL - 2)), PIECE_COLORS[_cur["type"]])
	# 预览
	draw_rect(Rect2(ORIGIN + Vector2(W * CELL + 24, 10), Vector2(130, 130)), Color(0.08, 0.09, 0.13))
	for c in PIECES[_next_type][0]:
		draw_rect(Rect2(ORIGIN + Vector2(W * CELL + 24 + 40, 40) + Vector2(c) * 22.0, Vector2(20, 20)), PIECE_COLORS[_next_type])
