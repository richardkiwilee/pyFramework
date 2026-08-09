## 装备选择子模式（unit_roster 的空槽回车进入）：列在库可用装备，回车装备。
class_name EquipPicker
extends BaseWindow

var unit_id: String = ""
var slot: int = -1
var ids: Array = []
var labels: Array = []
var _list: ListWidget

func build() -> void:
	win_title = Loc.t("choose_artifact")
	win_size = Vector2i(420, 400)
	var vbox := make_content()
	_list = ListWidget.new()
	_list.custom_minimum_size = Vector2(380, 320)
	_list.set_items(labels)
	_list.color_fn = func(d): return UiTheme.FG
	# 单击即装备（简单选择器无详情页；与事件弹窗同语义）
	_list.row_selected.connect(func(idx): _confirm(idx))
	_list.row_activated.connect(func(idx): _confirm(idx))
	vbox.add_child(_list)

func get_hints() -> Array:
	return [["↑↓", "move"], ["Enter", "confirm"], ["ESC", "cancel"]]

func enter_window(params: Variant = null) -> void:
	_list.focus_to(0)
	refresh_hints()

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_confirm(_list.focused)

func _confirm(idx: int) -> void:
	if idx < ids.size():
		SceneStack.close_window([unit_id, ids[idx]])
