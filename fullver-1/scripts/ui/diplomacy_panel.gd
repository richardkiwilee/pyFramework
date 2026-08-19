class_name DiplomacyPanel
extends Control
## =============================================================================
## DiplomacyPanel — 外交面板（世界遮罩层内弹出的模态面板）
## =============================================================================
## 展示玩家与各 AI 势力的关系，提供外交行动按钮。
## 所有行动走 GameManager.diplomacy_system（模型层校验），结果用 Alert 提示。
##
## 用法（世界遮罩层）：DiplomacyPanel.open(overlay) 创建并挂载。
## 只做展示与按钮——规则全在外交系统里（docs/00-design.md §2 逻辑表现分离）。
## =============================================================================

## 打开面板（静态工厂）：挂到 parent 下并返回实例
static func open(parent: Node) -> DiplomacyPanel:
	var panel := DiplomacyPanel.new()
	parent.add_child(panel)
	return panel


var _rows_box: VBoxContainer


func _ready() -> void:
	# 全屏：暗色遮罩 + 居中面板
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 300  # 高于遮罩层(200)与地图(0)

	# 暗色遮罩背景（点击遮罩关闭）
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)

	# 居中面板（UITheme.center：锚点居中 + position=-size/2，真正的居中）
	var panel := PanelContainer.new()
	panel.size = Vector2(760, 520)
	UITheme.center(panel)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(16))
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	# 标题行 + 关闭按钮
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)
	title_row.add_child(UITheme.make_label(I18n.t("ui.dip.title"), 20, UITheme.GOLD_BRIGHT))
	title_row.add_child(UITheme.make_label("   " + I18n.t("ui.dip.relation"), 13, UITheme.INK_DIM))
	var close_btn := UITheme.make_button(I18n.t("ui.common.close"), UITheme.default_button_style(), 13)
	close_btn.add_theme_color_override("font_color", UITheme.INK)
	close_btn.pressed.connect(func() -> void: queue_free())
	title_row.add_child(close_btn)

	# 每个 AI 势力一行
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 8)
	outer.add_child(_rows_box)

	_build_rows()


func _build_rows() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	var player: Faction = GameManager.game_state.player_faction()
	if player == null:
		return
	for faction in GameManager.game_state.ai_factions():
		_rows_box.add_child(_build_faction_row(player, faction))


## 单个势力的外交行：名称/态度/关系值 + 行动按钮
func _build_faction_row(player: Faction, faction: Faction) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# 势力名 + 态度
	var name_label := UITheme.make_label(faction.name_zh, 15, UITheme.INK)
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)

	var rel: Relation = GameManager.diplomacy_system.ensure_relation(player.id, faction.id)
	var level: String = GameManager.diplomacy_system.attitude_level(rel)
	var level_label := UITheme.make_label(_level_text(level), 13, _level_color(level))
	level_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(level_label)

	var value_label := UITheme.make_label("%.0f" % rel.attitude, 13, UITheme.INK2)
	value_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(value_label)

	# 行动按钮（按当前状态给可用/禁用反馈——校验仍由系统兜底）
	var actions := [
		["ui.dip.declare_war", func() -> void: _act_declare_war(faction)],
		["ui.dip.make_peace", func() -> void: _act_make_peace(faction)],
		["ui.dip.friendship", func() -> void: _act_friendship(faction)],
		["ui.dip.alliance", func() -> void: _act_alliance(faction)],
		["ui.dip.trade", func() -> void: _act_trade(faction)],
		["ui.dip.tribute", func() -> void: _act_tribute(faction)],
	]
	for action in actions:
		var bt := UITheme.make_button(I18n.t(action[0]), UITheme.default_button_style(), 12)
		bt.add_theme_color_override("font_color", UITheme.INK2)
		bt.pressed.connect(action[1])
		row.add_child(bt)
	return row


# ==================================================================
#  行动（调用外交系统，结果 → Alert + 刷新）
# ==================================================================

func _act_declare_war(faction: Faction) -> void:
	var r: Dictionary = _player_action(faction, "declare_war")
	_show_result(r, I18n.t("ui.dip.declare_war"))


func _act_make_peace(faction: Faction) -> void:
	var r: Dictionary = _player_action(faction, "make_peace")
	_show_result(r, I18n.t("ui.dip.make_peace"))


func _act_friendship(faction: Faction) -> void:
	var r: Dictionary = _player_action(faction, "friendship")
	_show_result(r, I18n.t("ui.dip.friendship"))


func _act_alliance(faction: Faction) -> void:
	var r: Dictionary = _player_action(faction, "alliance")
	_show_result(r, I18n.t("ui.dip.alliance"))


func _act_trade(faction: Faction) -> void:
	# 简化贸易：固定模板——给 30 金币，索 20 粮食
	var player: Faction = GameManager.game_state.player_faction()
	var r: Dictionary = GameManager.diplomacy_system.propose_trade(
		player, faction, {"gold": 30}, {"food": 20})
	if r.get("ok", false) and r.get("accepted", false):
		Alert.alert(I18n.t("ui.dip.accepted") + " (+%d)" % int(r.get("score", 0)), UITheme.GREEN)
	elif r.get("ok", false):
		Alert.alert(I18n.t("ui.dip.rejected") + " (%d)" % int(r.get("score", 0)), UITheme.RED)
	else:
		_show_result(r, I18n.t("ui.dip.trade"))
	_build_rows()


func _act_tribute(faction: Faction) -> void:
	var r: Dictionary = _player_action(faction, "tribute")
	if r.get("ok", false):
		Alert.alert(I18n.t("ui.dip.tribute") + " ✓ " + str(r.get("taken", {})), UITheme.GREEN)
	else:
		_show_result(r, I18n.t("ui.dip.tribute"))


## 执行"玩家对 AI 势力"的外交行动
func _player_action(faction: Faction, kind: String) -> Dictionary:
	var player: Faction = GameManager.game_state.player_faction()
	match kind:
		"declare_war":
			return GameManager.diplomacy_system.declare_war(player, faction)
		"make_peace":
			return GameManager.diplomacy_system.make_peace(player, faction)
		"friendship":
			return GameManager.diplomacy_system.declare_friendship(player, faction)
		"alliance":
			return GameManager.diplomacy_system.declare_alliance(player, faction)
		"tribute":
			return GameManager.diplomacy_system.demand_tribute(player, faction)
	return {"ok": false, "reason": "unknown"}


func _show_result(r: Dictionary, action_name: String) -> void:
	if r.get("ok", false):
		Alert.alert(action_name + " ✓", UITheme.GREEN)
	else:
		# 拒绝原因粗粒度提示（细节规则不在这里展开）
		Alert.alert(action_name + " ✗", UITheme.RED)
	_build_rows()


# ==================================================================
#  展示辅助
# ==================================================================

func _level_text(level: String) -> String:
	# 交战态的 i18n key 是 ui.dip.at_war（与其余等级 key 命名不同）
	var key := "ui.dip.at_war" if level == "war" else "ui.dip." + level
	var text := I18n.t(key)
	# key 不存在时 I18n 原样返回 key，这里兜底显示等级原文
	return level if text == key else text


func _level_color(level: String) -> Color:
	match level:
		"war": return UITheme.RED
		"hostile": return Color("#c2553a")
		"friendly": return UITheme.GREEN
		"allied": return UITheme.GOLD_BRIGHT
		_: return UITheme.INK2
