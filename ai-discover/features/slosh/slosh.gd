extends Node2D
## =============================================================================
## 摇晃水杯 —— 粒子水在杯内摇晃（重力 + 杯壁碰撞 + 软分离）
## =============================================================================
## · 60 个水粒子：重力下坠、杯壁反弹、粒子间软性推开；
## · 左右方向键/鼠标左右移动倾斜杯子（水向低侧涌动）；
## · 【🎲 重置】重新倒满。
## 物理步进（_water_step）为纯函数，可确定性测试。
## =============================================================================

const BOX := Rect2(240, 160, 500, 380)
const DROP_R := 11.0
const DROPS := 60

var _drops: Array = []      # {pos, vel}
var _tilt := 0.0            # 倾斜加速度（x 方向）

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_fill)
	_fill()


func _fill() -> void:
	_drops.clear()
	var cols := 12
	for i in DROPS:
		var x := BOX.position.x + 30.0 + (i % cols) * (DROP_R * 2.1)
		var y := BOX.end.y - 40.0 - (i / cols) * (DROP_R * 2.1)
		_drops.append({"pos": Vector2(x, y), "vel": Vector2.ZERO})
	status_label.text = "💧 左右方向键倾斜杯子"
	queue_redraw()


## 单步物理（供测试）
func _water_step(delta: float, tilt: float) -> void:
	for d in _drops:
		d["vel"] += Vector2(tilt, 900.0) * delta
		d["pos"] += d["vel"] * delta
		# 杯壁
		if d["pos"].x < BOX.position.x + DROP_R:
			d["pos"].x = BOX.position.x + DROP_R
			d["vel"].x = -d["vel"].x * 0.5
		if d["pos"].x > BOX.end.x - DROP_R:
			d["pos"].x = BOX.end.x - DROP_R
			d["vel"].x = -d["vel"].x * 0.5
		if d["pos"].y < BOX.position.y + DROP_R:
			d["pos"].y = BOX.position.y + DROP_R
			d["vel"].y = -d["vel"].y * 0.5
		if d["pos"].y > BOX.end.y - DROP_R:
			d["pos"].y = BOX.end.y - DROP_R
			d["vel"].y = -d["vel"].y * 0.5
	# 粒子软分离（两轮）
	for iter in 2:
		for i in _drops.size():
			for j in range(i + 1, _drops.size()):
				var a: Dictionary = _drops[i]
				var b: Dictionary = _drops[j]
				var diff: Vector2 = b["pos"] - a["pos"]
				var d := diff.length()
				if d > 0.001 and d < DROP_R * 1.9:
					var push := (DROP_R * 1.9 - d) * 0.5
					var n := diff / d
					a["pos"] -= n * push
					b["pos"] += n * push
	# 分离可能把粒子推出杯壁 → 最后统一钳回杯内
	for d in _drops:
		d["pos"].x = clampf(d["pos"].x, BOX.position.x + DROP_R, BOX.end.x - DROP_R)
		d["pos"].y = clampf(d["pos"].y, BOX.position.y + DROP_R, BOX.end.y - DROP_R)


func _process(delta: float) -> void:
	var target := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		target = -600.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		target = 600.0
	_tilt = lerpf(_tilt, target, delta * 6.0)
	_water_step(delta, _tilt)
	queue_redraw()


func _draw() -> void:
	# 杯子
	draw_rect(BOX, Color(0.55, 0.8, 0.95, 0.18))
	draw_rect(BOX, Color(0.7, 0.85, 0.95), false, 6.0)
	# 水粒子（两层圆做高光）
	for d in _drops:
		draw_circle(d["pos"], DROP_R, Color(0.2, 0.55, 0.95, 0.85))
		draw_circle(d["pos"] + Vector2(-3, -3), DROP_R * 0.4, Color(1, 1, 1, 0.35))
