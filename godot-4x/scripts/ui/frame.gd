## 程序生成边框面板（美术替换点）。
##
## 目前用 draw 绘制圆角背景 + 边框 + 标题，零美术资源（对应 Python 原型 draw_box）。
## 日后替换美术资源：把 _draw() 的绘制换成 NinePatchRect 贴图子节点即可，
## 调用方（各场景布局）不需要改动——见 UiTheme 注释。
class_name Frame
extends PanelContainer

var title: String = "":
	set(v):
		title = v
		queue_redraw()
var border_color: Color = UiTheme.BORDER:
	set(v):
		border_color = v
		queue_redraw()
var bg_color: Color = UiTheme.PANEL_BG:
	set(v):
		bg_color = v
		queue_redraw()
var title_color: Color = UiTheme.ACCENT
var title_font_size := 14
var corner_radius := 8
var title_offset := 12
var draw_title := true

func _init(title_: String = "") -> void:
	title = title_
	mouse_filter = Control.MOUSE_FILTER_PASS

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if size.x < 8 or size.y < 8:
		return
	# 背景
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(corner_radius)
	draw_style_box(sb, r)
	# 边框
	var c := border_color
	var lw := 1.0
	draw_line(Vector2(corner_radius, lw), Vector2(size.x - corner_radius, lw), c, lw)
	draw_line(Vector2(corner_radius, size.y - lw), Vector2(size.x - corner_radius, size.y - lw), c, lw)
	draw_line(Vector2(lw, corner_radius), Vector2(lw, size.y - corner_radius), c, lw)
	draw_line(Vector2(size.x - lw, corner_radius), Vector2(size.x - lw, size.y - corner_radius), c, lw)
	# 标题
	if draw_title and title != "":
		var font := get_theme_default_font()
		draw_string(font, Vector2(title_offset, title_font_size + 4),
			Loc.t(title), HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_font_size, title_color)

## 便捷工厂：包住子控件的带框面板。
static func wrap(child: Control, title_: String = "", margin: int = 8) -> Frame:
	var f := Frame.new(title_)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", margin)
	mc.add_theme_constant_override("margin_right", margin)
	mc.add_theme_constant_override("margin_top", margin)
	mc.add_theme_constant_override("margin_bottom", margin)
	mc.add_child(child)
	f.add_child(mc)
	return f
