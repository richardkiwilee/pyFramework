extends Node2D
## =============================================================================
## 像素画板 —— 网格点画 + 油漆桶泛洪填充（BFS）
## =============================================================================
## · 左侧 8 色调色盘 + 工具切换：🖌 画笔（左键/拖拽涂色）、
##   🪣 油漆桶（点一下把整个同色连通区域换成所选颜色）、🧽 橡皮；
## · 【随机涂鸦】生成彩色像素块；【清空】重置。
## 油漆桶 = 对"同色连通区域"的 BFS 泛洪填充（与图像软件一致）。
## =============================================================================

const GW := 32
const GH := 20
const CELL := 20.0
const ORIGIN := Vector2(190, 60)

const PALETTE: Array[Color] = [
	Color(0.9, 0.3, 0.3), Color(0.95, 0.6, 0.2), Color(0.95, 0.9, 0.3),
	Color(0.4, 0.85, 0.4), Color(0.3, 0.6, 0.95), Color(0.55, 0.4, 0.95),
	Color(0.95, 0.5, 0.8), Color(0.5, 0.45, 0.4),
]

const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _grid: Dictionary = {}    # Vector2i → 调色盘下标（无 = 空）
var _selected := 0
var _tool := "paint"          # paint / fill / erase
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# 调色盘
	var pal := HBoxContainer.new()
	pal.position = Vector2(16, 60)
	pal.add_theme_constant_override("separation", 6)
	layer.add_child(pal)
	for i in PALETTE.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PALETTE[i]
		sb.set_corner_radius_all(6)
		sb.border_color = Color(1, 1, 1, 0.95) if i == _selected else Color(0, 0, 0, 0.4)
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(_pick_color.bind(i, pal))
		pal.add_child(b)
	# 工具按钮
	var tools := HBoxContainer.new()
	tools.position = Vector2(16, 100)
	tools.add_theme_constant_override("separation", 8)
	layer.add_child(tools)
	for t in [["🖌 画笔", "paint"], ["🪣 油漆桶", "fill"], ["🧽 橡皮", "erase"], ["🎲 随机涂鸦", "random"], ["🧹 清空", "clear"]]:
		var b := Button.new()
		b.text = t[0]
		b.custom_minimum_size = Vector2(110, 36)
		b.pressed.connect(_on_tool.bind(t[1]))
		tools.add_child(b)
	queue_redraw()


func _pick_color(i: int, pal: HBoxContainer) -> void:
	_selected = i
	_tool = "paint"
	# 刷新色块描边（选中项白边）
	for j in pal.get_child_count():
		var b: Button = pal.get_child(j)
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal")
		sb.border_color = Color(1, 1, 1, 0.95) if j == _selected else Color(0, 0, 0, 0.4)


func _on_tool(t: String) -> void:
	if t == "random":
		_grid.clear()
		for y in GH:
			for x in GW:
				if randf() < 0.35:
					_grid[Vector2i(x, y)] = randi() % PALETTE.size()
	elif t == "clear":
		_grid.clear()
	else:
		_tool = t
	queue_redraw()


# ============================================================
#  油漆桶：同色连通区域泛洪填充（BFS）
# ============================================================
func _flood_fill(cell: Vector2i, new_idx: int) -> void:
	var target := int(_grid.get(cell, 0))
	if target == new_idx:
		return
	var queue: Array = [cell]
	var seen: Dictionary = {cell: true}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		_grid[cur] = new_idx
		for d in DIRS4:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.x >= GW or nb.y < 0 or nb.y >= GH:
				continue
			if seen.has(nb):
				continue
			if int(_grid.get(nb, 0)) != target:
				continue
			seen[nb] = true
			queue.push_back(nb)


# ============================================================
#  输入
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _pixel_to_cell(event.position)
		if _tool == "erase" and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_grid.erase(_hover)
		elif _tool == "paint" and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _in_grid(_hover):
				_grid[_hover] = _selected
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var cell := _pixel_to_cell(event.position)
		if not _in_grid(cell):
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_grid.erase(cell)
		elif _tool == "erase":
			_grid.erase(cell)
		elif _tool == "fill":
			_flood_fill(cell, _selected)
		else:
			_grid[cell] = _selected
		queue_redraw()


func _pixel_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - ORIGIN.x) / CELL)), int(floor((p.y - ORIGIN.y) / CELL)))


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GW and c.y >= 0 and c.y < GH


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	for y in GH:
		for x in GW:
			var cell := Vector2i(x, y)
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 1, CELL - 1))
			if _grid.has(cell):
				draw_rect(r, PALETTE[int(_grid[cell])])
			else:
				draw_rect(r, Color(0.16, 0.17, 0.21))
	# 网格线
	for y in GH + 1:
		draw_line(ORIGIN + Vector2(0, y * CELL), ORIGIN + Vector2(GW * CELL, y * CELL), Color(0.06, 0.07, 0.1), 1.0)
	for x in GW + 1:
		draw_line(ORIGIN + Vector2(x * CELL, 0), ORIGIN + Vector2(x * CELL, GH * CELL), Color(0.06, 0.07, 0.1), 1.0)
	# 悬停框
	if _in_grid(_hover):
		draw_rect(Rect2(ORIGIN + Vector2(_hover) * CELL, Vector2(CELL - 1, CELL - 1)), Color(1, 1, 1, 0.8), false, 2.0)
