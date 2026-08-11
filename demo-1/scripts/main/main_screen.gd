extends Control
## MainScreen - Formation screen controller. Manages team boards, unit editor, and overlays.

const TeamManagerClass = preload("res://scripts/main/team_manager.gd")
const BoardGridClass = preload("res://scripts/main/board_grid.gd")

@onready var top_bar: Label = $TopBar
@onready var zone_left: PanelContainer = $MainLayout/ZoneLeft
@onready var zone_right: PanelContainer = $MainLayout/ZoneRight
@onready var board_container: VBoxContainer = $MainLayout/ZoneLeft/VBoxLeft/ScrollContainer/BoardContainer
@onready var act_lab: Label = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/ActLab
@onready var btn_new_team: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnNewTeam
@onready var btn_disband: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnDisband
@onready var btn_battle: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnBattle
@onready var editor = $MainLayout/ZoneRight/UnitEditor
@onready var hint_bar: Label = $HintBar
@onready var char_picker = $MainLayout/ZoneLeft/Overlay/CharPicker

var team_manager  # TeamManager
var active_board_index: int = 0
var boards: Array = []  # Array[BoardGrid]
var selecting_slot: int = -1
var selecting_team: int = -1

# Equipment storage: {char_id: {slot_key: eq_id}}
var equipment_data: Dictionary = {}
# Current slot being equipped
var equip_pending_slot: String = ""
var equip_pending_char: String = ""


func _ready() -> void:
	team_manager = TeamManagerClass.new()
	add_child(team_manager)
	team_manager.team_changed.connect(_on_team_changed)

	# Theme the top bar
	top_bar.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	top_bar.add_theme_font_size_override("font_size", 14)

	act_lab.add_theme_color_override("font_color", UITheme.INK_DIM)
	act_lab.add_theme_font_size_override("font_size", 11)

	hint_bar.add_theme_color_override("font_color", UITheme.INK_DIM)
	hint_bar.add_theme_font_size_override("font_size", 11)
	hint_bar.text = "点击棋盘空格放置单位 · 点击已放置单位查看/编辑 · 右键移除单位"

	# Style buttons
	_style_btn(btn_new_team, "+ 新增队伍")
	_style_btn(btn_disband, "解散队伍")
	_style_battle_btn(btn_battle, "▶ 开始战斗")

	btn_new_team.pressed.connect(_on_new_team)
	btn_disband.pressed.connect(_on_disband_team)
	btn_battle.pressed.connect(_on_start_battle)

	# Connect editor equip signal
	editor.equip_slot_clicked.connect(_on_equip_slot_clicked)

	# Build boards
	_rebuild_boards()

	# Setup pickers
	_setup_char_picker()
	_setup_equip_picker()


func _style_btn(btn: Button, text: String) -> void:
	btn.text = text
	btn.add_theme_color_override("font_color", UITheme.INK)
	btn.add_theme_font_size_override("font_size", 12)
	btn.begin_bulk_theme_override()
	btn.add_theme_stylebox_override("normal", UITheme.default_button_style())
	btn.end_bulk_theme_override()


func _style_battle_btn(btn: Button, text: String) -> void:
	btn.text = text
	btn.add_theme_color_override("font_color", Color("2c1c0e"))
	btn.add_theme_font_size_override("font_size", 13)
	btn.begin_bulk_theme_override()
	btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	btn.end_bulk_theme_override()


func _rebuild_boards() -> void:
	for b in boards:
		b.queue_free()
	boards.clear()

	for i in range(team_manager.teams.size()):
		var board := BoardGridClass.new()
		board.team_index = i
		board.is_active = (i == active_board_index)
		board.refresh(i, team_manager.teams[i].units, board.is_active)
		board.slot_clicked.connect(_on_board_slot_clicked)
		board.slot_right_clicked.connect(_on_board_slot_right_clicked)
		board_container.add_child(board)
		boards.append(board)

	if boards.size() > 0:
		select_board(active_board_index)

	_update_act_lab()


func select_board(idx: int) -> void:
	if idx < 0 or idx >= boards.size():
		return
	active_board_index = idx
	for i in range(boards.size()):
		boards[i].is_active = (i == idx)
		boards[i].refresh(i, team_manager.teams[i].units, boards[i].is_active)
	_update_act_lab()


func _update_act_lab() -> void:
	var team = team_manager.get_team(active_board_index)
	var count := 0
	for uid in team.units:
		if uid != "":
			count += 1
	act_lab.text = "第%d队 · %d/6 单位" % [active_board_index + 1, count]


func _on_team_changed(_idx: int) -> void:
	_rebuild_boards()


func _on_board_slot_clicked(slot: int, board) -> void:
	var uid = team_manager.get_unit_at(board.team_index, slot)

	if uid == "":
		# Empty slot - open character picker to fill it
		selecting_slot = slot
		selecting_team = board.team_index
		_open_char_picker()
	else:
		# Occupied slot - select unit in editor with equipment data
		var eq = equipment_data.get(uid, {})
		editor.show_unit(uid, board.team_index, slot, eq)
		active_board_index = board.team_index
		_rebuild_boards()


func _on_board_slot_right_clicked(slot: int, board) -> void:
	var uid = team_manager.get_unit_at(board.team_index, slot)
	if uid != "":
		team_manager.remove_unit(board.team_index, slot)
		# Also clear equipment for this char
		equipment_data.erase(uid)
		editor.clear()


# ------------------------------------------------------------------ equipment
func _on_equip_slot_clicked(char_id: String, slot_key: String) -> void:
	equip_pending_char = char_id
	equip_pending_slot = slot_key
	_open_equip_picker()


func _setup_equip_picker() -> void:
	# Create equipment picker overlay programmatically
	var equip_picker := PanelContainer.new()
	equip_picker.name = "EquipPicker"
	equip_picker.visible = false
	equip_picker.set_anchors_preset(Control.PRESET_CENTER)
	equip_picker.offset_left = -280
	equip_picker.offset_top = -250
	equip_picker.offset_right = 280
	equip_picker.offset_bottom = 250

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.114, 0.094, 0.078, 0.95)
	sb.border_width_left = 2; sb.border_width_right = 2
	sb.border_width_top = 2; sb.border_width_bottom = 2
	sb.border_color = UITheme.GOLD
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10; sb.corner_radius_bottom_right = 10
	equip_picker.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	equip_picker.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "选择装备"
	title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): equip_picker.visible = false)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Filter row
	var filter_row := HBoxContainer.new()
	filter_row.name = "FilterRow"
	filter_row.add_theme_constant_override("separation", 8)
	var filter_label := Label.new()
	filter_label.text = "类型:"
	filter_label.add_theme_color_override("font_color", UITheme.INK_DIM)
	filter_label.add_theme_font_size_override("font_size", 11)
	filter_row.add_child(filter_label)
	var filter_opt := OptionButton.new()
	filter_opt.name = "FilterOpt"
	filter_opt.add_item("全部", 0)
	filter_opt.add_item("剑 sword", 1); filter_opt.add_item("斧 axe", 2)
	filter_opt.add_item("枪 spear", 3); filter_opt.add_item("弓 bow", 4)
	filter_opt.add_item("杖 staff", 5); filter_opt.add_item("盾 shield", 6)
	filter_opt.item_selected.connect(func(idx): _refresh_equip_list(equip_picker))
	filter_row.add_child(filter_opt)
	# Unequip button
	var unequip_btn := Button.new()
	unequip_btn.text = "卸下装备"
	unequip_btn.add_theme_color_override("font_color", UITheme.RED)
	unequip_btn.add_theme_font_size_override("font_size", 11)
	unequip_btn.pressed.connect(func():
		if equip_pending_char != "":
			if not equipment_data.has(equip_pending_char):
				equipment_data[equip_pending_char] = {}
			equipment_data[equip_pending_char].erase(equip_pending_slot)
			editor.equip_item(equip_pending_slot, "")
			equip_picker.visible = false
	)
	filter_row.add_child(unequip_btn)
	vbox.add_child(filter_row)

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.name = "EqList"
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	vbox.add_child(scroll)

	var overlay = $MainLayout/ZoneLeft/Overlay
	overlay.add_child(equip_picker)


func _open_equip_picker() -> void:
	var equip_picker = $MainLayout/ZoneLeft/Overlay/EquipPicker
	equip_picker.visible = true
	_refresh_equip_list(equip_picker)


func _refresh_equip_list(equip_picker: PanelContainer) -> void:
	var list = equip_picker.get_node("VBox/ScrollContainer/EqList")
	for child in list.get_children():
		child.queue_free()

	var filter_opt: OptionButton = equip_picker.get_node("VBox/FilterRow/FilterOpt")
	var filter_idx = filter_opt.selected
	var subtype_names := ["", "sword", "axe", "spear", "bow", "staff", "shield"]
	var filter_subtype = subtype_names[filter_idx] if filter_idx < subtype_names.size() else ""

	# Collect equipment IDs
	var all_eq = DataManager.get_all_equipment_ids()
	var filtered: Array = []
	for eq_id in all_eq:
		var eq = DataManager.get_equipment(eq_id)
		var st = eq.get("subtype", "")
		if filter_subtype == "" or st == filter_subtype:
			filtered.append(eq_id)

	# Sort by rarity and attack power
	filtered.sort_custom(func(a, b):
		var ea = DataManager.get_equipment(a); var eb = DataManager.get_equipment(b)
		var ra = ea.get("rarity", "common"); var rb = eb.get("rarity", "common")
		var rarity_order = {"legendary":0, "epic":1, "rare":2, "uncommon":3, "common":4}
		var ro = rarity_order.get(ra, 5) - rarity_order.get(rb, 5)
		if ro != 0: return ro < 0
		var sa = ea.get("stats", {}); var sb = eb.get("stats", {})
		return sa.get("atk", sa.get("mag", 0)) > sb.get("atk", sb.get("mag", 0))
	)

	var count := 0
	for eq_id in filtered:
		if count >= 80:  # limit display
			break
		var eq = DataManager.get_equipment(eq_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var eq_name = eq.get("name_zh", eq.get("name_en", "???"))
		var rarity = eq.get("rarity", "common")
		var stats = eq.get("stats", {})

		# Name and stats on one line
		var info := Label.new()
		var stat_str := ""
		for k in stats:
			stat_str += "%s+%d " % [k, stats[k]]
		info.text = "%s  [%s]  %s" % [eq_name, rarity, stat_str]
		info.add_theme_color_override("font_color", UITheme.rarity_color(rarity))
		info.add_theme_font_size_override("font_size", 12)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var sel_btn := Button.new()
		sel_btn.text = "装备"
		sel_btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		sel_btn.add_theme_font_size_override("font_size", 11)
		var eq_id_copy = eq_id
		sel_btn.pressed.connect(func():
			if equip_pending_char != "":
				if not equipment_data.has(equip_pending_char):
					equipment_data[equip_pending_char] = {}
				equipment_data[equip_pending_char][equip_pending_slot] = eq_id_copy
				editor.equip_item(equip_pending_slot, eq_id_copy)
				equip_picker.visible = false
		)
		row.add_child(sel_btn)
		list.add_child(row)
		count += 1


func _on_new_team() -> void:
	team_manager.add_team()
	active_board_index = team_manager.teams.size() - 1


func _on_disband_team() -> void:
	if team_manager.teams.size() > 1:
		team_manager.remove_team(active_board_index)


func _on_start_battle() -> void:
	if not team_manager.has_any_units():
		_show_toast("请先在队伍中放置至少一个单位！")
		return

	var active_team_ids = team_manager.get_team_unit_ids(active_board_index)
	if active_team_ids.is_empty():
		_show_toast("当前队伍为空，请先放置单位！")
		return

	BattleManager.reset()
	BattleManager.start_battle(active_team_ids)
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


# ------------------------------------------------------------------ character picker
func _setup_char_picker() -> void:
	char_picker.visible = false
	var close_btn = char_picker.get_node_or_null("Panel/Header/CloseBtn")
	if close_btn:
		close_btn.pressed.connect(func(): char_picker.visible = false)

	var list = char_picker.get_node_or_null("Panel/ScrollContainer/CharList")
	if not list:
		return


func _open_char_picker() -> void:
	char_picker.visible = true
	var list = char_picker.get_node_or_null("Panel/ScrollContainer/CharList")
	if not list:
		return

	# Clear existing rows
	for child in list.get_children():
		child.queue_free()

	var assigned = team_manager.get_all_assigned_char_ids()
	var all_ids = DataManager.get_all_character_ids()

	for cid in all_ids:
		var ch = DataManager.get_character(cid)
		var in_use = cid in assigned and cid != team_manager.get_unit_at(selecting_team, selecting_slot)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon := Label.new()
		icon.text = _char_icon(ch)
		icon.add_theme_font_size_override("font_size", 20)
		row.add_child(icon)

		var info := VBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "%s  [%s]" % [ch.get("name_zh", "???"), ch.get("class_zh", "")]
		name_lbl.add_theme_color_override("font_color", UITheme.INK if not in_use else UITheme.INK_DIM)
		name_lbl.add_theme_font_size_override("font_size", 13)
		info.add_child(name_lbl)

		var sub_lbl := Label.new()
		sub_lbl.text = ch.get("region", "") + " · " + ch.get("rarity", "")
		sub_lbl.add_theme_color_override("font_color", UITheme.INK_DIM)
		sub_lbl.add_theme_font_size_override("font_size", 10)
		info.add_child(sub_lbl)
		row.add_child(info)

		# Spacer
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		if in_use:
			var used := Label.new()
			used.text = "已编入"
			used.add_theme_color_override("font_color", UITheme.RED)
			used.add_theme_font_size_override("font_size", 11)
			row.add_child(used)
		else:
			var sel_btn := Button.new()
			sel_btn.text = "选择"
			sel_btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
			sel_btn.add_theme_font_size_override("font_size", 11)
			var cid_copy = cid
			sel_btn.pressed.connect(func():
				team_manager.set_unit(selecting_team, selecting_slot, cid_copy)
				char_picker.visible = false
				editor.show_unit(cid_copy, selecting_team, selecting_slot)
			)
			row.add_child(sel_btn)

		list.add_child(row)


func _char_icon(ch: Dictionary) -> String:
	var cls = ch.get("class_zh", "")
	var cls_icons := {
		"领主": "👑", "君主": "👑", "女祭司": "🙏", "斗士": "🛡️", "先锋": "🛡️",
		"兵士": "🔱", "剑士": "⚔️", "剑豪": "⚔️", "佣兵": "⚔️", "重装步兵": "🛡️",
		"角斗士": "💪", "狂战士": "💪", "战士": "🔨", "扫荡者": "🔨",
		"猎人": "🏹", "神猎手": "🏹", "射手": "🏹", "盗贼": "🗡️",
		"骑士": "🐴", "重骑士": "🐴", "白骑士": "🐴", "黑骑士": "🐴",
		"牧师": "✨", "主教": "✨", "法师": "🔥", "术士": "🔥",
		"魔女": "❄️", "女巫": "❄️", "萨满": "🌿", "德鲁伊": "🌿",
		"狮鹫骑士": "🦅", "飞龙骑士": "🐉", "精灵剑士": "⚔️",
	}
	return cls_icons.get(cls, "👤")


# ------------------------------------------------------------------ toast
func _show_toast(msg: String) -> void:
	var toast := Label.new()
	toast.text = msg
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", UITheme.INK)
	toast.add_theme_font_size_override("font_size", 13)
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_bottom = 1.0
	toast.offset_left = -200
	toast.offset_right = 200
	toast.offset_bottom = -50
	add_child(toast)

	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 0.0, 2.0).set_delay(1.5)
	tween.tween_callback(toast.queue_free)
