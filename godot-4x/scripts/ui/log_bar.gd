## 底部日志栏（对应 log.py render_log_bar：最近 3 条，warn 用警告色）。
## 全局日志：任何场景底部都显示，便于玩家看到操作失败原因。
class_name LogBar
extends Control

const HEIGHT := 26

var _label: Label

func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_constant_override("line_spacing", 0)

func refresh() -> void:
	var msgs := GameController.recent_log(3)
	if msgs.is_empty():
		_label.text = Loc.t("日志") + " " + Loc.t("（无）")
		_label.add_theme_color_override("font_color", UiTheme.DIM)
		return
	var parts: Array[String] = []
	for m in msgs:
		parts.append(m[0])
	_label.text = Loc.t("日志") + " │ " + " │ ".join(parts)
	# 任一 warn → 整行警告色
	var any_warn := false
	for m in msgs:
		if m[1]:
			any_warn = true
			break
	_label.add_theme_color_override("font_color", UiTheme.WARN if any_warn else UiTheme.DIM)
