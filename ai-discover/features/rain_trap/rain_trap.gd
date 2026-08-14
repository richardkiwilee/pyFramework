extends Node2D
## =============================================================================
## 接雨水 —— 经典算法可视化：柱状图能接住多少雨水
## =============================================================================
## · 随机高度柱条，左右双指针扫描计算每列水位；
## · 动画逐列"注水"显示积水（蓝色水位段）；
## · 【🎲 随机】【▶ 注水】；总量显示。
## 积水计算（_trap_water）为纯函数，可确定性测试。
## =============================================================================

const N := 14
const BAR_W := 76.0
const MAX_H := 320.0
const ORIGIN := Vector2(110, 560)

var _heights: Array = []      # 0..1
var _water: Array = []        # 每列水位 0..1
var _filling := 0             # 动画进度（已注水列数）
var _total := 0.0

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/RandomBtn.pressed.connect(_randomize)
	$CanvasLayer/FillBtn.pressed.connect(_fill)
	_randomize()


func _randomize() -> void:
	_heights.clear()
	for i in N:
		_heights.append(randf_range(0.1, 0.95))
	_water.clear()
	for i in N:
		_water.append(0.0)
	_filling = 0
	_total = 0.0
	status_label.text = "🌧 柱状图已随机 · 点【注水】看积水"
	queue_redraw()


## 积水计算（供测试与注水）：返回每列水位数组
func _trap_water(heights: Array) -> Array:
	var left_max: Array = []
	var m := 0.0
	for h in heights:
		m = maxf(m, h)
		left_max.append(m)
	var right_max: Array = []
	m = 0.0
	for i in range(heights.size() - 1, -1, -1):
		m = maxf(m, heights[i])
		right_max.push_front(m)
	var water: Array = []
	for i in heights.size():
		water.append(maxf(0.0, minf(left_max[i], right_max[i]) - heights[i]))
	return water


func _fill() -> void:
	_water = _trap_water(_heights)
	_filling = 0
	for w in _water:
		_total += w
	status_label.text = "🌧 注水中…"
	queue_redraw()


func _process(delta: float) -> void:
	if _filling < N and _total > 0.0:
		_filling += 1
		if _filling >= N:
			status_label.text = "🌧 总积水量 %.0f 单位" % (_total * 100.0)
		queue_redraw()


func _draw() -> void:
	# 柱条
	for i in N:
		var x := ORIGIN.x + i * BAR_W
		var h: float = _heights[i] * MAX_H
		draw_rect(Rect2(x + 6, ORIGIN.y - h, BAR_W - 12, h), Color(0.65, 0.55, 0.42))
	# 水位（动画逐列出现）
	for i in mini(_filling, N):
		var x := ORIGIN.x + i * BAR_W
		var base: float = _heights[i] * MAX_H
		var w: float = _water[i] * MAX_H
		if w > 0.5:
			draw_rect(Rect2(x + 6, ORIGIN.y - base - w, BAR_W - 12, w), Color(0.25, 0.6, 0.95, 0.75))
	# 基线
	draw_line(ORIGIN + Vector2(-10, 0), ORIGIN + Vector2(N * BAR_W + 10, 0), Color(0.3, 0.32, 0.4), 3.0)
