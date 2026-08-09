## 图标按钮（现代 4X 底部工具条风格）：程序绘制矢量图标 + 下方文字。
## 美术替换点：日后换真实图标时把 _draw 里的矢量绘制换成 TextureRect 子节点。
class_name IconButton
extends Control

signal pressed

enum Kind { TECH, SQUAD, RECRUIT, WIKI, LOG, SETTINGS, END_TURN, MORE }

var kind := Kind.TECH
var label := ""
var icon_color: Color = UiTheme.FG

var _hovered := false
var _pressed := false

func _init(kind_: Kind = Kind.TECH, label_: String = "") -> void:
	kind = kind_
	label = label_
	custom_minimum_size = Vector2(56, 58)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func():
		_hovered = false
		_pressed = false
		queue_redraw())

func _draw() -> void:
	var box := Rect2(0, 0, 56, 44)
	# 底框
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.PANEL_BG.darkened(0.2)
	sb.set_corner_radius_all(8)
	sb.border_color = UiTheme.ACCENT if _hovered else UiTheme.BORDER
	sb.set_border_width_all(_hovered if 2 else 1)
	draw_style_box(sb, box)
	# 图标
	var c := icon_color if not _hovered else UiTheme.ACCENT
	match kind:
		Kind.TECH:
			_draw_flask(c)
		Kind.SQUAD:
			_draw_person(c)
		Kind.RECRUIT:
			_draw_person(c)
			draw_string(get_theme_default_font(), Vector2(40, 30), "+",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.C_OWN)
		Kind.WIKI:
			_draw_book(c)
		Kind.LOG:
			_draw_log(c)
		Kind.SETTINGS:
			_draw_gear(c)
		Kind.END_TURN:
			_draw_fast_forward(c)
		Kind.MORE:
			_draw_more(c)
	# 文字
	var font := get_theme_default_font()
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2((56 - tw) / 2.0, 55), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.DIM.lightened(0.1))

## 烧瓶（科技/文化）。
func _draw_flask(c: Color) -> void:
	draw_line(Vector2(23, 8), Vector2(33, 8), c, 3.0)
	draw_line(Vector2(26, 8), Vector2(26, 14), c, 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(19, 14), Vector2(37, 14), Vector2(32, 32), Vector2(24, 32)]), c)

## 小人（部队/招募）。
func _draw_person(c: Color) -> void:
	draw_circle(Vector2(28, 13), 5.5, c)
	draw_rect(Rect2(19, 21, 18, 13), c)

## 书本（百科）。
func _draw_book(c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(c, 0.25)
	sb.set_corner_radius_all(3)
	draw_style_box(sb, Rect2(16, 12, 24, 22))
	draw_line(Vector2(28, 12), Vector2(28, 34), c, 2.0)

## 日志（纸页 + 行）。
func _draw_log(c: Color) -> void:
	draw_rect(Rect2(16, 10, 24, 26), c)
	draw_line(Vector2(20, 17), Vector2(36, 17), UiTheme.PANEL_BG.darkened(0.3), 2.0)
	draw_line(Vector2(20, 23), Vector2(36, 23), UiTheme.PANEL_BG.darkened(0.3), 2.0)
	draw_line(Vector2(20, 29), Vector2(32, 29), UiTheme.PANEL_BG.darkened(0.3), 2.0)

## 快进双三角（结束回合）。
func _draw_fast_forward(c: Color) -> void:
	for k in range(2):
		var ox: float = 20.0 + k * 9
		draw_colored_polygon(PackedVector2Array([
			Vector2(ox, 14), Vector2(ox + 9, 22), Vector2(ox, 30)]), c)

## 三个点（更多）。
func _draw_more(c: Color) -> void:
	for k in range(3):
		draw_circle(Vector2(18 + k * 10, 23), 3.0, c)

## 齿轮（设置）。
func _draw_gear(c: Color) -> void:
	draw_circle(Vector2(28, 23), 6.0, c)
	draw_circle(Vector2(28, 23), 2.5, UiTheme.PANEL_BG.darkened(0.2))
	for i in range(8):
		var ang := i * TAU / 8.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(Vector2(28, 23) + d * 8, Vector2(28, 23) + d * 11, c, 3.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			queue_redraw()
		elif _pressed:
			_pressed = false
			queue_redraw()
			pressed.emit()
		accept_event()
