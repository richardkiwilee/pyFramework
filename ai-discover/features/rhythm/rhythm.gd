extends Node2D
## =============================================================================
## 音游节拍 —— 四轨音符下落，按键在判定窗口内命中（Perfect/Good/Miss）
## =============================================================================
## · 固定音符谱面（确定性，可测试）以恒定速度下落；
## · D F J K 对应四轨，判定窗口：±0.08s Perfect，±0.20s Good；
## · 连击数与分数实时统计，Miss 断连击；谱面结束结算。
## 判定（_judge）为纯函数，可确定性测试。
## =============================================================================

const LANES := 4
const NOTE_SPEED := 300.0
const HIT_Y := 560.0
const PERFECT_W := 0.08
const GOOD_W := 0.20

## 谱面：(时刻, 轨道)
const PATTERN: Array = [
	[0.5, 0], [1.0, 1], [1.5, 2], [2.0, 3], [2.5, 0], [3.0, 3],
	[3.5, 1], [4.0, 2], [4.5, 0], [5.0, 2], [5.5, 1], [6.0, 3],
	[6.5, 0], [7.0, 1], [7.5, 2], [8.0, 3], [8.5, 0], [9.0, 1],
]

var _song_t := 0.0
var _notes: Array = []       # {lane, time, judged}
var _score := 0
var _combo := 0
var _max_combo := 0
var _over := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false
	status_label.text = "🎵 按 D F J K 击打 · 音符落到横线时按"


## 判定（供测试与输入）：返回 Perfect / Good / 空
func _judge(delta_time: float) -> String:
	if absf(delta_time) <= PERFECT_W:
		return "Perfect"
	if absf(delta_time) <= GOOD_W:
		return "Good"
	return ""


func _hit_lane(lane: int) -> void:
	if _over:
		return
	var best := -1
	var best_dt := 99.0
	for i in _notes.size():
		var n: Dictionary = _notes[i]
		if n["judged"] or n["lane"] != lane:
			continue
		var dt := absf(n["time"] - _song_t)
		if dt < best_dt and dt <= GOOD_W:
			best_dt = dt
			best = i
	if best < 0:
		return
	var verdict := _judge(_notes[best]["time"] - _song_t)
	_notes[best]["judged"] = true
	_score += 100 if verdict == "Perfect" else 50
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	status_label.text = "🎵 %s · 得分 %d · 连击 %d" % [verdict, _score, _combo]


func _process(delta: float) -> void:
	if _over:
		return
	_song_t += delta
	# 生成音符
	for p in PATTERN:
		if _song_t - delta <= p[0] and _song_t > p[0]:
			_notes.append({"lane": p[1], "time": p[0], "judged": false})
	# 漏击检测
	for n in _notes:
		if not n["judged"] and n["time"] + GOOD_W < _song_t:
			n["judged"] = true
			_combo = 0
			status_label.text = "🎵 Miss · 得分 %d" % _score
	# 谱面结束
	var all_done := true
	for n in _notes:
		if not n["judged"]:
			all_done = false
	if _song_t > PATTERN[PATTERN.size() - 1][0] + 1.0 and all_done:
		_over = true
		over_label.text = "🎉 谱面结束！得分 %d · 最大连击 %d" % [_score, _max_combo]
		over_label.visible = true
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var lane := -1
		match event.keycode:
			KEY_D: lane = 0
			KEY_F: lane = 1
			KEY_J: lane = 2
			KEY_K: lane = 3
		if lane >= 0:
			_hit_lane(lane)
			get_viewport().set_input_as_handled()


func _lane_x(lane: int) -> float:
	return 400.0 + lane * 160.0


func _draw() -> void:
	# 轨道
	for i in LANES:
		var x := _lane_x(i)
		draw_rect(Rect2(x - 45, 0, 90, 720), Color(0.12, 0.13, 0.19, 0.7))
		draw_line(Vector2(x - 45, 0), Vector2(x - 45, 720), Color(0.3, 0.34, 0.45), 1.5)
	# 判定线
	draw_line(Vector2(200, HIT_Y), Vector2(1080, HIT_Y), Color(0.95, 0.85, 0.4), 4.0)
	# 音符
	for n in _notes:
		if n["judged"]:
			continue
		var y: float = HIT_Y - (n["time"] - _song_t) * NOTE_SPEED
		if y < -20.0 or y > 720.0:
			continue
		var x := _lane_x(n["lane"])
		draw_circle(Vector2(x, y), 16, Color(0.4, 0.85, 1.0))
		draw_circle(Vector2(x, y), 16, Color(0.9, 0.95, 1.0), false, 2.0)
