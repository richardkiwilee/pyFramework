extends Node2D
## =============================================================================
## 刀光斩击 —— 按住拖拽挥出月牙刀光（2D shader）
## =============================================================================
## 按住左键拖拽 → 松开瞬间沿拖拽方向生成一道月牙斩击：
##   · 几何：以起点为中心的薄弧带（Polygon2D 条带网格，纯作裁剪形状）；
##   · 着色：slash.gdshader 按【屏幕坐标】计算梯度——内缘白热核心、
##     外缘主题色、月牙两端渐隐、沿弧能量条纹（不依赖多边形 UV）；
##   · 生命周期：0.3 秒淡出后自动释放，可连续挥砍叠加。
## =============================================================================

const SlashShader = preload("res://features/slash/slash.gdshader")

const VIEW_SIZE := Vector2(1280, 720)

const PALETTE: Array[Color] = [
	Color(0.55, 0.85, 1.0),   # 冰蓝
	Color(1.0, 0.75, 0.25),   # 金黄
	Color(1.0, 0.40, 0.35),   # 赤红
	Color(0.75, 0.50, 1.0),   # 紫电
]

var _drag_start := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	queue_redraw()


## 背景：道场地板线条
func _draw() -> void:
	var c := Color(0.25, 0.28, 0.38, 0.5)
	for i in 12:
		var y := 60.0 + i * 56.0
		draw_line(Vector2(40, y), Vector2(1240, y), c, 1.5)
		var x := 60.0 + i * 108.0
		draw_line(Vector2(x, 40), Vector2(x, 680), c, 1.5)
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.07, 0.08, 0.12), false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
			_dragging = true
		else:
			if _dragging and event.position.distance_to(_drag_start) > 40.0:
				_spawn_slash(_drag_start, event.position)
			_dragging = false
			get_viewport().set_input_as_handled()


## 生成一道斩击（逻辑层，便于测试）
func _spawn_slash(from: Vector2, to: Vector2) -> void:
	var ang: float = (to - from).angle()
	var dist := clampf(from.distance_to(to), 90.0, 300.0)
	# 刃长 = 拖拽距离；薄弧带：半径 = 拖拽距离 ± 刀身半宽
	var inner_r := dist - 24.0
	var outer_r := dist + 24.0
	var spread := 1.5          # 月牙张角（弧度）
	var n := 24                # 每侧采样点数

	# 条带多边形：内缘正向 + 外缘反向闭合（纯作裁剪形状）
	var pts := PackedVector2Array()
	for i in n + 1:
		var f := float(i) / n
		var a := ang + (f - 0.5) * spread
		pts.append(from + Vector2.from_angle(a) * inner_r)
	for i in n + 1:
		var f := 1.0 - float(i) / n
		var a := ang + (f - 0.5) * spread
		pts.append(from + Vector2.from_angle(a) * outer_r)

	var poly := Polygon2D.new()
	poly.polygon = pts
	var mat := ShaderMaterial.new()
	mat.shader = SlashShader
	mat.set_shader_parameter("slash_color", PALETTE[randi() % PALETTE.size()])
	mat.set_shader_parameter("center", from)
	mat.set_shader_parameter("ang", ang)
	mat.set_shader_parameter("spread", spread)
	mat.set_shader_parameter("inner_r", inner_r)
	mat.set_shader_parameter("outer_r", outer_r)
	mat.set_shader_parameter("view_size", VIEW_SIZE)
	poly.material = mat
	add_child(poly)

	# 0.3 秒淡出后释放
	var tw := create_tween()
	tw.tween_property(poly, "modulate:a", 0.0, 0.3)
	tw.tween_callback(poly.queue_free)
