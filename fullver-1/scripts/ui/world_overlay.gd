extends Control
## =============================================================================
## WorldOverlay — 大地图遮罩1（readme 场景结构第 3 项）
## =============================================================================
## 布局（用户确认版）：
##   - 顶部：全局资源栏占满窗口顶栏（左：回合数+资源；右：全部功能按钮）
##   - 右下角：圆形"结束回合"按钮
##   - 左下角：部队统帅竖长方形条（每个玩家军团一个，点击=快速选中该军团；
##     选中后的功能待后续）
##   - 左下角上方：消息面板（最近事件）
##
## ⚠️ 本环境实测坑：
##   - z_index 无视节点树顺序：本层 z_index=200 必须高于地图绘制层（z=0）
##   - 根节点 mouse_filter=IGNORE：全屏遮罩不能挡住地图点击，
##     只有按钮等可交互子控件收鼠标事件
## =============================================================================

var _turn_label: Label
var _resource_labels: Dictionary = {}   # 资源id → Label
var _msg_box: VBoxContainer
var _portrait_row: HBoxContainer


func _ready() -> void:
	# 根节点不挡鼠标（地图点击穿透），按钮正常收事件
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200

	_build_top_bar()
	_build_end_turn_button()
	_build_portraits()
	_build_message_panel()

	GameManager.game_event.connect(_on_game_event)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.game_started.connect(_on_game_started)
	_refresh_all()


## ---------------------------------------------------------------------------
## 顶部资源栏：占满窗口顶栏。
## 左：回合数 + 各资源（emoji + 数量合并为单标签）；右：全部功能按钮。
## ⚠️ 顶栏所有标签必须关闭自动换行（AUTOWRAP_OFF）——否则被挤压时
## 会逐字竖排（实测反馈），且 emoji 与数字合并后单标签一个字体即可。
## ---------------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)  # 左右锚点 0~1，占满整行
	# ⚠️ 对非等锚点控件设置 size 会触发引擎警告（size 会被锚点覆盖），
	# 正确做法：直接设 offsets（left=right=0 占满宽，top=0 bottom=56 定高）
	bar.offset_left = 0
	bar.offset_right = 0
	bar.offset_top = 0
	bar.offset_bottom = 56
	bar.add_theme_stylebox_override("panel", UITheme.panel_style(6))
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)

	# --- 左组：回合 + 资源（单标签 = emoji + 空格 + 数量，禁止换行）---
	_turn_label = _bar_label("", 15, UITheme.GOLD_BRIGHT)
	row.add_child(_turn_label)
	var resource_defs: Array = DataManager.get_resource_defs()
	for res_def in resource_defs:
		var res_id: String = res_def.get("id", "")
		# emoji 字体：含 emoji + ASCII 数字字形（数量是数字，混排安全）
		var label := _bar_label("%s 0" % ArtIndex.get_emoji(res_def.get("icon", "")), 15, UITheme.INK)
		label.add_theme_font_override("font", UITheme.emoji_font)
		row.add_child(label)
		_resource_labels[res_id] = label

	# --- 弹性间隔：把右组推到最右 ---
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# --- 右组：功能按钮 ---
	_add_top_button(row, I18n.t("ui.world.city_manage"), func() -> void: _open_city_manage())
	_add_top_button(row, I18n.t("ui.world.unit_editor"), func() -> void: _open_unit_editor())
	_add_top_button(row, I18n.t("ui.world.diplomacy"), func() -> void: _open_diplomacy())
	_add_top_button(row, I18n.t("ui.world.save"), func() -> void: _save_game())
	_add_top_button(row, I18n.t("ui.world.menu"), func() -> void: _open_menu())


## 顶栏专用标签：自动换行关闭（防挤压竖排），宽度收缩但不换行
func _bar_label(text: String, font_size: int, color: Color) -> Label:
	var lb := UITheme.make_label(text, font_size, color)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	lb.clip_text = false
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lb


func _add_top_button(row: HBoxContainer, text: String, callback: Callable) -> void:
	var bt := UITheme.make_button(text, UITheme.default_button_style(), 14)
	bt.add_theme_color_override("font_color", UITheme.INK)
	bt.custom_minimum_size = Vector2(0, 44)
	bt.pressed.connect(callback)
	row.add_child(bt)


## ---------------------------------------------------------------------------
## 圆形结束回合按钮（右下角）
## ---------------------------------------------------------------------------
func _build_end_turn_button() -> void:
	var bt := Button.new()
	bt.text = I18n.t("ui.world.end_turn")
	bt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bt.size = Vector2(112, 112)
	bt.position = Vector2(-bt.size.x - 28.0, -bt.size.y - 28.0)
	# 圆形：圆角半径 = 边长一半
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITheme.GOLD
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = UITheme.LINE2
	sb.corner_radius_top_left = 56
	sb.corner_radius_top_right = 56
	sb.corner_radius_bottom_left = 56
	sb.corner_radius_bottom_right = 56
	bt.add_theme_stylebox_override("normal", sb)
	bt.add_theme_stylebox_override("hover", sb)
	bt.add_theme_font_size_override("font_size", 15)
	bt.add_theme_color_override("font_color", Color("1a1408"))
	bt.focus_mode = Control.FOCUS_NONE
	bt.pressed.connect(_end_turn)
	add_child(bt)


## ---------------------------------------------------------------------------
## 左下角：部队统帅竖长方形条（每个玩家军团一个）
## 点击 = 快速选中该军团（选中后功能待后续）。
## ---------------------------------------------------------------------------
func _build_portraits() -> void:
	_portrait_row = HBoxContainer.new()
	_portrait_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_portrait_row.position = Vector2(16, -140.0)   # 底部留边距（竖条高 ~124）
	_portrait_row.add_theme_constant_override("separation", 8)
	add_child(_portrait_row)


func _refresh_portraits() -> void:
	for child in _portrait_row.get_children():
		child.queue_free()
	var gs: GameState = GameManager.game_state
	if gs == null:
		return
	var player_id: String = DataManager.get_player_faction_id()
	var player_armies: Array[Army] = gs.armies_of(player_id)
	for army in player_armies:
		var portrait := PanelContainer.new()
		portrait.custom_minimum_size = Vector2(76, 124)   # 竖长方形
		# 势力色边框 + 深底
		var sb := StyleBoxFlat.new()
		sb.bg_color = UITheme.PANEL2
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.border_color = UITheme.faction_color(player_id)
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		portrait.add_theme_stylebox_override("panel", sb)
		# 内容：⚔ 图标 + 军团名 + 兵力
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		portrait.add_child(inner)
		var icon := UITheme.make_label("⚔", 24, UITheme.GOLD_BRIGHT)
		icon.add_theme_font_override("font", UITheme.emoji_font)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(icon)
		var name_label := UITheme.make_label(army.id, 11, UITheme.INK)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(name_label)
		var count_label := UITheme.make_label("%d人" % army.team.unit_count(), 11, UITheme.INK2)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(count_label)
		# ⚠️ 闭包陷阱：复制循环变量
		var army_id_copy := army.id
		portrait.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var screen: WorldMapScreen = get_parent()
				screen.select_army_by_id(army_id_copy))
		_portrait_row.add_child(portrait)


## ---------------------------------------------------------------------------
## 消息面板：左下角、统帅条上方
## ---------------------------------------------------------------------------
func _build_message_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(16, -360.0)
	panel.size = Vector2(430, 212)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(8))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_msg_box = VBoxContainer.new()
	_msg_box.add_theme_constant_override("separation", 4)
	panel.add_child(_msg_box)


# ==================================================================
#  刷新与事件格式化
# ==================================================================

func _refresh_all() -> void:
	var gs: GameState = GameManager.game_state
	if gs == null:
		_turn_label.text = ""
		return
	_turn_label.text = I18n.t("ui.world.turn", [gs.turn])
	var player: Faction = gs.player_faction()
	if player != null:
		for res_id in _resource_labels:
			var res_icon: String = ""
			for res_def in DataManager.get_resource_defs():
				if res_def.get("id", "") == res_id:
					res_icon = ArtIndex.get_emoji(res_def.get("icon", ""))
					break
			_resource_labels[res_id].text = "%s %d" % [res_icon, int(player.resources.get(res_id, 0))]
	_refresh_messages()
	_refresh_portraits()


func _refresh_messages() -> void:
	for child in _msg_box.get_children():
		child.queue_free()
	var gs: GameState = GameManager.game_state
	if gs == null:
		return
	var events: Array = gs.recent_events(8)
	for ev in events:
		var text: String = _format_event(ev)
		if text == "":
			continue
		_msg_box.add_child(UITheme.make_label(text, 13, UITheme.INK2))


## 事件字典 → 展示文案（kind 对应 i18n 的 event.* key）
func _format_event(ev: Dictionary) -> String:
	var kind: String = ev.get("kind", "")
	var data: Dictionary = ev.get("data", {})
	match kind:
		"turn_start":
			return I18n.t("event.turn_start", [ev.get("turn", 0)])
		"city_captured":
			return I18n.t("event.city_captured", [
				_faction_name(data.get("new_owner", "")),
				data.get("city_name", ""),
			])
		"city_neutral":
			return I18n.t("event.city_neutral", [
				_faction_name(data.get("new_owner", "")),
				data.get("city_name", ""),
			])
		"battle_win":
			return I18n.t("event.battle_win", [
				_faction_name(data.get("winner", "")),
				data.get("city_name", ""),
			])
		"battle_lose":
			return I18n.t("event.battle_lose", [
				_faction_name(data.get("loser", "")),
				data.get("city_name", ""),
			])
		_:
			return ""


func _faction_name(faction_id: String) -> String:
	if faction_id == "":
		return "?"
	var fd: Dictionary = DataManager.get_faction(faction_id)
	return fd.get("name_zh", faction_id)


# ==================================================================
#  信号回调
# ==================================================================

func _on_game_event(_kind: String, _data: Dictionary) -> void:
	_refresh_all()


func _on_turn_started(_turn: int) -> void:
	_refresh_all()


func _on_game_started() -> void:
	_refresh_all()


# ==================================================================
#  按钮动作
# ==================================================================

func _end_turn() -> void:
	GameManager.end_turn()
	# 战斗请求由 battle_requested 信号驱动切场景；无战斗时回合自然推进


func _open_city_manage() -> void:
	var screen: WorldMapScreen = get_parent()
	GameManager.selected_city_id = screen.selected_city_id
	if GameManager.selected_city_id == "":
		Alert.alert(I18n.t("ui.world.own_city"), UITheme.INK2)
		return
	if ResourceLoader.exists("res://scenes/city_manage.tscn"):
		await GameManager.change_scene("res://scenes/city_manage.tscn")
	else:
		Alert.alert(I18n.t("ui.world.city_manage") + " — 未实现", UITheme.GOLD)


func _open_unit_editor() -> void:
	if ResourceLoader.exists("res://scenes/unit_editor.tscn"):
		await GameManager.change_scene("res://scenes/unit_editor.tscn")
	else:
		Alert.alert(I18n.t("ui.world.unit_editor") + " — 未实现", UITheme.GOLD)


func _open_diplomacy() -> void:
	if GameManager.diplomacy_system == null:
		Alert.alert(I18n.t("ui.world.diplomacy") + " — 未开局", UITheme.INK2)
		return
	DiplomacyPanel.open(self)


func _save_game() -> void:
	if GameManager.save_game(1):
		Alert.alert(I18n.t("ui.world.save") + " ✓", UITheme.GREEN)
	else:
		Alert.alert(I18n.t("ui.menu.save_failed"), UITheme.RED)


func _open_menu() -> void:
	await GameManager.change_scene("res://scenes/main_menu.tscn")
