extends Node2D
## =============================================================================
## 程序化云朵 —— 重叠圆团云 + 多层视差漂移
## =============================================================================
## · 每朵云 = 6~10 个随机重叠圆（自动形成蓬松剪影），底部叠加深色圆
##   做出体积阴影；
## · 三层视差（远慢近快），飘出屏幕后从另一侧循环进入；
## · 【🎲 重新生成】换随机布局。
## 生成与漂移（_gen_clouds/_drift_step）为纯函数，可确定性测试。
## =============================================================================

const LAYER_PARAMS := [
	{"count": 6, "speed": 14.0, "scale": 0.55, "alpha": 0.5},
	{"count": 5, "speed": 26.0, "scale": 0.85, "alpha": 0.7},
	{"count": 4, "speed": 44.0, "scale": 1.2, "alpha": 0.9},
]

var _clouds: Array = []     # {x, y, speed, scale, alpha, circles: [{dx, dy, r}]}

@onready var regen_btn: Button = $CanvasLayer/RegenBtn


func _ready() -> void:
	regen_btn.pressed.connect(_gen_clouds)
	_gen_clouds()


## 生成所有云（供测试）
func _gen_clouds() -> void:
	_clouds.clear()
	for layer in LAYER_PARAMS:
		for i in layer["count"]:
			_clouds.append(_make_cloud(layer))
	queue_redraw()


func _make_cloud(layer: Dictionary) -> Dictionary:
	var circles: Array = []
	var n := randi() % 5 + 6
	for i in n:
		circles.append({
			"dx": randf_range(-70, 70),
			"dy": randf_range(-18, 16),
			"r": randf_range(26, 58),
		})
	return {
		"x": randf_range(-80, 1360),
		"y": randf_range(60, 380),
		"speed": layer["speed"],
		"scale": layer["scale"],
		"alpha": layer["alpha"],
		"circles": circles,
	}


## 漂移推进（供测试）：返回换边数量
func _drift_step(delta: float) -> int:
	var wrapped := 0
	for c in _clouds:
		c["x"] += c["speed"] * delta
		if c["x"] > 1280.0 + 160.0:
			c["x"] = -160.0
			c["y"] = randf_range(60, 380)
			wrapped += 1
	return wrapped


func _process(delta: float) -> void:
	_drift_step(delta)
	queue_redraw()


func _draw() -> void:
	# 渐变天空
	for i in 24:
		var t := float(i) / 24.0
		draw_rect(Rect2(0, i * 30, 1280, 30), Color(0.3, 0.5, 0.75).lerp(Color(0.75, 0.85, 0.95), t))
	# 太阳
	draw_circle(Vector2(1080, 100), 42, Color(1.0, 0.95, 0.7, 0.95))
	draw_circle(Vector2(1080, 100), 60, Color(1.0, 0.9, 0.5, 0.25))
	# 云（先浅后深排序：按 y 画即可）
	for c in _clouds:
		var base := Color(0.98, 0.98, 1.0, c["alpha"])
		var shade := Color(0.72, 0.76, 0.85, c["alpha"])
		for ci in c["circles"]:
			var p := Vector2(c["x"] + ci["dx"], c["y"] + ci["dy"]) * 1.0
			var r: float = ci["r"] * c["scale"]
			draw_circle(p, r, base)
			draw_circle(p + Vector2(0, r * 0.28), r * 0.92, shade)
