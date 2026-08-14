extends Control
## =============================================================================
## 签名板 —— 手写签名绘制 + 导出 PNG（真实可用的 UI 组件）
## =============================================================================
## · 按住鼠标在白板上书写（笔迹累积到 ImageTexture，粗细可调）；
## · 【💾 保存】把签名导出为 PNG（user://signature.png）；
## · 【🧹 清空】重写。
## 笔迹绘制（_paint_stroke）为纯函数，可确定性测试。
## =============================================================================

const CANVAS_SIZE := Vector2(900, 400)

var _img: Image
var _tex: ImageTexture
var _drawing := false
var _last: Vector2 = Vector2(-1, -1)
var _brush := 4.0

@onready var canvas_rect: TextureRect = $CanvasRect
@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var brush_slider: HSlider = $CanvasLayer/Bar/BrushSlider


func _ready() -> void:
	_img = Image.create(int(CANVAS_SIZE.x), int(CANVAS_SIZE.y), false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.96, 0.95, 0.92, 1.0))
	_tex = ImageTexture.create_from_image(_img)
	canvas_rect.texture = _tex
	$CanvasLayer/Bar/ClearBtn.pressed.connect(_clear)
	$CanvasLayer/Bar/SaveBtn.pressed.connect(_save)
	canvas_rect.gui_input.connect(_on_canvas_input)
	brush_slider.min_value = 2
	brush_slider.max_value = 14
	brush_slider.value = 4
	brush_slider.value_changed.connect(func(v: float) -> void: _brush = v)


## 在画布坐标画一段（两点间插值补点），供输入与测试
func _paint_stroke(from: Vector2, to: Vector2) -> void:
	var dist := from.distance_to(to)
	var steps := maxi(1, int(dist / 2.0))
	for i in steps + 1:
		var p: Vector2 = from.lerp(to, float(i) / steps)
		for y in range(maxi(0, int(p.y) - int(_brush) - 1), mini(int(CANVAS_SIZE.y), int(p.y) + int(_brush) + 2)):
			for x in range(maxi(0, int(p.x) - int(_brush) - 1), mini(int(CANVAS_SIZE.x), int(p.x) + int(_brush) + 2)):
				var d := Vector2(x, y).distance_to(p)
				if d <= _brush:
					_img.set_pixel(x, y, Color(0.12, 0.13, 0.2, 1.0))
	_tex.update(_img)


func _clear() -> void:
	_img.fill(Color(0.96, 0.95, 0.92, 1.0))
	_tex.update(_img)
	status_label.text = "✍ 已清空"


func _save() -> void:
	var path := "user://signature.png"
	var err := _img.save_png(path)
	if err == OK:
		status_label.text = "💾 已保存到 %s" % ProjectSettings.globalize_path(path)
	else:
		status_label.text = "❌ 保存失败（错误码 %d）" % err


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drawing = true
			_last = event.position - canvas_rect.get_global_rect().position
		else:
			_drawing = false
			_last = Vector2(-1, -1)
	elif event is InputEventMouseMotion and _drawing:
		var p: Vector2 = event.position - canvas_rect.get_global_rect().position
		if _last.x >= 0:
			_paint_stroke(_last, p)
		_last = p
