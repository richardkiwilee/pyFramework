extends Node2D
## =============================================================================
## 鼠标拖尾 —— 彩虹彗尾跟随光标 + 点击扩散环
## =============================================================================
## 每帧记录光标位置（最多 TRAIL_LEN 个），逐点绘制：
##   头部大而亮（白炽核心 + 彩色光晕），尾部细而淡，色相沿轨迹渐变，
##   随时间整体流转 → 拖出"彩虹彗星"。
## 点击鼠标：以点击处为中心扩散一个渐隐光环。
## =============================================================================

const TRAIL_LEN := 55

var _points: Array = []        # 最近鼠标位置（新在前）
var _hue := 0.0
var _bursts: Array = []        # {pos, t} 扩散环


func _process(delta: float) -> void:
	_points.push_front(get_viewport().get_mouse_position())
	if _points.size() > TRAIL_LEN:
		_points.resize(TRAIL_LEN)   # 硬截断到最大长度
	_hue = fposmod(_hue + delta * 0.12, 1.0)

	for b in _bursts:
		b["t"] += delta
	_bursts = _bursts.filter(func(b: Dictionary) -> bool: return b["t"] < 0.6)

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_bursts.append({"pos": event.position, "t": 0.0})
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 深色背景 + 暗角
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.05, 0.09))

	# 尾迹：旧→新（尾部先画，头部最后覆盖）
	for i in range(_points.size() - 1, -1, -1):
		var f := 1.0 - float(i) / float(_points.size())   # 1 = 头部
		var p: Vector2 = _points[i]
		var r := 2.0 + f * f * 20.0
		var hue := fposmod(_hue + (1.0 - f) * 0.9, 1.0)
		var c := Color.from_hsv(hue, 0.85, 1.0)
		# 外层光晕（大而透明）
		draw_circle(p, r * 2.2, Color(c.r, c.g, c.b, f * f * 0.16))
		# 主体
		draw_circle(p, r, Color(c.r, c.g, c.b, f * f * 0.85))
		# 白炽核心
		draw_circle(p, r * 0.4, Color(1, 1, 1, f * 0.75))

	# 点击扩散环
	for b in _bursts:
		var t: float = b["t"]
		var fade := 1.0 - t / 0.6
		draw_arc(b["pos"], 6.0 + t * 260.0, 0, TAU, 64, Color(0.6, 0.9, 1.0, fade * 0.8), 3.5)
		draw_arc(b["pos"], 3.0 + t * 130.0, 0, TAU, 48, Color(1, 1, 1, fade * 0.5), 2.0)
