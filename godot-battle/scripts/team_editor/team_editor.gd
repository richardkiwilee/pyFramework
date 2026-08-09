# team_editor.gd
# 队伍编辑场景 — 配置双方队伍、装备，开始战斗
extends Control

# 队伍数据
var blue_active: Array[Dictionary] = []    # 蓝方上场单位
var blue_reserve: Array[Dictionary] = []   # 蓝方候补单位
var red_active: Array[Dictionary] = []     # 红方上场单位
var red_reserve: Array[Dictionary] = []    # 红方候补单位

const MAX_ACTIVE: int = 5
const MIN_ACTIVE: int = 3

# UI 容器引用
var _blue_active_container: VBoxContainer
var _blue_reserve_container: VBoxContainer
var _red_active_container: VBoxContainer
var _red_reserve_container: VBoxContainer
var _blue_title: Label
var _red_title: Label

# 装备弹窗
var _equip_popup: PopupPanel
var _equip_target_unit: Dictionary = {}
var _equip_slot_buttons: Array[Button] = []
var _equip_list_container: VBoxContainer
var _equip_slot_selected: String = "weapon"


func _ready() -> void:
	# 初始化队伍数据
	_init_teams()

	# 构建UI
	_build_ui()

	# 刷新显示
	_refresh_all()


func _init_teams() -> void:
	# 从UnitDatabase获取模板并创建深拷贝
	var blue_templates = UnitDatabase.get_blue_templates()
	var red_templates = UnitDatabase.get_red_templates()

	# 蓝方：默认所有单位上场（最多5个）
	for i in range(min(blue_templates.size(), MAX_ACTIVE)):
		var unit = UnitDatabase.create_unit_from_template(blue_templates[i].id)
		unit["row"] = 0 if i < 3 else 1
		unit["col"] = i if i < 3 else i - 3
		blue_active.append(unit)

	for i in range(MAX_ACTIVE, blue_templates.size()):
		var unit = UnitDatabase.create_unit_from_template(blue_templates[i].id)
		blue_reserve.append(unit)

	# 红方：默认前3个上场
	for i in range(min(red_templates.size(), 3)):
		var unit = UnitDatabase.create_unit_from_template(red_templates[i].id)
		unit["row"] = 0
		unit["col"] = i
		red_active.append(unit)

	for i in range(3, red_templates.size()):
		var unit = UnitDatabase.create_unit_from_template(red_templates[i].id)
		red_reserve.append(unit)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 背景
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#0d0d1a")
	add_child(bg)

	# 主 VBox
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# 标题
	var title = Label.new()
	title.text = "队伍编辑 - 战前准备"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#ffd700"))
	title.custom_minimum_size = Vector2(0, 50)
	main_vbox.add_child(title)

	# 提示
	var hint = Label.new()
	hint.text = "每方上场人数: %d~%d人 | 点击「装备」编辑装备" % [MIN_ACTIVE, MAX_ACTIVE]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("#888888"))
	main_vbox.add_child(hint)

	# 队伍区域
	var teams_hbox = HBoxContainer.new()
	teams_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(teams_hbox)

	# 蓝方面板
	var blue_panel = _create_team_panel("blue", "我方队伍 (蓝方)")
	teams_hbox.add_child(blue_panel)

	# VS分隔
	var vs_box = VBoxContainer.new()
	vs_box.custom_minimum_size = Vector2(60, 0)
	vs_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var vs_label = Label.new()
	vs_label.text = "⚔\nVS"
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.add_theme_font_size_override("font_size", 24)
	vs_label.add_theme_color_override("font_color", Color("#ffd700"))
	vs_box.add_child(vs_label)
	teams_hbox.add_child(vs_box)

	# 红方面板
	var red_panel = _create_team_panel("red", "敌方队伍 (红方)")
	teams_hbox.add_child(red_panel)

	# 底部按钮
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(bottom_hbox)

	var reset_btn = Button.new()
	reset_btn.text = "🔄 重置编队"
	reset_btn.custom_minimum_size = Vector2(180, 44)
	reset_btn.add_theme_font_size_override("font_size", 16)
	reset_btn.pressed.connect(_on_reset_pressed)
	bottom_hbox.add_child(reset_btn)

	var start_btn = Button.new()
	start_btn.text = "🎮 开始战斗"
	start_btn.custom_minimum_size = Vector2(220, 48)
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(_on_start_battle_pressed)
	bottom_hbox.add_child(start_btn)

	# 装备编辑弹窗
	_create_equipment_popup()


func _create_team_panel(team: String, title_text: String) -> Panel:
	var panel = Panel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#111133") if team == "blue" else Color("#331111")
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color("#4488ff") if team == "blue" else Color("#ff4444")
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# 队名标题
	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#4488ff") if team == "blue" else Color("#ff4444"))
	vbox.add_child(title)

	# 上场单位滚动区
	var active_scroll = ScrollContainer.new()
	active_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	active_scroll.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(active_scroll)

	var active_container = VBoxContainer.new()
	active_container.add_theme_constant_override("separation", 6)
	active_scroll.add_child(active_container)
	if team == "blue":
		_blue_active_container = active_container
		_blue_title = title
	else:
		_red_active_container = active_container
		_red_title = title

	# 分隔线
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 候补标签
	var reserve_label = Label.new()
	reserve_label.text = "── 候补单位 ──"
	reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reserve_label.add_theme_font_size_override("font_size", 13)
	reserve_label.add_theme_color_override("font_color", Color("#888888"))
	vbox.add_child(reserve_label)

	# 候补单位滚动区
	var reserve_scroll = ScrollContainer.new()
	reserve_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reserve_scroll.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(reserve_scroll)

	var reserve_container = VBoxContainer.new()
	reserve_container.add_theme_constant_override("separation", 6)
	reserve_scroll.add_child(reserve_container)
	if team == "blue":
		_blue_reserve_container = reserve_container
	else:
		_red_reserve_container = reserve_container

	return panel


func _create_equipment_popup() -> void:
	_equip_popup = PopupPanel.new()
	_equip_popup.set_size(Vector2(420, 480))
	_equip_popup.popup_window = true
	add_child(_equip_popup)

	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color("#1a1a3e")
	popup_style.border_width_left = 3
	popup_style.border_width_right = 3
	popup_style.border_width_top = 3
	popup_style.border_width_bottom = 3
	popup_style.border_color = Color("#ffd700")
	_equip_popup.add_theme_stylebox_override("panel", popup_style)

	var popup_vbox = VBoxContainer.new()
	popup_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_vbox.add_theme_constant_override("separation", 8)
	_equip_popup.add_child(popup_vbox)

	# 标题
	var popup_title = Label.new()
	popup_title.text = "装备编辑"
	popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_title.add_theme_font_size_override("font_size", 20)
	popup_title.add_theme_color_override("font_color", Color("#ffd700"))
	popup_vbox.add_child(popup_title)

	# 装备槽按钮
	var slots_grid = GridContainer.new()
	slots_grid.columns = 2
	slots_grid.add_theme_constant_override("h_separation", 10)
	slots_grid.add_theme_constant_override("v_separation", 8)
	popup_vbox.add_child(slots_grid)

	var slot_names = {
		"weapon": "武器",
		"offhand": "副手",
		"accessory1": "饰品1",
		"accessory2": "饰品2"
	}
	for slot_key in ["weapon", "offhand", "accessory1", "accessory2"]:
		var slot_btn = Button.new()
		slot_btn.text = "%s: 空" % slot_names[slot_key]
		slot_btn.custom_minimum_size = Vector2(180, 40)
		slot_btn.pressed.connect(_on_equip_slot_selected.bind(slot_key))
		slots_grid.add_child(slot_btn)
		_equip_slot_buttons.append(slot_btn)

	# 装备列表
	var list_label = Label.new()
	list_label.text = "可选装备："
	list_label.add_theme_font_size_override("font_size", 14)
	popup_vbox.add_child(list_label)

	var list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 180)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup_vbox.add_child(list_scroll)

	_equip_list_container = VBoxContainer.new()
	_equip_list_container.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_equip_list_container)

	# 卸下和关闭按钮
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 12)
	popup_vbox.add_child(btn_hbox)

	var unequip_btn = Button.new()
	unequip_btn.text = "卸下当前槽位"
	unequip_btn.custom_minimum_size = Vector2(140, 36)
	unequip_btn.pressed.connect(_on_unequip_pressed)
	btn_hbox.add_child(unequip_btn)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(100, 36)
	close_btn.pressed.connect(func(): _equip_popup.hide())
	btn_hbox.add_child(close_btn)


func _refresh_all() -> void:
	_refresh_team_panel(_blue_active_container, blue_active, true)
	_refresh_team_panel(_blue_reserve_container, blue_reserve, false)
	_refresh_team_panel(_red_active_container, red_active, true)
	_refresh_team_panel(_red_reserve_container, red_reserve, false)

	if _blue_title:
		_blue_title.text = "我方队伍 (蓝方) %d/%d" % [blue_active.size(), MAX_ACTIVE]
	if _red_title:
		_red_title.text = "敌方队伍 (红方) %d/%d" % [red_active.size(), MAX_ACTIVE]


func _refresh_team_panel(container: VBoxContainer, units: Array[Dictionary], is_active: bool) -> void:
	for child in container.get_children():
		child.queue_free()

	for unit in units:
		var card = UnitCard.new(unit, is_active)
		card.deploy_toggled.connect(_on_deploy_toggled)
		card.equipment_edit_requested.connect(_on_equipment_edit_requested)
		container.add_child(card)


func _on_deploy_toggled(unit_data: Dictionary) -> void:
	var team = unit_data.get("team", "blue")
	var active_list = blue_active if team == "blue" else red_active
	var reserve_list = blue_reserve if team == "blue" else red_reserve

	if active_list.has(unit_data):
		# 下阵
		active_list.erase(unit_data)
		reserve_list.append(unit_data)
	else:
		# 上阵 - 检查人数限制
		if active_list.size() >= MAX_ACTIVE:
			_show_message("上场人数已达上限(%d人)！" % MAX_ACTIVE)
			return
		reserve_list.erase(unit_data)
		active_list.append(unit_data)

	_refresh_all()


func _on_equipment_edit_requested(unit_data: Dictionary) -> void:
	_equip_target_unit = unit_data
	_equip_slot_selected = "weapon"
	_refresh_equip_popup()
	_equip_popup.popup_centered()


func _on_equip_slot_selected(slot: String) -> void:
	_equip_slot_selected = slot
	_refresh_equip_popup()


func _refresh_equip_popup() -> void:
	if _equip_target_unit.is_empty():
		return

	# 更新槽位按钮
	var slot_names = {
		"weapon": "武器",
		"offhand": "副手",
		"accessory1": "饰品1",
		"accessory2": "饰品2"
	}
	var slot_keys = ["weapon", "offhand", "accessory1", "accessory2"]
	for i in range(slot_keys.size()):
		var sk = slot_keys[i]
		var eq_id = _equip_target_unit.get("equipment", {}).get(sk, null)
		var eq_name = "空"
		if eq_id != null and eq_id != "":
			var eq = EquipmentDatabase.get_equipment(eq_id)
			eq_name = eq.get("name", "???") if not eq.is_empty() else "???"
		_equip_slot_buttons[i].text = "%s: %s" % [slot_names[sk], eq_name]

	# 更新可选装备列表
	for child in _equip_list_container.get_children():
		child.queue_free()

	var available_equip = EquipmentDatabase.get_equipment_for_slot(_equip_slot_selected)
	for eq in available_equip:
		var eq_btn = Button.new()
		eq_btn.text = "%s — %s" % [eq.get("name", "???"), eq.get("description", "")]
		eq_btn.custom_minimum_size = Vector2(0, 34)
		eq_btn.add_theme_font_size_override("font_size", 12)
		eq_btn.pressed.connect(_on_equip_item_selected.bind(eq.id))
		_equip_list_container.add_child(eq_btn)


func _on_equip_item_selected(equip_id: String) -> void:
	if _equip_target_unit.is_empty():
		return

	var eq = EquipmentDatabase.get_equipment(equip_id)
	if eq.is_empty():
		return

	var target_slot = eq.get("slot", "accessory")
	if target_slot == "accessory":
		# 饰品处理：放到第一个空饰品槽
		if _equip_slot_selected != "accessory1" and _equip_slot_selected != "accessory2":
			_equip_slot_selected = "accessory1"
	else:
		_equip_slot_selected = target_slot

	_equip_target_unit["equipment"][_equip_slot_selected] = equip_id
	_refresh_equip_popup()
	_refresh_all()


func _on_unequip_pressed() -> void:
	if _equip_target_unit.is_empty():
		return
	_equip_target_unit["equipment"][_equip_slot_selected] = null
	_refresh_equip_popup()
	_refresh_all()


func _on_reset_pressed() -> void:
	blue_active.clear()
	blue_reserve.clear()
	red_active.clear()
	red_reserve.clear()
	_init_teams()
	_refresh_all()
	_show_message("编队已重置！")


func _on_start_battle_pressed() -> void:
	var blue_count = blue_active.size()
	var red_count = red_active.size()

	if blue_count < MIN_ACTIVE or blue_count > MAX_ACTIVE:
		_show_message("蓝方人数需在 %d~%d 之间！" % [MIN_ACTIVE, MAX_ACTIVE])
		return
	if red_count < MIN_ACTIVE or red_count > MAX_ACTIVE:
		_show_message("红方人数需在 %d~%d 之间！" % [MIN_ACTIVE, MAX_ACTIVE])
		return

	if blue_count != red_count:
		_show_confirm_dialog("双方人数不一致",
			"蓝方 %d 人 vs 红方 %d 人\n确定开始战斗吗？" % [blue_count, red_count],
			_start_battle)
	else:
		_start_battle()


func _start_battle() -> void:
	# 深拷贝队伍数据到 BattleData
	BattleData.set_teams(blue_active.duplicate(true), red_active.duplicate(true))
	get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")


func _show_message(text: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = "提示"
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())


func _show_confirm_dialog(title: String, text: String, callback: Callable) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free(); callback.call())
	dialog.canceled.connect(func(): dialog.queue_free())
