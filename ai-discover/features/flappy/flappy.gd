extends Node2D
## =============================================================================
## 像素小鸟 —— 点击/空格拍翼，穿过管道间隙得分
## =============================================================================
## · 小鸟受重力下坠，点击/空格向上拍翼；
## · 管道从右向左移动，随机开口高度；穿过一组 +1 分；
## · 撞管道/地面 → 结束，R 重开。
## 物理与判定（_flap/_step/_collide）为纯函数，可确定性测试。
## =============================================================================

const GRAVITY := 900.0
const FLAP_V := -330.0
const PIPE_SPEED := 190.0
const PIPE_W := 70.0
const GAP_H := 170.0
const BIRD_R := 15.0
const GROUND_Y := 620.0

var _bird: Dictionary = {"pos": Vector2(300, 300), "vel": 0.0}
var _pipes: Array = []      # {x, gap_y, scored}
var _score := 0
var _over := false
var _spawn_t := 0.0

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false
	status_label.text = "🐤 点击/空格拍翼 · 穿过管道得分"


func _flap() -> void:
	if _over:
		return
	_bird["vel"] = FLAP_V


## 单步推进（供测试）：返回是否死亡
func _step(delta: float) -> bool:
	_bird["vel"] += GRAVITY * delta
	_bird["pos"].y += _bird["vel"] * delta
	# 撞地
	if _bird["pos"].y > GROUND_Y:
		return true
	# 管道推进
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 1.6
		_pipes.append({"x": 1320.0, "gap_y": randf_range(140, GROUND_Y - GAP_H - 60), "scored": false})
	for p in _pipes:
		p["x"] -= PIPE_SPEED * delta
	# 碰撞
	for p in _pipes:
		var in_x: bool = _bird["pos"].x + BIRD_R > p["x"] and _bird["pos"].x - BIRD_R < p["x"] + PIPE_W
		if in_x and (_bird["pos"].y - BIRD_R < p["gap_y"] or _bird["pos"].y + BIRD_R > p["gap_y"] + GAP_H):
			return true
	# 计分 + 清理
	var alive: Array = []
	for p in _pipes:
		if not p["scored"] and p["x"] + PIPE_W < _bird["pos"].x - BIRD_R:
			p["scored"] = true
			_score += 1
			status_label.text = "🐤 得分：%d" % _score
		if p["x"] + PIPE_W > -40.0:
			alive.append(p)
	_pipes = alive
	return false


func _process(delta: float) -> void:
	if _over:
		return
	if _step(delta):
		_over = true
		over_label.text = "💀 撞了！得分 %d · R 重开" % _score
		over_label.visible = true
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_flap()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 天空与地面
	draw_rect(Rect2(0, 0, 1280, GROUND_Y), Color(0.45, 0.7, 0.9))
	draw_rect(Rect2(0, GROUND_Y, 1280, 100), Color(0.3, 0.5, 0.25))
	# 管道（上下两段）
	for p in _pipes:
		draw_rect(Rect2(p["x"], 0, PIPE_W, p["gap_y"]), Color(0.25, 0.55, 0.3))
		draw_rect(Rect2(p["x"], p["gap_y"] + GAP_H, PIPE_W, GROUND_Y - p["gap_y"] - GAP_H), Color(0.25, 0.55, 0.3))
	# 小鸟
	var bp: Vector2 = _bird["pos"]
	draw_circle(bp, BIRD_R, Color(1, 0.85, 0.3))
	draw_circle(bp + Vector2(6, -4), 4, Color(0.1, 0.1, 0.1))
	draw_circle(bp + Vector2(9, -6), 3, Color(0.95, 0.95, 0.9))
	# 翅膀（随速度扇动）
	var wing := 6.0 + clampf(-_bird["vel"] * 0.02, -4.0, 10.0)
	draw_circle(bp + Vector2(-8, 3 - wing), 6, Color(0.95, 0.7, 0.2))
