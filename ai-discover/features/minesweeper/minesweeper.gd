extends Node2D
## =============================================================================
## 扫雷 —— 经典布雷/计数/零区泛洪展开/插旗
## =============================================================================
## · 10×10 网格、12 颗雷；左键翻开（零区自动泛洪展开），右键插旗；
## · 翻开雷 → 结束；翻开全部非雷格 → 胜利；
## · 【🎲 重开】。布雷/计数/展开为纯函数，可确定性测试。
## =============================================================================

const W := 10
const H := 10
const MINES := 12
const CELL := 56.0
const ORIGIN := Vector2(360, 60)

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _mines: Dictionary = {}
var _revealed: Dictionary = {}
var _flags: Dictionary = {}
var _over := false
var _won := false

@onready var status_label: Label = $CanvasLayer/StatusLabel
@onready var over_label: Label = $CanvasLayer/OverLabel


func _ready() -> void:
	over_label.visible = false
	$CanvasLayer/ResetBtn.pressed.connect(_new_game)
	_new_game()


func _new_game() -> void:
	_mines.clear()
	_revealed.clear()
	_flags.clear()
	_over = false
	_won = false
	over_label.visible = false
	# 随机布雷
	var placed := 0
	while placed < MINES:
		var c := Vector2i(randi() % W, randi() % H)
		if not _mines.has(c):
			_mines[c] = true
			placed += 1
	status_label.text = "💣 雷数 %d · 左键翻开 · 右键插旗" % MINES
	queue_redraw()


## 邻居雷数（供测试与显示）
func _neighbor_mines(c: Vector2i) -> int:
	var n := 0
	for d in DIRS8:
		if _mines.has(c + d):
			n += 1
	return n


## 翻开（供测试与输入）：返回是否踩雷
func _reveal(c: Vector2i) -> bool:
	if _over or _revealed.has(c) or _flags.has(c):
		return false
	if _mines.has(c):
		_over = true
		over_label.text = "💥 踩雷了！R 重开"
		over_label.visible = true
		return true
	# 泛洪展开（零区）
	var queue: Array = [c]
	var seen: Dictionary = {c: true}
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		_revealed[cur] = true
		if _neighbor_mines(cur) == 0:
			for d in DIRS8:
				var nb := cur + d
				if nb.x < 0 or nb.x >= W or nb.y < 0 or nb.y >= H or seen.has(nb):
					continue
				if _mines.has(nb) or _flags.has(nb):
					continue
				seen[nb] = true
				queue.push_back(nb)
	# 胜利（用实际雷数而非常量，测试清空雷时也能正确判定）
	if _revealed.size() == W * H - _mines.size():
		_over = true
		_won = true
		over_label.text = "🎉 扫雷成功！"
		over_label.visible = true
	queue_redraw()
	return false


func _toggle_flag(c: Vector2i) -> void:
	if _over or _revealed.has(c):
		return
	if _flags.has(c):
		_flags.erase(c)
	else:
		_flags[c] = true
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var c := Vector2i(
			int(floor((event.position.x - ORIGIN.x) / CELL)),
			int(floor((event.position.y - ORIGIN.y) / CELL)))
		if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_reveal(c)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_flag(c)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	for y in H:
		for x in W:
			var r := Rect2(ORIGIN + Vector2(x, y) * CELL, Vector2(CELL - 2, CELL - 2))
			var c := Vector2i(x, y)
			if _revealed.has(c):
				draw_rect(r, Color(0.3, 0.32, 0.38))
				var n := _neighbor_mines(c)
				if n > 0:
					var f := ThemeDB.fallback_font
					var txt := str(n)
					var size := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
					draw_string(f, r.get_center() + Vector2(-size.x / 2.0, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.9, 0.95))
				if _mines.has(c):
					draw_circle(r.get_center(), 14, Color(0.1, 0.1, 0.12))
			else:
				draw_rect(r, Color(0.5, 0.55, 0.65))
				if _flags.has(c):
					draw_circle(r.get_center(), 12, Color(0.95, 0.35, 0.3))
			draw_rect(r, Color(0.15, 0.16, 0.2, 0.6), false, 1.5)
