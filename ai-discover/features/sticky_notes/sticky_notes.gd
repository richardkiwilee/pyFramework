extends Control
## =============================================================================
## 便利贴板 —— 点击空白处创建便签，可拖拽移动、右键删除、随时编辑
## =============================================================================
## · 便签 = 柔和色面板 + 顶部拖拽条 + 可编辑文本框；
## · 按住顶部条拖动移动；右键顶部条删除；颜色随机取柔和色系；
## · 【🧹 清空】移除全部。
## 创建/删除逻辑可确定性测试。
## =============================================================================

const NOTE_SIZE := Vector2(210, 150)
const PASTEL: Array[Color] = [
	Color(1.0, 0.92, 0.6), Color(0.85, 0.95, 0.75), Color(0.75, 0.9, 1.0),
	Color(1.0, 0.8, 0.85), Color(0.9, 0.85, 1.0),
]

var _notes: Array = []      # {panel, header}
var _dragging: Dictionary = {}   # {panel, offset}

@onready var clear_btn: Button = $CanvasLayer/ClearBtn
@onready var count_label: Label = $CanvasLayer/CountLabel


func _ready() -> void:
	clear_btn.pressed.connect(_clear_all)
	_refresh_count()


## 创建便签（供输入与测试）
func _create_note(pos: Vector2) -> void:
	var panel := PanelContainer.new()
	panel.position = pos - NOTE_SIZE / 2.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = PASTEL[randi() % PASTEL.size()]
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 0.35, 0.2, 0.5)
	sb.content_margin_top = 30.0
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = NOTE_SIZE

	var header := ColorRect.new()
	header.position = Vector2(2, 2)
	header.size = Vector2(NOTE_SIZE.x - 4, 26)
	header.color = Color(0.3, 0.25, 0.1, 0.25)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(header)

	var edit := LineEdit.new()
	edit.placeholder_text = "写点什么…"
	panel.add_child(edit)

	add_child(panel)
	header.gui_input.connect(_on_header_input.bind(header))
	_notes.append({"panel": panel, "header": header})
	_refresh_count()


func _delete_note(idx: int) -> void:
	if idx < 0 or idx >= _notes.size():
		return
	_notes[idx]["panel"].queue_free()
	_notes.remove_at(idx)
	_refresh_count()


func _clear_all() -> void:
	for n in _notes:
		n["panel"].queue_free()
	_notes.clear()
	_refresh_count()


func _refresh_count() -> void:
	count_label.text = "📝 便签：%d 张" % _notes.size()


func _on_header_input(event: InputEvent, header: ColorRect) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var panel: Control = header.get_parent()
			_dragging = {"panel": panel, "offset": panel.position - get_viewport().get_mouse_position()}
		else:
			_dragging = {}
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var idx := -1
		for i in _notes.size():
			if _notes[i]["header"] == header:
				idx = i
		_delete_note(idx)
	elif event is InputEventMouseMotion and not _dragging.is_empty() and _dragging["panel"] == header.get_parent():
		_dragging["panel"].position = get_viewport().get_mouse_position() + _dragging["offset"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点在空白处 → 新建（不落在已有便签上）
		for n in _notes:
			if n["panel"].get_global_rect().has_point(event.position):
				return
		_create_note(event.position)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# 软木板纹理（点阵）
	for y in range(0, 720, 34):
		for x in range(0, 1280, 34):
			draw_circle(Vector2(x + (y / 34) % 2 * 17, y), 1.5, Color(0.35, 0.25, 0.15, 0.4))
