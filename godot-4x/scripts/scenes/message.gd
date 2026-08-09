## 消息框（对应 pyconsole/scenes/message.py）：任意键关闭。
class_name Message
extends BaseWindow

var text: String = ""
var close_hint: String = "close_hint"
var _label: Label

func build() -> void:
	win_title = Loc.t("message")
	win_size = Vector2i(480, 220)
	var vbox := make_content()
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 16)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_label)
	var hint := Label.new()
	hint.text = Loc.t(close_hint)
	hint.add_theme_color_override("font_color", UiTheme.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	# 鼠标关闭（回车之外的等价物）
	var ok_btn := Button.new()
	ok_btn.text = Loc.t("ok")
	ok_btn.custom_minimum_size = Vector2(120, 34)
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok_btn.pressed.connect(func(): SceneStack.close_window())
	vbox.add_child(ok_btn)

func enter_window(params: Variant = null) -> void:
	if params is Dictionary:
		if params.has("text"):
			text = params["text"]
		if params.has("close_hint"):
			close_hint = params["close_hint"]
	_label.text = Loc.t(text)

func get_hints() -> Array:
	return [["Enter", "close_hint"]]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		SceneStack.close_window()
