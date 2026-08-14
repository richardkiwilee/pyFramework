extends Control
## =============================================================================
## 巴恩斯利蕨 —— IFS 混沌游戏分形（4 个仿射变换随机迭代 5 万次）
## =============================================================================
## · 以概率 1% / 85% / 7% / 7% 选择四种仿射变换，从原点迭代出蕨叶；
## · 结果一次性绘制进 ImageTexture（高效展示数十万点）；
## · 【🎲 重新生成】换随机轨迹。
## 变换（_iterate）为纯函数，可确定性测试。
## =============================================================================

const ITERATIONS := 50000
const IMG_W := 700
const IMG_H := 900

var _img: Image
var _tex: ImageTexture

@onready var canvas_rect: TextureRect = $CanvasRect


func _ready() -> void:
	$CanvasLayer/RegenBtn.pressed.connect(_generate)
	_generate()


## 单步仿射变换（供测试与生成）：按概率选择 4 种变换之一
func _iterate(p: Vector2, r: float) -> Vector2:
	if r < 0.01:
		return Vector2(0.0, 0.16 * p.y)                          # 茎
	elif r < 0.86:
		return Vector2(0.85 * p.x + 0.04 * p.y, -0.04 * p.x + 0.85 * p.y + 1.6)   # 主叶
	elif r < 0.93:
		return Vector2(0.20 * p.x - 0.26 * p.y, 0.23 * p.x + 0.22 * p.y + 1.6)    # 左叶
	return Vector2(-0.15 * p.x + 0.28 * p.y, 0.26 * p.x + 0.24 * p.y + 0.44)      # 右叶


func _generate() -> void:
	_img = Image.create(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.03, 0.06, 0.04, 1.0))
	var p := Vector2.ZERO
	for i in ITERATIONS:
		p = _iterate(p, randf())
		# 蕨叶坐标 (-2.2..2.8, 0..10) 映射到画布
		var x := int((p.x + 2.5) / 5.2 * IMG_W)
		var y := int((10.5 - p.y) / 10.5 * IMG_H)
		if x >= 0 and x < IMG_W and y >= 0 and y < IMG_H:
			_img.set_pixel(x, y, Color(0.3, 0.85, 0.4, 1.0))
	_tex = ImageTexture.create_from_image(_img)
	canvas_rect.texture = _tex
