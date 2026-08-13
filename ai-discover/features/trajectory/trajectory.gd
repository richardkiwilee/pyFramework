extends Node2D
## =============================================================================
## 弹道预测 —— 鼠标瞄准显示抛物线虚线，点击发射炮弹击中目标
## =============================================================================
## · 炮弹 = 纯运动学抛物线（初速固定 620，重力 700，无空气阻力）；
## · 预测线：沿弹道每 0.04s 采样一个点，画成渐隐虚线（落到地面为止）；
## · 击中目标：目标闪红消失、+1 分、随机刷新一个新目标；
## · 落点尘雾：小圆点粒子散开。
## =============================================================================

const GRAVITY := 700.0
const LAUNCH_SPEED := 620.0
const GROUND_Y := 620.0
const CANNON := Vector2(140, 620)
const TARGET_COUNT := 4

var _aim := Vector2(0, -1)
var _ball: Dictionary = {}      # {pos, vel, trail}
var _puffs: Array = []          # {pos, t}
var _targets: Array = []        # {pos, alive, flash}
var _score := 0

@onready var score_label: Label = $CanvasLayer/ScoreLabel


func _ready() -> void:
	for i in TARGET_COUNT:
		_targets.append({
			"pos": Vector2(480 + i * 200 + randf_range(-40, 40), GROUND_Y - 28),
			"alive": true,
			"flash": 0.0,
		})


func _process(delta: float) -> void:
	# 炮弹运动学推进
	if not _ball.is_empty():
		_ball["vel"].y += GRAVITY * delta
		_ball["pos"] += _ball["vel"] * delta
		_ball["trail"].append(_ball["pos"])
		if _ball["trail"].size() > 60:
			_ball["trail"].pop_front()
		if _ball["pos"].y >= GROUND_Y:
			_impact(_ball["pos"])
			_ball = {}
	# 尘雾扩散
	for p in _puffs:
		p["t"] += delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return p["t"] < 0.5)
	# 目标受击闪红渐隐
	for t in _targets:
		if t["flash"] > 0.0:
			t["flash"] = maxf(0.0, t["flash"] - delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.position.y < CANNON.y - 40:
			_aim = (event.position - CANNON).normalized()
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y < CANNON.y - 40 and _ball.is_empty():
			_aim = (event.position - CANNON).normalized()
			_fire(_aim)
		get_viewport().set_input_as_handled()


## 发射（供测试直接调用）
func _fire(dir: Vector2) -> void:
	_ball = {"pos": CANNON, "vel": dir * LAUNCH_SPEED, "trail": [CANNON]}


## 落地：判定目标 + 尘雾
func _impact(pos: Vector2) -> void:
	for t in _targets:
		if t["alive"] and pos.distance_to(t["pos"]) < 55.0:
			t["alive"] = false
			t["flash"] = 0.35
			_score += 1
			score_label.text = "🎯 命中：%d" % _score
			# 随机位置刷新一个新目标
			t["pos"] = Vector2(randf_range(420, 1150), GROUND_Y - 28)
			t["alive"] = true
	for i in 8:
		_puffs.append({
			"pos": pos + Vector2(randf_range(-14, 14), randf_range(-8, 8)),
			"t": 0.0,
		})


## 弹道采样（供预测线绘制与测试）
func _predict(dir: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 60:
		var t := i * 0.04
		var p := CANNON + dir * LAUNCH_SPEED * t + Vector2(0, 0.5 * GRAVITY * t * t)
		pts.append(p)
		# t>0 才判定落地（炮口本身就在地面上，t=0 时立即 break 就错了）
		if t > 0.01 and p.y >= GROUND_Y:
			break
	return pts


func _draw() -> void:
	# 地面与天空
	draw_rect(Rect2(0, 0, 1280, GROUND_Y), Color(0.13, 0.18, 0.30))
	draw_rect(Rect2(0, GROUND_Y, 1280, 100), Color(0.24, 0.30, 0.20))
	# 预测虚线
	var pts := _predict(_aim)
	for i in pts.size() - 1:
		var f := 1.0 - float(i) / pts.size()
		draw_line(pts[i], pts[i + 1], Color(1, 1, 1, f * 0.55), 2.0)
		draw_circle(pts[i], 3.0, Color(1, 1, 1, f * 0.8))
	# 炮
	draw_circle(CANNON, 20, Color(0.3, 0.32, 0.38))
	draw_line(CANNON, CANNON + _aim * 46, Color(0.5, 0.52, 0.6), 10.0)
	# 目标（木桶）
	for t in _targets:
		if t["flash"] > 0.0:
			draw_rect(Rect2(t["pos"] - Vector2(28, 28), Vector2(56, 56)), Color(1.0, 0.3, 0.3))
		else:
			draw_rect(Rect2(t["pos"] - Vector2(28, 28), Vector2(56, 56)), Color(0.55, 0.36, 0.20))
			draw_rect(Rect2(t["pos"] - Vector2(28, 28), Vector2(56, 56)), Color(0.25, 0.15, 0.08), false, 2.0)
	# 炮弹 + 尾迹
	if not _ball.is_empty():
		for i in _ball["trail"].size():
			var f: float = float(i) / _ball["trail"].size()
			draw_circle(_ball["trail"][i], 4.0 * f, Color(1, 0.85, 0.4, f * 0.7))
		draw_circle(_ball["pos"], 9, Color(0.1, 0.1, 0.12))
	# 尘雾
	for p in _puffs:
		var f: float = 1.0 - p["t"] / 0.5
		draw_circle(p["pos"] + Vector2(p["t"] * 40.0, -p["t"] * 30.0), 4.0 * f, Color(0.6, 0.55, 0.45, f * 0.7))
