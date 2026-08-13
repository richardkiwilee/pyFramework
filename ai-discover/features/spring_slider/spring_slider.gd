extends Control
## =============================================================================
## 弹簧滑块 —— 带弹簧物理的 UI 滑块（拖动惯性过冲 + 松手吸附回档）
## =============================================================================
## · 拖动：手柄用弹簧动力学追随鼠标（滞后 + 过冲 + 阻尼震荡）；
## · 松手：弹簧自动弹回最近的档位（7 档，带弹跳动画）；
## · 档位值实时显示，7 档分别对应不同的表情与标签。
## 弹簧积分（_spring_step）为纯函数，可确定性测试。
## =============================================================================

const TRACK := Rect2(200, 300, 880, 8)
const STEPS := 7
const K := 130.0          # 弹簧刚度
const DAMP := 7.0         # 阻尼
const STEP_LABELS: Array[String] = ["🐌 超慢", "🐢 慢", "🚶 正常", "🏃 快", "🚀 很快", "⚡ 极速", "🌈 梦幻"]

var _pos := 640.0
var _vel := 0.0
var _dragging := false

@onready var value_label: Label = $CanvasLayer/ValueLabel


func _step_pos(i: int) -> float:
	return TRACK.position.x + TRACK.size.x * float(i) / float(STEPS - 1)


func _nearest_step(x: float) -> int:
	return int(round((x - TRACK.position.x) / TRACK.size.x * float(STEPS - 1)))


func _process(delta: float) -> void:
	var target := _pos
	if _dragging:
		var mouse := get_viewport().get_mouse_position()
		target = clampf(mouse.x, TRACK.position.x, TRACK.end.x)
	else:
		target = _step_pos(_nearest_step(_pos))   # 吸附最近的档位
	_spring_step(delta, target)
	queue_redraw()


## 单步弹簧积分（供测试）
func _spring_step(delta: float, target: float) -> void:
	var accel := -K * (_pos - target) - DAMP * _vel
	_vel += accel * delta
	_pos += _vel * delta
	var idx := _nearest_step(_pos)
	value_label.text = "档位 %d / %d  %s" % [idx + 1, STEPS, STEP_LABELS[idx]]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.y > TRACK.position.y - 60 and event.position.y < TRACK.end.y + 60:
			_dragging = true
			_pos = clampf(event.position.x, TRACK.position.x, TRACK.end.x)
			_vel = 0.0
		else:
			_dragging = false
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 轨道
	draw_rect(Rect2(TRACK.position.x, TRACK.position.y - 4, TRACK.size.x, 8), Color(0.2, 0.22, 0.3))
	# 档位刻度
	for i in STEPS:
		var x := _step_pos(i)
		draw_circle(Vector2(x, TRACK.get_center().y), 7, Color(0.35, 0.38, 0.5))
	# 已选部分
	draw_rect(Rect2(TRACK.position.x, TRACK.position.y - 4, _pos - TRACK.position.x, 8), Color(0.3, 0.7, 1.0))
	# 手柄（弹簧小球）
	draw_circle(Vector2(_pos, TRACK.get_center().y), 20, Color(0.95, 0.9, 0.75))
	draw_circle(Vector2(_pos, TRACK.get_center().y), 20, Color(0.5, 0.55, 0.7), false, 3.0)
