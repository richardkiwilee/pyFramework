## 通用键盘导航列表（对应 TUI 各场景的列表焦点语义）。
## 行数据任意（Variant），每行渲染文本 + 前景色（可函数化），支持滚动。
## 信号：row_selected(idx)（回车/空格触发）、focus_changed(idx)。
class_name ListWidget
extends Control

signal row_selected(idx: int)    # 单击/键盘移动：选中（看详情）
signal row_activated(idx: int)   # 双击/回车：确认执行
signal focus_changed(idx: int)

const ROW_H := 26
const PAD_X := 8

var items: Array = []                 # 行数据（Variant）
var focused := 0
var scroll := 0
var color_fn: Callable = Callable()   # (data) -> Color，缺省 FG
var text_fn: Callable = Callable()    # (data) -> String，缺省 str(data)
var show_focus := true
var selected_color: Color = UiTheme.ACCENT

var _rows_visible := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_items(arr: Array, keep_focus: bool = false) -> void:
	items = arr
	if not keep_focus:
		focused = 0
		scroll = 0
	if items.is_empty():
		focused = 0
	queue_redraw()

func row_text(data: Variant) -> String:
	if text_fn.is_valid():
		return text_fn.call(data)
	return str(data)

func row_color(data: Variant) -> Color:
	if color_fn.is_valid():
		return color_fn.call(data)
	return UiTheme.FG

func move_focus(delta: int) -> void:
	if items.is_empty():
		return
	focused = clampi(focused + delta, 0, items.size() - 1)
	_ensure_visible()
	focus_changed.emit(focused)
	queue_redraw()

func focus_to(idx: int) -> void:
	if items.is_empty():
		return
	focused = clampi(idx, 0, items.size() - 1)
	_ensure_visible()
	focus_changed.emit(focused)
	queue_redraw()

func _ensure_visible() -> void:
	if focused < scroll:
		scroll = focused
	elif focused >= scroll + _rows_visible:
		scroll = focused - _rows_visible + 1

## 滚轮滚动（不移动焦点）。
func scroll_by(delta: int) -> void:
	if items.is_empty() or items.size() <= _rows_visible:
		return
	scroll = clampi(scroll + delta, 0, items.size() - _rows_visible)
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var fsize := 14
	_rows_visible = maxi(0, int(size.y / ROW_H))
	for i in range(_rows_visible):
		var idx := scroll + i
		if idx >= items.size():
			break
		var y := i * ROW_H
		var r := Rect2(0, y, size.x, ROW_H)
		if show_focus and idx == focused:
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTheme.PANEL_BG.lightened(0.15)
			sb.set_corner_radius_all(4)
			draw_style_box(sb, r.grow(-1))
		var data: Variant = items[idx]
		var txt := row_text(data)
		var col := row_color(data)
		if idx == focused and show_focus:
			col = col.lightened(0.25)
		draw_string(font, Vector2(PAD_X, y + ROW_H * 0.65), txt,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD_X * 2, fsize, col)
	# 滚动提示
	if items.size() > _rows_visible:
		var bar_w := 4.0
		var frac := _rows_visible / float(items.size())
		var bar_y := scroll / float(maxi(1, items.size() - _rows_visible)) * (size.y - ROW_H * frac)
		draw_rect(Rect2(size.x - bar_w, bar_y, bar_w, ROW_H * frac), UiTheme.BORDER)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var idx := scroll + int(event.position.y / ROW_H)
		if idx >= 0 and idx < items.size():
			focus_to(idx)
			if event.button_index == MOUSE_BUTTON_LEFT:
				row_selected.emit(idx)          # 单击 = 选中
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				row_activated.emit(idx)         # 右键 = 确认
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll_by(-3)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll_by(3)
		accept_event()
	elif event is InputEventMouseButton and event.double_click 			and event.button_index == MOUSE_BUTTON_LEFT:
		var idx2 := scroll + int(event.position.y / ROW_H)
		if idx2 >= 0 and idx2 < items.size():
			focus_to(idx2)
			row_activated.emit(idx2)            # 双击 = 确认
		accept_event()
