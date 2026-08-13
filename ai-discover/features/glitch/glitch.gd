extends Control
## =============================================================================
## 故障风特效 —— CRT 扫描线 + RGB 色偏 + 随机撕裂（2D shader）
## =============================================================================
## · 全屏 ColorRect + glitch.gdshader：程序化霓虹底图叠三层故障；
## · GDScript 时钟驱动 u_time，撕裂带每帧重新随机；
## · 点击画面触发一次"大故障"脉冲（强度闪变）。
## =============================================================================

const GlitchShader = preload("res://features/glitch/glitch.gdshader")

var _clock_start: float = 0.0
var _pulse := 1.0

@onready var rect: ColorRect = $EffectRect


func _ready() -> void:
	_clock_start = Time.get_ticks_msec() / 1000.0
	rect.material.set_shader_parameter("view_size", Vector2(1280, 720))


func _process(delta: float) -> void:
	rect.material.set_shader_parameter("u_time", Time.get_ticks_msec() / 1000.0 - _clock_start)
	_pulse = lerpf(_pulse, 1.0, delta * 5.0)
	rect.material.set_shader_parameter("u_time", Time.get_ticks_msec() / 1000.0 - _clock_start + _pulse * 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pulse = 3.0
		get_viewport().set_input_as_handled()
