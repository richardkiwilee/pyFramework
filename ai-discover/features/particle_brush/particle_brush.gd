extends Control
## =============================================================================
## 粒子画笔 —— 按住拖拽在画布上作画：永久笔迹 + 发光粒子飞溅
## =============================================================================
## · 笔迹永久画进 ImageTexture（拖过即留痕，可叠加）；
## · 画笔颜色随时间沿彩虹循环；粒子飞溅点缀拖拽过程；
## · 【🧹 清空】重置画布。
## 笔迹绘制（_paint_at）与清空为纯逻辑，可确定性测试。
## =============================================================================

const CANVAS_SIZE := Vector2(1024, 560)
const BRUSH_R := 10

var _img: Image
var _tex: ImageTexture
var _hue := 0.0
var _painting := false

@onready var canvas_rect: TextureRect = $CanvasRect
@onready var sparks: CPUParticles2D = $Sparks


func _ready() -> void:
	_img = Image.create(int(CANVAS_SIZE.x), int(CANVAS_SIZE.y), false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.05, 0.05, 0.08, 1.0))
	_tex = ImageTexture.create_from_image(_img)
	canvas_rect.texture = _tex
	$CanvasLayer/ClearBtn.pressed.connect(_clear)
	sparks.emitting = false


## 在画布坐标画一笔（供输入与测试）
func _paint_at(canvas_pos: Vector2) -> void:
	var col := Color.from_hsv(_hue, 0.85, 1.0)
	for y in range(maxi(0, int(canvas_pos.y) - BRUSH_R), mini(int(CANVAS_SIZE.y), int(canvas_pos.y) + BRUSH_R + 1)):
		for x in range(maxi(0, int(canvas_pos.x) - BRUSH_R), mini(int(CANVAS_SIZE.x), int(canvas_pos.x) + BRUSH_R + 1)):
			if (x - canvas_pos.x) * (x - canvas_pos.x) + (y - canvas_pos.y) * (y - canvas_pos.y) <= BRUSH_R * BRUSH_R:
				_img.set_pixel(x, y, col)
	_tex.update(_img)


func _clear() -> void:
	_img.fill(Color(0.05, 0.05, 0.08, 1.0))
	_tex.update(_img)


func _process(delta: float) -> void:
	_hue = fposmod(_hue + delta * 0.25, 1.0)
	var mouse := get_viewport().get_mouse_position()
	var local := canvas_rect.get_global_rect()
	if _painting and local.has_point(mouse):
		var canvas_pos := mouse - local.position
		if canvas_pos.x >= 0 and canvas_pos.x < CANVAS_SIZE.x \
				and canvas_pos.y >= 0 and canvas_pos.y < CANVAS_SIZE.y:
			_paint_at(canvas_pos)
			sparks.position = mouse
			sparks.restart()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_painting = event.pressed


func _draw() -> void:
	pass
