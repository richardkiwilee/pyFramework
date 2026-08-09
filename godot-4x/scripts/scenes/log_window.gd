## 日志小窗（顶栏"日志"按钮）：右上角弹出，完整日志历史，滚轮上下滚动。
## 对应现代 4X 的消息日志面板；日志源为 GameController.log_messages 环形缓冲。
class_name LogWindow
extends BaseWindow

var _list_vbox: VBoxContainer

func build() -> void:
	win_title = Loc.t("log")
	win_size = Vector2i(520, 380)
	unresizable = true
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 10)
	mc.add_theme_constant_override("margin_right", 10)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 8)
	add_child(mc)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mc.add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 2)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)

func enter_window(params: Variant = null) -> void:
	_rebuild()
	place_top_right()

func _rebuild() -> void:
	for c in _list_vbox.get_children():
		c.queue_free()
	for entry in GameController.log_messages:
		var l := Label.new()
		l.text = entry[0]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color",
			UiTheme.WARN if entry[1] else UiTheme.FG)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_vbox.add_child(l)
	if _list_vbox.get_child_count() == 0:
		var empty := Label.new()
		empty.text = Loc.t("log_empty")
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", UiTheme.DIM)
		_list_vbox.add_child(empty)
