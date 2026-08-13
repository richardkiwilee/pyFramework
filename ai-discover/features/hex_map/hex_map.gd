extends Node2D
## =============================================================================
## 六边形地图 —— 轴向坐标网格 + 地形噪声 + Dijkstra 寻路
## =============================================================================
## 交互：
##   悬停       查看格子信息（右上角）+ 白色描边
##   左键       第一次点击设起点（蓝色），再点击设终点并自动寻路（橙色路径）
##              同时显示起点周围 4 步移动范围（浅蓝）
##   右键       把格子变成水域障碍 / 取消障碍
##
## 六边形使用轴向坐标 (q, r)，6 个邻接方向；高度由 value noise 生成，
## 移动代价 = 1 + 高度差（爬山更费力），用 Dijkstra 求最短路径。
## =============================================================================

const HEX_SIZE := 34.0          # 六边形中心到顶点的距离
const RADIUS := 5               # 地图半径（中心往外 5 圈）
const SQRT3 := 1.7320508
const ORIGIN := Vector2(390, 330)

const HEX_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, -1), Vector2i(-1, 1),
]

const HEIGHT_COLORS := [
	Color("#d8c07a"),   # 0 沙滩
	Color("#7ab648"),   # 1 草地
	Color("#3e8f3e"),   # 2 森林
	Color("#8a7f72"),   # 3 岩石
	Color("#e8e4da"),   # 4 雪顶
]

var _start := Vector2i(-999, -999)
var _goal := Vector2i(-999, -999)
var _path: Array = []
var _range: Array = []
var _hover := Vector2i(-999, -999)
var _obstacles: Dictionary = {}   # Vector2i → true（水域）

var _info_label: Label
var _hint_label: Label


func _ready() -> void:
	# HUD（代码构建，保持场景文件精简）
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(880, 16)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "⬡ 六边形地图"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	_info_label = Label.new()
	_info_label.text = "左键选起点/终点 · 右键画水域 · 移动代价 1+高度差"
	_info_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_info_label)
	layer.add_child(panel)

	_hint_label = Label.new()
	_hint_label.position = Vector2(16, 690)
	_hint_label.add_theme_font_size_override("font_size", 14)
	layer.add_child(_hint_label)
	queue_redraw()


# ============================================================
#  坐标工具
# ============================================================
func _hex_center(q: int, r: int) -> Vector2:
	return Vector2(HEX_SIZE * SQRT3 * (q + r * 0.5), HEX_SIZE * 1.5 * r) + ORIGIN


func _hex_corners(center: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU / 6.0 * (i + 0.5)   # 尖顶朝向（pointy-top）
		pts.append(center + Vector2(cos(a), sin(a)) * HEX_SIZE)
	return pts


func _in_grid(h: Vector2i) -> bool:
	return maxi(maxi(absi(h.x), absi(h.y)), absi(h.x + h.y)) <= RADIUS


func _neighbors(h: Vector2i) -> Array:
	var out: Array = []
	for d in HEX_DIRS:
		var nb := h + d
		if _in_grid(nb):
			out.append(nb)
	return out


## 像素 → 轴向坐标（cube 坐标四舍五入）
func _pixel_to_hex(p: Vector2) -> Vector2i:
	var lp := (p - ORIGIN) / HEX_SIZE
	var fr := lp.y / 1.5
	var fq := lp.x / SQRT3 - fr * 0.5
	var fx := fq
	var fz := fr
	var fy := -fx - fz
	var rx: float = round(fx)
	var ry: float = round(fy)
	var rz: float = round(fz)
	var dx := absf(rx - fx)
	var dy := absf(ry - fy)
	var dz := absf(rz - fz)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


# ============================================================
#  地形噪声（value noise）
# ============================================================
func _hash2(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n & 0x7fffffff) % 1000) / 1000.0


func _vnoise(x: float, y: float) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - xi
	var yf := y - yi
	xf = xf * xf * (3.0 - 2.0 * xf)
	yf = yf * yf * (3.0 - 2.0 * yf)
	return lerp(
		lerp(_hash2(xi, yi), _hash2(xi + 1, yi), xf),
		lerp(_hash2(xi, yi + 1), _hash2(xi + 1, yi + 1), xf),
		yf)


func _height_at(q: int, r: int) -> int:
	return int(_vnoise(q * 0.45 + 7.3, r * 0.45 + 3.1) * 5.0)


# ============================================================
#  Dijkstra 寻路（代价 1 + |高度差|）
# ============================================================
func _step_cost(a: Vector2i, b: Vector2i) -> int:
	return 1 + absi(_height_at(a.x, a.y) - _height_at(b.x, b.y))


## 返回 起点 → 终点 的格子序列（含两端）；无路返回空
func _find_path(start: Vector2i, goal: Vector2i) -> Array:
	var dist := {start: 0}
	var prev := {}
	var pq: Array = [start]   # 小地图用朴素数组做优先队列足够快
	while not pq.is_empty():
		var best_i := 0
		for i in pq.size():
			if dist[pq[i]] < dist[pq[best_i]]:
				best_i = i
		var cur: Vector2i = pq[best_i]
		pq.remove_at(best_i)
		if cur == goal:
			break
		for nb in _neighbors(cur):
			if _obstacles.has(nb):
				continue
			var nd: int = dist[cur] + _step_cost(cur, nb)
			if not dist.has(nb) or nd < dist[nb]:
				dist[nb] = nd
				prev[nb] = cur
				if not pq.has(nb):
					pq.append(nb)
	if not prev.has(goal) and goal != start:
		return []
	var path: Array = [goal]
	while path[0] != start:
		path.push_front(prev[path[0]])
	return path


## 起点周围 4 步移动范围
func _compute_range(start: Vector2i) -> Array:
	var dist := {start: 0}
	var pq: Array = [start]
	var out: Array = []
	while not pq.is_empty():
		var best_i := 0
		for i in pq.size():
			if dist[pq[i]] < dist[pq[best_i]]:
				best_i = i
		var cur: Vector2i = pq[best_i]
		pq.remove_at(best_i)
		if dist[cur] > 4:
			break
		if cur != start:
			out.append(cur)
		for nb in _neighbors(cur):
			if _obstacles.has(nb):
				continue
			var nd: int = dist[cur] + _step_cost(cur, nb)
			if nd <= 4 and (not dist.has(nb) or nd < dist[nb]):
				dist[nb] = nd
				if not pq.has(nb):
					pq.append(nb)
	return out


# ============================================================
#  交互
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _pixel_to_hex(event.position)
		_refresh_info()
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var h := _pixel_to_hex(event.position)
		if not _in_grid(h):
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键：水域障碍开关
			if _obstacles.has(h):
				_obstacles.erase(h)
			else:
				_obstacles[h] = true
				if h == _start:
					_start = Vector2i(-999, -999)
				if h == _goal:
					_goal = Vector2i(-999, -999)
			_path.clear()
			_range.clear()
			if _start.x > -900:
				_range = _compute_range(_start)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _obstacles.has(h):
				return
			if _start.x < -900:
				_start = h
				_range = _compute_range(_start)
			elif h == _start:
				# 再点起点 = 全部清除
				_start = Vector2i(-999, -999)
				_goal = Vector2i(-999, -999)
				_path.clear()
				_range.clear()
			else:
				_goal = h
				_path = _find_path(_start, _goal)
			_refresh_info()
			queue_redraw()


func _refresh_info() -> void:
	if _in_grid(_hover):
		var h := _hover
		var txt := "格子 (%d, %d)\n高度: %d" % [h.x, h.y, _height_at(h.x, h.y)]
		if _obstacles.has(h):
			txt += "\n类型: 🌊 水域(障碍)"
		else:
			txt += "\n类型: 陆地"
		if _path.size() > 1:
			txt += "\n路径长度: %d 步" % (_path.size() - 1)
		_info_label.text = txt
	_hint_label.text = "左键: 起点/终点寻路 · 右键: 水域障碍 · 再点起点清除 · 代价=1+高度差"


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	for q in range(-RADIUS, RADIUS + 1):
		for r in range(-RADIUS, RADIUS + 1):
			var h := Vector2i(q, r)
			if not _in_grid(h):
				continue
			var c := _hex_center(q, r)
			var pts := _hex_corners(c)
			if _obstacles.has(h):
				draw_colored_polygon(pts, Color("#2a6fb0"))          # 水域
			else:
				draw_colored_polygon(pts, HEIGHT_COLORS[_height_at(q, r)])
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.05, 0.06, 0.09, 0.55), 1.5)

	# 移动范围（浅蓝）
	for h in _range:
		draw_colored_polygon(_hex_corners(_hex_center(h.x, h.y)), Color(0.35, 0.6, 1.0, 0.35))

	# 路径（橙色线 + 端点）
	if _path.size() > 1:
		var line := PackedVector2Array()
		for h in _path:
			line.append(_hex_center(h.x, h.y))
		draw_polyline(line, Color(1.0, 0.55, 0.15, 0.95), 6.0)
		for h in _path:
			draw_circle(_hex_center(h.x, h.y), 4.5, Color(1.0, 0.7, 0.25))

	# 起点 / 终点标记
	if _start.x > -900:
		_draw_ring(_hex_center(_start.x, _start.y), Color(0.3, 0.6, 1.0))
	if _goal.x > -900:
		_draw_ring(_hex_center(_goal.x, _goal.y), Color(1.0, 0.25, 0.2))

	# 悬停描边
	if _in_grid(_hover):
		var pts := _hex_corners(_hex_center(_hover.x, _hover.y))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.9), 2.5)


func _draw_ring(center: Vector2, color: Color) -> void:
	draw_arc(center, 13.0, 0, TAU, 40, color, 5.0)
