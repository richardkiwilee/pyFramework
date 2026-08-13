extends Control
## =============================================================================
## 点击波纹 —— 深水背景，点击处泛起扩散涟漪（2D shader）
## =============================================================================
## 波纹数据（位置 + 出生时刻）由 GDScript 管理（最多 8 个，环形覆盖），
## 以 uniform 数组注入 shader；时间统一用 GDScript 时钟传入 u_time，
## 保证"出生时刻"与 shader 时钟同源。
## =============================================================================

const MAX_RIPPLES := 8
const LIFETIME := 2.5

var _ripple_pos: Array[Vector2] = []
var _ripple_time: Array[float] = []
var _next_slot := 0
var _clock_start: float = 0.0

@onready var rect: ColorRect = $EffectRect


func _ready() -> void:
	_clock_start = Time.get_ticks_msec() / 1000.0
	for i in MAX_RIPPLES:
		_ripple_pos.append(Vector2.ZERO)
		_ripple_time.append(-1.0)
	_push_params()


func _process(_delta: float) -> void:
	rect.material.set_shader_parameter("u_time", _now())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 - _clock_start


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_add_ripple(event.position)
		get_viewport().set_input_as_handled()


## 添加一个波纹（环形覆盖最旧的槽位），供测试直接调用
func _add_ripple(pos: Vector2) -> void:
	_ripple_pos[_next_slot] = pos
	_ripple_time[_next_slot] = _now()
	_next_slot = (_next_slot + 1) % MAX_RIPPLES
	_push_params()


func _push_params() -> void:
	var mat: ShaderMaterial = rect.material
	var pos_arr := PackedVector2Array(_ripple_pos)
	var time_arr := PackedFloat32Array(_ripple_time)
	for i in MAX_RIPPLES:
		mat.set_shader_parameter("ripple_pos", pos_arr)
		mat.set_shader_parameter("ripple_time", time_arr)
	mat.set_shader_parameter("view_size", Vector2(1280, 720))
