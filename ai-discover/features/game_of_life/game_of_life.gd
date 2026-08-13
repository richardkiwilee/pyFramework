extends Node2D
## =============================================================================
## 生命游戏 —— Conway 元胞自动机（B3/S23）
## =============================================================================
## · 左键/拖拽画细胞，右键/拖拽擦除；
## · ▶ 播放（速度可调）/ ⏭ 步进 / 🎲 随机 / 🧹 清空；
## · 世代与存活数实时统计。
## 实现：字典存活的细胞 + 邻居计数双缓冲（只遍历存活细胞的邻居，
## 比全网格扫描高效）；规则：存活 2 邻居维持、3 邻居新生，其余死亡。
## =============================================================================

const GW := 48
const GH := 27
const CELL := 24.0
const ORIGIN := Vector2(64, 44)

const NEIGHBORS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _cells: Dictionary = {}   # Vector2i → true
var _playing := false
var _tick := 0.35              # 每代间隔（秒）
var _timer := 0.0
var _gen := 0

@onready var play_btn: Button = $CanvasLayer/Bar/PlayBtn
@onready var speed_slider: HSlider = $CanvasLayer/Bar/SpeedSlider
@onready var stats_label: Label = $CanvasLayer/Bar/StatsLabel


func _ready() -> void:
	play_btn.pressed.connect(_toggle_play)
	$CanvasLayer/Bar/StepBtn.pressed.connect(_step)
	$CanvasLayer/Bar/RandomBtn.pressed.connect(_randomize)
	$CanvasLayer/Bar/ClearBtn.pressed.connect(_clear)
	speed_slider.value_changed.connect(func(v: float) -> void: _tick = lerpf(0.9, 0.05, v))
	_randomize()
	queue_redraw()


func _process(delta: float) -> void:
	if _playing:
		_timer += delta
		if _timer >= _tick:
			_timer = 0.0
			_step()
			queue_redraw()


## 一代演化（B3/S23）
func _step() -> void:
	var counts: Dictionary = {}
	for c in _cells.keys():
		for nb in NEIGHBORS8:
			var n: Vector2i = c + nb
			if n.x < 0 or n.x >= GW or n.y < 0 or n.y >= GH:
				continue
			counts[n] = int(counts.get(n, 0)) + 1
	var next: Dictionary = {}
	for c in counts.keys():
		var n: int = counts[c]
		if n == 3 or (n == 2 and _cells.has(c)):
			next[c] = true
	_cells = next
	_gen += 1
	stats_label.text = "世代 %d · 存活 %d" % [_gen, _cells.size()]


func _toggle_play() -> void:
	_playing = not _playing
	play_btn.text = "⏸ 暂停" if _playing else "▶ 播放"


func _randomize() -> void:
	_cells.clear()
	_gen = 0
	for y in GH:
		for x in GW:
			if randf() < 0.28:
				_cells[Vector2i(x, y)] = true
	stats_label.text = "世代 0 · 存活 %d" % _cells.size()
	queue_redraw()


func _clear() -> void:
	_cells.clear()
	_gen = 0
	_playing = false
	play_btn.text = "▶ 播放"
	stats_label.text = "世代 0 · 存活 0"
	queue_redraw()


# ============================================================
#  输入：画 / 擦细胞
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := _pixel_to_cell(event.position)
		if _in_grid(cell):
			if event.button_index == MOUSE_BUTTON_LEFT:
				_cells[cell] = true
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cells.erase(cell)
			queue_redraw()
	elif event is InputEventMouseMotion and event.button_mask != 0:
		var cell := _pixel_to_cell(event.position)
		if _in_grid(cell):
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_cells[cell] = true
			elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
				_cells.erase(cell)
			queue_redraw()


func _pixel_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - ORIGIN.x) / CELL)), int(floor((p.y - ORIGIN.y) / CELL)))


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GW and c.y >= 0 and c.y < GH


# ============================================================
#  绘制
# ============================================================
func _draw() -> void:
	# 背景网格
	for y in GH:
		for x in GW:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 1, CELL - 1))
			draw_rect(r, Color(0.11, 0.12, 0.17) if _cells.has(Vector2i(x, y)) else Color(0.16, 0.18, 0.24))
	# 活细胞（亮绿）
	for c in _cells.keys():
		draw_rect(Rect2(ORIGIN + Vector2(c) * CELL, Vector2(CELL - 1, CELL - 1)), Color(0.35, 0.85, 0.45))
