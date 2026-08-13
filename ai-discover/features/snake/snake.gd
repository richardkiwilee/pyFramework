extends Node2D
## =============================================================================
## 贪吃蛇 —— 经典小游戏（方向键/WASD 转向，吃食增长加速）
## =============================================================================
## 蛇身 = Vector2i 队列（头在前）；每 tick 前进一格：
##   吃到食物 → 不裁尾（长度+1）+ 分数+1 + 略微提速；
##   撞墙 / 咬到自己 → 游戏结束（按 R 重开）。
## 逻辑全部在 _tick() 里（与输入/渲染解耦），可直接测试。
## =============================================================================

const GW := 30
const GH := 20
const CELL := 22.0
const ORIGIN := Vector2(310, 50)

var _snake: Array[Vector2i] = [Vector2i(15, 10), Vector2i(14, 10), Vector2i(13, 10)]
var _dir := Vector2i(1, 0)
var _next_dir := Vector2i(1, 0)
var _food := Vector2i(21, 10)
var _move_timer := 0.0
var _interval := 0.13
var _score := 0
var _dead := false

@onready var score_label: Label = $CanvasLayer/ScoreLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false


func _process(delta: float) -> void:
	if _dead:
		return
	_move_timer += delta
	if _move_timer >= _interval:
		_move_timer = 0.0
		_tick()
		queue_redraw()
	score_label.text = "🍎 分数：%d" % _score


## 一帧逻辑（纯函数式，供测试）
func _tick() -> void:
	_dir = _next_dir
	var head: Vector2i = _snake[0] + _dir
	var ate := head == _food
	if not ate:
		_snake.pop_back()
	# 撞墙或咬到自己
	if head.x < 0 or head.x >= GW or head.y < 0 or head.y >= GH or _snake.has(head):
		_dead = true
		over_label.visible = true
		over_label.text = "💀 游戏结束！得分 %d · 按 R 重新开始" % _score
		return
	_snake.push_front(head)
	if ate:
		_score += 1
		_interval = maxf(0.05, _interval * 0.97)
		_spawn_food()


func _spawn_food() -> void:
	var free: Array = []
	for y in GH:
		for x in GW:
			var c := Vector2i(x, y)
			if not _snake.has(c):
				free.append(c)
	if free.is_empty():
		return
	_food = free[randi() % free.size()]


func _restart() -> void:
	_snake = [Vector2i(15, 10), Vector2i(14, 10), Vector2i(13, 10)]
	_dir = Vector2i(1, 0)
	_next_dir = Vector2i(1, 0)
	_food = Vector2i(21, 10)
	_interval = 0.13
	_score = 0
	_dead = false
	over_label.visible = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _dead:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_restart()
		return
	var want := Vector2i.ZERO
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		want = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		want = Vector2i(1, 0)
	elif event.is_action_pressed("ui_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_W):
		want = Vector2i(0, -1)
	elif event.is_action_pressed("ui_down") or (event is InputEventKey and event.pressed and event.keycode == KEY_S):
		want = Vector2i(0, 1)
	else:
		return
	# 禁止 180° 掉头（否则会瞬间咬到自己）
	if want != Vector2i.ZERO and want != -_dir:
		_next_dir = want
	get_viewport().set_input_as_handled()


func _draw() -> void:
	# 场地
	draw_rect(Rect2(ORIGIN - Vector2(6, 6), Vector2(GW * CELL + 12, GH * CELL + 12)), Color(0.10, 0.11, 0.16))
	for y in GH:
		for x in GW:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 1, CELL - 1))
			draw_rect(r, Color(0.15, 0.17, 0.22))
	# 食物
	draw_circle(ORIGIN + (Vector2(_food) + Vector2(0.5, 0.5)) * CELL, 8.5, Color(0.9, 0.3, 0.25))
	# 蛇（头深尾浅的绿色渐变）
	for i in _snake.size():
		var t := float(i) / _snake.size()
		var col := Color(0.15 + 0.55 * (1.0 - t), 0.75 + 0.15 * (1.0 - t), 0.25 + 0.2 * (1.0 - t))
		draw_rect(Rect2(ORIGIN + Vector2(_snake[i]) * CELL, Vector2(CELL - 1, CELL - 1)), col)
	# 蛇眼
	var head_c := ORIGIN + (Vector2(_snake[0]) + Vector2(0.5, 0.5)) * CELL
	draw_circle(head_c + Vector2(-4, -3), 2.0, Color(0.05, 0.05, 0.05))
	draw_circle(head_c + Vector2(4, -3), 2.0, Color(0.05, 0.05, 0.05))
