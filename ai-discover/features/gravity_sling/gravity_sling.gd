extends Node2D
## =============================================================================
## 重力弹射 —— 行星引力场 + 拖拽弹射彗星
## =============================================================================
## · 屏幕上有若干行星（引力源），彗星受 N 体引力影响（平方反比）；
## · 按住彗星拖拽蓄力（显示拉线），松开弹射；
## · 彗星拖出渐隐尾迹；撞进行星 → 被吸收 + 光爆；
## · 点击空白处添加新行星；【🎲 重置】恢复初始布局。
## 引力计算（_gravity_accel）为纯函数，可确定性测试。
## =============================================================================

const G := 260000.0
const PLANET_MIN_R := 22.0

var _planets: Array = []          # {pos, r}
var _comet: Dictionary = {"pos": Vector2(640, 500), "vel": Vector2.ZERO, "trail": []}
var _dragging := false
var _drag_from := Vector2.ZERO
var _absorptions: Array = []      # {pos, t}

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	_reset()


func _reset() -> void:
	_planets = [
		{"pos": Vector2(420, 300), "r": 34.0},
		{"pos": Vector2(860, 260), "r": 26.0},
		{"pos": Vector2(640, 560), "r": 22.0},
	]
	_comet = {"pos": Vector2(200, 200), "vel": Vector2.ZERO, "trail": []}
	_absorptions.clear()
	status_label.text = "🪐 拖拽彗星弹射 · 点击空白处加行星 · 撞行星被吸收"


## 行星对某点的引力加速度（供测试与模拟）
func _gravity_accel(pos: Vector2) -> Vector2:
	var accel := Vector2.ZERO
	for p in _planets:
		var diff: Vector2 = p["pos"] - pos
		var d := diff.length()
		if d > 5.0:
			accel += diff.normalized() * G / (d * d)
	return accel


func _process(delta: float) -> void:
	# 光爆淡出
	for a in _absorptions:
		a["t"] += delta
	_absorptions = _absorptions.filter(func(a: Dictionary) -> bool: return float(a["t"]) < 0.5)

	# 彗星运动学
	if not _dragging:
		_comet["vel"] += _gravity_accel(_comet["pos"]) * delta
		_comet["pos"] += _comet["vel"] * delta
		_comet["trail"].append(_comet["pos"])
		if _comet["trail"].size() > 120:
			_comet["trail"].pop_front()
		# 撞行星
		for p in _planets:
			if _comet["pos"].distance_to(p["pos"]) < p["r"]:
				_absorptions.append({"pos": p["pos"], "t": 0.0})
				_comet = {"pos": Vector2(200, 200), "vel": Vector2.ZERO, "trail": []}
				status_label.text = "💥 彗星被行星吸收！继续拖拽弹射"
				break
		# 飞出屏幕 → 重置
		var pos: Vector2 = _comet["pos"]
		if pos.x < -100 or pos.x > 1380 or pos.y < -100 or pos.y > 820:
			_comet = {"pos": Vector2(200, 200), "vel": Vector2.ZERO, "trail": []}
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.distance_to(_comet["pos"]) < 26.0:
				_dragging = true
				_drag_from = event.position
			else:
				_planets.append({"pos": event.position, "r": PLANET_MIN_R + randf() * 18.0})
				status_label.text = "🪐 已添加行星（%d 颗）· 点击空白处继续添加" % _planets.size()
		else:
			if _dragging:
				_comet["vel"] = (_drag_from - event.position) * 9.0
				_dragging = false
				status_label.text = "🚀 弹射！"
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_reset()
		queue_redraw()


func _draw() -> void:
	# 行星
	for p in _planets:
		draw_circle(p["pos"], p["r"], Color(0.55, 0.4, 0.75))
		draw_circle(p["pos"], p["r"], Color(0.85, 0.7, 1.0), false, 2.5)
		draw_circle(p["pos"] + Vector2(-p["r"] * 0.3, -p["r"] * 0.3), p["r"] * 0.25, Color(1, 1, 1, 0.5))
	# 彗星尾迹
	for i in _comet["trail"].size():
		var f: float = float(i) / _comet["trail"].size()
		draw_circle(_comet["trail"][i], 1.5 + 4.0 * f, Color(1, 0.85, 0.5, f * 0.6))
	# 弹射拉线
	if _dragging:
		var mouse := get_viewport().get_mouse_position()
		draw_line(_comet["pos"], mouse, Color(0.5, 0.8, 1.0, 0.7), 2.5)
		draw_circle(mouse, 6, Color(0.7, 0.9, 1.0))
	# 彗星
	draw_circle(_comet["pos"], 10, Color(1, 0.95, 0.8))
	draw_circle(_comet["pos"] + Vector2(-3, -4), 3, Color(1, 1, 1, 0.7))
	# 吸收光爆
	for a in _absorptions:
		var f: float = 1.0 - a["t"] / 0.5
		draw_arc(a["pos"], 30.0 + (1.0 - f) * 70.0, 0, TAU, 32, Color(1, 0.7, 1.0, f * 0.8), 3.0)
