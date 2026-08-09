## 顶部键提示栏（对应 game_scene.render_hints：键名 ACCENT + 说明 DIM）。
## 键名从 InputBindings 读实际绑定，改键后自动跟随；说明经 Loc.t 翻译。
class_name HintBar
extends Control

const HEIGHT := 30

var _labels: Array = []   # [Label]

func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## 从场景的 get_hints() 重建提示行。
func refresh(screen: BaseScreen) -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	var title_label := Label.new()
	title_label.text = Loc.t(screen.screen_title) if screen.screen_title != "" else ""
	title_label.add_theme_color_override("font_color", UiTheme.HEADING)
	title_label.add_theme_font_size_override("font_size", 15)
	add_child(title_label)
	_labels.append(title_label)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	add_child(hb)
	_labels.append(hb)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in screen.get_hints():
		var key: String = pair[0]
		var desc: String = pair[1]
		var key_label := Label.new()
		key_label.text = Loc.t(key)
		key_label.add_theme_color_override("font_color", UiTheme.ACCENT)
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(key_label)
		_labels.append(key_label)
		var desc_label := Label.new()
		desc_label.text = Loc.t(desc)
		desc_label.add_theme_color_override("font_color", UiTheme.DIM)
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(desc_label)
		_labels.append(desc_label)

## 键名 → 动作名（供场景写提示时用键名而非动作名）。
static func key_name(action: String) -> String:
	return InputBindings.action_key_name(action)
