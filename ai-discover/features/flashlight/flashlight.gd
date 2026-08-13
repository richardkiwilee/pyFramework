extends Control
## =============================================================================
## 手电筒光照 —— 光锥 shader 照亮"藏宝图"，锥向随鼠标移动方向转动
## =============================================================================
## · 全屏 ColorRect + flashlight.gdshader：彩色噪声藏宝图藏在黑暗中，
##   只有光锥内可见（角度锥形 + 距离衰减 + 柔边）；
## · 光锥方向 = 鼠标移动方向（GDScript 根据速度算角并推 uniform），
##   鼠标静止时保持最后方向；
## · 点击鼠标：光闪烁一下（flicker 快速脉冲）。
## =============================================================================

const FlashlightShader = preload("res://features/flashlight/flashlight.gdshader")

var _light_pos := Vector2(640, 360)
var _angle := -PI / 2.0     # 初始朝上
var _flicker := 1.0
var _mat: ShaderMaterial

@onready var rect: ColorRect = $EffectRect


func _ready() -> void:
	_mat = rect.material
	_push()


func _process(delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	# 只在鼠标位于窗口内时跟随（防止鼠标进出窗口时光源跳变）
	var in_window := Rect2(Vector2(1, 1), Vector2(1278, 718)).has_point(mouse)
	var vel := mouse - _light_pos
	if in_window and vel.length() > 3.0:
		_light_pos = mouse
		_angle = atan2(vel.y, vel.x)   # 锥向 = 移动方向
	# 闪烁衰减
	_flicker = lerpf(_flicker, 1.0, delta * 6.0)
	_push()


func _push() -> void:
	_mat.set_shader_parameter("light_pos", _light_pos)
	_mat.set_shader_parameter("light_angle", _angle)
	_mat.set_shader_parameter("flicker", _flicker)
	_mat.set_shader_parameter("view_size", Vector2(1280, 720))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_flicker = 0.35
		get_viewport().set_input_as_handled()
