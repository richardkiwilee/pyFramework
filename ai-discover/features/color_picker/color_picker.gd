extends Control
## =============================================================================
## 颜色拾取器 —— HSV 色环 + 明度/饱和度方形（经典 UI 组件）
## =============================================================================
## · 外圈色环选色相（72 段渐变绘制），内方形选饱和度/明度
##   （逐行渐变绘制），色环中央显示当前颜色；
## · 右侧实时预览：大色块 + 十六进制代码（可复制的显示）；
## · 点击/拖拽两处取色，坐标映射（_hue_at/_sv_at）为纯函数可测试。
## =============================================================================

const CENTER := Vector2(430, 350)
const RING_OUT := 220.0
const RING_IN := 178.0
const SQ_HALF := 140.0

var _hue := 0.0
var _sv := Vector2(0.85, 0.95)

@onready var hex_label: Label = $CanvasLayer/HexLabel
@onready var preview: ColorRect = $CanvasLayer/Preview


func _ready() -> void:
	_refresh_preview()
	queue_redraw()


## 当前颜色
func _current_color() -> Color:
	return Color.from_hsv(_hue, _sv.x, _sv.y)


## 色环上的角度 → 色相（供输入与测试）
func _hue_at(p: Vector2) -> float:
	var a := (p - CENTER).angle()
	return fposmod(a / TAU, 1.0)


## 方形内的位置 → 饱和度/明度（供输入与测试）
func _sv_at(p: Vector2) -> Vector2:
	var n := (p - CENTER) / SQ_HALF
	return Vector2(clampf(n.x, 0.0, 1.0), clampf(1.0 - n.y, 0.0, 1.0))


func _refresh_preview() -> void:
	var col := _current_color()
	preview.color = col
	hex_label.text = "HEX %s" % col.to_html(false).to_upper()


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var p: Vector2 = event.position
		if event is InputEventMouseMotion and event.button_mask == 0:
			return
		var d := p.distance_to(CENTER)
		if d > RING_IN and d < RING_OUT:
			_hue = _hue_at(p)
			_refresh_preview()
		elif d < SQ_HALF:
			_sv = _sv_at(p)
			_refresh_preview()
		queue_redraw()
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()


func _draw() -> void:
	# 色环（72 段）
	var segs := 72
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var pts := PackedVector2Array([
			CENTER + Vector2.from_angle(a0) * RING_IN,
			CENTER + Vector2.from_angle(a0) * RING_OUT,
			CENTER + Vector2.from_angle(a1) * RING_OUT,
			CENTER + Vector2.from_angle(a1) * RING_IN,
		])
		draw_colored_polygon(pts, Color.from_hsv(float(i) / segs, 1.0, 1.0))
	# 内方形：行渐变（横向 = 饱和度，纵向 = 明度）
	var square := Rect2(CENTER - Vector2(SQ_HALF, SQ_HALF), Vector2(SQ_HALF * 2.0, SQ_HALF * 2.0))
	for y in 96:
		var v := 1.0 - float(y) / 96.0
		var col := Color.from_hsv(_hue, 1.0, v)
		draw_line(square.position + Vector2(0, y * square.size.y / 96.0),
			square.position + Vector2(square.size.x, y * square.size.y / 96.0), col, square.size.y / 96.0 + 0.5)
	# 方形内的水平白→色渐变叠印（饱和度）
	for x in 64:
		var col := Color.from_hsv(_hue, float(x) / 64.0, 1.0)
		draw_line(square.position + Vector2(x * square.size.x / 64.0, 0),
			square.position + Vector2(x * square.size.x / 64.0, square.size.y), col, square.size.x / 64.0 + 0.5)
	# 选中点
	var sp := CENTER + Vector2(_sv.x, 1.0 - _sv.y) * SQ_HALF
	draw_circle(sp, 9, Color(0.05, 0.05, 0.05))
	draw_arc(sp, 9, 0, TAU, 20, Color(1, 1, 1), 3.0)
	# 色环选中标记
	draw_arc(CENTER, (RING_IN + RING_OUT) / 2.0, _hue * TAU - 0.06, _hue * TAU + 0.06, 8, Color(0.05, 0.05, 0.05), 6.0)
