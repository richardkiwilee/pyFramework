extends Node2D
## =============================================================================
## 弹簧绳索 —— Verlet 链：一端跟随鼠标，尾端带重物惯性甩动
## =============================================================================
## · 26 节质点链：头点每帧锁定鼠标，其余点 Verlet 积分（重力+阻尼），
##   每帧 6 轮距离约束迭代维持链长；
## · 拖动鼠标甩动，重物画圈、鞭打、悬挂都会自然出现；
## · 绘制：链身渐变色带（粗→细）+ 末端发光重物球。
## 逻辑与输入解耦（_head_target），可确定性测试。
## =============================================================================

const SEGS := 26
const SEG_LEN := 18.0

var _points: Array[Vector2] = []
var _prev: Array[Vector2] = []
var _head_target := Vector2(400, 200)

@onready var hint_label: Label = $CanvasLayer/HintLabel


func _ready() -> void:
	for i in SEGS + 1:
		_points.append(Vector2(400 + i * SEG_LEN, 200))
		_prev.append(Vector2(400 + i * SEG_LEN, 200))


func _process(delta: float) -> void:
	_head_target = get_viewport().get_mouse_position()
	_sim_step(delta)
	queue_redraw()


## 单步模拟（纯逻辑，供测试）
func _sim_step(delta: float) -> void:
	# 头点锁定目标
	_prev[0] = _points[0]
	_points[0] = _head_target
	# Verlet 其余点：重力 + 阻尼
	for i in range(1, SEGS + 1):
		var vel := (_points[i] - _prev[i]) * 0.97
		_prev[i] = _points[i]
		_points[i] += vel + Vector2(0, 420.0) * delta * delta
	# 距离约束迭代
	for iter in 6:
		for i in SEGS:
			_constrain(i, i + 1)


func _constrain(a: int, b: int) -> void:
	var delta_pos: Vector2 = _points[b] - _points[a]
	var d := delta_pos.length()
	if d < 0.001:
		return
	var diff := (d - SEG_LEN) * 0.5
	var n := delta_pos / d
	# 头点（索引 0）是固定锚点，不参与约束修正
	if a != 0:
		_points[a] += n * diff
	_points[b] -= n * diff


## 端点（供测试断言）
func _tail() -> Vector2:
	return _points[SEGS]


func _draw() -> void:
	if _points.size() < 2:
		return
	# 链身：粗→细 + 明→暗渐变
	for i in SEGS:
		var f := 1.0 - float(i) / SEGS
		var col := Color(0.45 + 0.4 * f, 0.55 + 0.35 * f, 0.9)
		draw_line(_points[i], _points[i + 1], col, 2.0 + 7.0 * f)
	# 头端抓手
	draw_circle(_points[0], 8, Color(0.9, 0.9, 1.0))
	# 末端重物（发光）
	var tail := _tail()
	draw_circle(tail, 16, Color(0.95, 0.8, 0.3))
	draw_circle(tail, 16, Color(1, 0.9, 0.6, 0.5), false, 3.0)
	draw_circle(tail, 7, Color(1, 1, 0.9))
