# battle_scene.gd
# 战斗场景 — 自动回合制对战
extends Control

# UI 引用
var _blue_formation: GridContainer
var _red_formation: GridContainer
var _combatant_nodes: Dictionary = {}  # key: unit_id -> CombatantNode
var _turn_label: Label
var _current_unit_label: Label
var _battle_log: RichTextLabel
var _speed_bar: HBoxContainer
var _pause_btn: Button
var _speed_btn: Button
var _result_popup: PopupPanel
var _result_label: Label
var _stats_label: Label

var _current_speed: int = 1  # 1x, 2x, 4x


func _ready() -> void:
	_build_ui()
	_connect_signals()

	# 开始战斗
	BattleManager.start_battle(self)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 背景
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#0a0a14")
	add_child(bg)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 顶部信息栏
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 20)
	main_vbox.add_child(top_bar)

	_turn_label = Label.new()
	_turn_label.text = "准备中..."
	_turn_label.add_theme_font_size_override("font_size", 20)
	_turn_label.add_theme_color_override("font_color", Color("#ffd700"))
	top_bar.add_child(_turn_label)

	_current_unit_label = Label.new()
	_current_unit_label.text = ""
	_current_unit_label.add_theme_font_size_override("font_size", 16)
	_current_unit_label.add_theme_color_override("font_color", Color.WHITE)
	top_bar.add_child(_current_unit_label)

	# 战场区域
	var battlefield = HBoxContainer.new()
	battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battlefield.add_theme_constant_override("separation", 20)
	battlefield.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(battlefield)

	# 蓝方阵型（左侧，反转：前排在下后排在上）
	_blue_formation = _create_formation_grid()
	battlefield.add_child(_blue_formation)

	# VS标签
	var vs_label = Label.new()
	vs_label.text = "⚔"
	vs_label.add_theme_font_size_override("font_size", 36)
	vs_label.add_theme_color_override("font_color", Color("#ffd700"))
	battlefield.add_child(vs_label)

	# 红方阵型（右侧，正常：前排在前排在后）
	_red_formation = _create_formation_grid()
	battlefield.add_child(_red_formation)

	# 底部面板
	var bottom = VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	main_vbox.add_child(bottom)

	# 速度条
	var speed_hbox = HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 4)
	var speed_label = Label.new()
	speed_label.text = "行动顺序: "
	speed_label.add_theme_font_size_override("font_size", 12)
	speed_label.add_theme_color_override("font_color", Color("#888888"))
	speed_hbox.add_child(speed_label)
	_speed_bar = HBoxContainer.new()
	_speed_bar.add_theme_constant_override("separation", 3)
	speed_hbox.add_child(_speed_bar)
	bottom.add_child(speed_hbox)

	# 战斗日志
	var log_panel = Panel.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_panel.custom_minimum_size = Vector2(0, 140)
	var log_style = StyleBoxFlat.new()
	log_style.bg_color = Color("#0d0d20")
	log_style.border_width_left = 1
	log_style.border_width_right = 1
	log_style.border_width_top = 1
	log_style.border_width_bottom = 1
	log_style.border_color = Color("#333366")
	log_panel.add_theme_stylebox_override("panel", log_style)
	bottom.add_child(log_panel)

	_battle_log = RichTextLabel.new()
	_battle_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_log.bbcode_enabled = true
	_battle_log.scroll_following = true
	_battle_log.add_theme_font_size_override("normal_font_size", 13)
	log_panel.add_child(_battle_log)

	# 控制栏
	var control_bar = HBoxContainer.new()
	control_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	control_bar.add_theme_constant_override("separation", 16)
	bottom.add_child(control_bar)

	_pause_btn = Button.new()
	_pause_btn.text = "⏸ 暂停"
	_pause_btn.custom_minimum_size = Vector2(100, 36)
	_pause_btn.pressed.connect(_on_pause_pressed)
	control_bar.add_child(_pause_btn)

	_speed_btn = Button.new()
	_speed_btn.text = "⏩ 2x"
	_speed_btn.custom_minimum_size = Vector2(100, 36)
	_speed_btn.pressed.connect(_on_speed_pressed)
	control_bar.add_child(_speed_btn)

	var return_btn = Button.new()
	return_btn.text = "↩ 返回编队"
	return_btn.custom_minimum_size = Vector2(120, 36)
	return_btn.pressed.connect(_on_return_pressed)
	control_bar.add_child(return_btn)

	# 战斗结果弹窗
	_create_result_popup()

	# 初始化战斗单位节点
	_populate_combatants()


func _create_formation_grid() -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.custom_minimum_size = Vector2(480, 480)
	return grid


func _populate_combatants() -> void:
	# 蓝方：填充阵型（前排0-2放后排行，后排0-2放前排行，形成互相面对的效果）
	# 阵型格：前排行(col0-2), 后排行(col0-2)
	# 蓝方左侧，前排(下方)对着红方
	_populate_team_formation(BattleManager.team_blue, _blue_formation)
	_populate_team_formation(BattleManager.team_red, _red_formation)


func _populate_team_formation(team: Array[Dictionary], grid: GridContainer) -> void:
	# 创建6个槽位（前排3+后排3）
	# Godot GridContainer: 从左到右，从上到下填充
	# 前排(index 0): 后排row=1, 前排(index 1): 前排row=0
	# 对于蓝方：上方显示后排，下方显示前排
	# 对于红方：上方显示前排，下方显示后排

	var is_blue = team.size() > 0 and team[0].get("team", "") == "blue"

	for slot_row in range(2):  # 0=显示上方, 1=显示下方
		for col in range(3):
			var node = _create_empty_slot(slot_row, col, is_blue)
			grid.add_child(node)

	# 放置单位到对应槽位
	for unit in team:
		var unit_row = unit.get("row", 0)  # 0=前排, 1=后排
		var unit_col = unit.get("col", 0)
		var node_index: int

		if is_blue:
			# 蓝方：前排在下(display_row=1), 后排在上(display_row=0)
			node_index = (1 - unit_row) * 3 + unit_col
		else:
			# 红方：前排在下(display_row=1), 后排在上(display_row=0)
			node_index = (1 - unit_row) * 3 + unit_col

		if node_index < grid.get_child_count():
			var old = grid.get_child(node_index)
			if old:
				old.queue_free()
			var combatant = CombatantNode.new(unit, unit_col)
			grid.add_child(combatant)
			grid.move_child(combatant, node_index)
			_combatant_nodes[unit.get("id", "")] = combatant


func _create_empty_slot(slot_row: int, col: int, is_blue: bool) -> Control:
	var placeholder = Control.new()
	placeholder.custom_minimum_size = Vector2(140, 220)
	placeholder.size = Vector2(140, 220)
	return placeholder


func _connect_signals() -> void:
	BattleManager.log_message.connect(_on_log_message)
	BattleManager.turn_started.connect(_on_turn_started)
	BattleManager.turn_ended.connect(_on_turn_ended)
	BattleManager.skill_used.connect(_on_skill_used)
	BattleManager.passive_triggered.connect(_on_passive_triggered)
	BattleManager.damage_dealt.connect(_on_damage_dealt)
	BattleManager.unit_died.connect(_on_unit_died)
	BattleManager.battle_ended.connect(_on_battle_ended)


func _on_log_message(msg: String, color: Color) -> void:
	var color_hex = "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	_battle_log.append_text("[color=%s]%s[/color]\n" % [color_hex, msg])


func _on_turn_started(unit_data: Dictionary) -> void:
	_current_unit_label.text = "当前: %s" % unit_data.get("name", "???")
	_turn_label.text = "第 %d 回合" % BattleManager.current_round

	# 高亮当前单位
	for id in _combatant_nodes:
		var node = _combatant_nodes[id]
		if node.unit_data == unit_data:
			node.set_highlight(true)
		else:
			node.set_highlight(false)

	# 更新速度条
	_update_speed_bar()


func _on_turn_ended(unit_data: Dictionary) -> void:
	var node = _combatant_nodes.get(unit_data.get("id", ""))
	if node:
		node.set_highlight(false)
		node.refresh_display()


func _on_skill_used(caster: Dictionary, skill: Dictionary, target: Dictionary, result: Dictionary) -> void:
	# 刷新相关单位显示
	_refresh_unit_display(caster)
	_refresh_unit_display(target)


func _on_passive_triggered(unit: Dictionary, skill: Dictionary, target: Dictionary, result: Dictionary) -> void:
	_refresh_unit_display(unit)
	_refresh_unit_display(target)


func _on_damage_dealt(target: Dictionary, damage: int) -> void:
	var node = _combatant_nodes.get(target.get("id", ""))
	if node:
		node.play_hit_shake()
		await get_tree().create_timer(0.05).timeout
		node.refresh_display()
		node.play_damage_number(damage, false)

	# 同步更新HP显示
	_refresh_unit_display(target)


func _on_unit_died(unit: Dictionary) -> void:
	var node = _combatant_nodes.get(unit.get("id", ""))
	if node:
		node.play_death()
		node.refresh_display()


func _on_battle_ended(winner: String, stats: Dictionary) -> void:
	_result_label.text = "🎉 蓝方胜利！" if winner == "blue" else ("💀 红方胜利！" if winner == "red" else "🤝 平局！")
	_result_label.add_theme_color_override("font_color",
		Color("#4488ff") if winner == "blue" else (Color("#ff4444") if winner == "red" else Color("#ffd700")))

	_stats_label.text = "蓝方存活: %d/%d | 红方存活: %d/%d\n" % [stats.blue_alive, stats.blue_total, stats.red_alive, stats.red_total]
	_stats_label.text += "蓝方总伤害: %d | 红方总伤害: %d\n" % [stats.total_damage_blue, stats.total_damage_red]
	_stats_label.text += "蓝方HP损失: %d | 红方HP损失: %d\n" % [stats.blue_hp_lost, stats.red_hp_lost]
	_stats_label.text += "总回合数: %d" % stats.rounds

	_result_popup.popup_centered()


func _on_pause_pressed() -> void:
	BattleManager.toggle_pause()
	_pause_btn.text = "▶ 继续" if BattleManager.paused else "⏸ 暂停"


func _on_speed_pressed() -> void:
	_current_speed = _current_speed * 2
	if _current_speed > 4:
		_current_speed = 1
	BattleManager.set_speed(_current_speed)
	_speed_btn.text = "⏩ %dx" % _current_speed


func _on_return_pressed() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "确认返回"
	dialog.dialog_text = "确定要返回编队界面吗？"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		dialog.queue_free()
		BattleManager.battle_active = false
		get_tree().change_scene_to_file("res://scenes/team_editor.tscn")
	)
	dialog.canceled.connect(func(): dialog.queue_free())


func _create_result_popup() -> void:
	_result_popup = PopupPanel.new()
	_result_popup.size = Vector2(400, 280)
	_result_popup.popup_window = true
	add_child(_result_popup)

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1a1a3e")
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color("#ffd700")
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_result_popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_popup.add_child(vbox)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 26)
	vbox.add_child(_result_label)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", Color("#aaaaaa"))
	vbox.add_child(_stats_label)

	var ok_btn = Button.new()
	ok_btn.text = "返回编队"
	ok_btn.custom_minimum_size = Vector2(140, 40)
	ok_btn.add_theme_font_size_override("font_size", 16)
	ok_btn.pressed.connect(func():
		_result_popup.hide()
		BattleManager.battle_active = false
		get_tree().change_scene_to_file("res://scenes/team_editor.tscn")
	)
	vbox.add_child(ok_btn)


func _update_speed_bar() -> void:
	for child in _speed_bar.get_children():
		child.queue_free()

	for unit in BattleManager.turn_order:
		if not unit.get("is_alive", false):
			continue

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = PlaceholderAssets.get_unit_portrait(unit.get("class_name", "knight"), unit.get("team", "blue"))
		icon.tooltip_text = unit.get("name", "???")

		if unit.get("ap_current", 0) <= 0:
			icon.modulate = Color(1, 1, 1, 0.3)

		_speed_bar.add_child(icon)


func _refresh_unit_display(unit_data: Dictionary) -> void:
	var node = _combatant_nodes.get(unit_data.get("id", ""))
	if node:
		node.refresh_display()
