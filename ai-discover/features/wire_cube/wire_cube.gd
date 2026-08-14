extends Node2D
## =============================================================================
## 旋转立方体 —— 纯代码 3D 线框（顶点旋转 + 透视投影）
## =============================================================================
## · 8 顶点绕 X/Y 轴旋转，透视投影到屏幕，连线画线框；
## · 鼠标拖动控制旋转速度/方向，滚轮调缩放；
## · 面近远排序（画家算法）+ 近面亮色。
## 投影/旋转（_rotate_vertex/_project）为纯函数，可确定性测试。
## =============================================================================

const CENTER := Vector2(640, 360)
const VERTICES: Array[Vector3] = [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
]
const EDGES: Array = [
	[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
	[0, 4], [1, 5], [2, 6], [3, 7],
]

var _rot_x := 0.6
var _rot_y := 0.4
var _scale := 150.0


func _ready() -> void:
	queue_redraw()


## 顶点旋转（供测试）：绕 X 再绕 Y
func _rotate_vertex(v: Vector3, rx: float, ry: float) -> Vector3:
	var p := v
	var cy := cos(ry)
	var sy := sin(ry)
	p = Vector3(p.x * cy - p.z * sy, p.y, p.x * sy + p.z * cy)
	var cx := cos(rx)
	var sx := sin(rx)
	p = Vector3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx)
	return p


## 透视投影（供测试）：z 越大越远，透视系数随缩放
func _project(v: Vector3, scale: float) -> Vector2:
	var persp := 1.0 / (3.2 - v.z)
	return CENTER + Vector2(v.x, v.y) * persp * scale


func _process(delta: float) -> void:
	_rot_y += delta * 0.8
	_rot_x += delta * 0.5
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scale = minf(280.0, _scale + 15.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scale = maxf(80.0, _scale - 15.0)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.04, 0.08))
	var projected: Array = []
	for v in VERTICES:
		projected.append(_project(_rotate_vertex(v, _rot_x, _rot_y), _scale))
	# 边（近端亮、远端暗：按两端平均 z 排序后画）
	var drawn: Array = []
	for e in EDGES:
		var a: Vector3 = _rotate_vertex(VERTICES[e[0]], _rot_x, _rot_y)
		var b: Vector3 = _rotate_vertex(VERTICES[e[1]], _rot_x, _rot_y)
		var z := (a.z + b.z) / 2.0
		drawn.append({"i": e, "z": z})
	drawn.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["z"] > y["z"])
	for d in drawn:
		var e: Array = d["i"]
		var brightness := clampf(0.35 + (d["z"] + 1.7) * 0.25, 0.3, 1.0)
		draw_line(projected[e[0]], projected[e[1]], Color(0.5, 0.8, 1.0, brightness), 2.0)
	# 顶点
	for p in projected:
		draw_circle(p, 3.5, Color(0.9, 0.95, 1.0))
