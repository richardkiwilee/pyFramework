extends Node2D
## =============================================================================
## 打砖块 —— 挡板接球消砖（经典弹球）
## =============================================================================
## · 鼠标移动挡板，点击发射小球；
## · 球与砖块/挡板/三面墙碰撞反弹，砖块击中即碎 +10 分；
## · 漏球扣命，命尽或清空全部砖块 → 结算，R 重开。
## 物理步进纯函数式（_physics_step），可确定性测试。
## =============================================================================

const BRICK_W := 96.0
const BRICK_H := 26.0
const COLS := 10
const ROWS := 5
const ORIGIN := Vector2(160, 80)
const BALL_R := 9.0
const PADDLE_W := 140.0

const ROW_COLORS: Array[Color] = [
	Color(0.95, 0.45, 0.45), Color(0.95, 0.7, 0.35), Color(0.95, 0.9, 0.4),
	Color(0.45, 0.85, 0.5), Color(0.45, 0.65, 0.95),
]

var _bricks: Dictionary = {}    # Vector2i → true
var _ball: Dictionary = {"pos": Vector2(640, 620), "vel": Vector2.ZERO, "stuck": true}
var _paddle_x := 640.0
var _score := 0
var _lives := 3
var _over := false

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	_build_bricks()
	queue_redraw()


func _build_bricks() -> void:
	_bricks.clear()
	for y in ROWS:
		for x in COLS:
			_bricks[Vector2i(x, y)] = true
	_score = 0
	_lives = 3
	_over = false
	_ball = {"pos": Vector2(640, 620), "vel": Vector2.ZERO, "stuck": true}
	status_label.text = "🕹 移动鼠标瞄准 · 点击发射"


func _brick_rect(c: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(c.x * (BRICK_W + 6), c.y * (BRICK_H + 6)), Vector2(BRICK_W, BRICK_H))


## 单步物理（供测试）
func _physics_step(delta: float) -> void:
	if _over or _ball["stuck"]:
		return
	var b: Dictionary = _ball
	b["pos"] += b["vel"] * delta
	# 三面墙
	if b["pos"].x < 12.0 + BALL_R:
		b["pos"].x = 12.0 + BALL_R
		b["vel"].x = -b["vel"].x
	if b["pos"].x > 1268.0 - BALL_R:
		b["pos"].x = 1268.0 - BALL_R
		b["vel"].x = -b["vel"].x
	if b["pos"].y < 12.0 + BALL_R:
		b["pos"].y = 12.0 + BALL_R
		b["vel"].y = -b["vel"].y
	# 挡板碰撞
	var paddle := Rect2(_paddle_x - PADDLE_W / 2.0, 660, PADDLE_W, 16)
	if b["vel"].y > 0 and b["pos"].y + BALL_R > paddle.position.y and b["pos"].y < paddle.end.y + BALL_R \
			and b["pos"].x > paddle.position.x and b["pos"].x < paddle.end.x:
		b["pos"].y = paddle.position.y - BALL_R
		var t := clampf((b["pos"].x - paddle.position.x) / PADDLE_W, 0.0, 1.0)
		var ang := lerpf(-2.3, -0.85, t)
		b["vel"] = Vector2.from_angle(ang) * 460.0
	# 砖块碰撞（就近扫描）
	for c in _bricks.keys():
		var rect := _brick_rect(c).grow(BALL_R)
		if rect.has_point(b["pos"]):
			_bricks.erase(c)
			_score += 10
			status_label.text = "🕹 得分：%d · 剩余砖块：%d" % [_score, _bricks.size()]
			# 按球与砖中心的位置关系决定翻转轴，并把球推出砖外（防止
			# 下一帧与相邻砖重复碰撞、在砖堆里来回振荡）
			var center := _brick_rect(c).get_center()
			if absf(b["pos"].x - center.x) < absf(b["pos"].y - center.y):
				b["vel"].y = -b["vel"].y
				b["pos"].y = rect.position.y - BALL_R if b["vel"].y < 0 else rect.end.y + BALL_R
			else:
				b["vel"].x = -b["vel"].x
				b["pos"].x = rect.position.x - BALL_R if b["vel"].x < 0 else rect.end.x + BALL_R
			break
	# 漏球
	if b["pos"].y > 720.0 + BALL_R:
		_lives -= 1
		if _lives <= 0:
			_over = true
			status_label.text = "💀 游戏结束！最终得分 %d · R 重开" % _score
		else:
			_ball = {"pos": Vector2(640, 620), "vel": Vector2.ZERO, "stuck": true}
			status_label.text = "💔 漏球！剩余生命 %d · 点击再次发射" % _lives
	# 胜利
	if _bricks.is_empty() and not _over:
		_over = true
		status_label.text = "🏆 清空全部砖块！得分 %d · R 重开" % _score


func _process(delta: float) -> void:
	_physics_step(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_paddle_x = clampf(event.position.x, 12.0 + PADDLE_W / 2.0, 1268.0 - PADDLE_W / 2.0)
		if _ball["stuck"]:
			_ball["pos"].x = _paddle_x
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _ball["stuck"] and not _over:
			_ball["stuck"] = false
			_ball["vel"] = Vector2(randf_range(-90, 90), -460.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_build_bricks()
		queue_redraw()


func _draw() -> void:
	# 砖块
	for c in _bricks.keys():
		var rect := _brick_rect(c)
		draw_rect(rect, ROW_COLORS[c.y % ROW_COLORS.size()])
		draw_rect(rect, Color(0.1, 0.1, 0.15, 0.5), false, 2.0)
	# 挡板
	draw_rect(Rect2(_paddle_x - PADDLE_W / 2.0, 660, PADDLE_W, 16), Color(0.85, 0.85, 0.95))
	draw_rect(Rect2(_paddle_x - PADDLE_W / 2.0, 660, PADDLE_W, 16), Color(0.3, 0.32, 0.4), false, 2.0)
	# 球
	draw_circle(_ball["pos"], BALL_R, Color(1, 1, 1))
	draw_circle(_ball["pos"], BALL_R, Color(0.2, 0.2, 0.25), false, 2.0)
