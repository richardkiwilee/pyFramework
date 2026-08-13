extends Node2D
## =============================================================================
## 传送带物流 —— 折线传送带把物品运到收集篮
## =============================================================================
## · L 形传送带（折线路径），带面绘制流动的箭头刻线表示方向；
## · 点击任意位置投料，物品沿折线匀速前进（自动投料每 1.2 秒一次）；
## · 到终点落入收集篮：物品淡出 + 计数 +1。
## 物品在折线上按"累计距离"参数化推进，拐弯自然。
## =============================================================================

const PATH: Array[Vector2] = [
	Vector2(120, 560), Vector2(580, 560), Vector2(580, 200), Vector2(1090, 200),
]
const BELT_SPEED := 150.0
const ITEM_COLORS: Array[Color] = [
	Color(0.95, 0.5, 0.3), Color(0.4, 0.8, 0.5), Color(0.45, 0.6, 1.0),
	Color(0.95, 0.85, 0.3), Color(0.8, 0.5, 0.95),
]

var _items: Array = []       # {dist, speed, color, t}
var _collected := 0
var _spawn_timer := 0.0
var _segs: Array = []        # {start, dir, len}
var _total_len := 0.0

@onready var count_label: Label = $CanvasLayer/CountLabel


func _ready() -> void:
	for i in PATH.size() - 1:
		var dir := PATH[i + 1] - PATH[i]
		_segs.append({"start": PATH[i], "dir": dir.normalized(), "len": dir.length()})
		_total_len += dir.length()


func _process(delta: float) -> void:
	# 物品前进
	for item in _items:
		item["dist"] += item["speed"] * delta
	# 到达终点 → 收集
	var done := 0
	for item in _items:
		if item["dist"] >= _total_len:
			_collected += 1
			done += 1
			count_label.text = "🧺 已收集：%d" % _collected
	if done > 0:
		var alive: Array = []
		for item in _items:
			if item["dist"] < _total_len:
				alive.append(item)
		_items = alive
	# 自动投料
	_spawn_timer += delta
	if _spawn_timer >= 1.2:
		_spawn_timer = 0.0
		_spawn_item()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn_item()
		get_viewport().set_input_as_handled()


func _spawn_item() -> void:
	_items.append({
		"dist": 0.0,
		"speed": BELT_SPEED * randf_range(0.9, 1.25),
		"color": ITEM_COLORS[randi() % ITEM_COLORS.size()],
	})


## 累计距离 → 折线上的点
func _point_at(dist: float) -> Vector2:
	var d := dist
	for seg in _segs:
		if d <= seg["len"]:
			return seg["start"] + seg["dir"] * d
		d -= seg["len"]
	return PATH[PATH.size() - 1]


func _draw() -> void:
	# 传送带带面 + 流动箭头刻线
	for seg in _segs:
		var a: Vector2 = seg["start"]
		var b: Vector2 = a + seg["dir"] * seg["len"]
		draw_line(a, b, Color(0.22, 0.24, 0.30), 34.0)
		draw_line(a, b, Color(0.32, 0.36, 0.46), 30.0)
		# 箭头刻线（随时间沿方向流动）
		var offset := fposmod(Time.get_ticks_msec() / 1000.0 * BELT_SPEED, 44.0)
		var d := offset
		while d < seg["len"]:
			var p: Vector2 = a + seg["dir"] * d
			var n: Vector2 = Vector2(-seg["dir"].y, seg["dir"].x)
			draw_line(p - n * 11.0, p + n * 11.0, Color(0.55, 0.6, 0.72, 0.8), 3.0)
			d += 44.0

	# 收集篮（终点）
	var end := PATH[PATH.size() - 1]
	draw_rect(Rect2(end + Vector2(10, -26), Vector2(52, 52)), Color(0.55, 0.4, 0.25))
	draw_rect(Rect2(end + Vector2(10, -26), Vector2(52, 52)), Color(0.2, 0.15, 0.1), false, 3.0)

	# 物品
	for item in _items:
		var p := _point_at(item["dist"])
		draw_rect(Rect2(p - Vector2(13, 13), Vector2(26, 26)), item["color"])
		draw_rect(Rect2(p - Vector2(13, 13), Vector2(26, 26)), Color(1, 1, 1, 0.7), false, 2.0)
