extends Node2D
## =============================================================================
## 太阳系轨道 —— 行星绕日公转（内快外慢）+ 轨道尾迹
## =============================================================================
## · 中央发光太阳 + 5 颗行星，周期随轨道半径增大（近似开普勒）；
## · 每颗行星拖出渐隐尾迹环；
## · 点击空白处添加随机行星；【🎲 重置】。
## 轨道采样（_planet_pos）为纯函数，可确定性测试。
## =============================================================================

const CENTER := Vector2(640, 360)

const PLANET_COLORS: Array[Color] = [
	Color(0.6, 0.75, 0.9), Color(0.95, 0.7, 0.4), Color(0.4, 0.75, 0.55),
	Color(0.9, 0.5, 0.7), Color(0.8, 0.8, 0.5), Color(0.6, 0.6, 0.9),
]

var _planets: Array = []      # {radius, period, size, color, trail, offset}
var _t := 0.0

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_reset)
	_reset()


func _reset() -> void:
	_planets = [
		{"radius": 90.0, "period": 6.0, "size": 10.0, "color": PLANET_COLORS[0], "trail": [], "offset": 0.0},
		{"radius": 150.0, "period": 10.0, "size": 13.0, "color": PLANET_COLORS[1], "trail": [], "offset": 1.3},
		{"radius": 210.0, "period": 15.0, "size": 16.0, "color": PLANET_COLORS[2], "trail": [], "offset": 2.7},
		{"radius": 270.0, "period": 21.0, "size": 12.0, "color": PLANET_COLORS[3], "trail": [], "offset": 4.1},
		{"radius": 330.0, "period": 28.0, "size": 15.0, "color": PLANET_COLORS[4], "trail": [], "offset": 5.4},
	]
	status_label.text = "🪐 点击空白处添加行星 · 内圈公转更快"


## 行星在时刻 t 的位置（供绘制与测试）
func _planet_pos(p: Dictionary, t: float) -> Vector2:
	var a: float = p["offset"] + TAU * t / p["period"]
	return CENTER + Vector2.from_angle(a) * p["radius"]


func _process(delta: float) -> void:
	_t += delta
	for p in _planets:
		p["trail"].append(_planet_pos(p, _t))
		if p["trail"].size() > 80:
			p["trail"].pop_front()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var d: float = event.position.distance_to(CENTER)
		if d > 60.0 and d < 400.0:
			_planets.append({
				"radius": d,
				"period": clampf(d / 12.0, 3.0, 40.0),
				"size": randf_range(8.0, 16.0),
				"color": PLANET_COLORS[randi() % PLANET_COLORS.size()],
				"trail": [],
				"offset": randf_range(0, TAU),
			})
			status_label.text = "🪐 已添加行星（%d 颗）" % _planets.size()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 太阳
	draw_circle(CENTER, 34, Color(1.0, 0.85, 0.4))
	draw_circle(CENTER, 34, Color(1.0, 0.6, 0.2, 0.4), false, 6.0)
	draw_circle(CENTER, 44, Color(1.0, 0.7, 0.3, 0.18))
	# 轨道圆
	for p in _planets:
		draw_arc(CENTER, p["radius"], 0, TAU, 64, Color(0.5, 0.55, 0.7, 0.25), 1.5)
	# 尾迹
	for p in _planets:
		for i in p["trail"].size():
			var f: float = float(i) / p["trail"].size()
			draw_circle(p["trail"][i], p["size"] * 0.5 * f, Color(p["color"].r, p["color"].g, p["color"].b, f * 0.5))
	# 行星
	for p in _planets:
		var pos := _planet_pos(p, _t)
		draw_circle(pos, p["size"], p["color"])
		draw_circle(pos + Vector2(-p["size"] * 0.3, -p["size"] * 0.3), p["size"] * 0.3, Color(1, 1, 1, 0.5))
