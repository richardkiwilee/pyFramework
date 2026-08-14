extends Control
## =============================================================================
## 放大镜 —— 圆形透镜 shader 放大屏幕内容（真实 UI 组件）
## =============================================================================
## · 底层铺满彩色内容（同心圆环 + 文字），透镜随鼠标移动，
##   透镜内通过"向圆心收缩采样"实现 2 倍放大；
## · 滚轮调放大倍率（1.5x ~ 3.5x）；
## · 采样偏移几何（_sample_uv）为纯函数，可确定性测试。
## =============================================================================

const MagnifierShader = preload("res://features/magnifier/magnifier.gdshader")
const VIEW_SIZE := Vector2(1280, 720)

var _zoom := 2.0
var _lens_pos := Vector2(640, 360)

@onready var rect: ColorRect = $EffectRect
@onready var zoom_label: Label = $CanvasLayer/ZoomLabel


func _ready() -> void:
	rect.material.set_shader_parameter("view_size", VIEW_SIZE)
	_push()


## 放大采样 UV（供测试）：屏幕 uv 按倍率向圆心收缩
func _sample_uv(uv: Vector2, center: Vector2, zoom: float) -> Vector2:
	var center_uv := center / VIEW_SIZE
	return uv + (uv - center_uv) * (1.0 / zoom - 1.0)


func _push() -> void:
	rect.material.set_shader_parameter("lens_center", _lens_pos)
	rect.material.set_shader_parameter("zoom", _zoom)
	zoom_label.text = "🔍 放大 %.1fx" % _zoom


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	if Rect2(Vector2(1, 1), Vector2(1278, 718)).has_point(mouse):
		_lens_pos = mouse
	_push()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(3.5, _zoom + 0.25)
			_push()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(1.5, _zoom - 0.25)
			_push()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	# 底层内容：同心彩色圆环 + 文字
	for i in 8:
		draw_arc(Vector2(640, 360), 40.0 + i * 55.0, 0, TAU, 96, Color.from_hsv(float(i) / 8.0, 0.8, 0.85), 14.0)
	var f := ThemeDB.fallback_font
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector2(640, 360) + Vector2.from_angle(a) * 260.0
		draw_string(f, p, "🔍", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.9, 0.9, 1.0))
	draw_string(f, Vector2(520, 300), "放大镜区域跟随鼠标", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.9, 0.8))
