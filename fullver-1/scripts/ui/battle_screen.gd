class_name BattleScreen
extends Control
## =============================================================================
## BattleScreen — 战斗场景（表现层：播放引擎预计算的行动队列）
## =============================================================================
## 职责边界：本类不计算任何战斗规则——引擎（BattleEngine）在场景进入时
## 根据 GameManager.pending_battle 创建，UI 通过信号 + next_action() 轮询播放。
##
## 布局（全代码构建，场景壳只有本根节点）：
##   顶部  — 回合标签 + 交战双方军团名
##   上部  — 敌方 3×3 单位卡片（前排 position 0-2 朝下）
##   下部  — 我方 3×3 单位卡片（前排 position 0-2 朝上）
##   右侧  — 战斗日志
##   结束  — 结果覆盖层（胜负 + 统计 + 返回按钮）
##
## 播放驱动：Timer 每 0.9 秒调 engine.next_action() 取一条行动，
##   根据 kind（attack/wait/heal/death/dot/cover/dodge/status）更新卡片与日志。
##   战斗结束 → battle_ended 信号 → 结果覆盖层 → 返回按钮 →
##   GameManager.resolve_battle_result() + 切回大地图。
##
## 类比 Python：相当于一个"回放器"——引擎已经算完，这里只是按序展示。
## =============================================================================

const TICK_SECONDS := 0.9

var engine: BattleEngine
var _timer: Timer
var _round_label: Label
var _player_cards: Dictionary = {}   # name_zh → 卡片根 Control
var _enemy_cards: Dictionary = {}
var _log_box: VBoxContainer
var _log_count: int = 0
var _overlay: Control = null
## 玩家势力是否进攻方。引擎口径：player_units = 进攻方。
## 玩家防守时（AI 进攻我方驻军）显示侧与胜负文案都要按此翻转。
var _player_is_attacker: bool = true


func _ready() -> void:
	# 防御：无进行中游戏时直接回大地图（冒烟测试与异常路径）。
	# 必须最先执行——后面的 UI 构建要读 GameManager.pending_battle。
	if GameManager.game_state == null:
		await GameManager.change_scene("res://scenes/world_map.tscn")
		return

	# 背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG
	add_child(bg)

	# 引擎必须先创建并 start_battle——UI 构建要读 engine 的单位列表
	var battle: Dictionary = GameManager.pending_battle
	var attacker: Army = GameManager.game_state.get_army(battle.get("attacker_army_id", ""))
	var defender: Army = GameManager.game_state.get_army(battle.get("defender_army_id", ""))
	if attacker == null or defender == null:
		# 数据异常：直接返回大地图（防御性回退）
		GameManager.resolve_battle_result({"result": "draw"})
		await GameManager.change_scene("res://scenes/world_map.tscn")
		return

	# 玩家视角判定：进攻方是玩家势力 → 正常视角；否则玩家是防守方
	_player_is_attacker = attacker.owner_faction_id == DataManager.get_player_faction_id()

	engine = BattleEngine.new()
	engine.battle_started.connect(_on_battle_started)
	engine.round_started.connect(_on_round_started)
	engine.battle_ended.connect(_on_battle_ended)
	engine.battle_action.connect(_on_battle_action)
	engine.start_battle(attacker, defender)

	_build_header()
	_build_units()
	_build_log()

	engine.begin_combat()

	# 播放心跳（demo-1 口径：0.9s 一条）
	_timer = Timer.new()
	_timer.wait_time = TICK_SECONDS
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()


# ==================================================================
#  UI 构建
# ==================================================================

func _build_header() -> void:
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.position = Vector2(0, 8)
	header.size = Vector2(0, 48)
	header.add_theme_stylebox_override("panel", UITheme.panel_header_style())
	add_child(header)
	var row := HBoxContainer.new()
	header.add_child(row)
	_round_label = UITheme.make_label(I18n.t("ui.battle.round", [1]), 16, UITheme.GOLD_BRIGHT)
	row.add_child(_round_label)
	var battle: Dictionary = GameManager.pending_battle
	var atk_name: String = _army_label(battle.get("attacker_army_id", ""))
	var def_name: String = _army_label(battle.get("defender_army_id", ""))
	row.add_child(UITheme.make_label("  %s %s %s" % [atk_name, I18n.t("ui.battle.vs"), def_name], 14, UITheme.INK2))


func _army_label(army_id: String) -> String:
	var army: Army = GameManager.game_state.get_army(army_id)
	if army == null:
		return "?"
	var fd: Dictionary = DataManager.get_faction(army.owner_faction_id)
	return "%s·%s" % [fd.get("name_zh", army.owner_faction_id), army.id]


## 双方 3×3 卡片区：position 0-2 = 前排（靠近中线）
func _build_units() -> void:
	var area_h: float = get_viewport_rect().size.y * 0.36
	_build_side_area(false, Vector2(0, 64), area_h)     # 敌方在上
	_build_side_area(true, Vector2(0, get_viewport_rect().size.y - area_h - 56), area_h)  # 我方在下


## 展示侧 → 引擎单位列表（玩家防守时互换）
func _display_units(is_player: bool) -> Array[BattleUnit]:
	if is_player == _player_is_attacker:
		return engine.player_units
	return engine.enemy_units


func _build_side_area(is_player: bool, origin: Vector2, area_h: float) -> void:
	var units: Array[BattleUnit] = _display_units(is_player)
	var cards: Dictionary = _player_cards if is_player else _enemy_cards
	# 按 position 排 3 行：0-2 前排、3-5 中排、6-8 后排
	for pos in range(9):
		var u: BattleUnit = null
		for candidate in units:
			if candidate.position == pos:
				u = candidate
				break
		var row: int = pos / 3
		var col: int = pos % 3
		# 我方前排（row 0）在最上（靠近中线）；敌方前排在最下
		var y_off: float = (2 - row) * (area_h / 3.0) if is_player else row * (area_h / 3.0)
		var card := PanelContainer.new()
		card.position = Vector2(origin.x + col * 210.0 + 180.0, origin.y + y_off + 4.0)
		card.size = Vector2(200, area_h / 3.0 - 8.0)
		card.add_theme_stylebox_override("panel", UITheme.panel_style(6))
		add_child(card)
		if u == null:
			card.add_child(UITheme.make_label("—", 13, UITheme.INK_DIM))
			continue
		card.add_child(_build_unit_card(u))
		cards[u.name_zh] = card


## 单张单位卡片：名字/职业 + HP 条 + 数值
func _build_unit_card(u: BattleUnit) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var name_label := UITheme.make_label("%s·%s" % [u.name_zh, u.class_zh], 13, UITheme.INK)
	box.add_child(name_label)
	var hp_text := UITheme.make_label("%d/%d" % [u.hp, u.max_hp], 11, UITheme.INK2)
	box.add_child(hp_text)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = u.max_hp
	bar.value = u.hp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.add_theme_stylebox_override("fill", _hp_fill_style(u))
	box.add_child(bar)
	return box


func _hp_fill_style(u: BattleUnit) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var ratio: float = float(u.hp) / float(max(1, u.max_hp))
	sb.bg_color = UITheme.GREEN if ratio > 0.5 else (UITheme.GOLD if ratio > 0.25 else UITheme.RED)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb


func _build_log() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.position = Vector2(get_viewport_rect().size.x - 320, 64)
	panel.size = Vector2(300, get_viewport_rect().size.y - 128)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(8))
	add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_log_box)


# ==================================================================
#  引擎信号与播放
# ==================================================================

func _on_battle_started() -> void:
	_log("—— " + I18n.t("ui.battle.round", [1]) + " ——", UITheme.GOLD)


func _on_round_started(round_num: int) -> void:
	_round_label.text = I18n.t("ui.battle.round", [round_num])
	_log("—— " + I18n.t("ui.battle.round", [round_num]) + " ——", UITheme.GOLD)


func _on_battle_action(action: Dictionary) -> void:
	# skipped 即时通知（demo-1 口径）
	_log("%s %s" % [action.get("actor_name", "?"), action.get("skill_name", "")], UITheme.INK_DIM)


func _tick() -> void:
	if engine == null:
		return
	var action: Dictionary = engine.next_action()
	if action.is_empty():
		return
	_process_action(action)


## 按行动类型播放（更新卡片 + 写日志）
func _process_action(action: Dictionary) -> void:
	var kind: String = action.get("kind", "")
	match kind:
		"attack":
			var dmg: int = int(action.get("damage", 0))
			var heal: int = int(action.get("heal", 0))
			var skill_name: String = action.get("skill_name", "")
			var targets: Array = action.get("targets", [])
			var desc := "%s %s" % [action.get("actor_name", "?"), skill_name]
			for t in targets:
				if int(t.get("damage", 0)) > 0:
					desc += " → %s -%d" % [t.get("name", "?"), int(t.get("damage", 0))]
				elif int(t.get("heal", 0)) > 0:
					desc += " → %s +%d" % [t.get("name", "?"), int(t.get("heal", 0))]
				if t.has("covered_by"):
					desc += "（%s 掩护）" % t.get("covered_by", "")
				if t.has("guarded") and t.get("guarded", false):
					desc += "（格挡）"
			_log(desc, UITheme.INK if dmg > 0 or heal > 0 else UITheme.INK2)
			_refresh_cards()
		"wait":
			var reason: String = action.get("reason", "")
			_log("%s 待机%s" % [action.get("actor_name", "?"), ("（" + reason + "）") if reason != "" else ""], UITheme.INK_DIM)
		"heal":
			var h: int = int(action.get("heal", 0))
			var source: String = action.get("heal_source", "")
			var heal_text := source_text(source)
			_log("%s %s +%d" % [action.get("actor_name", "?"), heal_text, h], UITheme.GREEN)
			_refresh_cards()
		"death":
			_log("☠ %s 阵亡" % action.get("actor_name", "?"), UITheme.RED)
			_refresh_cards()
		"dot":
			_log("%s 受到%s %d 点伤害" % [action.get("actor_name", "?"), action.get("dot_type", ""), int(action.get("damage", 0))], UITheme.GOLD)
			_refresh_cards()
		"cover":
			_log("%s 掩护了 %s" % [action.get("actor_name", "?"), action.get("target_name", "?")], UITheme.BLUE)
		"dodge":
			_log("%s 闪避了 %s 的攻击" % [action.get("actor_name", "?"), action.get("target_name", "?")], UITheme.BLUE)
		"status":
			_log("%s 中了状态：%s" % [action.get("actor_name", "?"), action.get("status_type", "")], UITheme.GOLD)


func source_text(source: String) -> String:
	match source:
		"lifesteal": return "吸血"
		"regen": return "再生"
		"heal_on_kill": return "击杀回复"
		"survive": return "挺过致命一击"
		"ap": return "回复AP"
		"pp": return "回复PP"
		_: return "回复"


## 刷新全部卡片（按引擎实时状态）
func _refresh_cards() -> void:
	for name in _player_cards:
		_refresh_one_card(name)
	for name in _enemy_cards:
		_refresh_one_card(name)


func _refresh_one_card(name: String) -> void:
	var card: PanelContainer = _player_cards.get(name, null)
	if card == null:
		card = _enemy_cards.get(name, null)
	if card == null:
		return
	var u: BattleUnit = engine._find_unit(name)
	if u == null:
		return
	# 重建卡片内容（简单可靠，卡片量小）
	for child in card.get_children():
		child.queue_free()
	if u.is_alive:
		card.add_child(_build_unit_card(u))
	else:
		card.add_child(UITheme.make_label("☠ %s" % u.name_zh, 13, UITheme.RED))


func _on_battle_ended(result: String) -> void:
	_final_result = result
	_timer.stop()
	_show_result_overlay(result)


## 结果覆盖层：胜负 + 统计 + 返回大地图
func _show_result_overlay(result: String) -> void:
	if _overlay != null:
		return
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.z_index = 400
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.size = Vector2(420, 300)
	UITheme.center(panel)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(20))
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	# result 是引擎口径（victory = 进攻方胜）。玩家防守时翻转成玩家视角文案。
	var title_text: String
	var title_color: Color
	match _map_result_for_display(result):
		"victory":
			title_text = I18n.t("ui.battle.victory")
			title_color = UITheme.GOLD_BRIGHT
		"defeat":
			title_text = I18n.t("ui.battle.defeat")
			title_color = UITheme.RED
		_:
			title_text = I18n.t("ui.battle.draw")
			title_color = UITheme.INK2
	var title := UITheme.make_label(title_text, 28, title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# 统计摘要（我方 = 玩家势力侧）
	var stats: Dictionary = engine.get_stats_summary()
	var p_stats: Dictionary = stats.get("player", {}) if _player_is_attacker else stats.get("enemy", {})
	var e_stats: Dictionary = stats.get("enemy", {}) if _player_is_attacker else stats.get("player", {})
	box.add_child(UITheme.make_label(
		"回合数: %d    我方输出: %d / 敌方输出: %d" % [
			int(stats.get("rounds", 0)),
			int(p_stats.get("total_damage_dealt", 0)),
			int(e_stats.get("total_damage_dealt", 0)),
		], 14, UITheme.INK2))

	var return_btn := UITheme.make_button(I18n.t("ui.battle.return"), UITheme.gold_button_style(), 15)
	return_btn.custom_minimum_size = Vector2(0, 40)
	return_btn.pressed.connect(_on_return)
	box.add_child(return_btn)


func _on_return() -> void:
	# 战斗结果应用（占城/解散）+ 回合流程续跑
	GameManager.resolve_battle_result({"result": _last_result()})
	# ⚠️ 关键修复：续跑可能又触发战斗（AI 回合连场进攻）。
	# 此时还在战斗场景里，battle_requested 信号没有世界场景监听（会丢），
	# 必须由本场景自己重入下一场战斗，否则回合流程卡死、
	# 移动力永不刷新（玩家"动不了"的直接原因）。
	if GameManager.turn_manager != null and GameManager.turn_manager.is_awaiting_battle():
		await GameManager.change_scene("res://scenes/battle.tscn")
	else:
		await GameManager.change_scene("res://scenes/world_map.tscn")


## 战斗最终结果（battle_ended 的 result 存一份，返回大地图时传给 GameManager）
## ⚠️ 存引擎口径（victory=进攻方胜）——resolve_battle_result 与后果应用都按此口径。
var _final_result: String = "draw"


func _last_result() -> String:
	return _final_result


## 引擎口径 → 玩家视角（玩家防守时翻转胜负）
func _map_result_for_display(result: String) -> String:
	if _player_is_attacker or result == "draw":
		return result
	return "defeat" if result == "victory" else "victory"


# ==================================================================
#  日志
# ==================================================================

func _log(text: String, color: Color) -> void:
	_log_count += 1
	var label := UITheme.make_label(text, 12, color)
	_log_box.add_child(label)
	_log_box.move_child(label, 0)  # 最新在最上
	# 限制日志量（防长战斗卡顿）
	if _log_count > 200:
		var children: Array = _log_box.get_children()
		for i in range(children.size() - 1, 150, -1):
			children[i].queue_free()
