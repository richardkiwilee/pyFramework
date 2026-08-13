extends Node2D
## =============================================================================
## 弹幕躲避 —— 鼠标移动躲避弹幕，坚持 30 秒即通关
## =============================================================================
## · 弹幕从四边随机位置生成并瞄准玩家，发射频率随时间加快；
## · 被击中扣命 + 1.2 秒无敌闪烁；命尽结束，坚持 30 秒胜利；
## · R 重开。碰撞与生成逻辑（_spawn_bullet/_bullet_step）可确定性测试。
## =============================================================================

const ARENA := Rect2(100, 60, 1080, 600)
const SURVIVE_TIME := 30.0
const PLAYER_R := 14.0

var _player := ARENA.get_center()
var _bullets: Array = []      # {pos, vel, t}
var _lives := 3
var _time := 0.0
var _spawn_t := 0.0
var _invuln := 0.0
var _over := false
var _won := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false


## 从随机边发射一枚瞄准玩家的子弹（供测试）
func _spawn_bullet() -> void:
	var side := randi() % 4
	var pos := Vector2.ZERO
	match side:
		0: pos = Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.position.y)
		1: pos = Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.end.y)
		2: pos = Vector2(ARENA.position.x, randf_range(ARENA.position.y, ARENA.end.y))
		_: pos = Vector2(ARENA.end.x, randf_range(ARENA.position.y, ARENA.end.y))
	var dir := (_player - pos).normalized()
	_bullets.append({"pos": pos, "vel": dir * randf_range(170.0, 260.0), "t": 0.0})


## 单步子弹推进与命中判定（供测试）
func _bullet_step(delta: float) -> int:
	var hits := 0
	var alive: Array = []
	for b in _bullets:
		b["pos"] += b["vel"] * delta
		b["t"] += delta
		var inside := ARENA.grow(60.0).has_point(b["pos"])
		if inside and b["pos"].distance_to(_player) < PLAYER_R + 6.0:
			hits += 1   # 命中，子弹消失
		elif inside:
			alive.append(b)
	_bullets = alive
	return hits


func _process(delta: float) -> void:
	if _over:
		return
	_time += delta
	_invuln = maxf(0.0, _invuln - delta)
	# 玩家跟随鼠标
	var mouse := get_viewport().get_mouse_position()
	_player = Vector2(
		clampf(mouse.x, ARENA.position.x, ARENA.end.x),
		clampf(mouse.y, ARENA.position.y, ARENA.end.y))
	# 发射（随时间加快）
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_bullet()
		_spawn_t = maxf(0.16, 0.5 - _time * 0.012)
	# 推进 + 命中
	var hits := _bullet_step(delta)
	if hits > 0 and _invuln <= 0.0:
		_lives -= 1
		_invuln = 1.2
		if _lives <= 0:
			_over = true
			over_label.text = "💀 被击落！坚持了 %.1f 秒 · R 重开" % _time
			over_label.visible = true
	# 胜利
	if _time >= SURVIVE_TIME and not _over:
		_over = true
		_won = true
		over_label.text = "🎉 生存成功！坚持了 30 秒"
		over_label.visible = true
	status_label.text = "❤ 生命 %d · 生存 %.1f / %d 秒" % [_lives, _time, SURVIVE_TIME]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _over and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()


func _draw() -> void:
	# 竞技场
	draw_rect(ARENA, Color(0.06, 0.07, 0.11))
	draw_rect(ARENA, Color(0.4, 0.45, 0.6), false, 3.0)
	# 子弹（发光圆点）
	for b in _bullets:
		draw_circle(b["pos"], 7, Color(1.0, 0.35, 0.45, 0.4))
		draw_circle(b["pos"], 4, Color(1.0, 0.6, 0.7))
	# 玩家（无敌时闪烁）
	var blink := 0.4 + 0.6 * absf(sin(_invuln * 10.0)) if _invuln > 0.0 else 1.0
	draw_circle(_player, PLAYER_R, Color(0.4, 0.85, 1.0, blink))
	draw_circle(_player, PLAYER_R, Color(0.8, 1.0, 1.0, blink), false, 2.0)
	draw_circle(_player, 5, Color(1, 1, 1, blink))
