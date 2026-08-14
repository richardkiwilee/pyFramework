extends Control
## =============================================================================
## 秒表 —— 开始/暂停/计次/重置（真实 UI 组件）
## =============================================================================
## · 大号数字时间显示（00:00.00），暂停后累计保持；
## · 【计次】记录每次圈时并列表显示；
## · 计时逻辑（_elapsed/_toggle/_lap/_reset）为纯函数式状态机，可确定性测试。
## =============================================================================

var _running := false
var _acc := 0.0          # 暂停时累计的时间
var _start_ms := 0.0
var _laps: Array = []

@onready var time_label: Label = $CanvasLayer/TimeLabel
@onready var laps_label: Label = $CanvasLayer/LapsLabel
@onready var toggle_btn: Button = $CanvasLayer/Bar/ToggleBtn


func _ready() -> void:
	toggle_btn.pressed.connect(_toggle)
	$CanvasLayer/Bar/LapBtn.pressed.connect(_lap)
	$CanvasLayer/Bar/ResetBtn.pressed.connect(_reset)


## 当前计时（供显示与测试）
func _elapsed() -> float:
	if _running:
		return _acc + Time.get_ticks_msec() / 1000.0 - _start_ms
	return _acc


func _toggle() -> void:
	if _running:
		_acc = _elapsed()
		_running = false
		toggle_btn.text = "▶ 开始"
	else:
		_start_ms = Time.get_ticks_msec() / 1000.0
		_running = true
		toggle_btn.text = "⏸ 暂停"


func _lap() -> void:
	if not _running:
		return
	var t := _elapsed()
	var prev: float = 0.0 if _laps.is_empty() else _laps[_laps.size() - 1]["total"]
	_laps.append({"total": t, "lap": t - prev})
	_refresh_laps()


func _reset() -> void:
	_running = false
	_acc = 0.0
	_laps.clear()
	toggle_btn.text = "▶ 开始"
	_refresh_laps()


func _format(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var cs := int(fmod(t, 1.0) * 100.0)
	return "%02d:%02d.%02d" % [m, s, cs]


func _refresh_laps() -> void:
	var lines := "计次：\n"
	for i in _laps.size():
		lines += "#%d  %s（圈时 %s）\n" % [i + 1, _format(_laps[i]["total"]), _format(_laps[i]["lap"])]
	laps_label.text = lines


func _process(_delta: float) -> void:
	time_label.text = "⏱ " + _format(_elapsed())
	queue_redraw()


func _draw() -> void:
	pass
