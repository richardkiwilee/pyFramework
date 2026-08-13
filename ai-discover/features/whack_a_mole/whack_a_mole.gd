extends Node2D
## =============================================================================
## 打地鼠 —— 3×3 地洞限时敲打（30 秒倒计时 + 难度递增加速）
## =============================================================================
## · 地鼠随机从洞中冒出（0.9~1.5 秒后缩回），点击敲中 +10 分；
## · 分数越高地鼠出现越频繁、停留越短；30 秒倒计时结束结算；
## · R 重开。核心逻辑（_pop/_whack/_expire）可确定性测试。
## =============================================================================

const GAME_TIME := 30.0
const HOLE_GRID := Vector2i(3, 3)
const HOLE_SPACING := 190.0
const ORIGIN := Vector2(355, 200)

var _moles: Dictionary = {}    # hole_idx → 剩余停留时间
var _score := 0
var _time_left := GAME_TIME
var _over := false
var _spawn_timer := 0.0
var _pops: Array = []          # {pos, t} 敲击特效

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false
	_spawn_interval()  # 初始化首只地鼠
	_pop_mole()


## 当前刷新间隔（分数越高越快）
func _spawn_interval() -> float:
	return maxf(0.35, 1.1 - _score * 0.012)


## 让一只地鼠从随机空洞冒出（供测试）
func _pop_mole() -> void:
	if _moles.size() >= 9:
		return
	var free: Array = []
	for i in 9:
		if not _moles.has(i):
			free.append(i)
	var idx: int = free[randi() % free.size()]
	_moles[idx] = randf_range(0.9, 1.5)


## 敲击（供输入与测试）
func _whack(idx: int) -> bool:
	if not _moles.has(idx) or _over:
		return false
	_moles.erase(idx)
	_score += 10
	_pops.append({"pos": _hole_center(idx), "t": 0.0})
	status_label.text = "🔨 得分：%d · 剩余 %.1f 秒" % [_score, _time_left]
	return true


func _hole_center(idx: int) -> Vector2:
	return ORIGIN + Vector2(idx % 3, idx / 3) * HOLE_SPACING


func _process(delta: float) -> void:
	if _over:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_over = true
		over_label.text = "⏰ 时间到！得分 %d · 按 R 再来一局" % _score
		over_label.visible = true
		return
	# 地鼠停留倒计时
	for idx in _moles.keys():
		_moles[idx] -= delta
		if _moles[idx] <= 0.0:
			_moles.erase(idx)
	# 刷新地鼠
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_pop_mole()
		_spawn_timer = _spawn_interval()
	# 特效
	for p in _pops:
		p["t"] += delta
	_pops = _pops.filter(func(p: Dictionary) -> bool: return p["t"] < 0.35)
	status_label.text = "🔨 得分：%d · 剩余 %.1f 秒" % [_score, _time_left]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _hole_at(event.position)
		if idx >= 0:
			_whack(idx)
		get_viewport().set_input_as_handled()


func _hole_at(p: Vector2) -> int:
	for i in 9:
		if p.distance_to(_hole_center(i)) < 62.0:
			return i
	return -1


func _draw() -> void:
	# 地面与洞口
	for i in 9:
		var c := _hole_center(i)
		draw_ellipse(c, 58.0, 30.0, Color(0.05, 0.05, 0.08))
		draw_ellipse(c, 48.0, 22.0, Color(0.2, 0.13, 0.09))
	# 地鼠（按剩余停留时间的比例冒头）
	for idx in _moles.keys():
		var c := _hole_center(idx)
		var lift := clampf(1.0 - _moles[idx] / 1.2, 0.15, 1.0)
		draw_circle(c + Vector2(0, -14 - 34 * lift), 26, Color(0.62, 0.42, 0.28))
		draw_circle(c + Vector2(-9, -22 - 34 * lift), 4, Color(0.1, 0.08, 0.06))
		draw_circle(c + Vector2(9, -22 - 34 * lift), 4, Color(0.1, 0.08, 0.06))
	# 敲击特效
	for p in _pops:
		var f: float = 1.0 - p["t"] / 0.35
		draw_arc(p["pos"], 20.0 + (1.0 - f) * 40.0, 0, TAU, 20, Color(1, 0.9, 0.5, f * 0.9), 4.0)

