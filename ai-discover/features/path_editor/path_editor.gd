extends Node2D
## =============================================================================
## 轨道编辑器 —— 点击布点、拖拽调形，火车沿 Catmull-Rom 样条循环行驶
## =============================================================================
## · 左键空白处加点；拖动控制点调整形状；右键控制点删除；
## · 轨道 = 过所有控制点的闭合 Catmull-Rom 样条（二阶连续）；
## · 【▶ 运行】火车沿轨道匀速行驶（按弧长近似等速）；
## · 【清空】重来。
## 核心 _sample_path(t) 是纯函数：t∈[0,1] 沿闭合轨道归一化参数。
## =============================================================================

const TRAIN_SPEED := 0.12   # 每秒走过的轨道比例（简化）

var _points: Array[Vector2] = []
var _dragging := -1
var _running := true
var _train_t := 0.0

@onready var run_btn: Button = $CanvasLayer/Bar/RunBtn


func _ready() -> void:
	# 预设一个环线，开箱即玩
	_points = [Vector2(300, 500), Vector2(500, 250), Vector2(800, 300), Vector2(950, 500), Vector2(700, 620)]
	run_btn.pressed.connect(_toggle_run)
	$CanvasLayer/Bar/ClearBtn.pressed.connect(func() -> void: _points.clear(); queue_redraw())
	queue_redraw()


func _toggle_run() -> void:
	_running = not _running
	run_btn.text = "⏸ 暂停" if _running else "▶ 运行"


func _process(delta: float) -> void:
	if _running and _points.size() >= 2:
		_train_t = fposmod(_train_t + TRAIN_SPEED * delta, 1.0)
		queue_redraw()


## Catmull-Rom 闭合样条采样（t ∈ [0,1) 归一化轨道参数）
func _sample_path(t: float) -> Vector2:
	if _points.size() < 2:
		return Vector2.ZERO
	var n := _points.size()
	var f := fposmod(t, 1.0) * n
	var i := int(floor(f)) % n
	var u: float = f - floor(f)
	var p0: Vector2 = _points[(i - 1 + n) % n]
	var p1: Vector2 = _points[i]
	var p2: Vector2 = _points[(i + 1) % n]
	var p3: Vector2 = _points[(i + 2) % n]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * u
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u
	)


# ============================================================
#  交互
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _point_at(event.position)
			if i >= 0:
				_dragging = i
			else:
				_points.append(event.position)
				queue_redraw()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = -1
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var i := _point_at(event.position)
			if i >= 0:
				_points.remove_at(i)
				queue_redraw()
	elif event is InputEventMouseMotion and _dragging >= 0:
		_points[_dragging] = event.position
		queue_redraw()


func _point_at(p: Vector2) -> int:
	for i in _points.size():
		if p.distance_to(_points[i]) < 16.0:
			return i
	return -1


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	# 样条轨道（细密采样连线）
	if _points.size() >= 2:
		var pts := PackedVector2Array()
		for i in 200:
			pts.append(_sample_path(float(i) / 200.0))
		draw_polyline(pts, Color(0.30, 0.34, 0.46), 8.0)
		draw_polyline(pts, Color(0.50, 0.58, 0.78), 3.0)
	# 控制点
	for i in _points.size():
		var col := Color(0.95, 0.85, 0.4) if i == _dragging else Color(0.8, 0.8, 0.9)
		draw_circle(_points[i], 10, col)
		draw_circle(_points[i], 10, Color(0.1, 0.1, 0.15), false, 2.0)
	# 火车
	if _points.size() >= 2:
		var tp := _sample_path(_train_t)
		draw_circle(tp, 14, Color(0.95, 0.4, 0.3))
		draw_circle(tp, 14, Color(1, 0.9, 0.8), false, 2.0)
		draw_circle(tp, 6, Color(1, 1, 1))
