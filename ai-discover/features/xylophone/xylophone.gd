extends Node2D
## =============================================================================
## 木琴 —— 8 根彩色音条（C 大调音阶），点击发声 + 敲击回弹
## =============================================================================
## · 音条从左到右音高递增，颜色按音高渐变；
## · 点击音条：合成短促衰减音（基波 + 谐波），音条向下回弹动画；
## · 键盘快捷键 Z X C V B N M + 高音 1。
## 音高映射（_note_freq/_bar_at）为纯函数，可确定性测试。
## =============================================================================

const SAMPLE_RATE := 22050
const BAR_W := 110.0
const BAR_H := 260.0
const ORIGIN := Vector2(80, 180)
const MIDI: Array[int] = [60, 62, 64, 65, 67, 69, 71, 72]   # C4 大调音阶

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _notes: Array = []        # {freq, age}
var _hit: Array = []          # {idx, t} 敲击动画

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## 音条下标 → 频率（供测试）
func _note_freq(idx: int) -> float:
	return 440.0 * pow(2.0, (MIDI[idx] - 69) / 12.0)


## 屏幕位置 → 音条下标（供输入与测试）
func _bar_at(p: Vector2) -> int:
	if p.y < ORIGIN.y or p.y > ORIGIN.y + BAR_H:
		return -1
	var idx := int(floor((p.x - ORIGIN.x) / BAR_W))
	if idx < 0 or idx >= MIDI.size():
		return -1
	return idx


## 敲击（供输入与测试）
func _hit_bar(idx: int) -> void:
	if idx < 0 or idx >= MIDI.size():
		return
	_notes.append({"freq": _note_freq(idx), "age": 0.0})
	_hit.append({"idx": idx, "t": 0.0})
	status_label.text = "🎵 音条 %d · %.0f Hz" % [idx + 1, _note_freq(idx)]


func _process(delta: float) -> void:
	# 音符衰减
	for n in _notes:
		n["age"] += delta
	_notes = _notes.filter(func(n: Dictionary) -> bool: return float(n["age"]) < 0.6)
	for h in _hit:
		h["t"] += delta
	_hit = _hit.filter(func(h: Dictionary) -> bool: return float(h["t"]) < 0.2)
	_fill_buffer()
	queue_redraw()


func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	while to_fill > 0:
		var frames := mini(to_fill, 512)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var s := 0.0
			for n in _notes:
				var age: float = n["age"]
				var env := exp(-age * 9.0)
				s += (sin(TAU * n["freq"] * _phase) + 0.3 * sin(TAU * n["freq"] * 2.0 * _phase)) * env * 0.25
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _bar_at(event.position)
		if idx >= 0:
			_hit_bar(idx)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var keymap := {KEY_Z: 0, KEY_X: 1, KEY_C: 2, KEY_V: 3, KEY_B: 4, KEY_N: 5, KEY_M: 6, KEY_1: 7}
		if keymap.has(event.keycode):
			_hit_bar(keymap[event.keycode])


func _draw() -> void:
	# 琴架
	draw_rect(Rect2(ORIGIN - Vector2(20, 30), Vector2(BAR_W * MIDI.size() + 40, BAR_H + 70)), Color(0.30, 0.22, 0.14))
	# 音条（敲击时下沉）
	for i in MIDI.size():
		var drop := 0.0
		for h in _hit:
			if int(h["idx"]) == i:
				drop = sin(h["t"] / 0.2 * PI) * 18.0
		var x := ORIGIN.x + i * BAR_W
		var hue := float(i) / 7.0
		var col := Color.from_hsv(fposmod(hue * 0.75 + 0.95, 1.0), 0.65, 0.9)
		draw_rect(Rect2(x, ORIGIN.y + drop, BAR_W - 12, BAR_H), col)
		draw_rect(Rect2(x, ORIGIN.y + drop, BAR_W - 12, BAR_H), Color(0.15, 0.12, 0.08, 0.5), false, 3.0)
		# 音符名
		var f := ThemeDB.fallback_font
		var names := ["C", "D", "E", "F", "G", "A", "B", "C"]
		draw_string(f, Vector2(x + BAR_W / 2.0 - 8, ORIGIN.y + BAR_H - 24), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.15, 0.12, 0.1))
