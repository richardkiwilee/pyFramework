extends CanvasLayer
## 极简 HUD：时刻读数 + 一条能拖的时间滑条 + 操作提示。
##
## 全部用代码搭，避免为了一个滑条引入主题资源文件；配色沿用游戏的暖灰，
## 免得在像素画面上糊一层突兀的系统控件。

const INK := Color(0.93, 0.90, 0.82)
const PANEL := Color(0.09, 0.09, 0.13, 0.72)
const ACCENT := Color(0.96, 0.76, 0.42)

var _main: Node
var _clock: Label
var _phase: Label
var _slider: HSlider
var _auto: Label
var _hint: Label
var _hint_t := 0.0
var _dragging := false


func setup(main_node: Node) -> void:
	_main = main_node

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- 左上角：标题 + 时刻
	var box := PanelContainer.new()
	box.position = Vector2(8, 8)
	box.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	box.add_child(vb)

	var title := Label.new()
	title.text = "HD-2D 大世界漫游"
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_font_size_override("font_size", 13)
	vb.add_child(title)

	_clock = Label.new()
	_clock.add_theme_color_override("font_color", INK)
	_clock.add_theme_font_size_override("font_size", 12)
	vb.add_child(_clock)

	_phase = Label.new()
	_phase.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86))
	_phase.add_theme_font_size_override("font_size", 11)
	vb.add_child(_phase)

	# ---- 底部：时间滑条
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_top = -34
	bar.offset_bottom = -8
	bar.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)

	var l0 := Label.new()
	l0.text = "时刻"
	l0.add_theme_color_override("font_color", INK)
	l0.add_theme_font_size_override("font_size", 12)
	hb.add_child(l0)

	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.001
	_slider.value = 0.34
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(0, 14)
	_slider.add_theme_stylebox_override("slider", _bar_style(Color(0.16, 0.16, 0.22)))
	_slider.add_theme_stylebox_override("grabber_area", _bar_style(ACCENT.darkened(0.25)))
	_slider.add_theme_stylebox_override("grabber_area_highlight", _bar_style(ACCENT))
	_slider.value_changed.connect(_on_slider)
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(func(_v: bool) -> void: _dragging = false)
	hb.add_child(_slider)

	_auto = Label.new()
	_auto.text = "T 自动"
	_auto.add_theme_color_override("font_color", Color(0.62, 0.66, 0.76))
	_auto.add_theme_font_size_override("font_size", 11)
	hb.add_child(_auto)

	# ---- 右下角：操作提示
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -240
	_hint.offset_top = -56
	_hint.offset_right = -10
	_hint.offset_bottom = -38
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.text = "WASD / 方向键 行走    T 昼夜自动播放    F1 影子    F2 界面"
	_hint.add_theme_color_override("font_color", Color(0.80, 0.84, 0.92, 0.85))
	_hint.add_theme_font_size_override("font_size", 11)
	root.add_child(_hint)


func _on_slider(v: float) -> void:
	_main.set_time(v)


func _process(delta: float) -> void:
	if _main == null or _main.daynight == null:
		return
	var dn = _main.daynight
	if not _dragging:
		_slider.set_value_no_signal(dn.time)
	_clock.text = dn.clock_text()
	_phase.text = dn.phase_text()
	_auto.modulate = Color(1, 1, 1) if dn.auto_advance else Color(1, 1, 1, 0.45)

	if _hint_t < 9.0:
		_hint_t += delta
		_hint.modulate = Color(1, 1, 1, clampf(9.0 - _hint_t, 0.0, 1.5) / 1.5)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	return s


func _bar_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	return s
