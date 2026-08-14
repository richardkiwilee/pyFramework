extends Node2D
## =============================================================================
## 保龄球 —— 拖拽瞄准抛球、击倒球瓶计分
## =============================================================================
## · 10 瓶三角排列；按住球拖拽蓄力（显示拉线），松手抛出；
## · 球瓶被撞倒（倒下动画 + 渐隐），每击倒一瓶 +10 分；
## · 球出界回位；【🔄 摆瓶】重置。
## 物理（_physics_step）为纯函数式，可确定性测试。
## =============================================================================

const BALL_R := 18.0
const PIN_R := 13.0
const BALL_START := Vector2(260, 560)
const PINS_ORIGIN := Vector2(880, 400)
const PIN_SPACING := 32.0

var _pins: Array = []        # {pos, fallen, t}
var _ball: Dictionary = {"pos": BALL_START, "vel": Vector2.ZERO, "active": false}
var _score := 0
var _dragging := false
var _drag_from := Vector2.ZERO

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_setup_pins)
	_setup_pins()


func _setup_pins() -> void:
	_pins.clear()
	for row in 4:
		for i in row + 1:
			_pins.append({
				"pos": PINS_ORIGIN + Vector2(row * PIN_SPACING, (i - row * 0.5) * PIN_SPACING),
				"fallen": false,
				"t": 0.0,
			})
	_score = 0
	_ball = {"pos": BALL_START, "vel": Vector2.ZERO, "active": false}
	status_label.text = "🎳 得分：0 · 按住球拖拽抛球"
	queue_redraw()


## 单步物理（供测试）：返回本次击倒数
func _physics_step(delta: float) -> int:
	var knocked := 0
	if _ball["active"]:
		_ball["pos"] += _ball["vel"] * delta
		_ball["vel"] *= 0.985
		# 撞瓶
		for p in _pins:
			if p["fallen"]:
				continue
			if p["pos"].distance_to(_ball["pos"]) < BALL_R + PIN_R:
				p["fallen"] = true
				p["t"] = 0.0
				_score += 10
				knocked += 1
		# 出界 → 球回位
		var bp: Vector2 = _ball["pos"]
		if bp.x > 1280.0 or bp.y > 720.0 or bp.y < 0.0:
			_ball = {"pos": BALL_START, "vel": Vector2.ZERO, "active": false}
	# 倒下渐隐
	for p in _pins:
		if p["fallen"]:
			p["t"] += delta
	return knocked


func _process(delta: float) -> void:
	var knocked := _physics_step(delta)
	if knocked > 0:
		status_label.text = "🎳 得分：%d · 击倒 %d 瓶" % [_score, _count_fallen()]
	queue_redraw()


func _count_fallen() -> int:
	var n := 0
	for p in _pins:
		if p["fallen"]:
			n += 1
	return n


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.distance_to(_ball["pos"]) < 40.0 and not _ball["active"]:
			_dragging = true
			_drag_from = event.position
		elif _dragging:
			_ball["vel"] = (_drag_from - event.position) * 11.0
			_ball["active"] = true
			_dragging = false
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 球道
	draw_rect(Rect2(120, 300, 900, 320), Color(0.40, 0.30, 0.20))
	# 拉线
	if _dragging:
		var mouse := get_viewport().get_mouse_position()
		draw_line(_ball["pos"], mouse, Color(0.5, 0.8, 1.0, 0.7), 2.5)
		draw_circle(mouse, 6, Color(0.7, 0.9, 1.0))
	# 球瓶
	for p in _pins:
		if p["fallen"]:
			var f := 1.0 - clampf(p["t"] / 0.4, 0.0, 1.0)
			# 倒下：向倒地方向躺平（简化为压扁 + 渐隐）
			draw_rect(Rect2(p["pos"] + Vector2(-PIN_R, -4), Vector2(PIN_R * 2, 8)), Color(0.95, 0.9, 0.85, f))
		else:
			draw_rect(Rect2(p["pos"] + Vector2(-9, -26), Vector2(18, 34)), Color(0.95, 0.9, 0.85))
			draw_rect(Rect2(p["pos"] + Vector2(-13, -6), Vector2(26, 12)), Color(0.95, 0.9, 0.85))
			draw_rect(Rect2(p["pos"] + Vector2(-13, 6), Vector2(26, 10)), Color(0.85, 0.8, 0.75))
			draw_rect(Rect2(p["pos"] + Vector2(-4, -24), Vector2(8, 20)), Color(0.8, 0.3, 0.3))
	# 球
	draw_circle(_ball["pos"], BALL_R, Color(0.3, 0.45, 0.9))
	draw_circle(_ball["pos"] + Vector2(-6, -7), 5, Color(1, 1, 1, 0.5))
