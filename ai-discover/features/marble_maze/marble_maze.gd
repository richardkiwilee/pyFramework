extends Node2D
## =============================================================================
## 弹珠迷宫 —— 倾斜棋盘滚动弹珠穿过迷宫到达终点
## =============================================================================
## · 方向键/WASD 倾斜棋盘（加速度控制），弹珠带惯性滑动；
## · 圆 vs 网格墙碰撞：就近 3×3 单元格做"最近点推离"解算；
## · 到达 ⭐ 终点计时胜利，R 重开。
## 物理与渲染分离（_physics_step 纯函数式），可确定性测试。
## =============================================================================

const CELL := 40.0
const ORIGIN := Vector2(240, 60)
const MARBLE_R := 13.0
const ACCEL := 900.0

const MAZE: Array[String] = [
	"################",
	"#S     #      G#",
	"# ###  #  ##   #",
	"#   #  #  #    #",
	"##  #  #  #  # #",
	"#   #     #    #",
	"# ###### ####  #",
	"#      #       #",
	"##  #  #  ###  #",
	"#   #  #    #  #",
	"################",
]

var _marble := Vector2.ZERO
var _vel := Vector2.ZERO
var _goal := Vector2.ZERO
var _start_time: float = 0.0
var _won := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var win_label: Label = $CanvasLayer/WinLabel


func _ready() -> void:
	_scan_maze()
	win_label.visible = false


func _scan_maze() -> void:
	for y in MAZE.size():
		for x in MAZE[y].length():
			var c := MAZE[y][x]
			if c == "S":
				_marble = _cell_center(Vector2i(x, y))
			elif c == "G":
				_goal = _cell_center(Vector2i(x, y))
	_start_time = Time.get_ticks_msec() / 1000.0
	_won = false


func _cell_center(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func _is_wall(x: int, y: int) -> bool:
	if y < 0 or y >= MAZE.size() or x < 0 or x >= MAZE[y].length():
		return true
	return MAZE[y][x] == "#"


## 单步物理：加速度 + 惯性 + 圆墙碰撞（供测试）
func _physics_step(delta: float, accel: Vector2) -> void:
	_vel += accel * delta
	_vel *= 0.985
	var p := _marble + _vel * delta
	# 圆 vs 网格墙（就近单元格，两轮迭代增强稳定性）
	for iter in 2:
		p = _resolve_collisions(p)
	_marble = p


## 把圆心推离所有相邻墙（最近点法）
func _resolve_collisions(p: Vector2) -> Vector2:
	var cx := int(floor((p.x - ORIGIN.x) / CELL))
	var cy := int(floor((p.y - ORIGIN.y) / CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not _is_wall(cx + dx, cy + dy):
				continue
			var rect := Rect2(ORIGIN + Vector2(cx + dx, cy + dy) * CELL, Vector2(CELL, CELL))
			var closest := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
			var diff := p - closest
			var d := diff.length()
			if d < MARBLE_R:
				if d > 0.001:
					p = closest + diff / d * MARBLE_R
				else:
					# 圆心在墙内（极端情况）：沿最小轴推出
					var push_x := minf(absf(p.x - rect.position.x), absf(p.x - rect.end.x))
					var push_y := minf(absf(p.y - rect.position.y), absf(p.y - rect.end.y))
					p = Vector2(p.x + MARBLE_R if push_x <= push_y else p.x, p.y if push_x <= push_y else p.y + MARBLE_R)
	return p


func _process(delta: float) -> void:
	if _won:
		return
	var accel := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		accel.x -= ACCEL
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		accel.x += ACCEL
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		accel.y -= ACCEL
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		accel.y += ACCEL
	_physics_step(delta, accel)
	queue_redraw()

	# 到达判定
	if _marble.distance_to(_goal) < CELL * 0.4:
		_won = true
		var t := Time.get_ticks_msec() / 1000.0 - _start_time
		win_label.text = "🎉 到达终点！用时 %.1f 秒" % t
		win_label.visible = true
		status_label.text = "按 R 重新开始"


func _unhandled_input(event: InputEvent) -> void:
	if _won and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_scan_maze()
		_vel = Vector2.ZERO
		win_label.visible = false
		status_label.text = ""
		queue_redraw()


func _draw() -> void:
	# 迷宫
	for y in MAZE.size():
		for x in MAZE[y].length():
			var rect := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL, CELL))
			if MAZE[y][x] == "#":
				draw_rect(rect, Color(0.30, 0.34, 0.46))
				draw_rect(rect.grow(-3), Color(0.38, 0.42, 0.56))
			else:
				draw_rect(rect, Color(0.12, 0.13, 0.18))
	# 终点
	draw_circle(_goal, 12, Color(1.0, 0.85, 0.3))
	draw_circle(_goal, 12, Color(1, 1, 1), false, 2.0)
	# 弹珠
	draw_circle(_marble, MARBLE_R, Color(0.95, 0.4, 0.35))
	draw_circle(_marble + Vector2(-4, -5), 4, Color(1, 1, 1, 0.6))
