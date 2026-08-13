extends Node2D
## =============================================================================
## 迷宫生成 —— 递归回溯(DFS)完美迷宫 + BFS 解法
## =============================================================================
## · 【🎲 生成】用深度优先回溯雕刻"完美迷宫"（任意两格间恰一条通路）；
## · 【🔦 解法】BFS 求 (0,0) → 右下角 的最短路径并画出；
## · 完美迷宫性质 = 生成树：全连通、无环路，可确定性测试。
## =============================================================================

const W := 21
const H := 15
const CELL := 34.0
const ORIGIN := Vector2(280, 60)

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _walls_h: Dictionary = {}   # (x,y) → 该格下方水平墙
var _walls_v: Dictionary = {}   # (x,y) → 该格右方垂直墙
var _solution: Array = []

@onready var status_label: Label = $CanvasLayer/Bar/StatusLabel


func _ready() -> void:
	$CanvasLayer/Bar/GenBtn.pressed.connect(_generate)
	$CanvasLayer/Bar/SolveBtn.pressed.connect(_solve)
	_generate()
	queue_redraw()


## 初始化：全墙
func _init_walls() -> void:
	_walls_h.clear()
	_walls_v.clear()
	for y in H:
		for x in W:
			_walls_h[Vector2i(x, y)] = true
			_walls_v[Vector2i(x, y)] = true


## 递归回溯生成（迭代栈实现），返回访问顺序（用于测试）
func _carve() -> Array:
	var visited: Dictionary = {}
	var order: Array = []
	var stack: Array = [Vector2i(0, 0)]
	visited[Vector2i(0, 0)] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		order.append(cur)
		# 随机洗牌的方向里找未访问邻居
		var dirs: Array[Vector2i] = DIRS4.duplicate()
		dirs.shuffle()
		var carved := false
		for d in dirs:
			var nb := cur + d
			if nb.x < 0 or nb.x >= W or nb.y < 0 or nb.y >= H or visited.has(nb):
				continue
			# 打通 cur→nb 之间的墙
			if d == Vector2i(1, 0):
				_walls_v[cur] = false
			elif d == Vector2i(-1, 0):
				_walls_v[nb] = false
			elif d == Vector2i(0, 1):
				_walls_h[cur] = false
			else:
				_walls_h[nb] = false
			visited[nb] = true
			stack.append(nb)
			carved = true
			break
		if not carved:
			stack.pop_back()
	return order


func _generate() -> void:
	_init_walls()
	_carve()
	_solution.clear()
	status_label.text = "🎲 迷宫已生成（%d×%d）· 点【解法】看最短路径" % [W, H]
	queue_redraw()


## BFS 求 (0,0) → (W-1,H-1) 最短路径（不穿墙）
func _solve() -> Array:
	var start := Vector2i(0, 0)
	var goal := Vector2i(W - 1, H - 1)
	var came: Dictionary = {}
	var queue: Array = [start]
	var seen: Dictionary = {start: true}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			break
		for d in DIRS4:
			var nb := cur + d
			if nb.x < 0 or nb.x >= W or nb.y < 0 or nb.y >= H or seen.has(nb):
				continue
			if not _passable(cur, d):
				continue
			seen[nb] = true
			came[nb] = cur
			queue.push_back(nb)
	var path: Array = []
	if came.has(goal):
		var c := goal
		while c != start:
			path.push_front(c)
			c = came[c]
	status_label.text = "🔦 解法路径：%d 步" % path.size()
	queue_redraw()
	return path


## cur 沿 d 方向是否有路（墙已打通）
func _passable(cur: Vector2i, d: Vector2i) -> bool:
	if d == Vector2i(1, 0):
		return not _walls_v[cur]
	if d == Vector2i(-1, 0):
		return not _walls_v[cur + d]
	if d == Vector2i(0, 1):
		return not _walls_h[cur]
	return not _walls_h[cur + d]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		_solution = _solve()
		queue_redraw()


func _draw() -> void:
	# 地面
	draw_rect(Rect2(ORIGIN - Vector2(6, 6), Vector2(W * CELL + 12, H * CELL + 12)), Color(0.10, 0.11, 0.16))
	# 解法路径
	if not _solution.is_empty():
		var pts := PackedVector2Array()
		for c in _solution:
			pts.append(ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL)
		draw_polyline(pts, Color(0.35, 0.9, 0.55), 6.0)
	# 墙
	for y in H:
		for x in W:
			if _walls_h.has(Vector2i(x, y)) and _walls_h[Vector2i(x, y)]:
				draw_line(ORIGIN + Vector2(x, y + 1) * CELL, ORIGIN + Vector2(x + 1, y + 1) * CELL, Color(0.55, 0.6, 0.75), 3.0)
			if _walls_v.has(Vector2i(x, y)) and _walls_v[Vector2i(x, y)]:
				draw_line(ORIGIN + Vector2(x + 1, y) * CELL, ORIGIN + Vector2(x + 1, y + 1) * CELL, Color(0.55, 0.6, 0.75), 3.0)
	# 外框
	draw_rect(Rect2(ORIGIN, Vector2(W * CELL, H * CELL)), Color(0.7, 0.75, 0.9), false, 4.0)
	# 起终点
	draw_circle(ORIGIN + Vector2(0.5, 0.5) * CELL, 9, Color(0.35, 0.9, 0.55))
	draw_circle(ORIGIN + Vector2(W - 0.5, H - 0.5) * CELL, 9, Color(0.95, 0.4, 0.35))
