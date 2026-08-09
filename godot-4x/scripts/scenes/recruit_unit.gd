## 招兵界面（对应 recruit_unit.py，普通兵）：全局招募普通兵种列表。
## 解锁判定：阵营任一己方据点建成对应招募建筑即解锁；可招状态分三色。
class_name RecruitUnitScreen
extends BasePage

var _list: ListWidget
var _detail: TextInfo
var _entries: Array = []   # [unit_type_id, 状态]

enum St { OK, POOR, LOCKED }

func build() -> void:
	page_title = Loc.t("recruit_unit")
	var vbox := make_content()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	var left := Frame.new(Loc.t("recruit_unit_list"))
	left.custom_minimum_size = Vector2(440, 0)
	hbox.add_child(left)
	_list = ListWidget.new()
	left.add_child(_list)
	_list.text_fn = func(d): return _row_text(d)
	_list.color_fn = func(d): return _row_color(d)
	_list.row_selected.connect(func(idx): _show(idx))
	_list.row_activated.connect(func(idx): _recruit(idx))
	var right := Frame.new(Loc.t("recruit_unit_detail"))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_detail = TextInfo.new()
	right.add_child(_detail)

func enter_page(params: Variant = null) -> void:
	_rebuild()
	refresh_hints()

func _rebuild() -> void:
	var g := GameController.game
	var f := GameController.player()
	_entries.clear()
	for tid in g.unit_type_defs:
		var ut: Units.UnitType = g.unit_type_defs[tid]
		# 找到对应招募建筑
		var bid := ""
		var bname := ""
		for b in g.building_defs:
			var bdef: Dictionary = g.building_defs[b]
			if bdef.get("recruits", []).has(tid):
				bid = b
				bname = bdef.get("name", b)
				break
		var has_building := false
		if bid != "":
			for sid in f.stronghold_ids:
				var sh: Variant = g.map.strongholds.get(sid)
				if sh == null:
					continue
				for b in sh.buildings:
					if b.type_id == bid:
						has_building = true
						break
				if has_building:
					break
		var st: int
		if not has_building:
			st = St.LOCKED
		elif f.resources.can_afford(ut.recruit_cost):
			st = St.OK
		else:
			st = St.POOR
		_entries.append([tid, st, bname])
	_list.set_items(_entries.duplicate())
	_show(0)

func _row_text(e: Array) -> String:
	var g := GameController.game
	var ut: Units.UnitType = g.unit_type_defs[e[0]]
	var status := _status_cn(e[1])
	return "%s  (%s)  %s" % [Loc.t(ut.name), e[2] if e[2] != "" else "-", status]

func _status_cn(st: int) -> String:
	match st:
		St.OK: return Loc.t("can_recruit")
		St.POOR: return Loc.t("resource_short")
		_: return Loc.t("not_built")

func _row_color(e: Array) -> Color:
	match e[1]:
		St.OK: return UiTheme.C_OWN
		St.POOR: return UiTheme.WARN
		_: return UiTheme.DISABLED

func _show(idx: int) -> void:
	if _entries.is_empty():
		_detail.text = Loc.t("no_items")
		return
	var g := GameController.game
	var e: Array = _entries[idx]
	var ut: Units.UnitType = g.unit_type_defs[e[0]]
	var lines: Array[String] = [
		Loc.t(ut.name),
		Loc.t("tags") + " " + _tags_str(ut.tags),
		Loc.t("cost") + " " + _cost_str(ut.recruit_cost),
		Loc.t("building") + " " + (e[2] if e[2] != "" else "-"),
	]
	if ut.desc != "":
		lines.append(ut.desc)
	_detail.text = "\n".join(lines)

func _tags_str(tags: Array) -> String:
	var parts: Array[String] = []
	for t in tags:
		parts.append(Units.TAG_CN.get(t, t))
	return "/".join(parts)

func _cost_str(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [Economy.RESOURCE_CN.get(k, k), int(cost[k])])
	return "、".join(parts) if not parts.is_empty() else Loc.t("cost_free")

func get_hints() -> Array:
	return [["↑↓", "move"], ["Enter", "recruit"], ["ESC", "close"]]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
		_show(_list.focused)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
		_show(_list.focused)
	elif event.is_action_pressed("ui_accept"):
		_recruit(_list.focused)

func _recruit(idx: int) -> void:
	if _entries.is_empty():
		return
	var e: Array = _entries[idx]
	if e[1] != St.OK:
		return
	var msg := GameController.game.action_recruit_unit(GameController.game.player_id, e[0])
	GameController.push_log(msg, msg.begins_with("失败"))
	_rebuild()
