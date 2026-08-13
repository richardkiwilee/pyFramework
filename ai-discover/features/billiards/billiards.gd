extends Node2D
## =============================================================================
## 台球 —— 瞄准射击、等质量弹性碰撞、库边反弹、球袋落袋
## =============================================================================
## · 移动鼠标瞄准（虚线），点击击球（固定力度）；
## · 球球碰撞 = 等质量完全弹性（交换法向速度分量）；库边反弹带损耗；
## · 六球袋：彩球落袋消失计分，母球落袋重新摆回开球点；
## · 全部彩球落袋 → 胜利结算。
## 物理步进（_physics_step）纯函数式，可确定性测试。
## =============================================================================

const TABLE := Rect2(140, 100, 1000, 520)
const BALL_R := 14.0
const SHOT_SPEED := 620.0
const CUE_START := Vector2(400, 360)

const BALL_COLORS: Array[Color] = [
	Color(0.9, 0.85, 0.2), Color(0.3, 0.5, 0.95), Color(0.9, 0.3, 0.3),
	Color(0.5, 0.3, 0.9), Color(0.95, 0.6, 0.2), Color(0.3, 0.75, 0.45),
	Color(0.6, 0.3, 0.4), Color(0.35, 0.35, 0.4), Color(0.9, 0.75, 0.5),
	Color(0.5, 0.7, 0.9),
]

var _balls: Array = []      # {pos, vel, color, active, cue}
var _pockets: Array[Vector2] = []
var _potted := 0
var _aim := Vector2(1, 0)
var _won := false

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	_pockets = [
		TABLE.position + Vector2(0, 0), TABLE.position + Vector2(TABLE.size.x / 2, -14),
		TABLE.position + Vector2(TABLE.size.x, 0),
		TABLE.position + Vector2(0, TABLE.size.y), TABLE.position + Vector2(TABLE.size.x / 2, TABLE.size.y + 14),
		TABLE.position + TABLE.size,
	]
	_rack()
	queue_redraw()


func _rack() -> void:
	_balls.clear()
	_balls.append({"pos": CUE_START, "vel": Vector2.ZERO, "color": Color(0.95, 0.95, 0.9), "active": true, "cue": true})
	var idx := 0
	for row in 4:
		for i in row + 1:
			_balls.append({
				"pos": Vector2(880, 360) + Vector2(row * 28.0, (i - row * 0.5) * 30.0),
				"vel": Vector2.ZERO,
				"color": BALL_COLORS[idx],
				"active": true,
				"cue": false,
			})
			idx += 1
	_potted = 0
	_won = false


## 单步物理（供测试）
func _physics_step(delta: float) -> void:
	var active: Array = []
	for b in _balls:
		if b["active"]:
			active.append(b)
	# 球球碰撞（等质量弹性：交换法向速度）
	for i in active.size():
		for j in range(i + 1, active.size()):
			var a: Dictionary = active[i]
			var b: Dictionary = active[j]
			var diff: Vector2 = b["pos"] - a["pos"]
			var d := diff.length()
			if d < BALL_R * 2.0 and d > 0.001:
				var n := diff / d
				var overlap := BALL_R * 2.0 - d
				a["pos"] -= n * overlap * 0.5
				b["pos"] += n * overlap * 0.5
				var rel: float = (a["vel"] - b["vel"]).dot(n)
				if rel > 0:
					a["vel"] -= n * rel
					b["vel"] += n * rel
			elif d <= 0.001:
				b["pos"] += Vector2(BALL_R, 0)
	# 移动 + 摩擦 + 库边
	for b in active:
		b["pos"] += b["vel"] * delta
		b["vel"] *= 0.992
		if b["pos"].x < TABLE.position.x + BALL_R:
			b["pos"].x = TABLE.position.x + BALL_R
			b["vel"].x = -b["vel"].x * 0.88
		if b["pos"].x > TABLE.end.x - BALL_R:
			b["pos"].x = TABLE.end.x - BALL_R
			b["vel"].x = -b["vel"].x * 0.88
		if b["pos"].y < TABLE.position.y + BALL_R:
			b["pos"].y = TABLE.position.y + BALL_R
			b["vel"].y = -b["vel"].y * 0.88
		if b["pos"].y > TABLE.end.y - BALL_R:
			b["pos"].y = TABLE.end.y - BALL_R
			b["vel"].y = -b["vel"].y * 0.88
		# 球袋
		for p in _pockets:
			if b["pos"].distance_to(p) < 26.0:
				b["active"] = false
				b["vel"] = Vector2.ZERO
				if b["cue"]:
					# 母球落袋：摆回开球点
					b["pos"] = CUE_START
					b["active"] = true
				else:
					_potted += 1
					status_label.text = "🎱 已落袋：%d / 10" % _potted
				break
	# 胜利
	if _potted >= 10 and not _won:
		_won = true
		status_label.text = "🏆 全部清台！点击【重新摆球】再来一局"


func _process(delta: float) -> void:
	_physics_step(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cue: Dictionary = _balls[0]
		_aim = (event.position - cue["pos"]).normalized()
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cue: Dictionary = _balls[0]
		if cue["active"] and cue["vel"].length() < 5.0:
			_aim = (event.position - cue["pos"]).normalized()
			cue["vel"] = _aim * SHOT_SPEED
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_rack()
		queue_redraw()


func _draw() -> void:
	# 台面
	draw_rect(TABLE, Color(0.16, 0.42, 0.26))
	draw_rect(TABLE, Color(0.08, 0.2, 0.12), false, 10.0)
	# 球袋
	for p in _pockets:
		draw_circle(p, 22, Color(0.05, 0.05, 0.08))
	# 瞄准线（母球静止时）
	var cue: Dictionary = _balls[0]
	if cue["active"] and cue["vel"].length() < 5.0:
		draw_line(cue["pos"], cue["pos"] + _aim * 260.0, Color(1, 1, 1, 0.55), 2.0)
		draw_circle(cue["pos"] + _aim * 260.0, 5, Color(1, 1, 1, 0.7))
	# 球
	for b in _balls:
		if b["active"]:
			draw_circle(b["pos"], BALL_R, b["color"])
			draw_circle(b["pos"] + Vector2(-4, -5), 4, Color(1, 1, 1, 0.55))
