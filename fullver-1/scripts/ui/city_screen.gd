class_name CityScreen
extends Control
## =============================================================================
## CityScreen — 城市管理场景（readme 场景结构第 4 项）
## =============================================================================
## 展示选中城市（GameManager.selected_city_id）的信息，
## 提供升级/征兵操作（规则走 GameManager.economy_system）。
## 只做展示与按钮——经济规则全在 EconomySystem（docs/00-design.md §2）。
## =============================================================================

var _info_box: VBoxContainer
var _city: City


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG
	add_child(bg)

	# 无选中城市（异常路径）：回大地图
	if GameManager.game_state == null or GameManager.selected_city_id == "":
		await GameManager.change_scene("res://scenes/world_map.tscn")
		return
	_city = GameManager.game_state.get_city(GameManager.selected_city_id)
	if _city == null:
		await GameManager.change_scene("res://scenes/world_map.tscn")
		return

	var panel := PanelContainer.new()
	panel.size = Vector2(560, 480)
	UITheme.center(panel)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(20))
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	# 标题行
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)
	title_row.add_child(UITheme.make_label("%s — %s" % [_city.name_zh, I18n.t("ui.city.title")], 22, UITheme.GOLD_BRIGHT))
	title_row.add_child(UITheme.make_label(I18n.t("ui.city.level", [_city.level]), 14, UITheme.INK2))

	# 信息区（每次操作后刷新）
	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 6)
	outer.add_child(_info_box)

	# 操作按钮
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	outer.add_child(btn_row)
	var upgrade_btn := UITheme.make_button(I18n.t("ui.city.upgrade"), UITheme.gold_button_style(), 14)
	upgrade_btn.pressed.connect(_on_upgrade)
	btn_row.add_child(upgrade_btn)
	var recruit_btn := UITheme.make_button(I18n.t("ui.city.recruit"), UITheme.default_button_style(), 14)
	recruit_btn.add_theme_color_override("font_color", UITheme.INK)
	recruit_btn.pressed.connect(_on_recruit)
	btn_row.add_child(recruit_btn)

	var back_btn := UITheme.make_button(I18n.t("ui.city.back"), UITheme.default_button_style(), 14)
	back_btn.add_theme_color_override("font_color", UITheme.INK2)
	back_btn.pressed.connect(_on_back)
	outer.add_child(back_btn)

	_refresh_info()


func _refresh_info() -> void:
	for child in _info_box.get_children():
		child.queue_free()
	if GameManager.game_state == null:
		return
	# 归属
	var owner_text: String
	if _city.is_neutral():
		owner_text = I18n.t("ui.world.neutral_city")
	else:
		var fd: Dictionary = DataManager.get_faction(_city.owner_faction_id)
		owner_text = fd.get("name_zh", _city.owner_faction_id)
	_info_box.add_child(UITheme.make_label("%s: %s" % [I18n.t("ui.dip.title") + "·归属", owner_text], 13, UITheme.INK2))
	# 每回合产出
	var econ: EconomySystem = GameManager.economy_system
	var production: Dictionary = econ.get_city_production(_city)
	var prod_parts: Array = []
	for res_def in DataManager.get_resource_defs():
		var res_id: String = res_def.get("id", "")
		var amount: int = int(production.get(res_id, 0))
		if amount > 0:
			prod_parts.append("%s %s +%d" % [ArtIndex.get_emoji(res_def.get("icon", "")), res_def.get("name_zh", res_id), amount])
	_info_box.add_child(UITheme.make_label(I18n.t("ui.city.production") + ": " + "  ".join(prod_parts), 13, UITheme.INK))
	# 驻军
	var garrison: Army = GameManager.game_state.get_army(_city.garrison_army_id)
	if garrison != null:
		_info_box.add_child(UITheme.make_label(
			"%s: %d 人（移动力 %d/%d）" % [I18n.t("ui.city.garrison"), garrison.team.unit_count(),
			garrison.move_points, garrison.max_move_points], 13, UITheme.GREEN))
	else:
		_info_box.add_child(UITheme.make_label(I18n.t("ui.city.garrison") + ": —", 13, UITheme.INK_DIM))
	# 升级费用
	var upgrade_cost: Dictionary = GameManager.economy_system.get_upgrade_cost(_city)
	var cost_parts: Array = []
	for res_id in upgrade_cost:
		cost_parts.append("%s %d" % [res_id, int(upgrade_cost[res_id])])
	_info_box.add_child(UITheme.make_label(I18n.t("ui.city.upgrade") + " " + I18n.t("ui.city.cost") + ": " + "  ".join(cost_parts), 12, UITheme.INK_DIM))


func _on_upgrade() -> void:
	var player: Faction = GameManager.game_state.player_faction()
	var r: Dictionary = GameManager.economy_system.upgrade_city(player, _city)
	if r.get("ok", false):
		Alert.alert(I18n.t("ui.city.upgrade") + " ✓", UITheme.GREEN)
		_refresh_info()
	else:
		var reason: String = r.get("reason", "")
		if reason == "insufficient":
			Alert.alert(I18n.t("ui.city.not_enough"), UITheme.RED)
		else:
			Alert.alert(I18n.t("ui.city.upgrade") + " ✗", UITheme.RED)


func _on_recruit() -> void:
	var player: Faction = GameManager.game_state.player_faction()
	var r: Dictionary = GameManager.economy_system.recruit_army(player, _city)
	if r.get("ok", false):
		Alert.alert(I18n.t("ui.city.recruit") + " ✓", UITheme.GREEN)
		_refresh_info()
	else:
		var reason: String = r.get("reason", "")
		if reason == "insufficient":
			Alert.alert(I18n.t("ui.city.not_enough"), UITheme.RED)
		else:
			Alert.alert(I18n.t("ui.city.recruit") + " ✗", UITheme.RED)


func _on_back() -> void:
	await GameManager.change_scene("res://scenes/world_map.tscn")
