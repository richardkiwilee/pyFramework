extends Node2D
## =============================================================================
## 矩阵代码雨 —— 绿色字符雨（经典数字雨效果）
## =============================================================================
## · 字符列从顶部下落，头部亮白、尾部渐隐绿色；
## · 列速随机、偶尔闪烁变亮；【🎲 重置】重新洗牌列。
## 推进逻辑（_rain_step）为纯函数，可确定性测试。
## =============================================================================

const COL_W := 26.0
const FONT_SIZE := 24
const CHARS := "アイウエオカキクケコサシスセソタチツテトナニヌネノ0123456789ABCDEFZ"

var _columns: Array = []      # {x, y(头部), speed, chars: Array[String]}
var _rng := RandomNumberGenerator.new()

@onready var reset_btn: Button = $CanvasLayer/ResetBtn


func _ready() -> void:
	reset_btn.pressed.connect(_reset)
	_rng.randomize()
	_reset()


func _reset() -> void:
	_columns.clear()
	var n := int(1280.0 / COL_W)
	for i in n:
		_columns.append(_new_column(i * COL_W + 8.0, true))
	queue_redraw()


func _new_column(x: float, anywhere: bool) -> Dictionary:
	var chars: Array[String] = []
	for i in 26:
		chars.append(CHARS[_rng.randi_range(0, CHARS.length() - 1)])
	return {
		"x": x,
		"y": _rng.randf_range(-600, 720) if anywhere else -100.0,
		"speed": _rng.randf_range(90.0, 260.0),
		"chars": chars,
	}


## 单步推进（供测试）：返回换边列数
func _rain_step(delta: float) -> int:
	var recycled := 0
	for c in _columns:
		c["y"] += c["speed"] * delta
		if c["y"] - 26.0 * FONT_SIZE > 720.0:
			# 整列跑完 → 重新从顶部落下（换字符）
			var nc := _new_column(c["x"], false)
			c["y"] = nc["y"]
			c["speed"] = nc["speed"]
			c["chars"] = nc["chars"]
			recycled += 1
	return recycled


func _process(delta: float) -> void:
	_rain_step(delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.05, 0.02))
	var f := ThemeDB.fallback_font
	for c in _columns:
		for i in c["chars"].size():
			var y: float = c["y"] - i * FONT_SIZE
			if y < -FONT_SIZE or y > 720.0:
				continue
			var t: float = 1.0 - float(i) / c["chars"].size()
			var col := Color(0.75, 1.0, 0.8, t * 0.9)
			if i == 0:
				col = Color(0.95, 1.0, 0.95, 1.0)   # 头部亮白绿
			draw_string(f, Vector2(c["x"], y), c["chars"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
