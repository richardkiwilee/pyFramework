class_name RelBar
extends Control
## =============================================================================
## RelBar — 居中零点的关系条（-100 .. +100）
## =============================================================================
## 负值向左画红、正值向右画绿，中心灰色刻度线为零点。
## 自定义绘制需在自身 _draw() 内进行，且节点必须有非零尺寸。
## =============================================================================

var value: float = 0.0:
	set(v):
		value = clampf(v, -100.0, 100.0)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(0, 16)


func _draw() -> void:
	var mid: float = size.x * 0.5
	var half_h: float = size.y * 0.25
	var y: float = size.y * 0.5 - half_h
	# 轨道
	draw_rect(Rect2(0.0, y, size.x, half_h * 2.0), Color("14161c"))
	# 数值段：从零点到 value 对应位置
	var x: float = mid + value / 100.0 * mid
	draw_rect(Rect2(minf(mid, x), y, absf(x - mid), half_h * 2.0),
		Color("e06c5b") if value < 0.0 else Color("7ec96e"))
	# 零点刻度
	draw_rect(Rect2(mid - 1.0, 0.0, 2.0, size.y), Color("8f8c9e"))
