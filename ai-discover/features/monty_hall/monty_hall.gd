extends Control
## =============================================================================
## 蒙提霍尔问题 —— 三门问题模拟：换门 vs 不换门的胜率
## =============================================================================
## · 手动玩法：先选一扇门，主持人打开一扇羊门，选择【坚持】或【换门】；
## · 【模拟 1 万次】批量验证两种策略的胜率收敛到 1/3 与 2/3；
## · 模拟（_simulate_once）为纯函数（传入 RNG），可确定性测试。
## =============================================================================

var _car := 0
var _pick := -1
var _revealed := -1
var _phase := 0        # 0 选门 / 1 主持揭晓后选择策略 / 2 结算
var _stats := {"stay": 0, "switch": 0, "trials": 0}

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var door_btns: HBoxContainer = $CanvasLayer/Doors


func _ready() -> void:
	$CanvasLayer/SimBtn.pressed.connect(_run_simulations)
	$CanvasLayer/ResetBtn.pressed.connect(_new_round)
	for i in 3:
		door_btns.get_child(i).pressed.connect(_on_door.bind(i))
	_new_round()


func _new_round() -> void:
	_car = randi() % 3
	_pick = -1
	_revealed = -1
	_phase = 0
	_refresh_doors()
	status_label.text = "🚪 先选一扇门（1/3 概率有车）"


## 单次模拟（供测试）：返回 {car, pick, revealed, stay_win, switch_win}
func _simulate_once(rng: RandomNumberGenerator) -> Dictionary:
	var car := rng.randi_range(0, 2)
	var pick := rng.randi_range(0, 2)
	# 主持人打开一扇既不是车也不是玩家选的羊门
	var doors := [0, 1, 2]
	var revealed := -1
	for d in doors:
		if d != car and d != pick:
			revealed = d
			break
	var remaining := -1
	for d in doors:
		if d != pick and d != revealed:
			remaining = d
	return {
		"car": car, "pick": pick, "revealed": revealed,
		"stay_win": pick == car,
		"switch_win": remaining == car,
	}


func _run_simulations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec()
	for i in 10000:
		var r := _simulate_once(rng)
		if r["stay_win"]:
			_stats["stay"] += 1
		if r["switch_win"]:
			_stats["switch"] += 1
		_stats["trials"] += 1
	status_label.text = "📊 %d 次模拟：坚持 %.1f%% · 换门 %.1f%%" % [
		_stats["trials"],
		100.0 * _stats["stay"] / _stats["trials"],
		100.0 * _stats["switch"] / _stats["trials"],
	]


func _on_door(idx: int) -> void:
	if _phase == 0:
		_pick = idx
		# 主持人揭晓
		for d in [0, 1, 2]:
			if d != _car and d != _pick:
				_revealed = d
				break
		_phase = 1
		_refresh_doors()
		status_label.text = "🚪 主持人打开了 %d 号门（羊）· 坚持还是换门？" % (_revealed + 1)
	elif _phase == 1:
		# 结算：换门按钮 = 点击与所选不同的未开之门
		if idx == _revealed:
			return
		var switched := idx != _pick
		var win := idx == _car
		_phase = 2
		_refresh_doors()
		status_label.text = "%s · 车在 %d 号门 ·【重开】再来" % ["🎉 你赢了！" if win else "😢 是羊…", _car + 1]


func _refresh_doors() -> void:
	for i in 3:
		var b: Button = door_btns.get_child(i)
		var text := "🚪 %d 号门" % (i + 1)
		if _phase >= 1 and i == _revealed:
			text = "🐐 羊"
		if _phase >= 2:
			text += " 🚗" if i == _car else " 🐐"
		b.text = text
		b.disabled = (_phase == 2) or (_phase == 1 and i == _revealed)


func _unhandled_input(_event: InputEvent) -> void:
	pass
