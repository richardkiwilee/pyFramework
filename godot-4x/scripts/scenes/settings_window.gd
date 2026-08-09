## 设置窗（顶栏"设置"按钮）：屏幕居中弹出。
## 内容：语言切换 / 按键绑定（点击条目→按下新键改绑）/ 保存游戏 / 返回主菜单。
class_name SettingsWindow
extends BaseWindow

var _lang_btn: Button
var _list: ListWidget
var _status: Label
var _capture_action := ""      # 正在等待按键的动作
var _rows: Array = []          # [[动作, 说明 key]]

func build() -> void:
	win_title = Loc.t("settings")
	win_size = Vector2i(460, 620)
	var vbox := make_content()
	# 语言
	_lang_btn = Button.new()
	_lang_btn.pressed.connect(_toggle_lang)
	vbox.add_child(_lang_btn)
	# 按键绑定
	var key_label := Label.new()
	key_label.text = Loc.t("keybindings")
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", UiTheme.HEADING)
	vbox.add_child(key_label)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UiTheme.ACCENT)
	vbox.add_child(_status)
	_list = ListWidget.new()
	_list.custom_minimum_size = Vector2(0, 320)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_list)
	_list.text_fn = func(d): return "%s  %s" % [Loc.t(d[1]), InputBindings.action_key_name(d[0])]
	_list.color_fn = func(d): return UiTheme.FG
	_list.row_selected.connect(func(idx): _start_capture(idx))
	# 动作按钮
	var save_btn := Button.new()
	save_btn.text = Loc.t("save_game")
	save_btn.pressed.connect(_save)
	vbox.add_child(save_btn)
	var menu_btn := Button.new()
	menu_btn.text = Loc.t("esc_to_menu")
	menu_btn.pressed.connect(func(): SceneStack.close_window("to_menu"))
	vbox.add_child(menu_btn)
	add_hint_label()

func enter_window(params: Variant = null) -> void:
	esc_closes = false   # ESC 在改键时用于取消；不捕获时手动关闭
	_rows.clear()
	for pair in InputBindings.HINTS:
		_rows.append([pair[0], pair[1]])
	var extra: Array = [
		["open_recruit_unit", "hint_recruit_unit"],
		["open_unit", "hint_unit"],
		["open_stronghold_overview", "hint_stronghold_overview"],
		["open_inventory", "hint_inventory"],
		["new_army", "hint_new_army"],
		["toggle_language", "hint_lang"],
	]
	for e in extra:
		_rows.append(e)
	_list.set_items(_rows)
	_refresh_lang()
	_set_status("")
	refresh_hints()

func _toggle_lang() -> void:
	Loc.toggle_language()
	_refresh_lang()

func _refresh_lang() -> void:
	var cur := "中文" if not Loc.is_english() else "English"
	_lang_btn.text = "%s: %s" % [Loc.t("lang_hint"), cur]

func _save() -> void:
	var msg := GameController.save()
	GameController.push_log(msg)
	_set_status(msg)

func _set_status(msg: String) -> void:
	_status.text = msg

## 点击条目 → 等待按下新键（ESC 取消）。
func _start_capture(idx: int) -> void:
	if idx >= _rows.size():
		return
	_capture_action = _rows[idx][0]
	_set_status("%s ..." % Loc.t("press_key_hint"))

func _finish_capture(key: Key) -> void:
	if _capture_action == "":
		return
	var ok := InputBindings.rebind(_capture_action, key)
	_set_status(Loc.t("keybound") + " %s" % OS.get_keycode_string(key) if ok else Loc.t("keybind_fail"))
	_capture_action = ""
	_list.queue_redraw()

func get_hints() -> Array:
	return [["ESC", "close"]]

func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _capture_action != "":
			if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
				_capture_action = ""
				_set_status("")
			else:
				_finish_capture(event.physical_keycode)
			return
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			SceneStack.close_window(null)
			return
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_start_capture(_list.focused)
