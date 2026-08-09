## 招募界面（对应 recruit.py，Z 键/左下"招募"）：屏幕三等分三栏。
## 每栏 = 一个招募池槽位（英雄信息 + 招募要求 + 底部招募按钮）。
## 顶部：据点切换（◀ 据点名 ▶，每据点独立 14 天刷新池）。
class_name RecruitScreen
extends BasePage

var _strongholds: Array = []   # 己方据点 id
var _sh_idx := 0
var _cols: Array = []          # [Frame, status_label, detail_label, btn]

func build() -> void:
	page_title = Loc.t("recruit")
	var vbox := make_content()
	vbox.add_theme_constant_override("separation", 8)
	# 顶部：据点切换
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 16)
	vbox.add_child(top)
	var prev := Button.new()
	prev.text = "◀"
	prev.pressed.connect(func(): _switch_stronghold(-1))
	top.add_child(prev)
	var sh_label := Label.new()
	sh_label.add_theme_font_size_override("font_size", 15)
	sh_label.add_theme_color_override("font_color", UiTheme.HEADING)
	sh_label.custom_minimum_size = Vector2(240, 0)
	sh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sh_label)
	var next := Button.new()
	next.text = "▶"
	next.pressed.connect(func(): _switch_stronghold(1))
	top.add_child(next)
	# 三栏
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	for i in range(3):
		var frame := Frame.new("%s %d" % [Loc.t("slot"), i + 1])
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(frame)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		frame.add_child(col)
		var status := Label.new()
		status.add_theme_font_size_override("font_size", 14)
		status.add_theme_color_override("font_color", UiTheme.HEADING)
		col.add_child(status)
		var detail := Label.new()
		detail.add_theme_font_size_override("font_size", 13)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(detail)
		var btn := Button.new()
		btn.text = Loc.t("recruit")
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(func(): _do_recruit(i))
		col.add_child(btn)
		_cols.append([frame, status, detail, btn])
	_frame_title = sh_label
	add_hint_label()

var _frame_title: Label

func enter_page(params: Variant = null) -> void:
	_strongholds.clear()
	var p := GameController.player()
	for sid in p.stronghold_ids:
		_strongholds.append(sid)
	_sh_idx = 0
	_rebuild()
	refresh_hints()

func _switch_stronghold(delta: int) -> void:
	if _strongholds.is_empty():
		return
	_sh_idx = (_sh_idx + delta + _strongholds.size()) % _strongholds.size()
	_rebuild()

func _pool() -> Variant:
	var f := GameController.player()
	return f.recruitment_pools.get(_strongholds[_sh_idx])

func _rebuild() -> void:
	var g := GameController.game
	if _strongholds.is_empty():
		_frame_title.text = Loc.t("no_stronghold")
		for col in _cols:
			col[1].text = ""
			col[2].text = ""
			col[3].visible = false
		return
	_frame_title.text = "%s: %s" % [Loc.t("stronghold"),
		Loc.t(g.map.strongholds[_strongholds[_sh_idx]].name)]
	var pool: Variant = _pool()
	for i in range(3):
		var frame: Frame = _cols[i][0]
		var status: Label = _cols[i][1]
		var detail: Label = _cols[i][2]
		var btn: Button = _cols[i][3]
		frame.title = "%s %d" % [Loc.t("slot"), i + 1]
		frame.queue_redraw()
		var hid: Variant = pool.offerings[i] if pool != null and i < pool.offerings.size() else null
		if hid == null:
			status.text = Loc.t("empty_slot")
			status.add_theme_color_override("font_color", UiTheme.DIM)
			detail.text = ""
			btn.visible = false
			continue
		var hdef: Heroes.HeroDef = g.hero_defs[hid]
		var f := GameController.player()
		var ok_belief := Heroes.meets_belief_req(f.belief, hdef.belief_req)
		var ok_res := f.resources.can_afford(hdef.recruit_cost)
		status.text = Loc.t(hdef.name)
		status.add_theme_color_override("font_color", UiTheme.GOLD)
		detail.text = _hero_detail(hdef, ok_belief, ok_res)
		btn.visible = true
		btn.disabled = not ok_belief or not ok_res

func _hero_detail(hdef: Heroes.HeroDef, ok_belief: bool, ok_res: bool) -> String:
	var lines: Array[String] = [
		Loc.t("tags") + " " + _tags_str(hdef.tags),
		Loc.t("cost") + " " + _cost_str(hdef.recruit_cost),
		Loc.t("belief_req") + " " + Heroes.describe_req(hdef.belief_req),
		Loc.t("skills") + " " + "、".join(hdef.skills),
	]
	if not ok_belief:
		lines.append(Loc.t("req_not_met"))
	elif not ok_res:
		lines.append(Loc.t("req_poor"))
	return "\n".join(lines)

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

func _do_recruit(col_idx: int) -> void:
	var g := GameController.game
	var pool: Variant = _pool()
	if pool == null or col_idx >= pool.offerings.size():
		return
	var hid: Variant = pool.offerings[col_idx]
	if hid == null:
		return
	var msg := g.action_recruit_hero(g.player_id, _strongholds[_sh_idx], hid)
	GameController.push_log(msg, msg.begins_with("失败"))
	_rebuild()

func get_hints() -> Array:
	return [["◀▶", "stronghold"], ["1-3", "column"], ["ESC", "close"]]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("filter_1"):
		_do_recruit(0)
	elif event.is_action_pressed("filter_2"):
		_do_recruit(1)
	elif event.is_action_pressed("filter_3"):
		_do_recruit(2)
	elif event.is_action_pressed("ui_left"):
		_switch_stronghold(-1)
	elif event.is_action_pressed("ui_right"):
		_switch_stronghold(1)
