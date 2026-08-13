extends Node2D
## =============================================================================
## 分形树 —— 递归分支 + 随机生长 + 风吹摆动
## =============================================================================
## · 树干在底部，每层分 2~3 枝、长度衰减、夹角随机；
## · 【🎲 重新生长】换随机种子生成新树；【🍃 风吹】开启枝条摆动；
## · 枝条层级越深越细、颜色从深棕渐变到叶绿；
## · 线段生成（_generate_branches）为纯函数，可确定性测试。
## =============================================================================

const MAX_DEPTH := 9

var _branches: Array = []      # {a, b, depth}
var _wind := true
var _t := 0.0

@onready var wind_btn: Button = $CanvasLayer/Bar/WindBtn


func _ready() -> void:
	$CanvasLayer/Bar/GrowBtn.pressed.connect(_grow)
	wind_btn.pressed.connect(_toggle_wind)
	_grow()


func _grow() -> void:
	_branches.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	_generate_branches(Vector2(640, 700), Vector2(0, -1), 130.0, 0, rng, MAX_DEPTH)
	queue_redraw()


## 递归生成枝条（纯函数式）
func _generate_branches(origin: Vector2, dir: Vector2, length: float, depth: int, rng: RandomNumberGenerator, max_depth: int) -> void:
	var end := origin + dir * length
	_branches.append({"a": origin, "b": end, "depth": depth})
	if depth >= max_depth or length < 10.0:
		return
	var child_len := length * rng.randf_range(0.68, 0.78)
	var spread := rng.randf_range(0.32, 0.5)
	var count := 3 if depth < 2 else 2
	for i in count:
		var t := -0.5 + float(i) / float(count - 1)   # -0.5..0.5
		var child_dir := dir.rotated(t * spread + rng.randf_range(-0.06, 0.06))
		_generate_branches(end, child_dir, child_len, depth + 1, rng, max_depth)


func _toggle_wind() -> void:
	_wind = not _wind
	wind_btn.text = "🍃 风：开" if _wind else "🍃 风：关"


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 640, 1280, 80), Color(0.14, 0.17, 0.10))
	for b in _branches:
		var depth: int = b["depth"]
		var f := 1.0 - float(depth) / (MAX_DEPTH + 1.0)
		var sway := 0.0
		if _wind:
			sway = sin(_t * 1.6 + depth * 0.8) * 3.0 * float(depth)
		var tip: Vector2 = b["b"] + Vector2(sway, 0)
		var col: Color = Color(0.35, 0.24, 0.14).lerp(Color(0.3, 0.65, 0.3), 1.0 - f)
		draw_line(b["a"], tip, col, 1.5 + 7.0 * f)
		# 最深层画叶子
		if depth >= MAX_DEPTH:
			draw_circle(tip, 5.0, Color(0.35, 0.75, 0.4, 0.9))
