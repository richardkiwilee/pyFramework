# battle_scene.gd
# 战斗场景 — 自动回合制对战
# 双方队伍左右排列，前排靠中间、后排靠两侧
extends Control

# UI 引用
var _blue_zone: Control
var _red_zone: Control
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

# 阵型布局常量 — 每个TeamZone内部定位
# 前排(row=0)离中间近, 后排(row=1)离两侧远
const CARD_W: int = 140
const CARD_H: int = 220
const ZONE_W: int = 440


func _ready() -> void:
	_build_ui()
	_connect_signals()

	# 开始战斗（_build_ui 中已调用 _populate_combatants）
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
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# 顶部信息栏
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 20)
	top_bar.custom_minimum_size = Vector2(0, 36)
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

	# 战场区域 — 蓝方(左) | VS | 红方(右)
	var battlefield = HBoxContainer.new()
	battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battlefield.add_theme_constant_override("separation", 0)
	battlefield.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(battlefield)

	# 蓝方区域（左半）
	_blue_zone = _create_team_zone("blue")
	battlefield.add_child(_blue_zone)

	# VS 标签
	var vs_panel = Control.new()
	vs_panel.custom_minimum_size = Vector2(60, 0)
	var vs_label = Label.new()
	vs_label.text = "⚔"
	vs_label.position = Vector2(10, 200)
	vs_label.add_theme_font_size_override("font_size", 36)
	vs_label.add_theme_color_override("font_color", Color("#ffd700"))
	vs_panel.add_child(vs_label)
	battlefield.add_child(vs_panel)

	# 红方区域（右半）
	_red_zone = _create_team_zone("red")
	battlefield.add_child(_red_zone)

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
	log_panel.custom_minimum_size = Vector2(0, 120)
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
	control_bar.custom_minimum_size = Vector2(0, 44)
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


func _create_team_zone(team: String) -> Control:
	var zone = Control.new()
	zone.custom_minimum_size = Vector2(ZONE_W, 530)
	zone.set_size(Vector2(ZONE_W, 530))

	# 队伍底色
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#111133") if team == "blue" else Color("#331111")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(bg)

	# 前后排分隔线
	var sep = ColorRect.new()
	sep.color = Color("#333355") if team == "blue" else Color("#553333")
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.add_child(sep)

	# 前后排标签
	var front_lbl = Label.new()
	front_lbl.add_theme_font_size_override("font_size", 11)
	front_lbl.add_theme_color_override("font_color", Color("#888888"))
	zone.add_child(front_lbl)

	var back_lbl = Label.new()
	back_lbl.add_theme_font_size_override("font_size", 11)
	back_lbl.add_theme_color_override("font_color", Color("#888888"))
	zone.add_child(back_lbl)

	if team == "blue":
		# 蓝方：前排靠右(近中间)，后排靠左(远离中间)
		sep.position = Vector2(220, 30)
		sep.set_size(Vector2(2, 480))
		front_lbl.text = "前排→"
		front_lbl.position = Vector2(235, 10)
		back_lbl.text = "←后排"
		back_lbl.position = Vector2(180, 10)
	else:
		# 红方：前排靠左(近中间)，后排靠右(远离中间)
		sep.position = Vector2(218, 30)
		sep.set_size(Vector2(2, 480))
		front_lbl.text = "←前排"
		front_lbl.position = Vector2(195, 10)
		back_lbl.text = "后排→"
		back_lbl.position = Vector2(230, 10)

	return zone


func _populate_combatants() -> void:
	# 清除上一场战斗的节点（防御性，防止重复叠加）
	for child in _blue_zone.get_children():
		if child is CombatantNode:
			child.queue_free()
	for child in _red_zone.get_children():
		if child is CombatantNode:
			child.queue_free()
	_combatant_nodes.clear()

	# 从 BattleData 读取队伍数据
	_populate_team_zone(BattleData.team_blue, _blue_zone, "blue")
	_populate_team_zone(BattleData.team_red, _red_zone, "red")


# 在队伍区域内按行列摆放单位
# 蓝方: 前排(row=0)靠右(x=240), 后排(row=1)靠左(x=80)
# 红方: 前排(row=0)靠左(x=80), 后排(row=1)靠右(x=240)
func _populate_team_zone(team: Array[Dictionary], zone: Control, team_color: String) -> void:
	var is_blue: bool = (team_color == "blue")

	# 前后排 X 坐标
	var front_x: int = 240 if is_blue else 80
	var back_x: int = 80 if is_blue else 240

	# 为每个存活单位创建 CombatantNode
	for unit in team:
		var row: int = unit.get("row", 0)
		var col: int = unit.get("col", 0)

		var pos_x: int = front_x if row == 0 else back_x
		# Y 坐标：根据列号垂直分布（0=下, 1=中, 2=上）
		var pos_y: int
		match col:
			0: pos_y = 300
			1: pos_y = 155
			_: pos_y = 10

		var combatant = CombatantNode.new(unit, col)
		combatant.position = Vector2(pos_x, pos_y)
		zone.add_child(combatant)
		_combatant_nodes[unit.get("id", "")] = combatant


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

	# 高亮当前单位，取消其他（跳过已释放的节点）
	for id in _combatant_nodes.keys():
		var node = _combatant_nodes[id]
		if not is_instance_valid(node):
			_combatant_nodes.erase(id)
			continue
		node.set_highlight(node.unit_data == unit_data)

	_update_speed_bar()


func _on_turn_ended(unit_data: Dictionary) -> void:
	var node = _combatant_nodes.get(unit_data.get("id", ""))
	if node and is_instance_valid(node):
		node.set_highlight(false)
		node.refresh_display()


func _on_skill_used(caster: Dictionary, skill: Dictionary, target: Dictionary, result: Dictionary) -> void:
	# 施法者闪光
	var caster_node = _combatant_nodes.get(caster.get("id", ""))
	if caster_node and is_instance_valid(caster_node):
		caster_node.play_caster_flash()

	await get_tree().create_timer(0.15).timeout

	# 目标闪光 + 受击动画
	var target_node = _combatant_nodes.get(target.get("id", ""))
	if target_node and is_instance_valid(target_node):
		if result.get("hit", false):
			var is_heal: bool = (skill.get("damage_type", "") == "heal")
			target_node.play_target_flash(skill.get("damage_type", "physical"), is_heal)
			if not is_heal:
				target_node.play_hit_shake()
			if result.get("damage", 0) > 0 or is_heal:
				target_node.play_damage_number(result.get("damage", 0), result.get("crit", false), is_heal)
		else:
			target_node.play_damage_number(0, false, false, true)  # MISS

	_refresh_unit_display(caster)
	_refresh_unit_display(target)


func _on_passive_triggered(unit: Dictionary, skill: Dictionary, target: Dictionary, result: Dictionary) -> void:
	# 被动触发方闪光
	var unit_node = _combatant_nodes.get(unit.get("id", ""))
	if unit_node and is_instance_valid(unit_node):
		unit_node.play_caster_flash()

	await get_tree().create_timer(0.1).timeout

	var target_node = _combatant_nodes.get(target.get("id", ""))
	if target_node and is_instance_valid(target_node) and result.get("hit", false) and result.get("damage", 0) > 0:
		target_node.play_target_flash(skill.get("damage_type", "physical"), false)
		target_node.play_hit_shake()
		target_node.play_damage_number(result.get("damage", 0), result.get("crit", false), false)

	_refresh_unit_display(unit)
	_refresh_unit_display(target)


func _on_damage_dealt(target: Dictionary, damage: int) -> void:
	_refresh_unit_display(target)


func _on_unit_died(unit: Dictionary) -> void:
	var unit_id = unit.get("id", "")
	var node = _combatant_nodes.get(unit_id)
	if node and is_instance_valid(node):
		node.play_death()  # 内部会调 refresh_display 设灰色


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
	_result_popup.set_size(Vector2(400, 280))
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
	if node and is_instance_valid(node):
		node.refresh_display()
