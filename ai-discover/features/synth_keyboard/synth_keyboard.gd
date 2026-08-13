extends Node2D
## =============================================================================
## 合成器键盘 —— 两八度钢琴键盘 + 实时复音合成（零音频素材）
## =============================================================================
## · AudioStreamGenerator 每帧合成：所有按下的键叠加
##   （正弦基波 + 0.4 倍二次谐波），带起音/释音包络；
## · 鼠标点击琴键发声、松开全部键停止（钢琴手感），黑键白键可点；
## · 键盘快捷键：Z X C V B N M（C4 大调音阶）+ Q W E R T Y U（C5）。
## =============================================================================

const SAMPLE_RATE := 22050
const WHITE_W := 66.0
const KEY_H := 240.0
const ORIGIN := Vector2(200, 300)

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## 两八度白键的 MIDI 号（C4=60 起）
const WHITE_MIDI: Array[int] = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83]

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _notes: Dictionary = {}      # midi → {freq, age, releasing}

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.25
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## 按下（midi → 频率，可复音）
func _note_on(midi: int) -> void:
	var freq := 440.0 * pow(2.0, (midi - 69) / 12.0)
	_notes[midi] = {"freq": freq, "age": 0.0, "releasing": false}
	status_label.text = "🎹 %s%d" % [NOTE_NAMES[midi % 12], midi / 12 - 1]


## 释放（带释音包络，0.3 秒后从合成池移除）
func _note_off(midi: int) -> void:
	if _notes.has(midi):
		_notes[midi]["releasing"] = true


func _release_all() -> void:
	for midi in _notes.keys():
		_notes[midi]["releasing"] = true


func _process(delta: float) -> void:
	# 包络推进
	var to_remove: Array = []
	for midi in _notes.keys():
		var n: Dictionary = _notes[midi]
		n["age"] += delta
		if n["releasing"] and n["age"] > 0.35:
			to_remove.append(midi)
	for midi in to_remove:
		_notes.erase(midi)

	_fill_buffer()


## 合成：所有音符叠加（基波 + 谐波，起音/释音包络）
func _fill_buffer() -> void:
	var to_fill := _playback.get_frames_available()
	while to_fill > 0:
		var frames := mini(to_fill, 1024)
		var chunk := PackedVector2Array()
		chunk.resize(frames)
		for i in frames:
			_phase += 1.0 / SAMPLE_RATE
			var s := 0.0
			for midi in _notes.keys():
				var n: Dictionary = _notes[midi]
				var env := clampf(n["age"] / 0.02, 0.0, 1.0)      # 起音
				if n["releasing"]:
					env *= 1.0 - clampf(n["age"] / 0.35, 0.0, 1.0)  # 释音
				s += (sin(TAU * n["freq"] * _phase) + 0.4 * sin(TAU * n["freq"] * 2.0 * _phase)) * env * 0.22
			chunk[i] = Vector2(s, s)
		_playback.push_buffer(chunk)
		to_fill -= frames


# ============================================================
#  键位几何与输入
# ============================================================
## 白键矩形（第 i 个白键）
func _white_rect(i: int) -> Rect2:
	return Rect2(ORIGIN + Vector2(i * WHITE_W, 0), Vector2(WHITE_W - 3, KEY_H))


## 黑键矩形（位于白键边界，C# D# F# G# A# 处）
func _black_rect(i: int) -> Rect2:
	# i 对应白键间隙：0=C# 1=D# 3=F# 4=G# 5=A#（每八度 7 白 5 黑）
	var gaps: Array[int] = [0, 1, 3, 4, 5]
	var octave := i / 5
	var g := gaps[i % 5]
	# 黑键位于"第 g 个白键之后"的边界处（+1）
	var x := ORIGIN.x + (octave * 7 + g + 1) * WHITE_W - 22.0
	return Rect2(Vector2(x, ORIGIN.y), Vector2(44, KEY_H * 0.62))


func _key_at(p: Vector2) -> String:
	# 先查黑键
	for i in 10:
		if _black_rect(i).has_point(p):
			var octave := i / 5
			var semitone: Array[int] = [1, 3, 6, 8, 10]
			return "midi:%d" % (60 + octave * 12 + semitone[i % 5])
	for i in WHITE_MIDI.size():
		if _white_rect(i).has_point(p):
			return "midi:%d" % WHITE_MIDI[i]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var key := _key_at(event.position)
			if key != "":
				_note_on(int(key.split(":")[1]))
				queue_redraw()
		else:
			_release_all()
			queue_redraw()
	# 键盘快捷键（两八度）
	if event is InputEventKey and event.pressed and not event.echo:
		var map := {
			KEY_Z: 60, KEY_X: 62, KEY_C: 64, KEY_V: 65, KEY_B: 67, KEY_N: 69, KEY_M: 71,
			KEY_Q: 72, KEY_W: 74, KEY_E: 76, KEY_R: 77, KEY_T: 79, KEY_Y: 81, KEY_U: 83,
		}
		if map.has(event.keycode):
			_note_on(map[event.keycode])
			queue_redraw()
	elif event is InputEventKey and not event.pressed and not event.echo:
		var map := {
			KEY_Z: 60, KEY_X: 62, KEY_C: 64, KEY_V: 65, KEY_B: 67, KEY_N: 69, KEY_M: 71,
			KEY_Q: 72, KEY_W: 74, KEY_E: 76, KEY_R: 77, KEY_T: 79, KEY_Y: 81, KEY_U: 83,
		}
		if map.has(event.keycode):
			_note_off(map[event.keycode])


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	# 白键
	for i in WHITE_MIDI.size():
		var r := _white_rect(i)
		var pressed := _notes.has(WHITE_MIDI[i])
		draw_rect(r, Color(0.96, 0.95, 0.92) if not pressed else Color(0.75, 0.85, 1.0))
		draw_rect(r, Color(0.3, 0.3, 0.35), false, 2.0)
	# 黑键
	for i in 10:
		var octave := i / 5
		var semitone: Array[int] = [1, 3, 6, 8, 10]
		var midi := 60 + octave * 12 + semitone[i % 5]
		var r := _black_rect(i)
		var pressed := _notes.has(midi)
		draw_rect(r, Color(0.12, 0.12, 0.16) if not pressed else Color(0.35, 0.5, 0.85))
		draw_rect(r, Color(0.05, 0.05, 0.08), false, 2.0)
		draw_rect(Rect2(r.position + Vector2(14, r.size.y - 22), Vector2(16, 14)), Color(0.35, 0.35, 0.42))
