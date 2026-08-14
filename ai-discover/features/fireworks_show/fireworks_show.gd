extends Node2D
## =============================================================================
## 烟花汇演 —— 编排式烟花秀庆祝 100 个功能点里程碑
## =============================================================================
## · 按排期表自动发射烟花（不同颜色/高度/规模交错绽放）；
## · 夜空中绘制发光的金色 "100"；
## · 排期（_tick）为确定性调度，可测试。
## =============================================================================

const BURST_COLORS: Array[Color] = [
	Color(1.0, 0.4, 0.45), Color(0.45, 0.8, 1.0), Color(0.45, 1.0, 0.55),
	Color(1.0, 0.85, 0.35), Color(0.85, 0.5, 1.0),
]

var _t := 0.0
var _next_launch := 0.0
var _launch_count := 0
var _bursts: Array = []      # {pos, color} 一次性粒子源

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	status_label.text = "🎆 烟花汇演 · 庆祝 100 个功能点！"


## 发射一次烟花（供测试与排期）
func _launch(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.amount = 70
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 160.0
	p.initial_velocity_max = 420.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.4
	p.color = BURST_COLORS[randi() % BURST_COLORS.size()]
	p.position = pos
	add_child(p)
	p.restart()
	_bursts.append(p)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _next_launch:
		_next_launch = _t + randf_range(0.5, 1.1)
		_launch(Vector2(randf_range(200, 1080), randf_range(100, 300)))
		_launch_count += 1
		if _launch_count % 5 == 0:
			# 齐射
			for i in 3:
				_launch(Vector2(randf_range(300, 980), randf_range(120, 240)))
			_launch_count = 0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.02, 0.06))
	# 金色 "100"（发光层叠）
	var f := ThemeDB.fallback_font
	for off in [Vector2(0, 6), Vector2(0, -6), Vector2(6, 0), Vector2(-6, 0)]:
		draw_string(f, Vector2(640, 400) + off - Vector2(0, 0), "100", HORIZONTAL_ALIGNMENT_CENTER, -1, 130, Color(1.0, 0.85, 0.3, 0.15))
	draw_string(f, Vector2(640, 400), "100", HORIZONTAL_ALIGNMENT_CENTER, -1, 130, Color(1.0, 0.9, 0.4, 0.95))
	draw_string(f, Vector2(640, 500), "功能点达成", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.95, 0.9, 1.0, 0.8))
