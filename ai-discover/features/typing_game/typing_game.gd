extends Node2D
## =============================================================================
## 打字练习 —— 下落单词逐个击破（实时正确性着色 + WPM 统计）
## =============================================================================
## · 单词从顶部下落，输入正确字母推进（绿），打错标红并计失误；
## · 完成一个单词得分、WPM/准确率实时统计；单词触底扣命；
## · 全部命尽 → 结算，R 重开。
## 判定逻辑（_on_key）为纯函数，可确定性测试。
## =============================================================================

const WORDS: Array[String] = [
	"code", "godot", "shader", "physics", "level", "quest", "dragon", "sword",
	"magic", "forest", "castle", "pixel", "sprite", "engine", "camera", "light",
]

const FONT_SIZE := 26
const FALL_SPEED_MIN := 28.0
const FALL_SPEED_MAX := 55.0

var _words: Array = []      # {text, typed, y, speed, x}
var _score := 0
var _errors := 0
var _lives := 5
var _over := false
var _typed_total := 0
var _start_time := 0.0

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	_start_time = Time.get_ticks_msec() / 1000.0
	over_label.visible = false
	_spawn_word()
	queue_redraw()


func _spawn_word() -> void:
	var text: String = WORDS[randi() % WORDS.size()]
	_words.append({
		"text": text,
		"typed": 0,
		"y": 30.0,
		"speed": randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX),
		"x": randf_range(120.0, 1100.0),
	})


## 键入一个字符（供输入与测试）
func _on_key(ch: String) -> void:
	if _over or _words.is_empty():
		return
	var w: Dictionary = _words[0]
	_typed_total += 1
	if ch == w["text"][w["typed"]]:
		w["typed"] += 1
		if w["typed"] >= w["text"].length():
			_score += w["text"].length() * 10
			_words.pop_front()
			_spawn_word()
	else:
		_errors += 1
	_refresh_status()
	queue_redraw()


func _refresh_status() -> void:
	var elapsed := maxf(1.0, Time.get_ticks_msec() / 1000.0 - _start_time)
	var wpm := int(_typed_total / 5.0 / (elapsed / 60.0))
	var acc := 100.0 * float(_typed_total - _errors) / maxf(1.0, float(_typed_total))
	status_label.text = "⌨ 得分 %d · 生命 %d · %d WPM · 准确率 %d%%" % [_score, _lives, wpm, int(acc)]


func _process(delta: float) -> void:
	if _over:
		return
	for w in _words:
		w["y"] += w["speed"] * delta
	# 触底
	if not _words.is_empty() and _words[0]["y"] > 560.0:
		_lives -= 1
		_words.pop_front()
		_spawn_word()
		if _lives <= 0:
			_over = true
			over_label.text = "💀 游戏结束！得分 %d" % _score
			over_label.visible = true
		_refresh_status()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if event is InputEventKey and event.pressed and event.unicode >= 32:
		_on_key(String.chr(event.unicode).to_lower())


func _draw() -> void:
	# 每个单词：已打部分绿色、未打白色（首词带下划线标记）
	for wi in _words.size():
		var w: Dictionary = _words[wi]
		var pos := Vector2(w["x"], w["y"])
		var typed_part: String = w["text"].substr(0, w["typed"])
		var rest: String = w["text"].substr(w["typed"])
		var f := ThemeDB.fallback_font
		draw_string(f, pos, typed_part, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.4, 0.95, 0.5))
		var tx := pos.x + f.get_string_size(typed_part, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(f, Vector2(tx, pos.y), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.9, 0.9, 0.95))
		if wi == 0:
			draw_line(pos + Vector2(0, 30), pos + Vector2(f.get_string_size(w["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x, 30), Color(0.5, 0.8, 1.0, 0.8), 3.0)
