extends Control
## BattleScene - Step-by-step battle playback with animations and stats summary.

@onready var round_label: Label = $Header/RoundLabel
@onready var player_grid: VBoxContainer = $BattleArea/PlayerSide/UnitGrid
@onready var enemy_grid: VBoxContainer = $BattleArea/EnemySide/UnitGrid
@onready var battle_log: VBoxContainer = $LogPanel/ScrollContainer/LogList
@onready var result_overlay: Control = $ResultOverlay
@onready var action_timer: Timer = $ActionTimer
@onready var return_btn: Button = $ReturnBtn
@onready var summary_player: VBoxContainer = $ResultOverlay/Panel/VBox/PlayerStats
@onready var summary_enemy: VBoxContainer = $ResultOverlay/Panel/VBox/EnemyStats
@onready var summary_header: Label = $ResultOverlay/Panel/VBox/SummaryHeader
@onready var summary_total: Label = $ResultOverlay/Panel/VBox/TotalStats
@onready var summary_close_btn: Button = $ResultOverlay/Panel/VBox/CloseBtn

var player_bars: Array = []
var enemy_bars: Array = []
var battle_done: bool = false


func _ready() -> void:
	result_overlay.visible = false
	return_btn.visible = false
	return_btn.pressed.connect(_on_return_to_formation)
	summary_close_btn.pressed.connect(_on_return_to_formation)

	BattleManager.battle_started.connect(_on_battle_started)
	BattleManager.round_started.connect(_on_round_started)
	BattleManager.battle_ended.connect(_on_battle_ended)

	action_timer.wait_time = 0.9
	action_timer.one_shot = false
	action_timer.timeout.connect(_on_action_tick)

	_style_return_btn()
	BattleManager.begin_combat()


func _style_return_btn() -> void:
	return_btn.add_theme_color_override("font_color", Color("2c1c0e"))
	return_btn.add_theme_font_size_override("font_size", 13)
	return_btn.begin_bulk_theme_override()
	return_btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	return_btn.end_bulk_theme_override()

	summary_close_btn.add_theme_color_override("font_color", Color("2c1c0e"))
	summary_close_btn.add_theme_font_size_override("font_size", 14)
	summary_close_btn.begin_bulk_theme_override()
	summary_close_btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	summary_close_btn.end_bulk_theme_override()


func _on_action_tick() -> void:
	if battle_done:
		return

	var action = BattleManager.next_action()

	if action.is_empty():
		if BattleManager.battle_active:
			# Between rounds — short wait
			pass
		else:
			# Battle should be over, but if ended signal hasn't fired yet, wait
			if not battle_done:
				pass
		return

	# Play the action
	_play_action(action)


func _play_action(action: Dictionary) -> void:
	match action.kind:
		"attack":
			_add_log("⚡ %s → %s  [%s]  -%d HP" % [
				action.actor_name, action.target_name,
				action.skill_name, action.damage
			])
			_animate_hit(action)
			_flash_unit(action.actor_name, UITheme.GOLD_BRIGHT)
			_flash_unit(action.target_name, UITheme.RED)
		"death":
			_add_log("💀 %s 阵亡！" % action.actor_name)
			_flash_unit(action.actor_name, Color.GRAY)

	_refresh_display_from_action(action)


func _flash_unit(unit_name: String, color: Color) -> void:
	for entry in player_bars + enemy_bars:
		if entry.unit.name_zh == unit_name:
			var card = entry.card
			var orig_mod = card.modulate
			card.modulate = color
			var tween := create_tween()
			tween.tween_property(card, "modulate", orig_mod, 0.4)
			break


func _animate_hit(_action: Dictionary) -> void:
	var orig_pos = position
	var tween := create_tween()
	tween.tween_property(self, "position:x", position.x + 4, 0.03)
	tween.tween_property(self, "position:x", position.x - 4, 0.03)
	tween.tween_property(self, "position:x", position.x + 2, 0.03)
	tween.tween_property(self, "position:x", orig_pos.x, 0.04)


func _refresh_display_from_action(action: Dictionary) -> void:
	# Update target unit display
	_update_unit_bar(action.target_name, action.target_hp, action.target_max_hp,
		action.target_alive if action.has("target_alive") else true, action.target_side)

	# Update actor unit display (for AP changes, etc.)
	if action.has("actor_ap"):
		_update_unit_bar(action.actor_name, action.actor_hp, action.actor_max_hp,
			true, action.actor_side, action.actor_ap, action.actor_max_ap)


func _update_unit_bar(unit_name: String, hp: int, max_hp: int, alive: bool, side: String,
		ap_val: int = -1, max_ap: int = -1) -> void:
	var bars = player_bars if side == "player" else enemy_bars
	for entry in bars:
		if entry.unit.name_zh == unit_name:
			var unit = entry.unit
			unit.hp = hp
			unit.max_hp = max_hp
			unit.is_alive = alive
			if ap_val >= 0:
				unit.ap = ap_val
				unit.max_ap = max_ap

			if unit.has("_hp_bar"):
				var bar: ProgressBar = unit._hp_bar
				bar.max_value = max_hp
				bar.value = hp
				if hp < max_hp * 0.3:
					bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.RED))
				elif hp < max_hp * 0.6:
					bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.GOLD))
				else:
					bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.GREEN))
			if unit.has("_hp_text"):
				unit._hp_text.text = "HP: %d/%d" % [hp, max_hp]
			if unit.has("_status_lbl"):
				unit._status_lbl.text = "存活" if alive else "阵亡"
				unit._status_lbl.add_theme_color_override("font_color", UITheme.GREEN if alive else UITheme.RED)
			if unit.has("_ap_pp") and ap_val >= 0:
				unit._ap_pp.text = "🔴AP:%d/%d  🔵PP:%d/%d" % [ap_val, max_ap, unit.pp, unit.max_pp]
			break


# ------------------------------------------------------------------ signal handlers
func _on_battle_started() -> void:
	_build_unit_displays()
	_add_log("⚔️ 战斗开始！双方共 %d vs %d 人参战" % [
		BattleManager.player_units.size(), BattleManager.enemy_units.size()
	])
	action_timer.start()


func _on_round_started(round_num: int) -> void:
	round_label.text = "第 %d 回合" % round_num
	_add_log("━━━ 第 %d 回合 ━━━" % round_num)


func _on_battle_ended(result: String) -> void:
	battle_done = true
	action_timer.stop()
	return_btn.visible = true

	var stats = BattleManager.get_stats_summary()
	_show_summary(result, stats)

	if result == "victory":
		_add_log("🏆 我方胜利！历经 %d 回合" % stats.rounds)
	else:
		_add_log("💀 我方败北...历经 %d 回合" % stats.rounds)


func _show_summary(result: String, stats: Dictionary) -> void:
	result_overlay.visible = true

	var result_text = "🎉 胜利！" if result == "victory" else "💔 败北..."
	var result_color = UITheme.GOLD_BRIGHT if result == "victory" else UITheme.RED
	summary_header.text = result_text
	summary_header.add_theme_color_override("font_color", result_color)
	summary_header.add_theme_font_size_override("font_size", 24)
	summary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Build player stats
	for child in summary_player.get_children():
		child.queue_free()
	_build_side_summary(summary_player, stats.player, "我方", UITheme.GOLD_BRIGHT)

	# Build enemy stats
	for child in summary_enemy.get_children():
		child.queue_free()
	_build_side_summary(summary_enemy, stats.enemy, "敌方", UITheme.RED)

	# Total summary
	summary_total.text = "我方输出: %d  我方承伤: %d\n敌方输出: %d  敌方承伤: %d" % [
		stats.player.total_damage_dealt, stats.player.total_damage_taken,
		stats.enemy.total_damage_dealt, stats.enemy.total_damage_taken,
	]
	summary_total.add_theme_color_override("font_color", UITheme.INK)
	summary_total.add_theme_font_size_override("font_size", 12)
	summary_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_side_summary(container: VBoxContainer, side_stats: Dictionary, label: String, color: Color) -> void:
	var header := Label.new()
	header.text = "—— %s ——  输出: %d  承伤: %d" % [label, side_stats.total_damage_dealt, side_stats.total_damage_taken]
	header.add_theme_color_override("font_color", color)
	header.add_theme_font_size_override("font_size", 12)
	container.add_child(header)

	for u in side_stats.units:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var status_icon := "✅" if u.alive else "💀"
		var name_lbl := Label.new()
		name_lbl.text = "%s %s [%s]" % [status_icon, u.name, u["class"]]
		name_lbl.add_theme_color_override("font_color", UITheme.INK if u.alive else UITheme.INK_DIM)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var dmg_lbl := Label.new()
		dmg_lbl.text = "输出:%d  承伤:%d  HP:%d/%d" % [u.damage_dealt, u.damage_taken, u.hp, u.max_hp]
		dmg_lbl.add_theme_color_override("font_color", UITheme.INK2)
		dmg_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(dmg_lbl)

		container.add_child(row)


# ------------------------------------------------------------------ unit card building
func _build_unit_displays() -> void:
	for child in player_grid.get_children():
		child.queue_free()
	for child in enemy_grid.get_children():
		child.queue_free()
	player_bars.clear()
	enemy_bars.clear()

	for unit in BattleManager.player_units:
		var card = _create_unit_card(unit, false)
		player_grid.add_child(card)
		player_bars.append({"unit": unit, "card": card})

	for unit in BattleManager.enemy_units:
		var card = _create_unit_card(unit, true)
		enemy_grid.add_child(card)
		enemy_bars.append({"unit": unit, "card": card})


func _create_unit_card(unit: Dictionary, is_enemy: bool) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	card.custom_minimum_size = Vector2(160, 90)

	var name_lbl := Label.new()
	name_lbl.text = "%s [%s]" % [unit.name_zh, unit.class_zh]
	name_lbl.add_theme_color_override("font_color", UITheme.RED if is_enemy else UITheme.GOLD_BRIGHT)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name_lbl)

	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = unit.max_hp
	hp_bar.value = unit.hp
	hp_bar.custom_minimum_size = Vector2(150, 14)
	hp_bar.add_theme_stylebox_override("fill", _hp_fill_style(UITheme.GREEN))
	card.add_child(hp_bar)
	unit["_hp_bar"] = hp_bar

	var hp_text := Label.new()
	hp_text.text = "HP: %d/%d" % [unit.hp, unit.max_hp]
	hp_text.add_theme_color_override("font_color", UITheme.INK)
	hp_text.add_theme_font_size_override("font_size", 10)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(hp_text)
	unit["_hp_text"] = hp_text

	var ap_pp := Label.new()
	ap_pp.text = "🔴AP:%d/%d  🔵PP:%d/%d" % [unit.ap, unit.max_ap, unit.pp, unit.max_pp]
	ap_pp.add_theme_color_override("font_color", UITheme.INK_DIM)
	ap_pp.add_theme_font_size_override("font_size", 9)
	ap_pp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(ap_pp)
	unit["_ap_pp"] = ap_pp

	var status_lbl := Label.new()
	status_lbl.text = "存活" if unit.is_alive else "阵亡"
	status_lbl.add_theme_color_override("font_color", UITheme.GREEN if unit.is_alive else UITheme.RED)
	status_lbl.add_theme_font_size_override("font_size", 9)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(status_lbl)
	unit["_status_lbl"] = status_lbl

	return card


func _hp_fill_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 3; sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3; sb.corner_radius_bottom_right = 3
	return sb


# ------------------------------------------------------------------ log
func _add_log(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", UITheme.INK2)
	lbl.add_theme_font_size_override("font_size", 11)
	battle_log.add_child(lbl)
	var scroll = battle_log.get_parent()
	if scroll and scroll is ScrollContainer:
		await get_tree().process_frame
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value


func _on_return_to_formation() -> void:
	BattleManager.reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
