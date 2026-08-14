extends Node2D
## =============================================================================
## 弹簧床 —— 小球重力弹跳：触床反弹 + 挤压形变 + 最高点记录
## =============================================================================
## · 小球自由落体，撞到弹簧床按恢复系数反弹（能量损耗后越跳越低）；
## · 触床瞬间小球压扁、离床拉长（scale 弹性动画）；
## · 记录并显示历史最高点；【🎲 重抛】从随机位置再落下。
## 物理步进（_bounce_step）为纯函数，可确定性测试。
## =============================================================================

const TRAMP_Y := 600.0
const BALL_R := 16.0
const GRAVITY := 900.0
const RESTITUTION := 0.82

var _ball: Dictionary = {"pos": Vector2(640, 80), "vel": Vector2(0, 0)}
var _max_h := 80.0
var _squash := 0.0    # >0 时压扁，<0 时拉长

@onready var height_label: Label = $CanvasLayer/HeightLabel


func _ready() -> void:
	$CanvasLayer/RedropBtn.pressed.connect(_redrop)
	_refresh_label()


func _redrop() -> void:
	_ball = {"pos": Vector2(randf_range(300, 980), randf_range(60, 200)), "vel": Vector2(0, 0)}
	_max_h = _ball["pos"].y
	_refresh_label()


## 单步物理（供测试）：返回本次是否触床
func _bounce_step(delta: float) -> bool:
	_ball["vel"].y += GRAVITY * delta
	_ball["pos"] += _ball["vel"] * delta
	var bounced := false
	if _ball["pos"].y > TRAMP_Y - BALL_R:
		_ball["pos"].y = TRAMP_Y - BALL_R
		_ball["vel"].y = -absf(_ball["vel"].y) * RESTITUTION
		_squash = 0.12
		bounced = true
	_max_h = minf(_max_h, _ball["pos"].y)
	return bounced


func _process(delta: float) -> void:
	_bounce_step(delta)
	# 形变衰减
	_squash = lerpf(_squash, 0.0, delta * 8.0)
	_refresh_label()
	queue_redraw()


func _refresh_label() -> void:
	height_label.text = "🎯 最高点：%.0f px（当前 %.0f）" % [_max_h, _ball["pos"].y]


func _draw() -> void:
	# 弹簧床
	draw_line(Vector2(480, TRAMP_Y), Vector2(800, TRAMP_Y), Color(0.85, 0.8, 0.9), 6.0)
	for i in 8:
		var x := 480.0 + i * 40.0
		draw_line(Vector2(x, TRAMP_Y), Vector2(x, TRAMP_Y + 26), Color(0.6, 0.58, 0.7), 4.0)
	draw_line(Vector2(480, TRAMP_Y + 26), Vector2(800, TRAMP_Y + 26), Color(0.45, 0.44, 0.55), 5.0)
	# 小球（带形变）
	var p: Vector2 = _ball["pos"]
	var sx := 1.0 - _squash * 1.4
	var sy := 1.0 + _squash * 1.4
	draw_set_transform(p, 0.0, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, BALL_R, Color(0.95, 0.5, 0.3))
	draw_circle(Vector2(-5, -6), 5, Color(1, 1, 1, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
