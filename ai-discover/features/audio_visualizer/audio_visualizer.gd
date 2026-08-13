extends Node2D
## =============================================================================
## 音乐可视化 —— 程序化合成和弦 + 实时频谱驱动的光柱/音环
## =============================================================================
## 零音频素材：AudioStreamGenerator 实时合成正弦波和弦
## （C → Am → F → G 循环，含低音），经 Master 总线的
## AudioEffectSpectrumAnalyzer 采集 32 段频谱，驱动绘制：
##   · 底部 32 根频率光柱（对数分段，彩虹着色，带峰值残影）；
##   · 中央圆形频谱"音环"（半径随各频段能量起伏）。
## 点击画面或按空格立即切换和弦。
## =============================================================================

const SAMPLE_RATE := 22050
const BAR_COUNT := 32

const CHORDS: Array[Array] = [
	[261.63, 329.63, 392.00],   # C 大调
	[220.00, 261.63, 329.63],   # Am
	[174.61, 220.00, 261.63],   # F
	[196.00, 246.94, 293.66],   # G
]
const CHORD_NAMES := ["C 大调", "A 小调", "F 大调", "G 大调"]
const CHORD_SECONDS := 1.6

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _phase := 0.0
var _chord := 0
var _chord_timer := 0.0
var _bars := PackedFloat32Array()
var _peaks := PackedFloat32Array()

@onready var chord_label: Label = $CanvasLayer/ChordLabel


func _ready() -> void:
	for i in BAR_COUNT:
		_bars.append(0.0)
		_peaks.append(0.0)

	# 合成器
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.4
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback

	# 频谱分析器挂在 Master 总线；Godot 4.2+ 的分析 API 在【实例】上
	var effect := AudioEffectSpectrumAnalyzer.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), effect, 0)
	_analyzer = AudioServer.get_bus_effect_instance(AudioServer.get_bus_index("Master"), 0)


func _process(delta: float) -> void:
	# 自动和弦进行
	_chord_timer += delta
	if _chord_timer >= CHORD_SECONDS:
		_chord_timer = 0.0
		_set_chord((_chord + 1) % CHORDS.size())

	_fill_buffer()

	# 采集频谱（对数分段 60Hz ~ 8kHz）
	for i in BAR_COUNT:
		var f0 := 60.0 * pow(8000.0 / 60.0, float(i) / BAR_COUNT)
		var f1 := 60.0 * pow(8000.0 / 60.0, float(i + 1) / BAR_COUNT)
		var mag: Vector2 = _analyzer.get_magnitude_for_frequency_range(f0, f1, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
		var v: float = mag.x   # 返回 Vector2：x=幅度，y=相位
		_bars[i] = pow(v, 0.55)
		_peaks[i] = maxf(_peaks[i] * 0.995, _bars[i])
	chord_label.text = "🎵 %s（自动进行 · 点击切换）" % CHORD_NAMES[_chord]
	queue_redraw()


## 往合成器缓冲填正弦波（和弦 + 低八度根音）
func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	var freqs: Array = CHORDS[_chord]
	while to_fill > 0:
		var frames := mini(to_fill, 1024)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var s := 0.0
			for f in freqs:
				s += sin(TAU * f * _phase) * 0.14
			s += sin(TAU * freqs[0] * 0.5 * _phase) * 0.22   # 低音
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames


func _set_chord(i: int) -> void:
	_chord = i


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_set_chord((_chord + 1) % CHORDS.size())
		get_viewport().set_input_as_handled()


## 绘制：底部频率光柱 + 中央频谱音环
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.04, 0.08))
	var c := Vector2(640, 400)

	# 中央音环：半径由各频段能量调制
	for i in 32:
		var a := TAU * i / 32.0
		var r := 150.0 + _bars[i] * 260.0
		var hue := float(i) / 32.0
		var col := Color.from_hsv(fposmod(hue + 0.55, 1.0), 0.85, 1.0)
		draw_line(c + Vector2.from_angle(a) * 150.0, c + Vector2.from_angle(a) * r, Color(col.r, col.g, col.b, 0.7), 3.0)
	draw_circle(c, 148.0, Color(0.08, 0.08, 0.14))
	draw_arc(c, 148.0, 0, TAU, 64, Color(0.4, 0.45, 0.6), 2.0)

	# 底部光柱
	var bw := 1280.0 / BAR_COUNT
	for i in BAR_COUNT:
		var h := _bars[i] * 300.0
		var hue := float(i) / BAR_COUNT
		var col := Color.from_hsv(hue, 0.9, 1.0)
		draw_rect(Rect2(i * bw + 2, 720 - h, bw - 4, h), col)
		# 峰值残影线
		draw_rect(Rect2(i * bw + 2, 720 - _peaks[i] * 300.0 - 3, bw - 4, 2), Color(1, 1, 1, 0.8))
