extends Node2D
## =============================================================================
## 滑动拼图 —— 经典 15-puzzle（4×4 数字滑块）
## =============================================================================
## · 点击空格相邻的数字块滑入空格；
## · 【🎲 洗牌】用"从目标态执行 300 次随机合法移动"的方式打乱（保证有解）；
## · 按 1..15 顺序排列即获胜，显示步数。
## 移动/胜利判定为纯函数，可确定性测试。
## =============================================================================

const N := 4
const CELL := 120.0
const ORIGIN := Vector2(400, 100)

var _tiles: Array = []     # 0..15，0 = 空格
var _moves := 0
var _won := false
var _shuffling := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var win_label: Label = $CanvasLayer/WinLabel


func _ready() -> void:
	$CanvasLayer/ShuffleBtn.pressed.connect(_shuffle)
	win_label.visible = false
	_reset()


func _reset() -> void:
	_tiles = []
	for i in 15:
		_tiles.append(i + 1)   # 1..15
	_tiles.append(0)          # 空格在右下角 = 目标态
	_moves = 0
	_won = false
	win_label.visible = false
	queue_redraw()


## 洗牌：随机合法移动 300 次（保证可解）
## 用独立 RNG + randomize()——不依赖全局 randi() 的种子质量
func _shuffle() -> void:
	_reset()
	_shuffling = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 300:
		var options := _movable_indices()
		if options.is_empty():
			break
		_move(options[rng.randi_range(0, options.size() - 1)])
	_shuffling = false
	_won = false
	# 极小概率回到目标态: 补一轮保证打乱
	if _check_solved():
		for i in 50:
			var options := _movable_indices()
			_move(options[rng.randi_range(0, options.size() - 1)])
	_moves = 0
	status_label.text = "🎲 已洗牌 · 点击数字块滑动"
	queue_redraw()


func _empty() -> int:
	return _tiles.find(0)


## 可移动（空格相邻）的块下标（供测试与洗牌）
func _movable_indices() -> Array:
	var e := _empty()
	var ex := e % N
	var ey := e / N
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ex + d.x
		var ny: int = ey + d.y
		if nx >= 0 and nx < N and ny >= 0 and ny < N:
			out.append(ny * N + nx)
	return out


## 移动块（供输入与测试）
func _move(idx: int) -> bool:
	if (_won and not _shuffling) or not _movable_indices().has(idx):
		return false
	var e := _empty()
	var tmp: int = _tiles[e]
	_tiles[e] = _tiles[idx]
	_tiles[idx] = tmp
	_moves += 1
	_check_win()
	status_label.text = "步数：%d" % _moves
	queue_redraw()
	return true


func _check_solved() -> bool:
	for i in 15:
		if _tiles[i] != i + 1:
			return false
	return true


func _check_win() -> void:
	if _shuffling:
		return
	if _check_solved():
		_won = true
		win_label.text = "🎉 拼好了！共用 %d 步" % _moves
		win_label.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(
			int(floor((event.position.x - ORIGIN.x) / CELL)),
			int(floor((event.position.y - ORIGIN.y) / CELL)))
		if c.x >= 0 and c.x < N and c.y >= 0 and c.y < N:
			_move(c.y * N + c.x)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	for i in 16:
		var v: int = _tiles[i]
		if v == 0:
			continue
		var r := Rect2(ORIGIN + Vector2(i % N, i / N) * CELL, Vector2(CELL - 6, CELL - 6))
		draw_rect(r, Color(0.28, 0.32, 0.44))
		draw_rect(r, Color(0.5, 0.55, 0.7), false, 2.0)
		var f := ThemeDB.fallback_font
		var txt := str(v)
		var size := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
		draw_string(f, r.get_center() + Vector2(-size.x / 2.0, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.95, 0.95, 1.0))
