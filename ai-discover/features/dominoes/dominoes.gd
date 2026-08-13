extends Node2D
## =============================================================================
## 多米诺骨牌 —— 点击推倒第一块，连锁倾倒
## =============================================================================
## · 12 块骨牌等距站立；点击第一块（或【🎲 推倒】）触发连锁：
##   每块绕底边倒下（0.22s），稍作延迟后推倒下一块；
## · 连锁完成后显示用时；【🔄 立起】复位。
## 连锁状态机（_knock）可确定性测试。
## =============================================================================

const COUNT := 12
const DOMINO_W := 18.0
const DOMINO_H := 90.0
const GAP := 56.0
const ORIGIN := Vector2(240, 560)

var _angles: Array[float] = []
var _fallen: Dictionary = {}   # idx → true
var _fall_start := 0.0
var _done := false

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_reset)
	_reset()


func _reset() -> void:
	_angles.clear()
	_fallen.clear()
	_done = false
	for i in COUNT:
		_angles.append(0.0)
	queue_redraw()
	status_label.text = "🎲 点击第一块骨牌推倒"


## 推倒第 i 块（供点击与测试）
func _knock(i: int) -> void:
	if i >= COUNT or _fallen.has(i):
		return
	if i == 0:
		_fall_start = Time.get_ticks_msec() / 1000.0
	var tw := create_tween()
	tw.tween_method(_set_angle.bind(i), 0.0, 85.0, 0.22)
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void:
		_fallen[i] = true
		_knock(i + 1)
		if i == COUNT - 1:
			_done = true
			var elapsed := Time.get_ticks_msec() / 1000.0 - _fall_start
			status_label.text = "🎉 连锁完成！用时 %.2f 秒 · 【立起】再来一次" % elapsed)
	queue_redraw()


func _set_angle(a: float, i: int) -> void:
	_angles[i] = a
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.distance_to(_top_of(0)) < 70.0 and not _fallen.has(0):
			_knock(0)
		get_viewport().set_input_as_handled()


func _top_of(i: int) -> Vector2:
	return ORIGIN + Vector2(i * GAP + DOMINO_W / 2.0, -DOMINO_H / 2.0)


func _draw() -> void:
	# 地面
	draw_rect(Rect2(ORIGIN.x - 30, ORIGIN.y, COUNT * GAP + 60, 8), Color(0.25, 0.27, 0.34))
	for i in COUNT:
		var base := ORIGIN + Vector2(i * GAP + DOMINO_W / 2.0, 0)
		var a := deg_to_rad(_angles[i])
		# 倒下时绕底边旋转：顶部偏移
		var top := base + Vector2(sin(a), -cos(a)) * DOMINO_H
		var col := Color(0.95, 0.85, 0.6) if i == 0 else Color(0.85, 0.8, 0.9)
		draw_line(base, top, col, DOMINO_W)
		# 骨牌圆点
		var mid := (base + top) / 2.0
		draw_circle(mid, 4, Color(0.2, 0.2, 0.3))
