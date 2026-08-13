extends Node2D
## =============================================================================
## 帕斯卡三角 —— 模 N 染色可视化（模 2 时呈现谢尔宾斯基三角形！）
## =============================================================================
## · 逐行生成帕斯卡三角（加法递推避免阶乘溢出）；
## · 每个数对模数 N 取余并按余数着色，N 可拖动滑杆调整（2~12）；
## · 行数固定 48 行，中心对齐金字塔布局。
## 行生成（_next_row）为纯函数，可确定性测试。
## =============================================================================

const ROWS := 48
const CELL := 16.0

var _rows: Array = []          # 每行 = Array[int]（已取模）
var _modulus := 2

@onready var slider: HSlider = $CanvasLayer/Slider
@onready var mod_label: Label = $CanvasLayer/ModLabel


func _ready() -> void:
	slider.min_value = 2
	slider.max_value = 12
	slider.value = 2
	slider.value_changed.connect(func(v: float) -> void:
		_modulus = int(v)
		mod_label.text = "模数 N = %d" % _modulus
		_generate()
		queue_redraw())
	_generate()
	queue_redraw()


## 下一行 = 上两数之和取模（供测试）
func _next_row(prev: Array, modulus: int) -> Array:
	var row: Array = [1]
	for i in prev.size() - 1:
		row.append((int(prev[i]) + int(prev[i + 1])) % modulus)
	row.append(1 % modulus)
	return row


func _generate() -> void:
	_rows.clear()
	var row: Array = [1 % _modulus]
	for r in ROWS:
		_rows.append(row)
		row = _next_row(row, _modulus)


## 余数 → 颜色
func _color_for(v: int) -> Color:
	var t := float(v) / maxf(1.0, float(_modulus - 1))
	return Color.from_hsv(fposmod(t * 0.72 + 0.55, 1.0), 0.75, 0.9)


func _draw() -> void:
	for r in _rows.size():
		var row: Array = _rows[r]
		var y := 60.0 + r * CELL
		var total_w := row.size() * CELL
		for c in row.size():
			var x := 640.0 - total_w / 2.0 + c * CELL
			draw_rect(Rect2(x, y, CELL - 1, CELL - 1), _color_for(int(row[c])))
