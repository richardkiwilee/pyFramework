## 据点一览（对应 stronghold.py）：4 层嵌套窗口。
## W1 据点列表 → W2 单据点详情 → W3 槽位操作（建造/拆除）→ W4 候选建筑。
## → 逐层进入，← 回退，回车等同 →。非己方据点只读。
class_name StrongholdScreen
extends BasePage

var preselect: String = ""   # 预选据点 id（V 总览进入）
var _layer := 0           # 0=W1 1=W2 2=W3 3=W4
var _stronghold_id := ""
var _slot_idx := -1       # W3 选中的槽位
var _list: ListWidget     # 当前层列表
var _detail: TextInfo
var _frame_title: Label
var _state: Dictionary = {}   # 层状态（列表数据/焦点）


func build() -> void:
	page_title = Loc.t("stronghold")
	var vbox := make_content()
	_frame_title = Label.new()
	_frame_title.add_theme_font_size_override("font_size", 14)
	_frame_title.add_theme_color_override("font_color", UiTheme.HEADING)
	vbox.add_child(_frame_title)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	var left := Frame.new(Loc.t("stronghold_list"))
	left.custom_minimum_size = Vector2(360, 0)
	hbox.add_child(left)
	_list = ListWidget.new()
	left.add_child(_list)
	_list.text_fn = func(d): return d[0]
	_list.color_fn = func(d): return d[1]
	_list.row_selected.connect(func(idx): _render_detail())
	_list.row_activated.connect(func(idx): _enter_layer(idx))
	var right := Frame.new(Loc.t("stronghold_detail"))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_detail = TextInfo.new()
	right.add_child(_detail)

func enter_page(params: Variant = null) -> void:
	esc_closes = false   # ESC = 回退层，不是关闭窗口
	_layer = 0
	_stronghold_id = ""
	if params is Dictionary and params.get("preselect", "") != "":
		preselect = params["preselect"]
	if preselect != "":
		_stronghold_id = preselect
		_layer = 1
		_rebuild_list()
	else:
		_enter_layer(0)
	refresh_hints()

## 层数据：layer 0 = 据点列表；1 = 详情（无列表，detail 显示）；2 = 槽位；3 = 候选建筑。
func _enter_layer(idx: int) -> void:
	var g := GameController.game
	match _layer:
		0:
			# 进入单据点
			var sids := _stronghold_ids()
			if idx >= sids.size():
				return
			_stronghold_id = sids[idx]
			_layer = 1
		1:
			# 详情层：仅己方据点可进入槽位层
			var sh: MapSystem.Stronghold = g.map.strongholds[_stronghold_id]
			if sh.owner == g.player_id:
				_layer = 2
		2:
			# 槽位层：已建 → 拆除；空槽 → 候选建筑
			var sh2: MapSystem.Stronghold = g.map.strongholds[_stronghold_id]
			if idx < sh2.size:
				if idx < sh2.buildings.size():
					var b: MapSystem.Building = sh2.buildings[idx]
					var msg := g.action_demolish(g.player_id, _stronghold_id, b.id)
					GameController.push_log(msg, msg.begins_with("失败"))
				else:
					_slot_idx = idx
					_layer = 3
		3:
			# 候选建筑层：回车建造
			var cand: Array = _list.items[idx]
			if cand.size() >= 3:
				var msg2 := g.action_build(g.player_id, _stronghold_id, cand[2])
				GameController.push_log(msg2, msg2.begins_with("失败"))
				_layer = 2
				_rebuild_list()
				return
	_rebuild_list()

func _stronghold_ids() -> Array:
	var g := GameController.game
	var out: Array = []
	for sid in g.map.strongholds:
		out.append(sid)
	return out

func _rebuild_list() -> void:
	var g := GameController.game
	var rows: Array = []
	match _layer:
		0:
			for sid in _stronghold_ids():
				var sh: MapSystem.Stronghold = g.map.strongholds[sid]
				var col := UiTheme.C_OWN if sh.owner == g.player_id else (
					UiTheme.C_NEUTRAL if sh.owner == "" else UiTheme.C_ENEMY)
				rows.append(["%s %s" % [Loc.t(sh.name), "(都)" if sh.is_capital else ""], col])
			_list.set_items(rows)
			_frame_title.text = Loc.t("layer_strongholds")
		1:
			_list.set_items([])
			_frame_title.text = Loc.t("layer_detail")
			_render_detail()
		2:
			var sh: MapSystem.Stronghold = g.map.strongholds[_stronghold_id]
			_frame_title.text = "%s - %s" % [Loc.t(sh.name), Loc.t("layer_slots")]
			for i in range(sh.size):
				if i < sh.buildings.size():
					var b: MapSystem.Building = sh.buildings[i]
					rows.append(["%d. %s  %s" % [i + 1, Loc.t(b.name), Loc.t("demolish")], UiTheme.FG])
				else:
					rows.append(["%d. %s" % [i + 1, Loc.t("empty_slot")], UiTheme.DIM])
			_list.set_items(rows)
		3:
			var sh3: MapSystem.Stronghold = g.map.strongholds[_stronghold_id]
			_frame_title.text = "%s - %s %d" % [Loc.t(sh3.name), Loc.t("build_candidates"), _slot_idx + 1]
			var cands := _build_candidates(sh3)
			rows = cands
			_list.set_items(rows)
			_render_detail()

## 可建建筑候选：[名称, 色, type_id]。
func _build_candidates(sh: MapSystem.Stronghold) -> Array:
	var g := GameController.game
	var p := GameController.player()
	var out: Array = []
	for bid in g.building_defs:
		var bdef: Dictionary = g.building_defs[bid]
		var kind: String = bdef.get("kind", "")
		if kind not in ["produce", "recruit", "special"]:
			continue
		# 已建过同类型？原型允许重复建（槽位内），此处不查
		var requires: Array = bdef.get("requires", [])
		var unmet := g._unmet_requires(g.player_id, requires)
		var affordable := p.resources.can_afford(bdef.get("cost", {}))
		var col: Color
		if not unmet.is_empty():
			col = UiTheme.C_ENEMY
		elif not affordable:
			col = UiTheme.WARN
		else:
			col = UiTheme.C_NEUTRAL
		out.append([Loc.t(bdef.get("name", bid)), col, bid])
	return out

func _render_detail() -> void:
	var g := GameController.game
	if _layer == 0 or _stronghold_id == "":
		_detail.text = Loc.t("select_stronghold")
		return
	var sh: MapSystem.Stronghold = g.map.strongholds[_stronghold_id]
	var owner := Loc.t("neutral") if sh.owner == "" else Loc.t(g.factions[sh.owner].name)
	var lines: Array[String] = [
		"%s  %s" % [Loc.t(sh.name), owner],
		"%s %d/%d   %s: %s" % [Loc.t("slots"), sh.buildings.size(), sh.size,
			Loc.t("landmark"), Loc.t(sh.landmark.name) if sh.landmark != null else "-"],
	]
	for b in sh.buildings:
		lines.append("  - " + Loc.t(b.name))
	if _layer == 3 and not _list.items.is_empty():
		var bid: String = _list.items[_list.focused][2]
		var bdef: Dictionary = g.building_defs.get(bid, {})
		var extra: Array[String] = []
		var cost: Dictionary = bdef.get("cost", {})
		var cost_parts: Array[String] = []
		for k in cost:
			cost_parts.append("%s %d" % [Economy.RESOURCE_CN.get(k, k), int(cost[k])])
		extra.append(Loc.t("cost") + " " + "、".join(cost_parts))
		var requires: Array = bdef.get("requires", [])
		if not requires.is_empty():
			extra.append(Loc.t("requires") + " " + "、".join(requires))
		var produces: Dictionary = bdef.get("produces", {})
		if not produces.is_empty():
			var prod_parts: Array[String] = []
			for k in produces:
				prod_parts.append("%s %d" % [Economy.RESOURCE_CN.get(k, k), int(produces[k])])
			extra.append(Loc.t("produces") + " " + "、".join(prod_parts))
		lines.append("")
		lines.append_array(extra)
	_detail.text = "\n".join(lines)

func get_hints() -> Array:
	return [
		["↑↓", "move"], ["→/Enter", "enter"], ["←", "back"],
		["Enter", "build" if _layer == 3 else "enter"], ["ESC", "close"],
	]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
		_render_detail()
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
		_render_detail()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		_enter_layer(_list.focused)
	elif event.is_action_pressed("ui_left"):
		if _layer > 0:
			_layer -= 1
			if _layer == 1:
				_stronghold_id = ""
			_rebuild_list()
	elif event.is_action_pressed("ui_cancel"):
		# ESC：非首层回退一层；首层关闭窗口返回主界面（反馈#1）
		if _layer > 0:
			_layer -= 1
			if _layer == 1:
				_stronghold_id = ""
			_rebuild_list()
		else:
			close_requested.emit()

func refresh() -> void:
	_rebuild_list()
