## 据点总览（对应 stronghold_overview.py）：表格纵览所有据点。
## 1234 筛选（我方/敌方/中立/全部）；回车进入据点场景预选该据点。
class_name StrongholdOverviewScreen
extends BasePage

enum Filter { OWN, ENEMY, NEUTRAL, ALL }

var _list: ListWidget
var _filter := Filter.OWN
var _strongholds: Array = []   # [id] 过滤后

func build() -> void:
	page_title = Loc.t("stronghold_overview")
	var vbox := make_content()
	var frame := Frame.new(Loc.t("stronghold_overview"))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(frame)
	_list = ListWidget.new()
	frame.add_child(_list)
	_list.text_fn = func(d): return _row_text(d)
	_list.color_fn = func(d): return _row_color(d)
	_list.row_selected.connect(func(idx): pass)
	_list.row_activated.connect(func(idx): _open(idx))

func _row_text(id: String) -> String:
	var g := GameController.game
	var sh: MapSystem.Stronghold = g.map.strongholds[id]
	var parts: Array[String] = ["◆" + Loc.t(sh.name)]
	if sh.is_capital:
		parts.append("(都)")
	parts.append(Loc.t(sh.landmark.name) if sh.landmark != null else "-")
	for slot in range(5):
		if slot < sh.size:
			if slot < sh.buildings.size():
				parts.append(Loc.t(sh.buildings[slot].name))
			else:
				parts.append("·")
		else:
			parts.append("X")
	return "  ".join(parts)

func _row_color(id: String) -> Color:
	var sh: MapSystem.Stronghold = GameController.game.map.strongholds[id]
	if sh.owner == GameController.game.player_id:
		return UiTheme.C_OWN
	if sh.owner == "":
		return UiTheme.C_NEUTRAL
	return UiTheme.C_ENEMY

func enter_page(params: Variant = null) -> void:
	_rebuild()
	refresh_hints()

func _rebuild() -> void:
	var g := GameController.game
	_strongholds.clear()
	for sid in g.map.strongholds:
		var sh: MapSystem.Stronghold = g.map.strongholds[sid]
		var ok_pass := false
		match _filter:
			Filter.OWN:
				ok_pass = sh.owner == g.player_id
			Filter.ENEMY:
				ok_pass = sh.owner != "" and sh.owner != g.player_id
			Filter.NEUTRAL:
				ok_pass = sh.owner == ""
			Filter.ALL:
				ok_pass = true
		if ok_pass:
			_strongholds.append(sid)
	_list.set_items(_strongholds)

func _open(idx: int) -> void:
	if idx >= _strongholds.size():
		return
	open_page(load("res://scenes/windows/stronghold.tscn").instantiate(),
		{"preselect": _strongholds[idx]})

func get_hints() -> Array:
	return [
		["↑↓", "move"], ["Enter", "open"], ["1-4", "filter"], ["ESC", "close"],
	]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("filter_1"):
		_filter = Filter.OWN
		_rebuild()
	elif event.is_action_pressed("filter_2"):
		_filter = Filter.ENEMY
		_rebuild()
	elif event.is_action_pressed("filter_3"):
		_filter = Filter.NEUTRAL
		_rebuild()
	elif event.is_action_pressed("filter_4"):
		_filter = Filter.ALL
		_rebuild()
	elif event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
	elif event.is_action_pressed("ui_accept"):
		_open(_list.focused)

