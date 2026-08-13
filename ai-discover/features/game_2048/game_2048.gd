extends Node2D
## =============================================================================
## 2048 —— 方向键滑动合并（经典数字合成）
## =============================================================================
## · 方向键/WASD 向四个方向滑动：同数相邻合并、空格压缩；
## · 每次有效移动后在随机空格生成 2（10% 概率 4）；
## · 合成 2048 胜利；无路可走时失败；R 重开。
## 合并（_merge_row/_slide）为纯函数，可确定性测试。
## =============================================================================

const N := 4
const CELL := 120.0
const ORIGIN := Vector2(400, 100)

const TILE_COLORS: Dictionary = {
	2: Color(0.85, 0.82, 0.72), 4: Color(0.9, 0.8, 0.55), 8: Color(0.95, 0.6, 0.35),
	16: Color(0.9, 0.45, 0.3), 32: Color(0.9, 0.3, 0.3), 64: Color(0.8, 0.25, 0.4),
	128: Color(0.9, 0.8, 0.3), 256: Color(0.9, 0.75, 0.25), 512: Color(0.9, 0.7, 0.2),
	1024: Color(0.8, 0.6, 0.9), 2048: Color(1.0, 0.85, 0.4),
}

var _grid: Array = []      # [y][x]
var _score := 0
var _over := false
var _won := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false
	_new_game()


func _new_game() -> void:
	_grid = []
	for y in N:
		var row: Array = []
		for x in N:
			row.append(0)
		_grid.append(row)
	_score = 0
	_over = false
	_won = false
	over_label.visible = false
	_spawn()
	_spawn()
	_refresh_status()


## 单行向左合并（供测试）：返回 [合并后行, 得分, 是否变化]
func _merge_row(r: Array) -> Array:
	var vals: Array = []
	for v in r:
		if int(v) != 0:
			vals.append(int(v))
	var out: Array = []
	var gained := 0
	var i := 0
	while i < vals.size():
		if i + 1 < vals.size() and vals[i] == vals[i + 1]:
			out.append(vals[i] * 2)
			gained += vals[i] * 2
			i += 2
		else:
			out.append(vals[i])
			i += 1
	while out.size() < N:
		out.append(0)
	var changed := false
	for j in N:
		if out[j] != int(r[j]):
			changed = true
	return [out, gained, changed]


## 取第 idx 行/列（dir 决定方向，供 _slide）
func _line(idx: int, dir: Vector2i, reverse: bool) -> Array:
	var out: Array = []
	for i in N:
		var c := Vector2i(
			idx if dir.x != 0 else i,
			idx if dir.y != 0 else i)
		if reverse:
			c = Vector2i(N - 1 - c.x if dir.x != 0 else c.x, N - 1 - c.y if dir.y != 0 else c.y)
		out.append(_grid[c.y][c.x])
	return out


func _write_line(idx: int, dir: Vector2i, reverse: bool, line: Array) -> void:
	for i in N:
		var c := Vector2i(
			idx if dir.x != 0 else i,
			idx if dir.y != 0 else i)
		if reverse:
			c = Vector2i(N - 1 - c.x if dir.x != 0 else c.x, N - 1 - c.y if dir.y != 0 else c.y)
		_grid[c.y][c.x] = line[i]


## 滑动（供输入与测试）：返回 [得分, 是否变化]
func _slide(dir: Vector2i) -> Array:
	var gained := 0
	var changed := false
	# 向左/上 = 从低位开始压缩（reverse=false）；向右/下 = 反向
	var reverse := dir.x > 0 or dir.y > 0
	for idx in N:
		var line := _line(idx, dir, reverse)
		var result: Array = _merge_row(line)
		gained += result[1]
		if result[2]:
			changed = true
		_write_line(idx, dir, reverse, result[0])
	return [gained, changed]


func _spawn() -> void:
	var empty: Array = []
	for y in N:
		for x in N:
			if _grid[y][x] == 0:
				empty.append(Vector2i(x, y))
	if empty.is_empty():
		return
	var c: Vector2i = empty[randi() % empty.size()]
	_grid[c.y][c.x] = 4 if randf() < 0.1 else 2


func _can_move() -> bool:
	for y in N:
		for x in N:
			if _grid[y][x] == 0:
				return true
			if x + 1 < N and _grid[y][x] == _grid[y][x + 1]:
				return true
			if y + 1 < N and _grid[y][x] == _grid[y + 1][x]:
				return true
	return false


func _refresh_status() -> void:
	status_label.text = "🔢 得分：%d" % _score
	if _won and not _over:
		over_label.text = "🏆 合成 2048！继续挑战更高分"
		over_label.visible = true


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_new_game()
		return
	var dir := Vector2i.ZERO
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		dir = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		dir = Vector2i(1, 0)
	elif event.is_action_pressed("ui_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_W):
		dir = Vector2i(0, -1)
	elif event.is_action_pressed("ui_down") or (event is InputEventKey and event.pressed and event.keycode == KEY_S):
		dir = Vector2i(0, 1)
	else:
		return
	var result: Array = _slide(dir)
	_score += result[0]
	if result[1]:
		_spawn()
		for y in N:
			for x in N:
				if _grid[y][x] == 2048:
					_won = true
		if not _can_move():
			_over = true
			over_label.text = "💀 无路可走！最终得分 %d · R 重开" % _score
			over_label.visible = true
	_refresh_status()
	get_viewport().set_input_as_handled()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(ORIGIN - Vector2(14, 14), Vector2(N * CELL + 28, N * CELL + 28)), Color(0.42, 0.38, 0.32))
	for y in N:
		for x in N:
			var v: int = _grid[y][x]
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 10, CELL - 10))
			var col: Color = TILE_COLORS.get(v, Color(0.75, 0.72, 0.65))
			if v == 0:
				col = Color(0.52, 0.48, 0.42)
			draw_rect(r, col)
			if v != 0:
				var f := ThemeDB.fallback_font
				var txt := str(v)
				var size := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 36)
				draw_string(f, r.get_center() + Vector2(-size.x / 2.0, 13), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.15, 0.13, 0.1))
