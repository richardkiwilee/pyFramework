extends Control
## =============================================================================
## 波形画板 —— 手绘波形曲线，实时合成发声（把画变成声音）
## =============================================================================
## · 在画布上按住拖动绘制振幅曲线（x = 时间，y = 振幅）；
## · ▶ 播放：AudioStreamGenerator 按 22050Hz 采样读取曲线 → 循环发声；
## · 【🎲 随机】生成随机波形（噪声感音色）·【🧹 清空】。
## 波形采样（_sample_wave）为纯函数，可确定性测试。
## =============================================================================

const SAMPLE_RATE := 22050
const CANVAS := Rect2(150, 150, 980, 320)

var _points: PackedVector2Array = []    # 归一化 (0..1, 0..1) 波形
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _playing := false
var _drawing := false

@onready var play_btn: Button = $CanvasLayer/Bar/PlayBtn
@onready var canvas_rect: Control = $CanvasRect


func _ready() -> void:
	$CanvasLayer/Bar/RandomBtn.pressed.connect(_random_wave)
	$CanvasLayer/Bar/ClearBtn.pressed.connect(_clear)
	play_btn.pressed.connect(_toggle_play)
	# 画布点击由画布自己接收（STOP 过滤控件会吃掉 _unhandled_input）
	canvas_rect.gui_input.connect(_on_canvas_input)
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.3
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_random_wave()


func _toggle_play() -> void:
	_playing = not _playing
	play_btn.text = "⏸ 停止" if _playing else "▶ 播放"


## 归一化波形采样（t ∈ [0,1)，线性插值；无点返回 0）
func _sample_wave(t: float) -> float:
	if _points.is_empty():
		return 0.0
	var f := fposmod(t, 1.0) * _points.size()
	var i := int(floor(f)) % _points.size()
	var j := (i + 1) % _points.size()
	var u: float = f - floor(f)
	return lerpf(_points[i].y, _points[j].y, u)


func _process(delta: float) -> void:
	# 画线输入
	var mouse := get_viewport().get_mouse_position()
	if _drawing and canvas_rect.get_global_rect().has_point(mouse):
		var n := (mouse - CANVAS.position) / CANVAS.size
		_points.append(Vector2(n.x, clampf(n.y, 0.0, 1.0)))
		canvas_rect.queue_redraw()
	# 发声
	if _playing:
		_fill_buffer()


func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	while to_fill > 0:
		var frames := mini(to_fill, 1024)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var s := (_sample_wave(_phase * 1.5) * 2.0 - 1.0) * 0.35
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames


func _random_wave() -> void:
	_points.clear()
	for i in 64:
		_points.append(Vector2(float(i) / 64.0, randf()))
	canvas_rect.queue_redraw()


func _clear() -> void:
	_points.clear()
	canvas_rect.queue_redraw()


## 画布 gui_input：按下开始新波形（清空旧线），松开停止
func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_points.clear()
			_drawing = true
		else:
			_drawing = false
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 画布底
	draw_rect(CANVAS, Color(0.08, 0.09, 0.13))
	draw_rect(CANVAS, Color(0.3, 0.34, 0.45), false, 2.0)
	# 零线
	var zero := CANVAS.position + Vector2(0, CANVAS.size.y / 2.0)
	draw_line(zero, zero + Vector2(CANVAS.size.x, 0), Color(0.4, 0.45, 0.6, 0.6), 1.0)
	# 波形
	if _points.size() > 1:
		var pts := PackedVector2Array()
		for p in _points:
			pts.append(CANVAS.position + Vector2(p.x * CANVAS.size.x, p.y * CANVAS.size.y))
		draw_polyline(pts, Color(0.35, 0.9, 0.6), 2.5)
