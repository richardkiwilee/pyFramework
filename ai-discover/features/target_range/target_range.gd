extends Node2D
## =============================================================================
## 打靶射击 —— 移动靶横穿屏幕，准星点击射击
## =============================================================================
## · 靶子以随机速度左右横穿，出屏后从另一侧重新进入；
## · 准星跟随鼠标（隐藏系统光标），点击判定命中（红心=高分环）；
## · 命中环扩散动画 + 计分；命中率统计。
## 命中判定（_hit_at）为纯函数，可确定性测试。
## =============================================================================

const TARGET_R := 40.0
const BULLSEYE_R := 14.0

var _targets: Array = []     # {pos, speed, dir}
var _shots := 0
var _hits := 0
var _score := 0
var _rings: Array = []       # {pos, t, hit}

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_reset)
	_reset()
	Input.set_custom_mouse_cursor(null)   # 隐藏系统光标


func _reset() -> void:
	_targets = []
	for i in 5:
		_targets.append({
			"pos": Vector2(randf_range(200, 1080), randf_range(120, 500)),
			"speed": randf_range(90.0, 220.0),
			"dir": 1.0 if randf() < 0.5 else -1.0,
		})
	_shots = 0
	_hits = 0
	_score = 0
	_rings.clear()
	status_label.text = "🎯 移动准星点击射击"
	queue_redraw()


## 命中判定（供测试与输入）：返回得分（0 = 未中）
func _hit_at(p: Vector2) -> int:
	for i in _targets.size():
		var d := p.distance_to(_targets[i]["pos"])
		if d <= TARGET_R:
			var points := 50 if d <= BULLSEYE_R else 20
			_targets[i]["pos"] = Vector2(randf_range(200, 1080), randf_range(120, 500))
			_targets[i]["dir"] = 1.0 if randf() < 0.5 else -1.0
			_rings.append({"pos": _targets[i]["pos"], "t": 0.0, "hit": true})
			return points
	_rings.append({"pos": p, "t": 0.0, "hit": false})
	return 0


func _process(delta: float) -> void:
	for t in _targets:
		t["pos"].x += t["speed"] * t["dir"] * delta
		if t["pos"].x > 1240.0:
			t["pos"].x = 40.0
		if t["pos"].x < 40.0:
			t["pos"].x = 1240.0
	for r in _rings:
		r["t"] += delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["t"]) < 0.4)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shots += 1
		var points := _hit_at(event.position)
		if points > 0:
			_hits += 1
			_score += points
		var acc := 100.0 * _hits / maxf(1.0, _shots)
		status_label.text = "🎯 得分 %d · 命中率 %d%%（%d/%d）" % [_score, int(acc), _hits, _shots]
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 靶子（同心环 + 红心）
	for t in _targets:
		var c: Vector2 = t["pos"]
		draw_circle(c, TARGET_R, Color(0.95, 0.95, 0.9))
		draw_circle(c, TARGET_R * 0.66, Color(0.9, 0.35, 0.3))
		draw_circle(c, BULLSEYE_R, Color(0.85, 0.2, 0.2))
		draw_circle(c, 5, Color(0.2, 0.05, 0.05))
	# 命中环
	for r in _rings:
		var f: float = 1.0 - r["t"] / 0.4
		var col := Color(0.4, 0.9, 0.5, f * 0.8) if r["hit"] else Color(0.9, 0.5, 0.4, f * 0.6)
		draw_arc(r["pos"], 12.0 + (1.0 - f) * 46.0, 0, TAU, 28, col, 4.0)
	# 准星（跟随鼠标）
	var mouse := get_viewport().get_mouse_position()
	draw_line(mouse + Vector2(-12, 0), mouse + Vector2(12, 0), Color(1, 0.5, 0.5), 2.0)
	draw_line(mouse + Vector2(0, -12), mouse + Vector2(0, 12), Color(1, 0.5, 0.5), 2.0)
	draw_circle(mouse, 4, Color(1, 0.5, 0.5))
