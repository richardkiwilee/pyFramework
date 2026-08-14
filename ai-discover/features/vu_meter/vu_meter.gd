extends Node2D
## =============================================================================
## 音量表 —— 音频电平驱动的 VU 表 + 峰值保持（经典音频 UI 组件）
## =============================================================================
## · 程序化合成的音量起伏信号（LFO 调制）驱动电平；
## · 左/右双声道条 + 分段刻度（绿/黄/红区）+ 峰值保持线缓慢回落；
## · 音量滑杆可调。电平采样（_sample_level）为纯函数，可确定性测试。
## =============================================================================

const SAMPLE_RATE := 22050

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _level := 0.0
var _peak := 0.0
var _volume := 0.7

@onready var slider: HSlider = $CanvasLayer/Slider
@onready var level_label: Label = $CanvasLayer/LevelLabel


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.value = 0.7
	slider.value_changed.connect(func(v: float) -> void: _volume = v)


## 当前时刻的电平（供测试与显示）：LFO 起伏的合成音量
func _sample_level(t: float) -> float:
	var wave := 0.5 + 0.5 * sin(TAU * 0.4 * t) * sin(TAU * 2.6 * t)
	return clampf(wave * _volume, 0.0, 1.0)


func _process(delta: float) -> void:
	_level = _sample_level(Time.get_ticks_msec() / 1000.0)
	_peak = maxf(_peak, _level)
	_peak = maxf(_level, _peak - delta * 0.15)   # 峰值缓慢回落
	_fill_buffer()
	level_label.text = "电平 %.0f%% · 峰值 %.0f%%" % [_level * 100.0, _peak * 100.0]
	queue_redraw()


func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	while to_fill > 0:
		var frames := mini(to_fill, 512)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var s := sin(TAU * 220.0 * _phase) * _sample_level(Time.get_ticks_msec() / 1000.0)
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames


func _draw() -> void:
	# 双声道表体
	for ch in 2:
		var x := 480.0 + ch * 120.0
		draw_rect(Rect2(x, 180, 56, 380), Color(0.08, 0.09, 0.13))
		# 分段（24 段，绿/黄/红）
		for i in 24:
			var t := float(i) / 23.0
			var col := Color(0.35, 0.85, 0.45)
			if t > 0.75:
				col = Color(0.95, 0.4, 0.35)
			elif t > 0.5:
				col = Color(0.95, 0.8, 0.3)
			var lit := _level >= t
			var seg := Rect2(x + 4, 180 + (23 - i) * 15.2, 48, 11)
			draw_rect(seg, col if lit else Color(0.18, 0.2, 0.26))
		# 峰值线
		var peak_y := 180 + (1.0 - _peak) * 372.0
		draw_line(Vector2(x, peak_y), Vector2(x + 56, peak_y), Color(1, 1, 1, 0.9), 3.0)
