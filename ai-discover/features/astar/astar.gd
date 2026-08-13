extends Node2D
## =============================================================================
## A* 寻路可视化 —— 网格地图 + 启发式搜索逐步展开动画
## =============================================================================
## 交互：
##   左键/拖拽 画墙    右键/拖拽 擦墙
##   【寻路】运行 A*（曼哈顿启发式），逐步回放"展开过程"：
##     浅蓝 = 待探索(open) · 灰蓝 = 已探索(closed) · 黄 = 当前节点
##   【随机墙】【清空】自明；绿色 = 起点，红色 = 终点。
## 展开结束显示最终路径（橙色）与统计（扩展节点数 / 路径长度）。
## =============================================================================

const GRID_W := 24
const GRID_H := 14
const CELL := 44.0
const ORIGIN := Vector2(52, 80)

const START := Vector2i(1, 1)
const GOAL := Vector2i(GRID_W - 2, GRID_H - 2)

var _walls: Dictionary = {}     # Vector2i → true
var _steps: Array = []          # A* 回放步骤 [{current, open, closed}]
var _path: Array = []
var _step_idx := 0
var _anim_timer: Timer

var _status: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(52, 12)
	bar.add_theme_constant_override("separation", 10)
	layer.add_child(bar)
	for data in [["🔍 寻路", "_on_run"], ["🎲 随机墙", "_on_random"], ["🧹 清空", "_on_clear"]]:
		var b := Button.new()
		b.text = data[0]
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(Callable(self, data[1]))
		bar.add_child(b)
	_status = Label.new()
	_status.position = Vector2(52, 712 - 42)
	_status.size = Vector2(1100, 30)
	_status.add_theme_font_size_override("font_size", 15)
	layer.add_child(_status)
	_status.text = "左键画墙 · 右键擦墙 · 点【寻路】看 A* 展开过程"

	_anim_timer = Timer.new()
	_anim_timer.wait_time = 0.025
	_anim_timer.timeout.connect(_on_step_tick)
	add_child(_anim_timer)

	queue_redraw()


# ============================================================
#  输入：画墙 / 擦墙
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := _pixel_to_cell(event.position)
		if _valid(cell):
			if event.button_index == MOUSE_BUTTON_LEFT:
				_walls[cell] = true
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_walls.erase(cell)
			queue_redraw()
	elif event is InputEventMouseMotion and event.button_mask != 0:
		var cell := _pixel_to_cell(event.position)
		if _valid(cell):
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_walls[cell] = true
			elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_walls.erase(cell)
			queue_redraw()


func _pixel_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - ORIGIN.x) / CELL)), int(floor((p.y - ORIGIN.y) / CELL)))


func _valid(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GRID_W and c.y >= 0 and c.y < GRID_H \
		and c != START and c != GOAL


const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _neighbors4(c: Vector2i) -> Array:
	var out: Array = []
	for d in DIRS4:
		var nb := c + d
		if nb.x >= 0 and nb.x < GRID_W and nb.y >= 0 and nb.y < GRID_H:
			out.append(nb)
	return out


# ============================================================
#  A* 搜索
# ============================================================
func _h(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)   # 曼哈顿启发式


## 完整跑一遍 A*，记录每一步的 open/closed 用于回放
func _astar() -> Dictionary:
	var g := {START: 0}
	var f := {START: _h(START, GOAL)}
	var came := {}
	var closed := {}
	var open: Array = [START]
	var steps: Array = []

	while not open.is_empty():
		var best := 0
		for i in open.size():
			if f[open[i]] < f[open[best]]:
				best = i
		var cur: Vector2i = open[best]
		open.remove_at(best)
		closed[cur] = true
		steps.append({"current": cur, "open": open.duplicate(), "closed": closed.keys()})
		if cur == GOAL:
			break
		for nb in _neighbors4(cur):
			if closed.has(nb) or _walls.has(nb):
				continue
			var ng: int = g[cur] + 1
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng
				f[nb] = ng + _h(nb, GOAL)
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)

	var path: Array = []
	if came.has(GOAL):
		var c := GOAL
		while c != START:
			path.push_front(c)
			c = came[c]
	return {"steps": steps, "path": path}


func _on_run() -> void:
	var result := _astar()
	_steps = result["steps"]
	_path = result["path"]
	_step_idx = 0
	_anim_timer.start()
	_status.text = "⏳ 展开中…（%d 个节点待回放）" % _steps.size()
	queue_redraw()


func _on_step_tick() -> void:
	_step_idx += 2   # 每帧展开 2 个节点，加快回放
	queue_redraw()
	if _step_idx >= _steps.size():
		_anim_timer.stop()
		if _path.is_empty():
			_status.text = "❌ 无路可达！共扩展 %d 个节点" % _steps.size()
		else:
			_status.text = "✅ 路径长度 %d 步 · 共扩展 %d 个节点" % [_path.size(), _steps.size()]


func _on_random() -> void:
	_walls.clear()
	for y in GRID_H:
		for x in GRID_W:
			var c := Vector2i(x, y)
			if c != START and c != GOAL and randf() < 0.24:
				_walls[c] = true
	_steps.clear()
	_path.clear()
	queue_redraw()


func _on_clear() -> void:
	_walls.clear()
	_steps.clear()
	_path.clear()
	_anim_timer.stop()
	_status.text = "已清空 · 点【寻路】看 A* 展开过程"
	queue_redraw()


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	# 当前回放进度内的 closed / open
	var closed_shown: Dictionary = {}
	var open_shown: Array = []
	var current := Vector2i(-1, -1)
	var shown := _steps.slice(0, mini(_step_idx + 1, _steps.size()))
	for s in shown:
		for c in s["closed"]:
			closed_shown[c] = true
		open_shown = s["open"]
		current = s["current"]

	for y in GRID_H:
		for x in GRID_W:
			var cell := Vector2i(x, y)
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 1, CELL - 1))
			if _walls.has(cell):
				draw_rect(r, Color(0.28, 0.32, 0.42))
			elif closed_shown.has(cell):
				draw_rect(r, Color(0.30, 0.42, 0.55))
			elif open_shown.has(cell):
				draw_rect(r, Color(0.35, 0.65, 0.85, 0.55))
			else:
				draw_rect(r, Color(0.14, 0.16, 0.22))
			# 网格线
			draw_rect(r, Color(0.05, 0.06, 0.1, 0.4), false, 1.0)
	# 当前节点（黄色）
	if current.x >= 0:
		draw_rect(Rect2(ORIGIN + Vector2(current) * CELL, Vector2(CELL - 1, CELL - 1)), Color(1.0, 0.85, 0.25))
	# 最终路径（橙色）
	if _step_idx >= _steps.size() and _path.size() > 0:
		var pts := PackedVector2Array()
		for c in _path:
			pts.append(ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL)
		draw_polyline(pts, Color(1.0, 0.55, 0.15), 5.0)
	# 起点 / 终点
	draw_rect(Rect2(ORIGIN + Vector2(START) * CELL, Vector2(CELL - 1, CELL - 1)), Color(0.25, 0.75, 0.35))
	draw_rect(Rect2(ORIGIN + Vector2(GOAL) * CELL, Vector2(CELL - 1, CELL - 1)), Color(0.9, 0.3, 0.25))
