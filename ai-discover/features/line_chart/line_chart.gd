extends Control
## =============================================================================
## 折线图 —— 坐标轴/网格/数据折线/数据点/悬停取值（数据可视化组件）
## =============================================================================
## · 【🎲 随机数据】生成 12 点随机序列并连线；
## · 悬停显示最近数据点的数值；
## · 坐标映射（_to_screen）为纯函数，可确定性测试。
## =============================================================================

const CHART := Rect2(180, 100, 900, 480)
const MARGIN_X := 60.0
const MARGIN_Y := 46.0

var _data: Array = []       # 0..1 值序列
var _hover := -1

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/RandomBtn.pressed.connect(_randomize)
	_randomize()


func _randomize() -> void:
	_data.clear()
	for i in 12:
		_data.append(randf_range(0.08, 0.92))
	status_label.text = "📈 数据点：%d" % _data.size()
	queue_redraw()


## 数据点下标/值 → 屏幕坐标（供绘制与测试）
func _to_screen(i: int, v: float) -> Vector2:
	var x := CHART.position.x + MARGIN_X + float(i) / maxf(1.0, _data.size() - 1) * (CHART.size.x - MARGIN_X * 2.0)
	var y := CHART.end.y - MARGIN_Y - v * (CHART.size.y - MARGIN_Y * 2.0)
	return Vector2(x, y)


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = -1
		for i in _data.size():
			if _to_screen(i, _data[i]).distance_to(event.position) < 22.0:
				_hover = i
				break
		if _hover >= 0:
			status_label.text = "📈 点 %d · 值 %.2f" % [_hover + 1, _data[_hover]]


func _draw() -> void:
	# 图表底
	draw_rect(CHART, Color(0.10, 0.11, 0.16))
	# 网格
	for i in 5:
		var t := float(i) / 4.0
		var y := CHART.position.y + t * CHART.size.y
		draw_line(Vector2(CHART.position.x, y), Vector2(CHART.end.x, y), Color(0.25, 0.27, 0.34, 0.6), 1.0)
		var x := CHART.position.x + t * CHART.size.x
		draw_line(Vector2(x, CHART.position.y), Vector2(x, CHART.end.y), Color(0.25, 0.27, 0.34, 0.6), 1.0)
	# 坐标轴
	draw_line(Vector2(CHART.position.x, CHART.end.y), CHART.end, Color(0.5, 0.55, 0.7), 2.5)
	draw_line(CHART.position, Vector2(CHART.position.x, CHART.end.y), Color(0.5, 0.55, 0.7), 2.5)
	# 折线
	if _data.size() > 1:
		var pts := PackedVector2Array()
		for i in _data.size():
			pts.append(_to_screen(i, _data[i]))
		draw_polyline(pts, Color(0.35, 0.8, 0.95), 3.0)
	# 数据点
	for i in _data.size():
		var p := _to_screen(i, _data[i])
		draw_circle(p, 6 if i == _hover else 4, Color(0.95, 0.85, 0.4) if i == _hover else Color(0.4, 0.85, 0.95))
