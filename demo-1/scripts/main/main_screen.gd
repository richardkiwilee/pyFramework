extends Control
## =============================================================================
## MainScreen — 队伍编成主界面控制器（滚轮棋盘版，对标网页版）
## =============================================================================
## 作用：协调滚轮(ReelView)、右侧编辑器(UnitEditor)、角色选择器、
##       装备/技能/条件选择弹窗等所有 UI 组件。
##
## 界面布局：
##   +----------------------------------------------+
##   |  TopBar — 标题栏                              |
##   +----------+-----------------------------------+
##   | ZoneLeft | ZoneRight                         |
##   | (滚轮机框 | (UnitEditor — 装备卡/属性/策略)     |
##   | +行动条) |                                    |
##   +----------+-----------------------------------+
##   |  HintBar — 按键提示                           |
##   +----------------------------------------------+
##
## 按键操作（对齐网页版）：
##   ↑/↓ / 滚轮  滚动队伍      PgUp/PgDn 跳一页(teams.size())
##   ←/→         切换队内单位   Enter    下一队
##   空格         移动模式（←→↑↓遍历9格，空格/回车确认，Esc取消）
##   A            待命池放置到首个空格
##   Del/Back     移除选中单位（队长不可移除）
##   E/Q          焦点→右/左    Esc     关闭弹窗/取消移动
##
## 数据流概述：
##   TeamManager（数据层）↔ MainScreen（控制器）↔ ReelView/UnitEditor（视图）
##
##   MainScreen 持有两份运行时状态（不在角色 JSON 中，同网页版）：
##     equipment_data: {char_id: {slot_key: eq_id}}     装备
##     strategy_data:  {char_id: [{skill, cond1, cond2}]} 行动策略
## =============================================================================

# 预加载类 — 类似于 Python 的 import
# preload() 在脚本解析时执行（编译期），返回的是 PackedScene 或 GDScript 类引用
const TeamManagerClass = preload("res://scripts/main/team_manager.gd")

# ------------------------------------------------------------------ @onready 节点引用
@onready var top_bar: Label = $TopBar
@onready var zone_left: PanelContainer = $MainLayout/ZoneLeft
@onready var zone_right: PanelContainer = $MainLayout/ZoneRight
@onready var reel = $MainLayout/ZoneLeft/VBoxLeft/ReelView
@onready var act_lab: Label = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/ActLab
@onready var btn_prev: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnPrev
@onready var btn_next: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnNext
@onready var btn_new_team: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnNewTeam
@onready var btn_disband: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnDisband
@onready var btn_battle: Button = $MainLayout/ZoneLeft/VBoxLeft/ActionBar/BtnBattle
@onready var editor = $MainLayout/ZoneRight/UnitEditor
@onready var hint_bar: Label = $HintBar
@onready var overlay: Control = $MainLayout/ZoneLeft/Overlay
@onready var char_picker: PanelContainer = $MainLayout/ZoneLeft/Overlay/CharPicker

# ------------------------------------------------------------------ 运行时状态

## TeamManager 实例 — 队伍数据管理者（非 Autoload，手动创建）
var team_manager: TeamManager  # TeamManager 实例

## 当前选中的队伍索引（滚轮居中的队伍）
var active_team_idx: int = 0

## 选中单位ID（"" = 无选中）
var sel_unit_id: String = ""

## 移动模式状态：源单位 + 目标格
var move_src_id: String = ""
var move_target := Vector2i(-1, -1)

## 焦点在左区（true）还是右区（false）——影响滚轮与按键路由
var focus_left := true

## 装备数据：{char_id: {slot_key: eq_id}}
var equipment_data: Dictionary = {}

## 行动策略数据：{char_id: [{skill, cond1, cond2}]}
var strategy_data: Dictionary = {}

## 角色选择器（tscn 中的 CharPicker）模式："bench"（待命池放置）/ "captain"（选队长）
var char_picker_mode: String = ""
var char_picker_ctx: Dictionary = {}   # bench 模式：{"r": int, "c": int}

## 装备选择器上下文：哪个角色的哪个槽位正在等待选择装备
var equip_pending_slot: String = ""   # "weapon" / "shield" / "acc1" / "acc2"
var equip_pending_char: String = ""   # 角色ID

## 当前打开的 PickerFactory 弹窗（装备/技能/条件）
var _modal_panel: PanelContainer = null

# 焦点高亮 stylebox（_ready 时捕获默认样式）
var _zone_left_default: StyleBox
var _zone_right_default: StyleBox


# ==================================================================
#  _ready() — 初始化
# ==================================================================

func _ready() -> void:
	# --- 创建 TeamManager 实例 ---
	team_manager = TeamManagerClass.new()
	add_child(team_manager)
	team_manager.team_changed.connect(_on_team_changed)

	# --- 恢复队伍数据 / 预填充默认队伍 ---
	if DataManager.saved_teams.size() > 0:
		for t in DataManager.saved_teams:
			team_manager.normalize_team(t)
		team_manager.teams = DataManager.saved_teams.duplicate(true)
		print("[MainScreen] 已恢复 %d 支队伍数据" % team_manager.teams.size())
		DataManager.saved_teams.clear()
	else:
		team_manager.prefill_default_teams()  # 3队×3随机角色+队长（对齐网页版开局）

	# --- 捕获默认面板样式（焦点切换用） ---
	_zone_left_default = zone_left.get_theme_stylebox("panel")
	_zone_right_default = zone_right.get_theme_stylebox("panel")

	# --- 顶部标题栏样式 ---
	top_bar.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	top_bar.add_theme_font_size_override("font_size", 14)

	# --- 状态栏/提示栏样式 ---
	act_lab.add_theme_color_override("font_color", UITheme.INK_DIM)
	act_lab.add_theme_font_size_override("font_size", 11)
	hint_bar.add_theme_color_override("font_color", UITheme.INK_DIM)
	hint_bar.add_theme_font_size_override("font_size", 11)

	# --- 按钮样式与信号 ---
	_style_btn(btn_prev, "‹ 上一队")
	_style_btn(btn_next, "下一队 ›")
	_style_btn(btn_new_team, "＋ 新增队伍")
	_style_btn(btn_disband, "解散队伍")
	_style_battle_btn(btn_battle, "开始战斗")
	btn_prev.pressed.connect(func(): reel.feed(-1))
	btn_next.pressed.connect(func(): reel.feed(1))
	btn_new_team.pressed.connect(_on_new_team)
	btn_disband.pressed.connect(_on_disband_team)
	btn_battle.pressed.connect(_on_start_battle)

	# --- 编辑器信号 ---
	editor.equip_slot_clicked.connect(_on_equip_slot_clicked)
	editor.strategy_skill_clicked.connect(_on_strategy_skill_clicked)
	editor.strategy_cond_clicked.connect(_on_strategy_cond_clicked)
	editor.strategy_row_delete.connect(_on_strategy_row_delete)

	# --- 滚轮信号 ---
	reel.settled.connect(_on_reel_settled)
	reel.unit_clicked.connect(_on_reel_unit_clicked)
	reel.cell_clicked.connect(_on_reel_cell_clicked)

	# --- 右侧空白点击关闭弹窗（子控件 STOP 不会冒泡到 zone_right）---
	zone_right.gui_input.connect(_on_zone_right_input)

	# --- 角色选择器 ---
	_setup_char_picker()

	# --- 初始状态 ---
	sel_unit_id = team_manager.get_captain(0)
	_set_zone_focus(true)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()
	_update_top_bar()
	_update_hint()


# ==================================================================
#  按钮样式工具
# ==================================================================

## 常规按钮样式 — 深色背景+浅色文字
func _style_btn(btn: Button, text: String) -> void:
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE  # 关键：防止按钮抢走方向键/回车/空格
	btn.add_theme_color_override("font_color", UITheme.INK)
	btn.add_theme_font_size_override("font_size", 12)
	btn.begin_bulk_theme_override()
	btn.add_theme_stylebox_override("normal", UITheme.default_button_style())
	btn.end_bulk_theme_override()


## 战斗按钮样式 — 金色背景+深色文字（突出显示，最重要的操作按钮）
func _style_battle_btn(btn: Button, text: String) -> void:
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", Color("2c1c0e"))  # 深棕色文字
	btn.add_theme_font_size_override("font_size", 13)
	btn.begin_bulk_theme_override()
	btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	btn.end_bulk_theme_override()


# ==================================================================
#  键盘输入 — _unhandled_input（按键表见文件头注释）
# ==================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: Key = event.keycode

	# --- Esc：取消移动 → 关闭角色选择器 → 关闭弹窗 ---
	if k == KEY_ESCAPE:
		if move_src_id != "":
			_cancel_move()
			get_viewport().set_input_as_handled()
			return
		if char_picker.visible:
			if char_picker_mode == "captain":
				_show_toast("新建失败：未选择队长，已取消。", true)
			_close_char_picker()
			get_viewport().set_input_as_handled()
			return
		if _modal_panel != null and is_instance_valid(_modal_panel):
			_close_modal()
			get_viewport().set_input_as_handled()
			return

	# --- E / Q：切换焦点（任意焦点可用）---
	if k == KEY_E:
		_set_zone_focus(false)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_Q:
		_set_zone_focus(true)
		get_viewport().set_input_as_handled()
		return

	# --- 右焦点时其余按键不生效（网页版一致）---
	if not focus_left:
		return

	# --- ↑/↓：移动模式遍历行 / 滚动队伍 ---
	if k == KEY_UP:
		if move_src_id != "" and move_target != Vector2i(-1, -1):
			move_target = Vector2i(posmod(move_target.x - 1, 3), move_target.y)
			_refresh_reel()
		else:
			reel.feed(-1)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_DOWN:
		if move_src_id != "" and move_target != Vector2i(-1, -1):
			move_target = Vector2i(posmod(move_target.x + 1, 3), move_target.y)
			_refresh_reel()
		else:
			reel.feed(1)
		get_viewport().set_input_as_handled()
		return

	# --- PgUp/PgDn：整页滚动 ---
	if k == KEY_PAGEUP:
		reel.feed(-1, true)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_PAGEDOWN:
		reel.feed(1, true)
		get_viewport().set_input_as_handled()
		return

	# --- A：待命池放置到第一个空格 ---
	if k == KEY_A and move_src_id == "":
		_close_char_picker()
		_close_modal()
		_open_bench_picker()
		get_viewport().set_input_as_handled()
		return

	# --- ←/→：移动模式遍历 9 格 / 队内切换单位 ---
	if k == KEY_LEFT or k == KEY_RIGHT:
		var step := 1 if k == KEY_RIGHT else -1
		if move_src_id != "" and move_target != Vector2i(-1, -1):
			var idx := move_target.x * 3 + move_target.y
			idx = posmod(idx + step, 9)
			move_target = Vector2i(idx / 3, idx % 3)
			_refresh_reel()
		else:
			_cycle_units(step)
		get_viewport().set_input_as_handled()
		return

	# --- Enter：移动模式确认 / 下一队 ---
	if k == KEY_ENTER:
		if move_src_id != "":
			_confirm_move()
		else:
			reel.feed(1)
		get_viewport().set_input_as_handled()
		return

	# --- 空格：移动模式确认 / 进入移动模式 ---
	if k == KEY_SPACE:
		if move_src_id != "":
			_confirm_move()
		elif sel_unit_id != "":
			move_src_id = sel_unit_id
			move_target = team_manager.find_unit_cell(active_team_idx, sel_unit_id)
			_refresh_reel()
			_update_act_lab()
		get_viewport().set_input_as_handled()
		return

	# --- Del/Backspace：移除选中单位 ---
	if k == KEY_DELETE or k == KEY_BACKSPACE:
		if sel_unit_id != "":
			_remove_selected_unit()
		get_viewport().set_input_as_handled()


## 队内循环切换选中单位（step ±1）
func _cycle_units(step: int) -> void:
	var ids: Array = team_manager.get_team_unit_ids(active_team_idx)
	if ids.is_empty():
		return
	var pos: int = ids.find(sel_unit_id)
	if pos == -1:
		pos = 0
	else:
		pos = posmod(pos + step, ids.size())
	sel_unit_id = ids[pos]
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()


## 移除选中单位（队长保护）
func _remove_selected_unit() -> void:
	var team: Dictionary = team_manager.get_team(active_team_idx)
	if sel_unit_id == team.get("captain", ""):
		_show_toast("队长不可移除，请先在别队更换队长。", true)
		return
	var cell := team_manager.find_unit_cell(active_team_idx, sel_unit_id)
	if cell == Vector2i(-1, -1):
		return
	team_manager.set_unit(active_team_idx, cell.x * 3 + cell.y, "")
	sel_unit_id = team_manager.get_captain(active_team_idx)
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()


# ==================================================================
#  移动模式
# ==================================================================

## 确认移动：目标格==源格则取消；否则移动或交换
func _confirm_move() -> void:
	if move_src_id == "":
		return
	var src_cell := team_manager.find_unit_cell(active_team_idx, move_src_id)
	if src_cell == move_target:
		_cancel_move()  # 目标格就是源单位 → 取消移动
		return
	var occ: String = team_manager.get_unit_at_rc(active_team_idx, move_target.x, move_target.y)
	if occ != "":
		team_manager.swap_units(active_team_idx, src_cell.x * 3 + src_cell.y, move_target.x * 3 + move_target.y)
	else:
		team_manager.move_unit(active_team_idx, src_cell.x * 3 + src_cell.y, move_target.x * 3 + move_target.y)
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()


func _cancel_move() -> void:
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	_refresh_reel()
	_update_act_lab()


# ==================================================================
#  滚轮信号处理
# ==================================================================

## 滚轮停稳且中心队伍变化 → 切换活跃队伍
func _on_reel_settled(idx: int) -> void:
	if idx == active_team_idx:
		_update_act_lab()
		return
	active_team_idx = idx
	# 切换队伍时关闭可能残留的弹窗（避免显示旧队伍的过期数据）
	_close_char_picker()
	_close_modal()
	# 选中单位若不在该队 → 回退到队长（若无则 null）
	var team: Dictionary = team_manager.get_team(active_team_idx)
	var in_team := false
	for uid in team.units:
		if uid == sel_unit_id:
			in_team = true
			break
	if not in_team:
		var cap: String = team.get("captain", "")
		if cap != "":
			sel_unit_id = cap
		else:
			sel_unit_id = ""
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()
	_update_top_bar()


## 点击棋子
func _on_reel_unit_clicked(team_idx: int, r: int, c: int) -> void:
	if not reel.is_settled() or team_idx != active_team_idx:
		reel.scroll_to(team_idx)
		return
	var uid: String = team_manager.get_unit_at_rc(team_idx, r, c)
	if uid == "":
		return
	if move_src_id != "":
		if uid == move_src_id:
			_cancel_move()  # 点自己 → 取消移动
			return
		# 交换两个单位
		var a_cell := team_manager.find_unit_cell(team_idx, move_src_id)
		var b_cell := team_manager.find_unit_cell(team_idx, uid)
		if a_cell != Vector2i(-1, -1) and b_cell != Vector2i(-1, -1):
			team_manager.swap_units(team_idx, a_cell.x * 3 + a_cell.y, b_cell.x * 3 + b_cell.y)
		move_src_id = ""
		move_target = Vector2i(-1, -1)
	sel_unit_id = uid
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()


## 点击空格子
func _on_reel_cell_clicked(team_idx: int, r: int, c: int) -> void:
	if not reel.is_settled() or team_idx != active_team_idx:
		reel.scroll_to(team_idx)
		return
	var occ: String = team_manager.get_unit_at_rc(team_idx, r, c)
	if move_src_id != "":
		if occ == move_src_id:
			_cancel_move()
			return
		var src_cell := team_manager.find_unit_cell(team_idx, move_src_id)
		if src_cell != Vector2i(-1, -1):
			if occ != "":
				team_manager.swap_units(team_idx, src_cell.x * 3 + src_cell.y, r * 3 + c)
			else:
				team_manager.move_unit(team_idx, src_cell.x * 3 + src_cell.y, r * 3 + c)
		move_src_id = ""
		move_target = Vector2i(-1, -1)
		sel_unit_id = team_manager.get_unit_at_rc(team_idx, r, c)
		_refresh_reel()
		_show_editor_unit()
		_update_act_lab()
		return
	if occ != "":
		# 点击已放置单位所在格 → 选中
		sel_unit_id = occ
		_refresh_reel()
		_show_editor_unit()
		_update_act_lab()
		return
	# 空格子 → 放置弹窗（待命池）
	_open_char_picker("bench", {"r": r, "c": c})


## 队伍数据变更 → 刷新滚轮与状态栏
func _on_team_changed(_idx: int) -> void:
	_refresh_reel()
	_update_act_lab()
	_update_top_bar()


## 将 MainScreen 状态打包注入滚轮视图
func _refresh_reel() -> void:
	reel.refresh({
		"teams": team_manager.teams,
		"active_idx": active_team_idx,
		"sel_id": sel_unit_id,
		"move_src": move_src_id,
		"move_target": move_target,
		"focus_left": focus_left,
	})


# ==================================================================
#  焦点切换（E/Q）
# ==================================================================

func _set_zone_focus(left: bool) -> void:
	focus_left = left
	_refresh_reel()
	# 焦点边框：活跃区金亮描边（网页版 .focused）
	var focused := UITheme.panel_style(8)
	focused.border_width_left = 2
	focused.border_width_right = 2
	focused.border_width_top = 2
	focused.border_width_bottom = 2
	focused.border_color = UITheme.GOLD_BRIGHT
	if left:
		zone_left.add_theme_stylebox_override("panel", focused)
		zone_right.add_theme_stylebox_override("panel", _zone_right_default)
	else:
		zone_left.add_theme_stylebox_override("panel", _zone_left_default)
		zone_right.add_theme_stylebox_override("panel", focused)
	_update_hint()


func _on_zone_right_input(event: InputEvent) -> void:
	# 点击右侧空白 → 关闭弹窗（子控件 STOP，点击它们不会到达这里）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_modal()


# ==================================================================
#  状态栏 / 标题栏 / 提示栏
# ==================================================================

func _update_act_lab() -> void:
	var team: Dictionary = team_manager.get_team(active_team_idx)
	if move_src_id != "":
		var src_name: String = DataManager.get_character(move_src_id).get("name_zh", "")
		var tgt := ""
		if move_target != Vector2i(-1, -1):
			tgt = " · 目标格 (%d,%d)" % [move_target.x + 1, move_target.y + 1]
		act_lab.text = "移动中：%s%s · ←→↑↓ 遍历格子 · 空格/回车 确认 · Esc 取消" % [src_name, tgt]
	elif sel_unit_id != "":
		var ch := DataManager.get_character(sel_unit_id)
		var cap_tag := " · 队长" if sel_unit_id == team.get("captain", "") else ""
		act_lab.text = "%s · %s%s（%s）" % [team.get("name", "?"), ch.get("name_zh", "???"), cap_tag, sel_unit_id]
	else:
		var count := team_manager.get_team_unit_ids(active_team_idx).size()
		act_lab.text = "%s · %d/9 人 · 点击空格放置单位" % [team.get("name", "?"), count]


func _update_top_bar() -> void:
	var team: Dictionary = team_manager.get_team(active_team_idx)
	var count := team_manager.get_team_unit_ids(active_team_idx).size()
	top_bar.text = "圣兽之王 · 编队战斗  [%s · %d/9人]" % [team.get("name", "?"), count]


## 按键提示（对齐网页版 hint-bar 文案）
func _update_hint() -> void:
	if move_src_id != "":
		hint_bar.text = "焦点：左 · 移动模式 · ←→↑↓ 遍历棋盘格 · 空格/回车 确认 · Esc 取消"
	elif focus_left:
		hint_bar.text = "焦点：左 · ↑↓/滚轮 滚动队伍 · ←→ 切换单位 · 空格 移动模式 · A 上场单位 · Del 移除 · E 焦点→右 · Esc 关闭弹窗"
	else:
		hint_bar.text = "焦点：右 · 点击装备槽 / 策略格 弹出选择窗 · Q 焦点→左 · Esc 关闭弹窗"


# ==================================================================
#  按钮回调
# ==================================================================

## 新增队伍 → 队长选择器（对齐网页版：必须选队长）
func _on_new_team() -> void:
	if team_manager.teams.size() >= TeamManagerClass.MAX_TEAMS:
		_show_toast("已达队伍上限（8支）。", true)
		return
	_open_char_picker("captain", {})


## 解散队伍 → 释放单位，保持至少 1 队
func _on_disband_team() -> void:
	if team_manager.teams.size() <= 1:
		_show_toast("没有队伍可解散。", true)
		return
	var team: Dictionary = team_manager.get_team(active_team_idx)
	var name: String = team.get("name", "?")
	var freed := team_manager.get_team_unit_ids(active_team_idx).size()
	team_manager.remove_team(active_team_idx)
	active_team_idx = mini(active_team_idx, team_manager.teams.size() - 1)
	sel_unit_id = ""
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	reel.scroll_to(active_team_idx)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()
	_show_toast("已解散队伍「%s」，%d 名单位已回到待命池。" % [name, freed])


## 开始战斗（流程不变）
func _on_start_battle() -> void:
	if not team_manager.has_any_units():
		_show_toast("请先在队伍中放置至少一个单位！")
		return
	var active_team_ids: Array = team_manager.get_team_unit_ids(active_team_idx)
	if active_team_ids.is_empty():
		_show_toast("当前队伍为空，请先放置单位！")
		return
	# 保存队伍数据到 DataManager（切换场景后恢复编队）
	DataManager.saved_teams = team_manager.teams.duplicate(true)
	BattleManager.reset()
	BattleManager.start_battle(active_team_ids)
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


# ==================================================================
#  编辑器集成
# ==================================================================

## 右侧编辑器显示选中单位（含装备与策略数据）
func _show_editor_unit() -> void:
	if sel_unit_id == "":
		editor.clear()
		return
	var cell := team_manager.find_unit_cell(active_team_idx, sel_unit_id)
	if cell == Vector2i(-1, -1):
		editor.clear()
		return
	editor.show_unit(sel_unit_id, active_team_idx, cell.x * 3 + cell.y,
		equipment_data.get(sel_unit_id, {}), strategy_data.get(sel_unit_id, []))


# ==================================================================
#  行动策略编辑（弹窗在左侧覆盖层）
# ==================================================================

func _on_strategy_skill_clicked(char_id: String, row_idx: int, is_new: bool) -> void:
	if not strategy_data.has(char_id):
		strategy_data[char_id] = []
	_open_skill_picker(char_id, row_idx, is_new)


func _on_strategy_cond_clicked(char_id: String, row_idx: int, field: String) -> void:
	if row_idx < 0 or row_idx >= strategy_data.get(char_id, []).size():
		return
	_open_cond_picker(char_id, row_idx, field)


func _on_strategy_row_delete(char_id: String, row_idx: int) -> void:
	var rows: Array = strategy_data.get(char_id, [])
	if row_idx < 0 or row_idx >= rows.size():
		return
	rows.remove_at(row_idx)
	_close_modal()
	_show_editor_unit()


## 技能选择弹窗
func _open_skill_picker(char_id: String, row_idx: int, is_new: bool) -> void:
	var rows: Array = strategy_data.get(char_id, [])
	var cur: String = ""
	if not is_new and row_idx < rows.size():
		cur = rows[row_idx].get("skill", "")
	var foot := "选择一个技能新增为策略；Esc 取消。" if is_new else "点击技能进行更换；点击「卸下技能」清除该格。"
	var m := PickerFactory.build_modal(overlay, "选择技能 · %s" % DataManager.get_character(char_id).get("name_zh", ""), foot)
	_modal_panel = m.panel
	var body: VBoxContainer = m.body

	# 卸下技能行
	if not is_new and cur != "":
		var clr := Button.new()
		clr.text = "卸下技能（%s）" % DataManager.get_skill(cur).get("name_zh", "")
		clr.focus_mode = Control.FOCUS_NONE
		clr.add_theme_color_override("font_color", UITheme.RED)
		clr.add_theme_font_size_override("font_size", 12)
		clr.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		clr.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		clr.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
		clr.pressed.connect(func():
			rows[row_idx]["skill"] = ""
			_close_modal()
			_show_editor_unit()
		)
		body.add_child(clr)

	# 技能列表
	for sk_id in DataManager.get_all_skill_ids():
		var sk := DataManager.get_skill(sk_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var type_icon := "🔴" if sk.get("type", "") == "active" else "🔵"
		var ico := Label.new()
		ico.text = type_icon
		ico.add_theme_font_override("font", UITheme.emoji_font)
		ico.add_theme_font_size_override("font_size", 20)
		row.add_child(ico)

		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		name_lbl.text = "%s  AP:%d PP:%d" % [sk.get("name_zh", "???"), sk.get("ap_cost", 0), sk.get("pp_cost", 0)]
		name_lbl.add_theme_color_override("font_color", UITheme.INK)
		name_lbl.add_theme_font_size_override("font_size", 13)
		mid.add_child(name_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = sk.get("description_zh", "")
		desc_lbl.add_theme_color_override("font_color", UITheme.INK_DIM)
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mid.add_child(desc_lbl)
		row.add_child(mid)

		var mark := Label.new()
		mark.text = "✓ 已选" if cur == sk_id else ""
		mark.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		mark.add_theme_font_size_override("font_size", 11)
		row.add_child(mark)

		var sk_copy = sk_id  # 闭包陷阱！必须复制到局部变量
		row.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if is_new:
					if rows.size() >= 8:
						_show_toast("已达上限 8 条策略。", true)
						return
					rows.append({"skill": sk_copy, "cond1": "", "cond2": ""})
					_close_modal()
					_show_editor_unit()
				else:
					rows[row_idx]["skill"] = sk_copy
					_close_modal()
					_show_editor_unit()
		)
		body.add_child(row)
	_modal_panel.visible = true


## 条件选择弹窗
func _open_cond_picker(char_id: String, row_idx: int, field: String) -> void:
	var rows: Array = strategy_data.get(char_id, [])
	var cur: String = rows[row_idx].get(field, "")
	var other_field := "cond2" if field == "cond1" else "cond1"
	var other: String = rows[row_idx].get(other_field, "")
	var field_zh := "条件 1" if field == "cond1" else "条件 2"
	var m := PickerFactory.build_modal(overlay, "选择%s · %s" % [field_zh, DataManager.get_character(char_id).get("name_zh", "")],
		"点击条件进行设置；点击「卸下条件」清除该格。")
	_modal_panel = m.panel
	var body: VBoxContainer = m.body

	# 卸下条件行
	if cur != "":
		var clr := Button.new()
		clr.text = "卸下条件（%s）" % DataManager.get_condition(cur).get("name_zh", "")
		clr.focus_mode = Control.FOCUS_NONE
		clr.add_theme_color_override("font_color", UITheme.RED)
		clr.add_theme_font_size_override("font_size", 12)
		clr.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		clr.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		clr.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
		clr.pressed.connect(func():
			rows[row_idx][field] = ""
			_close_modal()
			_show_editor_unit()
		)
		body.add_child(clr)

	# 条件列表
	for cd_id in DataManager.get_all_condition_ids():
		var cd := DataManager.get_condition(cd_id)
		var dup: bool = (cd_id == other)  # 已用于另一条件 → 禁用
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.modulate.a = 0.45 if dup else 1.0

		var ico := Label.new()
		ico.text = "·"
		ico.add_theme_font_size_override("font_size", 16)
		ico.add_theme_color_override("font_color", UITheme.GOLD if not dup else UITheme.INK_DIM)
		row.add_child(ico)

		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		name_lbl.text = cd.get("name_zh", "???") + (" （已用于另一条件）" if dup else "")
		name_lbl.add_theme_color_override("font_color", UITheme.INK2 if not dup else UITheme.INK_DIM)
		name_lbl.add_theme_font_size_override("font_size", 13)
		mid.add_child(name_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = cd.get("description_zh", "")
		desc_lbl.add_theme_color_override("font_color", UITheme.INK_DIM)
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mid.add_child(desc_lbl)
		row.add_child(mid)

		var mark := Label.new()
		mark.text = "✓" if cur == cd_id else ""
		mark.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		mark.add_theme_font_size_override("font_size", 11)
		row.add_child(mark)

		var cd_copy = cd_id  # 闭包陷阱
		if not dup:
			row.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					rows[row_idx][field] = cd_copy
					_close_modal()
					_show_editor_unit()
			)
		body.add_child(row)
	_modal_panel.visible = true


# ==================================================================
#  装备选择弹窗
# ==================================================================

## 装备槽点击 → 打开仓库弹窗
func _on_equip_slot_clicked(char_id: String, slot_key: String) -> void:
	equip_pending_char = char_id
	equip_pending_slot = slot_key
	_open_equip_picker()


## 各槽位允许的装备子类型（数据驱动，替代旧版筛选下拉框）
func _slot_subtypes(slot_key: String) -> Array:
	match slot_key:
		"weapon":
			return ["sword", "axe", "spear", "bow", "staff"]
		"shield":
			return ["shield", "greatshield"]
		_:
			return []  # 饰品槽：全部装备


func _open_equip_picker() -> void:
	var slot_zh := {"weapon": "武器", "shield": "盾牌", "acc1": "饰品1", "acc2": "饰品2"}
	var ch_name: String = DataManager.get_character(equip_pending_char).get("name_zh", "")
	var m := PickerFactory.build_modal(overlay,
		"仓库 · %s槽位 · %s" % [slot_zh.get(equip_pending_slot, "?"), ch_name],
		"点击装备进行装备 / 卸下。已装备者标 E。")
	_modal_panel = m.panel
	var body: VBoxContainer = m.body

	# --- 卸下装备行 ---
	if equipment_data.get(equip_pending_char, {}).has(equip_pending_slot):
		var unequip := Button.new()
		unequip.text = "卸下装备"
		unequip.focus_mode = Control.FOCUS_NONE
		unequip.add_theme_color_override("font_color", UITheme.RED)
		unequip.add_theme_font_size_override("font_size", 12)
		unequip.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		unequip.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		unequip.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
		unequip.pressed.connect(func():
			equipment_data[equip_pending_char].erase(equip_pending_slot)
			editor.equip_item(equip_pending_slot, "")
			_close_modal()
		)
		body.add_child(unequip)

	# --- 筛选 + 排序 ---
	var subtypes: Array = _slot_subtypes(equip_pending_slot)
	var all_eq: Array = DataManager.get_all_equipment_ids()
	var filtered: Array = []
	for eq_id in all_eq:
		var eq := DataManager.get_equipment(eq_id)
		if subtypes.is_empty() or eq.get("subtype", "") in subtypes:
			filtered.append(eq_id)
	# 排序：稀有度优先 → 攻击力优先（沿用旧版比较器）
	filtered.sort_custom(func(a, b):
		var ea = DataManager.get_equipment(a)
		var eb = DataManager.get_equipment(b)
		var rarity_order := {"legendary": 0, "epic": 1, "rare": 2, "uncommon": 3, "common": 4}
		var ro: int = rarity_order.get(ea.get("rarity", "common"), 5) - rarity_order.get(eb.get("rarity", "common"), 5)
		if ro != 0:
			return ro < 0
		var sa: Dictionary = ea.get("stats", {})
		var sb2: Dictionary = eb.get("stats", {})
		return sa.get("atk", sa.get("mag", 0)) > sb2.get("atk", sb2.get("mag", 0))
	)

	# --- 装备行 ---
	var my_eq: Dictionary = equipment_data.get(equip_pending_char, {})
	var count := 0
	for eq_id in filtered:
		if count >= 80:
			break
		var eq := DataManager.get_equipment(eq_id)
		var rarity: String = eq.get("rarity", "common")
		var stats: Dictionary = eq.get("stats", {})
		var stat_zh := {"atk": "物攻", "mag": "魔攻", "def": "物防", "mdf": "魔防", "spd": "先制", "hp": "HP"}

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var ico := Label.new()
		ico.text = editor.eq_icon(eq)
		ico.add_theme_font_override("font", UITheme.emoji_font)
		ico.add_theme_font_size_override("font_size", 22)
		row.add_child(ico)

		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		var e_tag := "E " if my_eq.values().has(eq_id) else ""
		name_lbl.text = "%s%s · 品阶 %s" % [e_tag, eq.get("name_zh", "???"), rarity]
		name_lbl.add_theme_color_override("font_color", UITheme.rarity_color(rarity))
		name_lbl.add_theme_font_size_override("font_size", 13)
		mid.add_child(name_lbl)
		var stat_str := ""
		for k in stats:
			stat_str += "%s %+d  " % [stat_zh.get(k, k), stats[k]]
		var stat_lbl := Label.new()
		stat_lbl.text = stat_str
		stat_lbl.add_theme_color_override("font_color", UITheme.INK_DIM)
		stat_lbl.add_theme_font_size_override("font_size", 11)
		mid.add_child(stat_lbl)
		row.add_child(mid)

		# 状态按钮：卸下 / 已装备于其他槽 / 装备
		var in_this_slot: bool = my_eq.get(equip_pending_slot, "") == eq_id
		var in_other_slot := ""
		for k in my_eq:
			if my_eq[k] == eq_id and k != equip_pending_slot:
				in_other_slot = k
				break
		if in_this_slot or in_other_slot != "":
			var act := Button.new()
			act.focus_mode = Control.FOCUS_NONE
			act.add_theme_font_size_override("font_size", 11)
			if in_this_slot:
				act.text = "卸下"
				act.add_theme_color_override("font_color", UITheme.INK)
				var eq_copy = eq_id
				act.pressed.connect(func():
					equipment_data[equip_pending_char].erase(equip_pending_slot)
					editor.equip_item(equip_pending_slot, "")
					_close_modal()
				)
			else:
				act.text = "已装备于%s" % slot_zh.get(in_other_slot, "?")
				act.disabled = true
				act.add_theme_color_override("font_color", UITheme.INK_DIM)
			row.add_child(act)
		else:
			var act := Button.new()
			act.text = "装备"
			act.focus_mode = Control.FOCUS_NONE
			act.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
			act.add_theme_font_size_override("font_size", 11)
			act.begin_bulk_theme_override()
			act.add_theme_stylebox_override("normal", UITheme.gold_button_style())
			act.end_bulk_theme_override()
			var eq_copy = eq_id  # 闭包陷阱
			act.pressed.connect(func():
				if not equipment_data.has(equip_pending_char):
					equipment_data[equip_pending_char] = {}
				# 同一装备先从该角色其他槽卸下（对齐网页版 equip()）
				for k in equipment_data[equip_pending_char].keys():
					if equipment_data[equip_pending_char][k] == eq_copy:
						equipment_data[equip_pending_char].erase(k)
				equipment_data[equip_pending_char][equip_pending_slot] = eq_copy
				editor.equip_item(equip_pending_slot, eq_copy)
				_close_modal()
			)
			row.add_child(act)

		body.add_child(row)
		count += 1
	_modal_panel.visible = true


## 关闭 PickerFactory 弹窗
func _close_modal() -> void:
	if _modal_panel != null and is_instance_valid(_modal_panel):
		_modal_panel.visible = false
		_modal_panel.queue_free()
	_modal_panel = null


# ==================================================================
#  角色选择器（tscn CharPicker，两种模式：待命池 / 选队长）
# ==================================================================

func _setup_char_picker() -> void:
	char_picker.visible = false
	var close_btn = char_picker.get_node_or_null("Panel/Header/CloseBtn")
	if close_btn:
		close_btn.focus_mode = Control.FOCUS_NONE
		close_btn.pressed.connect(func(): _close_char_picker())


func _close_char_picker() -> void:
	char_picker.visible = false
	char_picker_mode = ""


## 打开角色选择器
##   mode "bench"    — 待命池（不属于任何队伍的角色），放置到 ctx 的 {r, c}
##   mode "captain"  — 全部角色，选择后创建新队伍
func _open_char_picker(mode: String, ctx: Dictionary = {}) -> void:
	char_picker_mode = mode
	char_picker_ctx = ctx
	char_picker.visible = true

	var title = char_picker.get_node_or_null("Panel/Header/Title")
	if mode == "bench":
		var team: Dictionary = team_manager.get_team(active_team_idx)
		title.text = "待命池 · 放置到 (%d,%d) · %s" % [ctx.r + 1, ctx.c + 1, team.get("name", "?")]
	else:
		title.text = "新增队伍 · 选择队长"

	var list = char_picker.get_node_or_null("Panel/ScrollContainer/CharList")
	if not list:
		return
	for child in list.get_children():
		child.queue_free()

	var assigned: Array = team_manager.get_all_assigned_char_ids()
	var all_ids: Array = DataManager.get_all_character_ids()

	# 待命池 = 所有角色 - 已编入角色
	if mode == "bench":
		all_ids = all_ids.filter(func(cid): return cid not in assigned)
		if all_ids.is_empty():
			var hint := Label.new()
			hint.text = "所有单位已在本队中，待命池为空。"
			hint.add_theme_color_override("font_color", UITheme.INK_DIM)
			hint.add_theme_font_size_override("font_size", 11)
			list.add_child(hint)
			return

	for cid in all_ids:
		var ch := DataManager.get_character(cid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon := Label.new()
		icon.text = editor.char_icon(ch)
		icon.add_theme_font_override("font", UITheme.emoji_font)
		icon.add_theme_font_size_override("font_size", 20)
		row.add_child(icon)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		name_lbl.text = "%s  [%s]" % [ch.get("name_zh", "???"), ch.get("class_zh", "")]
		name_lbl.add_theme_color_override("font_color", UITheme.INK)
		name_lbl.add_theme_font_size_override("font_size", 13)
		info.add_child(name_lbl)
		var sub_lbl := Label.new()
		sub_lbl.text = ch.get("region", "") + " · " + ch.get("rarity", "")
		sub_lbl.add_theme_color_override("font_color", UITheme.INK_DIM)
		sub_lbl.add_theme_font_size_override("font_size", 10)
		info.add_child(sub_lbl)
		row.add_child(info)

		var cid_copy = cid  # 闭包陷阱
		if mode == "captain":
			var btn := Button.new()
			btn.text = "设为队长"
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
			btn.add_theme_font_size_override("font_size", 11)
			btn.pressed.connect(func(): _create_team_with_captain(cid_copy))
			row.add_child(btn)
		else:
			var btn := Button.new()
			btn.text = "＋ 放置"
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
			btn.add_theme_font_size_override("font_size", 11)
			btn.pressed.connect(func(): _place_bench_char(cid_copy))
			row.add_child(btn)

		list.add_child(row)


## 键盘 A 键：自动找第一个空格并打开待命池
func _open_bench_picker() -> void:
	var team: Dictionary = team_manager.get_team(active_team_idx)
	if team.is_empty():
		_show_toast("没有队伍，请先新建。", true)
		return
	var count := team_manager.get_team_unit_ids(active_team_idx).size()
	if count >= 9:
		_show_toast("棋盘已满（9/9），无法再放置单位。", true)
		return
	var empty_cell := Vector2i(-1, -1)
	for slot in range(9):
		if team.units[slot] == "":
			empty_cell = Vector2i(slot / 3, slot % 3)
			break
	if empty_cell == Vector2i(-1, -1):
		_show_toast("棋盘已满（9/9），无法再放置单位。", true)
		return
	_open_char_picker("bench", {"r": empty_cell.x, "c": empty_cell.y})


## 待命池放置：二次校验 → 从其他队移除 → 放置
func _place_bench_char(cid: String) -> void:
	var r: int = char_picker_ctx.get("r", -1)
	var c: int = char_picker_ctx.get("c", -1)
	if r < 0 or c < 0:
		_close_char_picker()
		return
	var team: Dictionary = team_manager.get_team(active_team_idx)
	if team_manager.get_team_unit_ids(active_team_idx).size() >= 9 or team.units[r * 3 + c] != "":
		_show_toast("放置失败：棋盘已满或该格已被占用。", true)
		_close_char_picker()
		return
	team_manager.remove_char_from_all_teams(cid)  # 确保单位唯一归属
	team_manager.set_unit(active_team_idx, r * 3 + c, cid)
	sel_unit_id = cid
	move_src_id = ""
	move_target = Vector2i(-1, -1)
	_close_char_picker()
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()


## 选队长创建新队伍 → 滚动到新队
func _create_team_with_captain(cid: String) -> void:
	team_manager.remove_char_from_all_teams(cid)
	var idx := team_manager.add_team_with_captain(cid)
	if idx < 0:
		_show_toast("已达队伍上限（8支）。", true)
		_close_char_picker()
		return
	var cap_name: String = DataManager.get_character(cid).get("name_zh", "")
	active_team_idx = idx
	sel_unit_id = cid
	_close_char_picker()
	reel.scroll_to(idx)
	_refresh_reel()
	_show_editor_unit()
	_update_act_lab()
	_show_toast("已新建队伍「%s」，队长：%s" % [team_manager.get_team(idx).get("name", "?"), cap_name])


# ==================================================================
#  Toast 提示
# ==================================================================

## 显示临时提示消息：显示 1.5 秒 → 2 秒淡出 → 销毁节点
func _show_toast(msg: String, is_err: bool = false) -> void:
	var toast := Label.new()
	toast.text = msg
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", UITheme.RED if is_err else UITheme.INK)
	toast.add_theme_font_size_override("font_size", 13)

	# 定位在屏幕底部居中
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
