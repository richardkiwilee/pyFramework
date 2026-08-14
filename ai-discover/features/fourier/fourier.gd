extends Node2D
## =============================================================================
## 傅里叶绘图 —— 旋转矢量臂（Epicycle）用傅里叶级数描画心形
## =============================================================================
## · 目标形状（心形参数方程）采样 100 点，做离散傅里叶变换（DFT）
##   得到 25 个旋转矢量（k=-12..12）；
## · 所有矢量首尾相连旋转，末端轨迹复现心形；
## · 【▶ 播放】动画开关 · 轨迹渐隐。
## DFT 系数（_compute_coeffs/_reconstruct）为纯函数，可确定性测试。
## =============================================================================

const SAMPLES := 100
const K_MAX := 12
const SCALE := 10.0

var _coeffs: Array = []      # [{k, vec}]
var _trail: Array = []       # 末端轨迹
var _t := 0.0
var _playing := true

@onready var play_btn: Button = $CanvasLayer/PlayBtn


func _ready() -> void:
	play_btn.pressed.connect(func() -> void:
		_playing = not _playing
		play_btn.text = "⏸ 暂停" if _playing else "▶ 播放")
	_compute_coeffs()


## 心形参数方程（t ∈ 0..1）
func _target_shape(t: float) -> Vector2:
	var a := TAU * t
	var x := 16.0 * pow(sin(a), 3.0)
	var y := 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
	return Vector2(x, -y) * SCALE


## DFT：采样 → 复数系数（供测试与绘制）
func _compute_coeffs() -> void:
	_coeffs.clear()
	for k in range(-K_MAX, K_MAX + 1):
		var sum := Vector2.ZERO
		for n in SAMPLES:
			var f := _target_shape(float(n) / SAMPLES)
			var ang := -TAU * k * n / SAMPLES
			sum += Vector2(
				f.x * cos(ang) - f.y * sin(ang),
				f.x * sin(ang) + f.y * cos(ang))
		_coeffs.append({"k": k, "vec": sum / SAMPLES})


## 用系数重构时刻 t 的位置（供测试与绘制）：只累加前 j 个矢量
func _reconstruct(t: float, j: int) -> Vector2:
	var p := Vector2.ZERO
	for i in mini(j, _coeffs.size()):
		var k: int = _coeffs[i]["k"]
		var v: Vector2 = _coeffs[i]["vec"]
		var ang := TAU * k * t
		p += Vector2(v.x * cos(ang) - v.y * sin(ang), v.x * sin(ang) + v.y * cos(ang))
	return p


func _process(delta: float) -> void:
	if _playing:
		_t += delta * 0.25
		_trail.append(_reconstruct(_t, _coeffs.size()) + Vector2(640, 380))
		if _trail.size() > 300:
			_trail.pop_front()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.09))
	# 轨迹（渐隐）
	for i in _trail.size():
		var f := float(i) / _trail.size()
		draw_circle(_trail[i], 1.5, Color(1.0, 0.55, 0.65, f * 0.8))
	# 旋转矢量臂
	var origin := Vector2(640, 380)
	for i in _coeffs.size():
		var end := origin + _reconstruct(_t, i + 1) - _reconstruct(_t, i) + Vector2.ZERO
		# 每条臂 = 从当前原点指向下一点
		var v: Vector2 = _coeffs[i]["vec"]
		var k: int = _coeffs[i]["k"]
		var ang := TAU * k * _t
		var arm := Vector2(v.x * cos(ang) - v.y * sin(ang), v.x * sin(ang) + v.y * cos(ang))
		var next := origin + arm
		draw_circle(origin, arm.length(), Color(0.35, 0.5, 0.8, 0.25), false, 1.5)
		draw_line(origin, next, Color(0.6, 0.75, 1.0, 0.8), 2.0)
		origin = next
	# 笔尖
	draw_circle(origin, 6, Color(1.0, 0.5, 0.6))
