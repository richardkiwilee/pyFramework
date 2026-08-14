extends Node2D
## =============================================================================
## 粒子黑洞 —— 点击生成引力奇点，粒子螺旋坠入
## =============================================================================
## · 屏幕漂浮彩色粒子，慢速漂移；点击放置黑洞；
## · 粒子受黑洞平方反比引力吸引，靠近时加速螺旋坠入（被吞并后重生）；
## · 【🧹 清空】移除所有黑洞。
## 引力/吞并逻辑（_gravity_step）为纯函数，可确定性测试。
## =============================================================================

const PARTICLE_COUNT := 160
const G := 220000.0

var _particles: Array = []     # {pos, vel, color}
var _holes: Array = []         # Vector2

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ClearBtn.pressed.connect(_clear)
	for i in PARTICLE_COUNT:
		_particles.append({
			"pos": Vector2(randf_range(60, 1220), randf_range(60, 660)),
			"vel": Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			"color": Color.from_hsv(randf(), 0.7, 0.95),
		})
	status_label.text = "🕳 点击放置黑洞（%d 个）" % _holes.size()


func _clear() -> void:
	_holes.clear()
	status_label.text = "🕳 点击放置黑洞（0 个）"
	queue_redraw()


## 单步推进（供测试）：返回被吞粒子数
func _gravity_step(delta: float) -> int:
	var swallowed := 0
	for p in _particles:
		# 漂移 + 黑洞引力
		for h in _holes:
			var diff: Vector2 = h - p["pos"]
			var d: float = diff.length()
			if d > 2.0:
				p["vel"] += diff.normalized() * G / (d * d) * delta
			if d < 14.0:
				# 被吞并 → 远处重生
				p["pos"] = Vector2(randf_range(60, 1220), randf_range(60, 660))
				p["vel"] = Vector2(randf_range(-20, 20), randf_range(-20, 20))
				swallowed += 1
				break
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.995
		# 屏边软边界
		p["pos"].x = clampf(p["pos"].x, 20.0, 1260.0)
		p["pos"].y = clampf(p["pos"].y, 20.0, 700.0)
	return swallowed


func _process(delta: float) -> void:
	_gravity_step(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_holes.append(event.position)
		status_label.text = "🕳 点击放置黑洞（%d 个）" % _holes.size()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.03, 0.06))
	# 粒子
	for p in _particles:
		draw_circle(p["pos"], 2.5, p["color"])
	# 黑洞：暗核 + 吸积环
	for h in _holes:
		draw_circle(h, 22, Color(0.01, 0.01, 0.02))
		draw_arc(h, 26, 0, TAU, 32, Color(0.9, 0.6, 0.2, 0.8), 3.0)
		draw_arc(h, 34, 0, TAU, 32, Color(0.9, 0.5, 0.1, 0.35), 5.0)
