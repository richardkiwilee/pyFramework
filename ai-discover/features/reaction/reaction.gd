extends Control
## =============================================================================
## 反应测试 —— 等待绿灯亮起后尽快点击，测 5 轮平均反应时
## =============================================================================
## · 红灯随机 1~3 秒后变绿，绿灯后点击 → 记录反应时；抢跑（红时点）判罚；
## · 5 轮取平均，显示每轮成绩与最佳；
## · 状态机（_start_round/_on_click）可确定性测试。
## =============================================================================

var _state := "idle"      # idle / waiting / ready / done
var _light_time := 0.0
var _click_time := 0.0
var _round := 0
var _times: Array = []

@onready var lamp: ColorRect = $Center/VBox/ClickArea/Lamp
@onready var status_label: Label = $Center/VBox/StatusLabel
@onready var round_label: Label = $Center/VBox/RoundLabel


func _ready() -> void:
	$Center/VBox/StartBtn.pressed.connect(_begin)
	$Center/VBox/ClickArea.gui_input.connect(_on_click)


## 开始一轮（供测试）：红灯随机延时
func _start_round() -> void:
	_state = "waiting"
	_light_time = Time.get_ticks_msec() / 1000.0 + randf_range(1.0, 3.0)
	lamp.color = Color(0.85, 0.2, 0.2)
	status_label.text = "🔴 红灯…等它变绿再点！"


func _begin() -> void:
	_round = 0
	_times.clear()
	_next_round()


func _next_round() -> void:
	if _round >= 5:
		_state = "done"
		var avg := 0.0
		for t in _times:
			avg += t
		avg /= maxf(1.0, _times.size())
		status_label.text = "🏁 完成！平均反应 %.0f ms" % (avg * 1000.0)
		lamp.color = Color(0.3, 0.3, 0.35)
		return
	_round += 1
	_start_round()


## 点击（供输入与测试）：返回结果文本
func _on_click(_event: InputEvent) -> void:
	if not (_event is InputEventMouseButton and _event.pressed and _event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _state == "waiting":
		# 抢跑：重来本轮
		_start_round()
		status_label.text = "⛔ 抢跑！重新等待"
	elif _state == "ready":
		_click_time = Time.get_ticks_msec() / 1000.0
		var ms := (_click_time - _light_time) * 1000.0
		_times.append(ms)
		_state = "idle"
		status_label.text = "✅ 本轮 %.0f ms" % ms
		_next_round()


func _process(_delta: float) -> void:
	if _state == "waiting" and Time.get_ticks_msec() / 1000.0 >= _light_time:
		_state = "ready"
		lamp.color = Color(0.3, 0.85, 0.4)
		status_label.text = "🟢 绿灯！快点击！"
	if not _times.is_empty():
		var best: float = _times[0]
		for t in _times:
			best = mini(best, t)
		round_label.text = "第 %d/5 轮 · 最佳 %.0f ms" % [_round, best * 1000.0]
