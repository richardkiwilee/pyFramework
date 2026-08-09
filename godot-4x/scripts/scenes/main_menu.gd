## 主菜单（Godot 最佳实践：按钮式，鼠标点击）。
## 开始游戏 / 继续游戏 / 退出游戏 + 语言切换。主界面切换用 change_scene（旧场景销毁）。
class_name MainMenu
extends BaseScreen

var _lang_btn: Button
var _menu_btns: Array = []   # [btn_start, btn_continue, btn_quit, btn_lang]

func build() -> void:
	screen_title = "TheGreatConquest"
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)
	var title := Label.new()
	title.text = "TheGreatConquest"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", UiTheme.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = Loc.t("subtitle")
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UiTheme.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	vbox.add_child(_spacer())
	# 按钮
	var btn_start := Button.new()
	btn_start.text = Loc.t("start_game")
	btn_start.custom_minimum_size = Vector2(320, 40)
	btn_start.pressed.connect(_start_game)
	vbox.add_child(btn_start)
	_menu_btns.append(btn_start)
	var btn_continue := Button.new()
	btn_continue.text = Loc.t("continue_game")
	btn_continue.custom_minimum_size = Vector2(320, 40)
	btn_continue.pressed.connect(_continue_game)
	vbox.add_child(btn_continue)
	_menu_btns.append(btn_continue)
	var btn_quit := Button.new()
	btn_quit.text = Loc.t("quit_game")
	btn_quit.custom_minimum_size = Vector2(320, 40)
	btn_quit.pressed.connect(func(): get_tree().quit())
	vbox.add_child(btn_quit)
	_menu_btns.append(btn_quit)
	_menu_btns.append(_lang_btn)
	# 语言切换
	_lang_btn = Button.new()
	_lang_btn.custom_minimum_size = Vector2(320, 32)
	_lang_btn.pressed.connect(_toggle_lang)
	vbox.add_child(_lang_btn)
	_refresh_lang()

func _spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, 20)
	return s

func _start_game() -> void:
	GameController.new_game()
	SceneStack.change_scene(load("res://scenes/game_screen.tscn").instantiate())

func _continue_game() -> void:
	var msg := GameController.load()
	if GameController.game != null and not msg.begins_with("无存档") and not msg.begins_with("读取失败"):
		SceneStack.change_scene(load("res://scenes/game_screen.tscn").instantiate())
	else:
		GameController.push_log(msg, true)

func _toggle_lang() -> void:
	Loc.toggle_language()
	if _menu_btns.size() >= 4:
		_menu_btns[0].text = Loc.t("start_game")
		_menu_btns[1].text = Loc.t("continue_game")
		_menu_btns[2].text = Loc.t("quit_game")
	_refresh_lang()
	refresh_hints()

func _refresh_lang() -> void:
	var cur := "中文" if not Loc.is_english() else "English"
	_lang_btn.text = "%s: %s" % [Loc.t("lang_hint"), cur]

## 键盘导航：↑↓ 切换焦点，Enter 由按钮自身处理。
func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		if _menu_btns.is_empty():
			return
		var cur := 0
		for i in range(_menu_btns.size()):
			if _menu_btns[i].has_focus():
				cur = i
				break
		var delta := -1 if event.is_action_pressed("ui_up") else 1
		var next := (cur + delta + _menu_btns.size()) % _menu_btns.size()
		_menu_btns[next].grab_focus()
		accept_event()
	elif event.is_action_pressed("toggle_language"):
		_toggle_lang()

func enter_scene(params: Variant = null) -> void:
	super(params)
	if not _menu_btns.is_empty():
		_menu_btns[0].grab_focus()
