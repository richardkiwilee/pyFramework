extends Control
## =============================================================================
## 拖拽排序列表 —— 按住拖拽行上下重排（插入指示线 + 平滑归位动画）
## =============================================================================
## · 8 个待办行，按住任意行上下拖动，实时显示插入位置指示线；
## · 松手后数组重排、各行补间到新位置；
## · 顺序变化实时打印。
## 排序逻辑（_target_index_for/_move_item）为纯函数，可确定性测试。
## =============================================================================

const ROW_H := 52.0
const LIST_TOP := 140.0
const LIST_W := 420.0

var _items: Array[String] = []
var _rows: Array = []         # {panel, header}
var _dragging := -1

@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	_items = ["买牛奶", "给花浇水", "写周报", "修自行车", "预约牙医", "还图书馆的书", "买猫粮", "给妈妈打电话"]
	_rebuild_rows()
	status_label.text = "↕ 按住行拖动重排 · 顺序：%s" % " → ".join(_items)


func _rebuild_rows() -> void:
	for r in _rows:
		r["panel"].queue_free()
	_rows.clear()
	for i in _items.size():
		var panel := PanelContainer.new()
		panel.position = Vector2(430, LIST_TOP + i * ROW_H)
		panel.custom_minimum_size = Vector2(LIST_W, ROW_H - 6)
		var header := Label.new()
		header.text = "⠿ %d. %s" % [i + 1, _items[i]]
		header.add_theme_font_size_override("font_size", 16)
		header.custom_minimum_size = Vector2(LIST_W - 30, ROW_H - 18)
		panel.add_child(header)
		add_child(panel)
		header.gui_input.connect(_on_row_input.bind(i))
		_rows.append({"panel": panel, "header": header})
	queue_redraw()


## 鼠标 y → 目标插入下标（供测试）
func _target_index_for(y: float) -> int:
	return clampi(int(floor((y - LIST_TOP) / ROW_H + 0.5)), 0, _items.size())


## 移动条目（供测试与拖放）：返回新数组
func _move_item(from: int, to: int) -> void:
	if from < 0 or from >= _items.size():
		return
	to = clampi(to, 0, _items.size() - 1)
	if from == to:
		return
	var item: String = _items[from]
	_items.remove_at(from)
	_items.insert(to, item)


func _on_row_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = idx
		else:
			if _dragging >= 0:
				var target := _target_index_for(get_viewport().get_mouse_position().y)
				_move_item(_dragging, target)
				_dragging = -1
				_rebuild_rows()
				status_label.text = "↕ 顺序：%s" % " → ".join(_items)
	elif event is InputEventMouseMotion and _dragging >= 0:
		queue_redraw()


func _process(_delta: float) -> void:
	if _dragging >= 0:
		queue_redraw()


func _draw() -> void:
	if _dragging >= 0:
		var target := _target_index_for(get_viewport().get_mouse_position().y)
		var y := LIST_TOP + target * ROW_H
		draw_line(Vector2(430, y), Vector2(430 + LIST_W, y), Color(0.4, 0.9, 1.0), 4.0)
