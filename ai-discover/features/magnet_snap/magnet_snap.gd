extends Control
## =============================================================================
## 磁力吸附拖拽 —— 拖动方块，松手自动吸附到最近的空槽位
## =============================================================================
## · 4×4 槽位网格（右侧），彩色方块堆（左侧）；
## · 拖动方块跟随鼠标，实时高亮"将吸附的最近空槽"（吸附半径内）；
## · 松手：吸附半径内有空槽 → 平滑滑入槽心并锁定；
##         没有可用槽 → 弹回原位置；
## · 点击已入槽的方块可以再次拿起。
## =============================================================================

const SLOT_GRID := Vector2i(4, 4)
const SLOT_SPACING := 118.0
const SLOT_ORIGIN := Vector2(560, 120)
const SNAP_RADIUS := 95.0

const BLOCK_COLORS: Array[Color] = [
	Color(0.90, 0.35, 0.30), Color(0.35, 0.75, 0.40), Color(0.30, 0.55, 0.95),
	Color(0.95, 0.80, 0.25), Color(0.70, 0.40, 0.95), Color(0.35, 0.85, 0.85),
	Color(0.95, 0.60, 0.25), Color(0.85, 0.45, 0.70),
]

var _slots: Array[Vector2] = []
var _blocks: Array = []             # {node, home, slot}  slot=-1 未入槽
var _dragging: Dictionary = {}      # {node, offset}
var _snap_target := -1

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	for gy in SLOT_GRID.y:
		for gx in SLOT_GRID.x:
			_slots.append(SLOT_ORIGIN + Vector2(gx, gy) * SLOT_SPACING)
	# 左侧方块堆
	for i in BLOCK_COLORS.size():
		var b := _make_block(BLOCK_COLORS[i], i)
		var home := Vector2(90 + (i % 2) * 130, 140 + (i / 2) * 130)
		b.position = home
		_blocks.append({"node": b, "home": home, "slot": -1})
	queue_redraw()


func _make_block(color: Color, idx: int) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(84, 84)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.set_border_width_all(3)
	var panel := Panel.new()
	panel.size = Vector2(84, 84)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(panel)
	var l := Label.new()
	l.text = "★%d" % (idx + 1)
	l.size = Vector2(84, 84)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 22)
	b.add_child(l)
	b.gui_input.connect(_on_block_input.bind(b))
	add_child(b)
	return b


func _on_block_input(event: InputEvent, b: Control) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_start_drag(b)
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_drag()


func _start_drag(b: Control) -> void:
	var entry := _entry_of(b)
	_dragging = {"node": b, "offset": b.position - get_viewport().get_mouse_position()}
	if entry["slot"] >= 0:
		entry["slot"] = -1   # 拿起即脱离槽位
	b.z_index = 50


func _entry_of(b: Control) -> Dictionary:
	for e in _blocks:
		if e["node"] == b:
			return e
	return {}


func _process(_delta: float) -> void:
	if _dragging.is_empty():
		return
	var b: Control = _dragging["node"]
	b.position = get_viewport().get_mouse_position() + _dragging["offset"]
	# 找最近空槽（吸附半径内）
	_snap_target = _nearest_free_slot(b.position + Vector2(42, 42))
	queue_redraw()


func _end_drag() -> void:
	if _dragging.is_empty():
		return
	var b: Control = _dragging["node"]
	var entry := _entry_of(b)
	_dragging = {}
	b.z_index = 0
	if _snap_target >= 0:
		entry["slot"] = _snap_target
		var tw := b.create_tween()
		tw.tween_property(b, "position", _slots[_snap_target] - Vector2(42, 42), 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		status_label.text = "🧲 吸附到槽位 %d" % _snap_target
	else:
		var tw := b.create_tween()
		tw.tween_property(b, "position", entry["home"], 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		status_label.text = "没有可用槽位，方块弹回"
	_snap_target = -1
	queue_redraw()


func _nearest_free_slot(pos: Vector2) -> int:
	var best := -1
	var best_d := SNAP_RADIUS
	for i in _slots.size():
		if _slot_taken(i):
			continue
		var d := pos.distance_to(_slots[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _slot_taken(idx: int) -> bool:
	for e in _blocks:
		if e["slot"] == idx:
			return true
	return false


func _draw() -> void:
	# 槽位
	for i in _slots.size():
		var p := _slots[i]
		if _slot_taken(i):
			draw_circle(p, 34, Color(0.20, 0.24, 0.32))
		else:
			draw_circle(p, 34, Color(0.11, 0.13, 0.19))
		if _snap_target == i:
			draw_arc(p, 42, 0, TAU, 32, Color(0.4, 0.9, 1.0), 4.0)   # 吸附预告
		draw_arc(p, 34, 0, TAU, 32, Color(0.35, 0.4, 0.55), 2.0)
	draw_line(Vector2(430, 60), Vector2(430, 660), Color(0.2, 0.22, 0.3), 2.0)
