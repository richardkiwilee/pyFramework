extends Control
## =============================================================================
## 万花筒 —— 扇形折叠对称图案（2D shader）
## =============================================================================
## · shader 把极角按 N 重对称折叠，噪声场在折叠空间采样 → 天然万花筒；
## · 点击：分瓣数 +2（4/6/8/10/12 循环）；滚轮：图案缩放；
## · 图案随时间缓慢流动演化。
## =============================================================================

const KaleidoscopeShader = preload("res://features/kaleidoscope/kaleidoscope.gdshader")

var _sectors := 6
var _zoom := 1.0
var _clock_start: float = 0.0

@onready var rect: ColorRect = $EffectRect
@onready var info_label: Label = $CanvasLayer/InfoLabel


func _ready() -> void:
	_clock_start = Time.get_ticks_msec() / 1000.0
	_push()


func _process(_delta: float) -> void:
	rect.material.set_shader_parameter("u_time", Time.get_ticks_msec() / 1000.0 - _clock_start)


func _push() -> void:
	var mat: ShaderMaterial = rect.material
	mat.set_shader_parameter("sectors", _sectors)
	mat.set_shader_parameter("zoom", _zoom)
	mat.set_shader_parameter("view_size", Vector2(1280, 720))
	info_label.text = "🔮 分瓣：%d · 缩放：%.1f" % [_sectors, _zoom]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_sectors = 4 if _sectors >= 12 else _sectors + 2
			_push()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 1.15, 0.4, 3.0)
			_push()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom / 1.15, 0.4, 3.0)
			_push()
			get_viewport().set_input_as_handled()
