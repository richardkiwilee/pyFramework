extends Node2D
## =============================================================================
## 泡泡龙 —— 瞄准射击、同色三连消除、悬空泡泡掉落
## =============================================================================
## · 顶部网格彩色泡泡，底部发射器随鼠标瞄准；
## · 发射的泡泡沿直线飞行，命中泡泡/顶边后吸附到最近的空格；
## · 同色连通 ≥3 消除；失去支撑的泡泡整簇掉落；
## · 清空全部泡泡胜利。
## 核心逻辑（_snap_cell/_find_match/_drop_floating）为纯函数，可确定性测试。
## =============================================================================

const COLS := 10
const ROWS := 7
const CELL := 52.0
const ORIGIN := Vector2(110, 60)
const SHOOTER := Vector2(370, 660)   # 网格 x 范围 110~630，发射器取正中
const COLORS: Array[Color] = [
	Color(0.95, 0.45, 0.45), Color(0.45, 0.8, 0.5), Color(0.45, 0.6, 0.95),
	Color(0.95, 0.8, 0.35), Color(0.8, 0.5, 0.95),
]

var _grid: Dictionary = {}    # Vector2i → 颜色下标
var _bullet: Dictionary = {}  # {pos, vel, color}
var _score := 0

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	$CanvasLayer/ResetBtn.pressed.connect(_new_game)
	_new_game()


func _new_game() -> void:
	_grid.clear()
	_bullet = {}
	_score = 0
	for y in 3:
		for x in COLS:
			_grid[Vector2i(x, y)] = randi() % COLORS.size()
	status_label.text = "🫧 得分：0 · 剩余 %d" % _grid.size()
	queue_redraw()


## 沿射线找吸附格（供测试与射击）：返回 Vector2i(-1,-1) 表示出界
func _snap_cell(from: Vector2, dir: Vector2) -> Vector2i:
	var d := dir.normalized()
	var t := 0.0
	while t < 2000.0:
		t += 4.0
		var p := from + d * t
		# 出界判定要区分方向：发射器在网格下方，向上射时起点的 y 天然大于网格底
		if p.x < ORIGIN.x - CELL or p.x > ORIGIN.x + COLS * CELL:
			return Vector2i(-1, -1)
		if p.y > ORIGIN.y + ROWS * CELL + 30.0 and d.y > 0.0:
			return Vector2i(-1, -1)
		if p.y < ORIGIN.y - CELL:
			return Vector2i(-1, -1)
		var c := Vector2i(int(floor((p.x - ORIGIN.x) / CELL)), int(floor((p.y - ORIGIN.y) / CELL)))
		if c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS:
			if _grid.has(c):
				# 命中该格 → 吸附到射线来的方向前一格
				var prev := p - d * 12.0
				var pc := Vector2i(int(floor((prev.x - ORIGIN.x) / CELL)), int(floor((prev.y - ORIGIN.y) / CELL)))
				if not _grid.has(pc) and pc.x >= 0 and pc.x < COLS and pc.y >= 0 and pc.y < ROWS:
					return pc
				return Vector2i(-1, -1)
			if p.y <= ORIGIN.y:
				# 顶边吸附
				return c
	return Vector2i(-1, -1)


## 同色连通块（BFS，供测试与消除）
func _find_match(c: Vector2i) -> Array:
	if not _grid.has(c):
		return []
	var color: int = _grid[c]
	var region: Array = []
	var queue: Array = [c]
	var seen: Dictionary = {c: true}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		region.append(cur)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if seen.has(nb) or not _grid.has(nb):
				continue
			if int(_grid[nb]) != color:
				continue
			seen[nb] = true
			queue.push_back(nb)
	return region


## 悬空检测：从顶行 BFS，未被触及的格子整簇掉落（返回掉落格）
func _drop_floating() -> Array:
	var supported: Dictionary = {}
	var queue: Array = []
	for x in COLS:
		if _grid.has(Vector2i(x, 0)):
			supported[Vector2i(x, 0)] = true
			queue.append(Vector2i(x, 0))
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if supported.has(nb) or not _grid.has(nb):
				continue
			supported[nb] = true
			queue.push_back(nb)
	var fallen: Array = []
	for c in _grid.keys():
		if not supported.has(c):
			fallen.append(c)
	for c in fallen:
		_grid.erase(c)
	return fallen


## 射击（供输入与测试）：发射、吸附、消除、掉落一步到位
func _shoot(dir: Vector2) -> void:
	var color := randi() % COLORS.size()
	var target := _snap_cell(SHOOTER, dir)
	if target.x < 0:
		return
	_grid[target] = color
	var region := _find_match(target)
	if region.size() >= 3:
		for c in region:
			_grid.erase(c)
		_score += region.size() * 10
	var fallen := _drop_floating()
	_score += fallen.size() * 5
	status_label.text = "🫧 得分：%d · 剩余 %d" % [_score, _grid.size()]
	if _grid.is_empty():
		status_label.text = "🎉 清空！最终得分 %d" % _score
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position - SHOOTER)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# 瞄准线
	var mouse := get_viewport().get_mouse_position()
	if mouse.y < SHOOTER.y:
		draw_line(SHOOTER, SHOOTER + (mouse - SHOOTER).normalized() * 90.0, Color(1, 1, 1, 0.5), 2.5)
	# 网格泡泡
	for c in _grid.keys():
		var p := ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * CELL
		draw_circle(p, CELL * 0.42, COLORS[int(_grid[c])])
		draw_circle(p + Vector2(-7, -8), 6, Color(1, 1, 1, 0.45))
	# 发射器
	draw_circle(SHOOTER, 26, Color(0.35, 0.4, 0.5))
	draw_circle(SHOOTER, 16, COLORS[randi() % COLORS.size()])
