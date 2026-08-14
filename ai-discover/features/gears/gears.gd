extends Node2D
## =============================================================================
## 齿轮传动 —— 啮合齿轮按齿比联动旋转
## =============================================================================
## · 主动轮匀速旋转，从动轮按齿数反比联动（ω2 = -ω1 × r1 / r2）；
## · 3 齿轮链（大-中-小）：小轮转速最快，视觉上体现传动比；
## · 【🎲 换布局】随机齿数。
## 传动比（_driven_speed）为纯函数，可确定性测试。
## =============================================================================

var _gears: Array = []      # {pos, r, teeth, angle, speed}

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/RerollBtn.pressed.connect(_roll)
	_roll()


func _roll() -> void:
	_gears = [
		{"pos": Vector2(420, 340), "r": 110.0, "teeth": 22, "angle": 0.0, "speed": 1.2},
		{"pos": Vector2(700, 340), "r": 70.0, "teeth": 14, "angle": 0.0, "speed": 0.0},
		{"pos": Vector2(880, 340), "r": 42.0, "teeth": 9, "angle": 0.0, "speed": 0.0},
	]
	status_label.text = "⚙ 齿数 22 : 14 : 9 · 传动比 1 : 1.57 : 2.44"


## 从动轮转速（供测试与联动）：啮合反向、齿比反比
func _driven_speed(drive: Dictionary, driven: Dictionary) -> float:
	return -drive["speed"] * drive["teeth"] / driven["teeth"]


func _process(delta: float) -> void:
	_gears[0]["angle"] += _gears[0]["speed"] * delta
	for i in range(1, _gears.size()):
		_gears[i]["speed"] = _driven_speed(_gears[i - 1], _gears[i])
		_gears[i]["angle"] += _gears[i]["speed"] * delta
	queue_redraw()


func _draw() -> void:
	for g in _gears:
		var c: Vector2 = g["pos"]
		var r: float = g["r"]
		var teeth: int = g["teeth"]
		var ang: float = g["angle"]
		# 轮体
		draw_circle(c, r * 0.82, Color(0.5, 0.52, 0.6))
		draw_circle(c, r * 0.82, Color(0.25, 0.26, 0.32), false, 4.0)
		# 轮齿（沿圆周）
		for t in teeth:
			var a := ang + TAU * t / teeth
			var dir := Vector2.from_angle(a)
			draw_line(c + dir * (r * 0.8), c + dir * r, Color(0.42, 0.44, 0.52), 7.0)
		# 中心轴孔
		draw_circle(c, 14, Color(0.2, 0.21, 0.26))
		draw_circle(c, 14, Color(0.8, 0.82, 0.9), false, 3.0)
		# 辐条
		for i in 4:
			var a := ang + TAU * i / 4.0
			var dir := Vector2.from_angle(a)
			draw_line(c, c + dir * r * 0.7, Color(0.32, 0.33, 0.4), 4.0)
		# 转向标记
		var mark := c + Vector2.from_angle(ang) * r * 0.55
		draw_circle(mark, 6, Color(0.95, 0.8, 0.3))
