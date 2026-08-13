extends Node2D
## =============================================================================
## 节拍器 —— BPM 可调、合成点击音（强拍重音）+ 视觉摆动
## =============================================================================
## · 滑杆调 BPM（40~240），每拍合成一次短促点击音（衰减正弦），
##   4/4 每小节第一拍为重音（更大音量）；
## · 摆锤随拍左右摆动，拍数/小节计数显示。
## 节拍判定（_step）为纯函数（手动推进时间），可确定性测试。
## =============================================================================

const SAMPLE_RATE := 22050

var _bpm := 120.0
var _t := 0.0
var _next_beat := 0.0
var _beats := 0
var _click_end := -1.0      # 点击音结束时间
var _click_strong := false
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0

@onready var bpm_slider: HSlider = $CanvasLayer/Slider
@onready var bpm_label: Label = $CanvasLayer/BpmLabel
@onready var beat_label: Label = $CanvasLayer/BeatLabel


func _ready() -> void:
	$CanvasLayer/PlayBtn.pressed.connect(_toggle_play)
	bpm_slider.min_value = 40
	bpm_slider.max_value = 240
	bpm_slider.value = 120
	bpm_slider.value_changed.connect(func(v: float) -> void: _bpm = v)
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_bpm = _bpm


## 手动推进（供测试与 _process）：到拍点触发节拍
func _step(delta: float) -> void:
	_t += delta
	if _t >= _next_beat:
		_next_beat += 60.0 / _bpm
		_beats += 1
		_click_end = _t + 0.05
		_click_strong = (_beats % 4 == 1)
		beat_label.text = "第 %d 拍 · 第 %d 小节" % [_beats, (_beats - 1) / 4 + 1]
		bpm_label.text = "BPM %d" % int(_bpm)


func _toggle_play() -> void:
	if _next_beat < _t:
		_next_beat = _t
	$CanvasLayer/PlayBtn.text = "⏸ 暂停" if not _paused else "▶ 播放"
	_paused = not _paused


var _paused := false


func _process(delta: float) -> void:
	if not _paused:
		_step(delta)
	_fill_buffer()
	queue_redraw()


## 合成：点击音 = 短促衰减正弦（重音更强）
func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	while to_fill > 0:
		var frames := mini(to_fill, 512)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var s := 0.0
			if _t < _click_end:
				var age := (_click_end - 0.05) - _t   # 负进展? 改用剩余
				age = maxf(0.0, _click_end - _t)
				s = sin(TAU * 1500.0 * _phase) * exp(-age * 80.0) * (0.5 if _click_strong else 0.3)
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames


func _draw() -> void:
	var c := Vector2(640, 200)
	# 摆锤轴
	draw_circle(c, 8, Color(0.7, 0.7, 0.8))
	# 摆锤角度: 按当前小节内拍相位摆动
	var beat_phase := 0.0
	if _next_beat > _t and _next_beat - _t <= 60.0 / _bpm:
		beat_phase = 1.0 - (_next_beat - _t) / (60.0 / _bpm)
	var ang := sin(beat_phase * PI) * 0.9
	var tip := c + Vector2.from_angle(PI / 2.0 + ang) * 210.0
	draw_line(c, tip, Color(0.8, 0.8, 0.9), 5.0)
	draw_circle(tip, 26, Color(0.95, 0.8, 0.4))
	draw_circle(tip, 26, Color(0.5, 0.42, 0.2), false, 3.0)
