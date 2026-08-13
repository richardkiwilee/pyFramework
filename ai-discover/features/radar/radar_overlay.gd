extends Control
## =============================================================================
## radar_overlay.gd — 小地图内的装饰层
##   sweep = false：雷达同心圆环 + 十字刻度（静态）
##   sweep = true ：扫描扇形（由父节点旋转它实现扫描动画）
## =============================================================================

@export var sweep := false


func _draw() -> void:
	if sweep:
		# 半透明扫描扇（顶点色：中心亮 → 边缘透明）
		var c := size / 2.0
		var pts := PackedVector2Array([c])
		var cols := PackedColorArray([Color(0.3, 0.9, 1.0, 0.35)])
		for i in 9:
			var a := float(i) / 8.0 * 0.5
			pts.append(c + Vector2.from_angle(a - 0.25) * size.x * 0.75)
			cols.append(Color(0.3, 0.9, 1.0, 0.02))
		draw_polygon(pts, cols)
	else:
		var c := size / 2.0
		draw_arc(c, size.x * 0.46, 0, TAU, 64, Color(0.3, 0.9, 1.0, 0.8), 2.0)
		draw_arc(c, size.x * 0.30, 0, TAU, 64, Color(0.3, 0.9, 1.0, 0.45), 1.5)
		draw_arc(c, size.x * 0.15, 0, TAU, 64, Color(0.3, 0.9, 1.0, 0.3), 1.5)
		draw_line(Vector2(c.x, 2), Vector2(c.x, size.y - 2), Color(0.3, 0.9, 1.0, 0.35), 1.5)
		draw_line(Vector2(2, c.y), Vector2(size.x - 2, c.y), Color(0.3, 0.9, 1.0, 0.35), 1.5)
		# 边缘圆框
		draw_arc(c, c.x - 1.0, 0, TAU, 64, Color(0.3, 0.9, 1.0, 0.9), 2.5)
