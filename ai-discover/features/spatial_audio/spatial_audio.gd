extends Node3D
## =============================================================================
## 3D 环绕音效 —— 程序化合成音源绕听者旋转（立体声定位）
## =============================================================================
## · AudioStreamGenerator 合成柔和循环音，由 AudioStreamPlayer3D 播放；
## · 音源绕圆轨匀速飞行，耳机中能听到声音左右环绕 + 距离近响远轻；
## · 相机固定（听者位置），轨道与音源可视化；
## · 速度滑杆可调。
## 轨道位置（_source_pos）为纯函数，可确定性测试。
## =============================================================================

const SAMPLE_RATE := 22050
const RADIUS := 6.0

var _t := 0.0
var _speed := 0.5        # 圈/秒
var _player3d: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _source_mesh: MeshInstance3D

@onready var slider: HSlider = $CanvasLayer/Slider


func _ready() -> void:
	# 合成器 + 3D 播放器
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	_player3d = AudioStreamPlayer3D.new()
	_player3d.stream = gen
	_player3d.unit_size = 8.0
	_player3d.max_distance = 30.0
	add_child(_player3d)
	_player3d.play()
	_playback = _player3d.get_stream_playback() as AudioStreamGeneratorPlayback

	# 轨道环 + 音源球可视化
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.08
	torus.outer_radius = RADIUS + 0.08
	ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.4, 0.45, 0.6)
	ring.material_override = rmat
	add_child(ring)

	_source_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	_source_mesh.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.9, 0.7, 0.3)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.7, 0.2)
	_source_mesh.material_override = smat
	add_child(_source_mesh)

	slider.min_value = 0.1
	slider.max_value = 1.5
	slider.value = 0.5
	slider.value_changed.connect(func(v: float) -> void: _speed = v)


## 音源在时刻 t 的位置（供绘制与测试）
func _source_pos(t: float) -> Vector3:
	return Vector3(cos(t * TAU * _speed) * RADIUS, 1.2, sin(t * TAU * _speed) * RADIUS)


func _process(delta: float) -> void:
	_t += delta
	var pos := _source_pos(_t)
	_player3d.position = pos
	_source_mesh.position = pos
	_fill_buffer()


## 合成：柔和持续音（双正弦 + 缓慢颤音）
func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	while to_fill > 0:
		var frames := mini(to_fill, 512)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var vib := 1.0 + 0.15 * sin(TAU * 4.0 * _phase)
			var s := sin(TAU * 220.0 * _phase) * vib + 0.4 * sin(TAU * 440.0 * _phase)
			s *= 0.3
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames
