extends Control
## =============================================================================
## 惯性滚动列表 —— 拖拽惯性滚动 + 边界弹性回弹（自实现滚动物理）
## =============================================================================
## · 不使用 ScrollContainer：列表视口 = clip_contents 裁剪窗口，
##   内容 VBox 的 position.y 由自实现物理驱动；
## · 拖动：内容跟随鼠标，记录拖速；松手：惯性继续滑行 + 摩擦衰减；
## · 超出边界：弹簧回弹（橡胶带效果）。
## 物理步进（_scroll_step）为纯函数，可确定性测试。
## =============================================================================

const ITEM_H := 58.0
const ITEM_COUNT := 30
const LIST_RECT := Rect2(490, 90, 300, 540)
const FRICTION := 0.94
const SPRING_K := 160.0

var _offset := 0.0
var _vel := 0.0
var _dragging := false
var _last_y := 0.0
var _box: VBoxContainer

@onready var viewport_ctrl: Control = $ListViewport
@onready var offset_label: Label = $CanvasLayer/OffsetLabel


func _ready() -> void:
	viewport_ctrl.clip_contents = true
	_box = VBoxContainer.new()
	viewport_ctrl.add_child(_box)
	for i in ITEM_COUNT:
		var item := Label.new()
		item.custom_minimum_size = Vector2(300, ITEM_H)
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_theme_font_size_override("font_size", 16)
		item.text = "📄 条目 %02d" % (i + 1)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.16 + (i % 2) * 0.03, 0.22)
		sb.set_corner_radius_all(8)
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		item.add_theme_stylebox_override("normal", sb)
		_box.add_child(item)
	_box.position.y = -_offset


func _max_offset() -> float:
	return maxf(0.0, ITEM_COUNT * ITEM_H - LIST_RECT.size.y)


## 单步滚动物理（供测试）：不拖动时惯性滑行 + 边界弹簧
func _scroll_step(delta: float) -> void:
	_offset += _vel * delta
	_vel *= FRICTION
	# 边界弹簧回弹
	if _offset < 0.0:
		_offset += (-SPRING_K * _offset) * delta
		_vel = 0.0
	elif _offset > _max_offset():
		_offset += (-SPRING_K * (_offset - _max_offset())) * delta
		_vel = 0.0
	_box.position.y = -_offset
	offset_label.text = "滚动偏移 %.0f / %.0f · 速度 %.0f" % [_offset, _max_offset(), _vel]


func _process(delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	if _dragging:
		# 直接跟随 + 记录拖速
		_vel = (_last_y - mouse.y) / maxf(delta, 0.001)
		_offset += (_last_y - mouse.y)
		_last_y = mouse.y
		_offset = clampf(_offset, -60.0, _max_offset() + 60.0)
		_box.position.y = -_offset
		offset_label.text = "滚动偏移 %.0f / %.0f（拖动中）" % [_offset, _max_offset()]
	else:
		_scroll_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and LIST_RECT.has_point(event.position):
			_dragging = true
			_last_y = event.position.y
		else:
			_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()
