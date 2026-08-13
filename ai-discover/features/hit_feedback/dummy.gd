extends Node2D
## 训练木桩：纯 _draw 绘制的靶子（头 + 身体 + 底座杆）

func _draw() -> void:
	# 底座杆
	draw_rect(Rect2(-10, 70, 20, 120), Color(0.45, 0.38, 0.3))
	# 身体（沙袋形）
	draw_circle(Vector2(0, -10), 62, Color(0.55, 0.42, 0.26))
	draw_rect(Rect2(-46, -60, 92, 110), Color(0.55, 0.42, 0.26))
	# 头
	draw_circle(Vector2(0, -92), 34, Color(0.62, 0.48, 0.30))
	# 眼睛（被打的委屈表情）
	draw_circle(Vector2(-12, -96), 4, Color(0.15, 0.12, 0.1))
	draw_circle(Vector2(12, -96), 4, Color(0.15, 0.12, 0.1))
	# 缝线细节
	draw_line(Vector2(-46, -20), Vector2(46, -20), Color(0.4, 0.3, 0.18), 2.0)
	draw_line(Vector2(-46, 10), Vector2(46, 10), Color(0.4, 0.3, 0.18), 2.0)
