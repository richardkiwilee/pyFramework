## 事件选择弹窗（§9：回合开始随机触发的选择支；Godot 版做成交互弹窗，
## 优于 TUI 的自动选 0 方案——玩家可自由选择）。
class_name EventDialog
extends BaseWindow

var event: GameEvents.GameEvent = null
var _list: ListWidget
var _detail: TextInfo
var _title_label: Label

func build() -> void:
	win_title = Loc.t("event")
	win_size = Vector2i(600, 440)
	var vbox := make_content()
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	vbox.add_child(_title_label)
	_detail = TextInfo.new()
	_detail.custom_minimum_size = Vector2(540, 150)
	vbox.add_child(_detail)
	_list = ListWidget.new()
	_list.custom_minimum_size = Vector2(540, 120)
	_list.color_fn = func(d): return UiTheme.FG
	# 事件选项无"详情"语义：单击/双击/回车都直接执行选择
	_list.row_selected.connect(func(idx): _choose(idx))
	_list.row_activated.connect(func(idx): _choose(idx))
	vbox.add_child(_list)

func get_hints() -> Array:
	return [["↑↓", "move"], ["Enter/Click", "confirm"]]

func enter_window(params: Variant = null) -> void:
	if event == null and params is GameEvents.GameEvent:
		event = params
	_title_label.text = Loc.t(event.title)
	_detail.text = Loc.t(event.text)
	var opts: Array = []
	for o in event.options:
		opts.append(o.label)
	_list.set_items(opts)
	_list.focus_to(0)
	refresh_hints()

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_choose(_list.focused)

func _choose(idx: int) -> void:
	if idx < event.options.size():
		var msg := GameController.game.resolve_event(idx)
		GameController.push_log(msg)
		SceneStack.close_window("event_chosen")
