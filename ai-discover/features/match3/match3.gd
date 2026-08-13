extends Node2D
## =============================================================================
## 三消游戏 —— 交换相邻宝石、三连消除、下落补位
## =============================================================================
## · 8×8 网格、5 色宝石；点击一颗选中，再点相邻一颗交换；
## · 交换后若无三连则自动换回；
## · 三连（横/竖 ≥3 同色）消除计分，上方宝石下落、顶部补新，
##   并检查连锁；消除处播放扩散光圈。
## 核心逻辑（_find_matches/_settle）与渲染分离，可确定性测试。
## =============================================================================

const GW := 8
const GH := 8
const CELL := 64.0
const ORIGIN := Vector2(384, 52)
const GEM_COLORS: Array[Color] = [
	Color(0.95, 0.4, 0.4), Color(0.45, 0.85, 0.45), Color(0.4, 0.6, 0.95),
	Color(0.95, 0.85, 0.35), Color(0.8, 0.5, 0.95),
]

var _grid: Array = []          # [y][x] → 颜色下标
var _selected := Vector2i(-1, -1)
var _pops: Array = []          # {pos, t} 消除扩散光圈
var _score := 0

@onready var score_label: Label = $CanvasLayer/ScoreLabel


func _ready() -> void:
	_new_grid()
	queue_redraw()


## 初始网格（保证无现成三连）
func _new_grid() -> void:
	_grid.clear()
	for y in GH:
		var row: Array = []
		for x in GW:
			var c := randi() % GEM_COLORS.size()
			# 避免初始三连：与左侧/上方两格同色则重选
			while (x >= 2 and row[x - 1] == c and row[x - 2] == c) \
					or (y >= 2 and _grid[y - 1][x] == c and _grid[y - 2][x] == c):
				c = randi() % GEM_COLORS.size()
			row.append(c)
		_grid.append(row)


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GW and c.y >= 0 and c.y < GH


# ============================================================
#  核心逻辑（确定性）
# ============================================================
## 找所有 ≥3 连的格子
func _find_matches() -> Array:
	var found: Dictionary = {}
	for y in GH:
		for x in GW:
			var c: int = _grid[y][x]
			# 横三连
			if x + 2 < GW and _grid[y][x + 1] == c and _grid[y][x + 2] == c:
				for i in 3:
					found[Vector2i(x + i, y)] = true
			# 竖三连
			if y + 2 < GH and _grid[y + 1][x] == c and _grid[y + 2][x] == c:
				for i in 3:
					found[Vector2i(x, y + i)] = true
	return found.keys()


## 消除 + 下落 + 补新（一次级联），返回本轮消除数
func _settle(matches: Array) -> int:
	for c in matches:
		_grid[c.y][c.x] = -1
	# 每列下落
	for x in GW:
		var write := GH - 1
		for y in range(GH - 1, -1, -1):
			if _grid[y][x] != -1:
				_grid[write][x] = _grid[y][x]
				write -= 1
		for y in range(write, -1, -1):
			_grid[y][x] = randi() % GEM_COLORS.size()
	return matches.size()


## 交换两格；无消除则换回（返回是否成功消除）
func _try_swap(a: Vector2i, b: Vector2i) -> bool:
	var tmp: int = _grid[a.y][a.x]
	_grid[a.y][a.x] = _grid[b.y][b.x]
	_grid[b.y][b.x] = tmp
	var matches := _find_matches()
	if matches.is_empty():
		# 换回
		var tmp2: int = _grid[a.y][a.x]
		_grid[a.y][a.x] = _grid[b.y][b.x]
		_grid[b.y][b.x] = tmp2
		return false
	# 级联处理
	var total := 0
	while not matches.is_empty():
		total += _settle(matches)
		for c in matches:
			_pops.append({"pos": _cell_center(c), "t": 0.0})
		matches = _find_matches()
	_score += total * 10
	score_label.text = "💎 得分：%d" % _score
	return true


func _cell_center(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


# ============================================================
#  输入
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var cell := Vector2i(int(floor((event.position.x - ORIGIN.x) / CELL)), int(floor((event.position.y - ORIGIN.y) / CELL)))
	if not _in_grid(cell):
		return
	if _selected.x < 0:
		_selected = cell
	elif cell == _selected:
		_selected = Vector2i(-1, -1)
	elif absi(cell.x - _selected.x) + absi(cell.y - _selected.y) == 1:
		_try_swap(_selected, cell)
		_selected = Vector2i(-1, -1)
	else:
		_selected = cell
	queue_redraw()


func _process(delta: float) -> void:
	for p in _pops:
		p["t"] += delta
	_pops = _pops.filter(func(p: Dictionary) -> bool: return p["t"] < 0.45)


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	draw_rect(Rect2(ORIGIN - Vector2(8, 8), Vector2(GW * CELL + 16, GH * CELL + 16)), Color(0.10, 0.11, 0.17))
	for y in GH:
		for x in GW:
			var c := _cell_center(Vector2i(x, y))
			draw_circle(c, 25, GEM_COLORS[_grid[y][x]])
			draw_arc(c, 25, 0, TAU, 20, Color(1, 1, 1, 0.35), 2.0)
			# 顶部高光
			draw_circle(c + Vector2(-7, -9), 6, Color(1, 1, 1, 0.5))
	# 选中框
	if _selected.x >= 0:
		var c := _cell_center(_selected)
		draw_arc(c, 30, 0, TAU, 32, Color(1, 1, 1, 0.95), 4.0)
	# 消除扩散光圈
	for p in _pops:
		var f: float = 1.0 - p["t"] / 0.45
		draw_arc(p["pos"], 8.0 + (1.0 - f) * 60.0, 0, TAU, 32, Color(1, 1, 1, f * 0.9), 3.0)
