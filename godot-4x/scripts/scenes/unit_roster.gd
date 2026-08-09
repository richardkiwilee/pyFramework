## 单位一览（对应 unit.py，X 键）：跨部队全局花名册。
## W1 单位列表；W2 详情（属性 3 列/维护费/训练消耗/技能面板）+ 底部训练按钮 + 4 装备槽。
## 装备槽：空槽回车进选择子模式；满槽回车卸下。
class_name UnitRosterScreen
extends BasePage

var _unit_ids: Array = []
var _list: ListWidget
var _detail: TextInfo
var _buttons: HBoxContainer
var _equip_mode := false   # 装备选择子模式
var _equip_slot := -1
var _equip_list: ListWidget

func build() -> void:
	page_title = Loc.t("unit_roster")
	var vbox := make_content()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	var left := Frame.new(Loc.t("unit_list"))
	left.custom_minimum_size = Vector2(320, 0)
	hbox.add_child(left)
	_list = ListWidget.new()
	left.add_child(_list)
	_list.text_fn = func(d): return _unit_row_text(d)
	_list.color_fn = func(d): return _unit_row_color(d)
	_list.row_selected.connect(func(idx): _show(idx))
	var right := Frame.new(Loc.t("unit_detail"))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_detail = TextInfo.new()
	right.add_child(_detail)
	# 底部操作区：训练 + 4 装备槽
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(_buttons)

func _my_units() -> Array:
	var g := GameController.game
	var out: Array = []
	for uid in g.unit_index:
		var u: Units.Unit = g.unit_index[uid]
		if g._unit_owner(u) == g.player_id:
			out.append(uid)
	out.sort()
	return out

func _unit_row_text(uid: String) -> String:
	var g := GameController.game
	var u: Units.Unit = g.unit_index[uid]
	var loc := _unit_loc(u)
	return "%s  Lv%d %s" % [Loc.t(u.name), u.level, loc]

func _unit_row_color(uid: String) -> Color:
	var g := GameController.game
	var u: Units.Unit = g.unit_index[uid]
	if not u.alive:
		return UiTheme.C_ENEMY
	if u.is_hero:
		return UiTheme.GOLD
	return UiTheme.FG

func _unit_loc(u: Units.Unit) -> String:
	var g := GameController.game
	if u.army_id == "":
		if GameController.player().standby.has(u.id):
			return Loc.t("standby_ok") if int(GameController.player().standby[u.id]) <= 0 else Loc.t("standby_cd")
		return "-"
	var army: Variant = g.armies.get(u.army_id)
	if army != null:
		return "%s @ %s" % [army.name, Loc.t(g.map.node_name(army.node_id))]
	return "-"

func enter_page(params: Variant = null) -> void:
	_unit_ids = _my_units()
	_list.set_items(_unit_ids)
	_rebuild_buttons()
	_show(0)
	refresh_hints()

func _show(idx: int) -> void:
	if _unit_ids.is_empty():
		_detail.text = Loc.t("no_items")
		return
	var g := GameController.game
	var u: Units.Unit = g.unit_index[_unit_ids[idx]]
	var lines: Array[String] = []
	# 名称/词条/英雄/部队/位置
	var tagstr := ""
	for i in range(u.tags.size()):
		if i > 0:
			tagstr += "/"
		tagstr += Units.TAG_CN.get(u.tags[i], u.tags[i])
	lines.append("%s [%s]%s" % [Loc.t(u.name), tagstr, Loc.t("hero") if u.is_hero else ""])
	lines.append("%s %s" % [Loc.t("location"), _unit_loc(u)])
	lines.append("%s %d   %s %d/%d" % [Loc.t("level"), u.level, Loc.t("hp_short"),
		int(u.cur_hp), int(u.base.get("hp", 1))])
	# 17 项属性 3 列
	var attr_parts: Array[String] = []
	for attr in Units.UNIT_ATTRS:
		attr_parts.append("%s %d" % [Units.ATTR_CN[attr], int(u.base.get(attr, 0))])
	# 有效属性（含修正）在战斗中体现，这里展示 base
	var cols := 3
	var per := ceili(attr_parts.size() / float(cols))
	for r in range(per):
		var row: Array[String] = []
		for c in range(cols):
			var i := r + c * per
			row.append(attr_parts[i] if i < attr_parts.size() else "")
		lines.append("  ".join(row))
	lines.append("%s %s" % [Loc.t("maintenance"), _cost_str(g._maintenance_cost(u))])
	lines.append("%s %s" % [Loc.t("train_cost_short"), _cost_str(g._train_cost(u))])
	# 技能面板
	var skill_names: Array[String] = []
	for sid in u.effective_skills():
		skill_names.append(_skill_desc(g, sid))
	if not skill_names.is_empty():
		lines.append("")
		lines.append(Loc.t("skills"))
		lines.append_array(skill_names)
	_detail.text = "\n".join(lines)

func _skill_desc(g: Game, sid: String) -> String:
	var sd: Dictionary = g.defs.get("skills", {}).get(sid, {})
	if sd.is_empty():
		return sid
	var parts: Array[String] = [Loc.t(sd.get("name", sid))]
	var kind: String = sd.get("kind", "perk")
	parts.append(Loc.t("kind_" + kind))
	if sd.has("ap_cost") or sd.has("mana_cost"):
		parts.append("AP%d/M%d" % [int(sd.get("ap_cost", 0)), int(sd.get("mana_cost", 0))])
	var effs := Effects.build_skill_effects(sd)
	var desc_parts: Array[String] = []
	for e in effs:
		desc_parts.append(_effect_desc(e))
	if not desc_parts.is_empty():
		parts.append("(" + "、".join(desc_parts) + ")")
	return " ".join(parts)

func _effect_desc(e: Effects.Effect) -> String:
	var p: Dictionary = e.params
	match e.effect_type:
		"flat_attr": return "%s %+d" % [Units.ATTR_CN.get(p.get("attr", ""), "?"), int(p.get("value", 0))]
		"pct_attr": return "%s %+d%%" % [Units.ATTR_CN.get(p.get("attr", ""), "?"), int(float(p.get("value", 0)) * 100)]
		"tag_bonus": return "%s[%s] %+d" % [Units.ATTR_CN.get(p.get("attr", ""), "?"),
			Units.TAG_CN.get(p.get("tag", ""), "?"), int(p.get("value", 0))]
		"moon_regen": return "%s x%s" % [Loc.t("moon_regen"), str(p.get("scale", 1))]
		"aura_flat": return "%s(aura) %+d" % [Units.ATTR_CN.get(p.get("attr", ""), "?"), int(p.get("value", 0))]
		"ap_damage": return "%s %d" % [Loc.t("skill_damage"), int(p.get("value", 0))]
		"apply_status": return "%s %d" % [Triggers.STATUS_CN.get(p.get("status", ""), p.get("status", "")),
			int(p.get("duration", 1))]
		_: return e.effect_type

func _cost_str(cost: Dictionary) -> String:
	if cost.is_empty():
		return Loc.t("cost_free")
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [Economy.RESOURCE_CN.get(k, k), int(cost[k])])
	return "、".join(parts)

func _rebuild_buttons() -> void:
	for c in _buttons.get_children():
		c.queue_free()
	if _unit_ids.is_empty():
		return
	var u: Units.Unit = GameController.game.unit_index[_unit_ids[_list.focused]]
	# 训练按钮
	var train_btn := Button.new()
	var trainable := GameController.game.is_trainable(u)
	train_btn.text = Loc.t("train_btn")
	train_btn.disabled = not trainable[0]
	train_btn.pressed.connect(func():
		var msg := GameController.game.action_train(GameController.game.player_id, u.id)
		GameController.push_log(msg, msg.begins_with("失败"))
		_show(_list.focused)
		_rebuild_buttons())
	train_btn.tooltip_text = trainable[1] if not trainable[0] else ""
	_buttons.add_child(train_btn)
	# 4 装备槽
	for slot in range(Units.ARTIFACT_SLOTS):
		var def_id: Variant = u.artifacts[slot] if slot < u.artifacts.size() else null
		var btn := Button.new()
		if def_id != null and GameController.game.artifact_defs.has(def_id):
			var art: Units.Artifact = GameController.game.artifact_defs[def_id]
			btn.text = "%d:%s" % [slot + 1, Loc.t(art.name)]
		else:
			btn.text = "%d:%s" % [slot + 1, Loc.t("empty_slot")]
		var slot_capture := slot
		btn.pressed.connect(func(): _on_slot_press(u.id, slot_capture))
		_buttons.add_child(btn)

## 装备槽操作：满槽 → 卸下；空槽 → 进入装备选择子模式。
func _on_slot_press(uid: String, slot: int) -> void:
	var g := GameController.game
	var u: Units.Unit = g.unit_index[uid]
	if slot < u.artifacts.size() and u.artifacts[slot] != null:
		var msg := g.action_unequip(g.player_id, uid, slot)
		GameController.push_log(msg, msg.begins_with("失败"))
		_show(_list.focused)
		_rebuild_buttons()
	else:
		_equip_mode = true
		_equip_slot = slot
		_open_equip_picker(u)

func _open_equip_picker(u: Units.Unit) -> void:
	var g := GameController.game
	# 可选装备：在库可用 > 0 的定义
	var options: Array = []
	var ids: Array = []
	for def_id in g.artifact_defs:
		if g.available_count(g.player_id, def_id) > 0:
			var art: Units.Artifact = g.artifact_defs[def_id]
			options.append(Loc.t(art.name))
			ids.append(def_id)
	if options.is_empty():
		GameController.push_log(Loc.t("no_artifact_avail"), true)
		_equip_mode = false
		return
	var picker: EquipPicker = load("res://scenes/windows/equip_picker.tscn").instantiate()
	picker.unit_id = u.id
	picker.slot = _equip_slot
	picker.ids = ids
	picker.labels = options
	SceneStack.open_window(picker)

func return_page(value: Variant = null) -> void:
	_equip_mode = false
	if value is Array and value.size() == 2:
		var msg := GameController.game.action_equip(GameController.game.player_id,
			value[0], value[1], _equip_slot)
		GameController.push_log(msg, msg.begins_with("失败"))
	_show(_list.focused)
	_rebuild_buttons()

func get_hints() -> Array:
	return [
		["↑↓", "move"], ["Enter", "slot"], ["T", "train"], ["ESC", "close"],
	]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
		_show(_list.focused)
		_rebuild_buttons()
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
		_show(_list.focused)
		_rebuild_buttons()
	elif event.is_action_pressed("scroll_up"):
		_detail.scroll_by(-5)
	elif event.is_action_pressed("scroll_down"):
		_detail.scroll_by(5)
	elif event.is_action_pressed("ui_accept"):
		# 回车：训练（焦点单位）
		if not _unit_ids.is_empty():
			var u: Units.Unit = GameController.game.unit_index[_unit_ids[_list.focused]]
			var trainable := GameController.game.is_trainable(u)
			if trainable[0]:
				var msg := GameController.game.action_train(GameController.game.player_id, u.id)
				GameController.push_log(msg, msg.begins_with("失败"))
				_show(_list.focused)
				_rebuild_buttons()
