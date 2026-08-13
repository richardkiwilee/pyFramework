extends Node2D
## =============================================================================
## 星空飞越 —— 2D 伪 3D 星流（深度投影 + 鼠标转向 + 星痕）
## =============================================================================
## · 每颗星 = {x, y, z}：z 以速度向镜头推进，屏幕位置 = 中心 + (x,y)/z；
## · z 过近 → 回收到远处（无缝循环）；
## · 鼠标左右移动使飞船横向漂移（星流反向掠过）；
## · 近处亮星拖出速度线。
## 投影与推进（_star_step）为纯函数，可确定性测试。
## =============================================================================

const STAR_COUNT := 220
const SPEED := 0.9          # z 方向前进速度
const CENTER := Vector2(640, 360)

var _stars: Array = []      # {x, y, z}
var _ship_x := 0.0


func _ready() -> void:
	for i in STAR_COUNT:
		_stars.append(_new_star())


func _new_star() -> Dictionary:
	return {
		"x": randf_range(-900, 900),
		"y": randf_range(-600, 600),
		"z": randf_range(1.0, 12.0),
	}


## 单步推进（供测试）
func _star_step(delta: float) -> void:
	for s in _stars:
		s["z"] -= SPEED * delta
		if s["z"] < 0.35:
			s["z"] = 12.0
			s["x"] = randf_range(-900, 900)
			s["y"] = randf_range(-600, 600)


## 投影（供绘制与测试）
func _project(s: Dictionary) -> Vector2:
	return CENTER + Vector2(s["x"] + _ship_x * 2.0, s["y"]) / s["z"]


func _process(delta: float) -> void:
	# 鼠标转向（左负右正）
	var mouse := get_viewport().get_mouse_position()
	var target := (mouse.x - CENTER.x) * 2.2
	_ship_x = lerpf(_ship_x, target, delta * 4.0)
	_star_step(delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.01, 0.03))
	for s in _stars:
		var p := _project(s)
		var depth_f: float = 1.0 - (s["z"] - 0.35) / 11.65   # 近 = 1
		var r: float = 0.8 + 2.2 * depth_f
		draw_circle(p, r, Color(0.85, 0.9, 1.0, 0.3 + 0.7 * depth_f))
		# 近处星痕（速度线）
		if s["z"] < 3.0:
			var trail: Vector2 = Vector2(0, 0) - Vector2(_ship_x * 2.0, 0) / s["z"] * 2.0
			draw_line(p, p - trail * 6.0, Color(0.7, 0.85, 1.0, 0.5 * depth_f), 1.5)
	# 飞船
	draw_circle(CENTER + Vector2(_ship_x, 0), 8, Color(0.4, 0.9, 1.0))
	draw_circle(CENTER + Vector2(_ship_x, 0), 8, Color(0.8, 1.0, 1.0), false, 2.0)
