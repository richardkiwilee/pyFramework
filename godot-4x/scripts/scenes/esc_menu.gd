## 退出选单（对应 esc_menu.py）：继续 / 保存 / 读取 / 返回主菜单。
class_name EscMenu
extends BaseWindow

var _list: ListWidget
var _menu: Array = []

func build() -> void:
	win_title = Loc.t("esc_menu")
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var frame := Frame.new(Loc.t("esc_menu"))
	frame.custom_minimum_size = Vector2(360, 260)
	center.add_child(frame)
	_menu = [Loc.t("esc_resume"), Loc.t("esc_save"), Loc.t("esc_load"), Loc.t("esc_to_menu")]
	_list = ListWidget.new()
	_list.custom_minimum_size = Vector2(320, 26 * 4 + 8)
	_list.set_items(_menu)
	_list.color_fn = func(d): return UiTheme.FG
	frame.add_child(_list)

func get_hints() -> Array:
	return [["↑↓", "move"], ["Enter", "confirm"], ["ESC", "close"]]

func enter_window(params: Variant = null) -> void:
	_list.focus_to(0)
	refresh_hints()

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		match _list.focused:
			0:   # 继续
				SceneStack.close_window()
			1:   # 保存
				var msg := GameController.save()
				GameController.push_log(msg)
				SceneStack.close_window("saved")
			2:   # 读取
				var msg2 := GameController.load()
				GameController.push_log(msg2)
				if GameController.game != null and not msg2.begins_with("读取失败") \
						and not msg2.begins_with("无存档"):
					SceneStack.close_window("saved")
				else:
					GameController.push_log(msg2, true)
			3:   # 返回主菜单
				SceneStack.close_window("to_menu")
