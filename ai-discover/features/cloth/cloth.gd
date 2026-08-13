extends Node2D
## =============================================================================
## 布料模拟 —— Verlet 积分 + 距离约束（经典物理布料）
## =============================================================================
## · 20×14 质点网格：Verlet 积分做运动（重力 + 风 + 阻尼），
##   每帧 8 轮距离约束迭代把相邻质点间距拉回 SPACING；
## · 顶部两角固定（晾衣绳），布料自然下垂摆动；
## · 交互：拖拽任意质点拉扯布料，松手弹回；【风】开关；【重置】。
## =============================================================================

const COLS := 20
const ROWS := 14
const SPACING := 22.0
const ORIGIN := Vector2(380, 60)

var _points: Array[Vector2] = []
var _prev: Array[Vector2] = []
var _pinned: Dictionary = {}   # idx → 固定位置
var _wind := true
var _grabbed := -1

@onready var wind_btn: Button = $CanvasLayer/Bar/WindBtn


func _ready() -> void:
	for y in ROWS:
		for x in COLS:
			var p := ORIGIN + Vector2(x * SPACING, y * SPACING)
			_points.append(p)
			_prev.append(p)
	# 顶部两角固定
	_pinned[0] = ORIGIN
	_pinned[COLS - 1] = ORIGIN + Vector2((COLS - 1) * SPACING, 0)
	wind_btn.pressed.connect(_toggle_wind)
	$CanvasLayer/Bar/ResetBtn.pressed.connect(_reset)


func _toggle_wind() -> void:
	_wind = not _wind
	wind_btn.text = "🌬 风：开" if _wind else "🌬 风：关"


func _reset() -> void:
	_points.clear()
	_prev.clear()
	_grabbed = -1
	for y in ROWS:
		for x in COLS:
			var p := ORIGIN + Vector2(x * SPACING, y * SPACING)
			_points.append(p)
			_prev.append(p)
	queue_redraw()


func _process(delta: float) -> void:
	# 1. Verlet 积分：pos += (pos - prev) * 阻尼 + 加速度 * dt²
	var accel := Vector2(0, 780.0)
	if _wind:
		accel.x += sin(Time.get_ticks_msec() / 1000.0 * 2.4) * 420.0
	for i in _points.size():
		if _pinned.has(i) or i == _grabbed:
			continue
		var vel := (_points[i] - _prev[i]) * 0.985
		_prev[i] = _points[i]
		_points[i] += vel + accel * delta * delta

	# 2. 距离约束迭代（横竖相邻各 8 轮）
	for iter in 8:
		for y in ROWS:
			for x in COLS:
				var i := y * COLS + x
				if x < COLS - 1:
					_constrain(i, i + 1)
				if y < ROWS - 1:
					_constrain(i, i + COLS)
	queue_redraw()


func _constrain(a: int, b: int) -> void:
	var delta_pos: Vector2 = _points[b] - _points[a]
	var d := delta_pos.length()
	if d < 0.001:
		return
	var diff := (d - SPACING) * 0.5
	var n := delta_pos / d
	if not _pinned.has(a):
		_points[a] += n * diff
	if not _pinned.has(b):
		_points[b] -= n * diff


## 最近质点（供拖拽与测试）
func _nearest_point(p: Vector2) -> int:
	var best := -1
	var best_d := 30.0
	for i in _points.size():
		var d := p.distance_to(_points[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_grabbed = _nearest_point(event.position)
		else:
			_grabbed = -1
	elif event is InputEventMouseMotion and _grabbed >= 0:
		_points[_grabbed] = event.position
		_prev[_grabbed] = event.position
		queue_redraw()


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	# 竖线 / 横线（按行渐变着色）
	for y in ROWS:
		for x in COLS:
			var i := y * COLS + x
			var shade := 0.35 + 0.45 * float(y) / ROWS
			var col := Color(shade, shade * 0.8 + 0.1, shade * 0.5)
			if x < COLS - 1:
				draw_line(_points[i], _points[i + 1], col, 1.8)
			if y < ROWS - 1:
				draw_line(_points[i], _points[i + COLS], col, 1.8)
	# 固定点
	for idx in _pinned.keys():
		draw_circle(_pinned[idx], 6, Color(1, 0.85, 0.4))
	# 拖拽中的点
	if _grabbed >= 0:
		draw_circle(_points[_grabbed], 9, Color(1, 1, 1), false, 3.0)
