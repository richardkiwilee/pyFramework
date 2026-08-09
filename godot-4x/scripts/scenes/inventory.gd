## 仓库（对应 inventory.py）：装备定义一览（def_id 库存计数模型）。
## W1 装备列表（名称 库{可用}/装{已装备}）；W2 详情（效果/归属）。
## S 卖出（+10 金币）、X 卸下（从某已装备单位卸下回库，须该单位在己方据点）。
class_name InventoryScreen
extends BasePage

var _list: ListWidget
var _detail: TextInfo
var _def_ids: Array = []

func build() -> void:
	page_title = Loc.t("inventory")
	var vbox := make_content()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	var left := Frame.new(Loc.t("inventory_list"))
	left.custom_minimum_size = Vector2(400, 0)
	hbox.add_child(left)
	_list = ListWidget.new()
	left.add_child(_list)
	_list.text_fn = func(d): return _row_text(d)
	_list.color_fn = func(d): return _row_color(d)
	_list.row_selected.connect(func(idx): _show(idx))
	var right := Frame.new(Loc.t("inventory_detail"))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_detail = TextInfo.new()
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail)
	# 操作按钮（S 卖出 / X 卸下的鼠标等价物）
	var ops := HBoxContainer.new()
	ops.add_theme_constant_override("separation", 8)
	right.add_child(ops)
	var sell_btn := Button.new()
	sell_btn.text = Loc.t("sell")
	sell_btn.pressed.connect(func(): _sell_focused())
	ops.add_child(sell_btn)
	var unequip_btn := Button.new()
	unequip_btn.text = Loc.t("unequip")
	unequip_btn.pressed.connect(func(): _unequip_focused())
	ops.add_child(unequip_btn)

func enter_page(params: Variant = null) -> void:
	_rebuild()
	refresh_hints()

func _rebuild() -> void:
	var g := GameController.game
	_def_ids.clear()
	for def_id in g.artifact_defs:
		_def_ids.append(def_id)
	_def_ids.sort()
	_list.set_items(_def_ids)
	_show(0)

func _row_text(def_id: String) -> String:
	var g := GameController.game
	var art: Units.Artifact = g.artifact_defs[def_id]
	var avail := g.available_count(g.player_id, def_id)
	var eq := g.equipped_count(g.player_id, def_id)
	return "%s  库{%d}/装{%d}" % [Loc.t(art.name), avail, eq]

func _row_color(def_id: String) -> Color:
	var g := GameController.game
	if g.available_count(g.player_id, def_id) > 0:
		return UiTheme.FG
	return UiTheme.DIM

func _show(idx: int) -> void:
	if _def_ids.is_empty():
		_detail.text = Loc.t("no_items")
		return
	var g := GameController.game
	var def_id: String = _def_ids[idx]
	var art: Units.Artifact = g.artifact_defs[def_id]
	var lines: Array[String] = [
		"%s  [%s]" % [Loc.t(art.name), Loc.t("rarity_" + art.rarity)],
		"%s %d   %s %d   %s %d" % [Loc.t("stock"), int(GameController.player().inventory.get(def_id, 0)),
			Loc.t("avail"), g.available_count(g.player_id, def_id),
			Loc.t("equipped"), g.equipped_count(g.player_id, def_id)],
	]
	# 归属列表
	var holders: Array[String] = []
	for uid in g.unit_index:
		var u: Units.Unit = g.unit_index[uid]
		if u.artifacts.has(def_id):
			holders.append(u.name)
	if not holders.is_empty():
		lines.append(Loc.t("held_by") + " " + "、".join(holders))
	# 效果描述
	lines.append("")
	for e in art.effects:
		lines.append(_effect_desc(e))
	_detail.text = "\n".join(lines)

func _effect_desc(e: Dictionary) -> String:
	match e.get("type", ""):
		"flat_attr":
			return "%s %+d" % [Units.ATTR_CN.get(e["params"].get("attr", ""), "?"),
				int(e["params"].get("value", 0))]
		"tag_grant":
			return "%s: %s" % [Loc.t("grant_tag"), Units.TAG_CN.get(e["params"].get("tag", ""), "?")]
		"skill_grant":
			return "%s: %s" % [Loc.t("grant_skill"), e["params"].get("skill", "?")]
		_: return str(e)

func get_hints() -> Array:
	return [
		["↑↓", "move"], ["S", "sell"], ["X", "unequip"],
		["Enter", "detail"], ["ESC", "close"],
	]

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("sell_artifact"):
		_sell_focused()
	elif event.is_action_pressed("unequip_artifact"):
		_unequip_focused()
	elif event.is_action_pressed("ui_up"):
		_list.move_focus(-1)
		_show(_list.focused)
	elif event.is_action_pressed("ui_down"):
		_list.move_focus(1)
		_show(_list.focused)

## 卖出当前聚焦行（S 键与卖出按钮共用）。
func _sell_focused() -> void:
	if _def_ids.is_empty():
		return
	var def_id: String = _def_ids[_list.focused]
	var msg := GameController.game.action_sell_artifact(GameController.game.player_id, def_id)
	GameController.push_log(msg, msg.begins_with("失败"))
	_rebuild()

## 卸下当前聚焦行（X 键与卸下按钮共用）。
func _unequip_focused() -> void:
	if _def_ids.is_empty():
		return
	_unequip_one(_def_ids[_list.focused])

## 找一件装备该定义的单位卸其槽（须该单位在己方据点）。
func _unequip_one(def_id: String) -> void:
	var g := GameController.game
	if g.equipped_count(g.player_id, def_id) <= 0:
		GameController.push_log(Loc.t("not_equipped"), true)
		return
	for uid in g.unit_index:
		var u: Units.Unit = g.unit_index[uid]
		if u.army_id != "" and not g._unit_in_own_stronghold(GameController.player(), u):
			continue
		if u.artifacts.has(def_id):
			var slot := u.artifacts.find(def_id)
			var msg := g.action_unequip(g.player_id, u.id, slot)
			GameController.push_log(msg, msg.begins_with("失败"))
			_rebuild()
			return
	GameController.push_log(Loc.t("unequip_impossible"), true)
