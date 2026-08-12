extends Control
## =============================================================================
## MainScreen — 队伍编成主界面控制器
## =============================================================================
## 作用：管理整个队伍编成界面的交互逻辑。
##       包括棋盘(BoardGrid)、角色编辑器(UnitEditor)、角色选择器、
##       装备选择器等所有 UI 组件的协调。
##
## 界面布局：
##   +----------------------------------------------+
##   |  TopBar — 标题栏                              |
##   +----------+-----------------------------------+
##   | ZoneLeft | ZoneRight                         |
## |   | (队伍列表| (UnitEditor — 角色详情面板)       |
## |   | +操作按钮|   · 装备槽位                       |
## |   | +选择器) |   · 属性数值                       |
##   |          |   · 技能列表                       |
##   +----------+-----------------------------------+
##   |  HintBar — 操作提示                           |
##   +----------------------------------------------+
##
## 数据流概述：
##   TeamManager（数据层）↔ MainScreen（控制器）↔ BoardGrid/UnitEditor（视图）
##
##   MainScreen 持有 equipment_data 字典：
##     {char_id: {"weapon": eq_id, "shield": eq_id, ...}}
##   装备数据不和角色数据混在一起，而是独立维护，方便跨队伍共享装备。
## =============================================================================

# 预加载类 — 类似于 Python 的 import
# preload() 在脚本解析时执行（编译期），返回的是 PackedScene 或 GDScript 类引用
# const 确保这些引用不会被意外修改
const TeamManagerClass = preload("res://scripts/main/team_manager.gd")
const BoardGridClass = preload("res://scripts/main/board_grid.gd")

# ------------------------------------------------------------------ @onready 节点引用
# $ 语法 — 等价于 get_node() 的简写，路径以 / 分隔
# 例如 $MainLayout/ZoneLeft 等价于 get_node("MainLayout/ZoneLeft")
#
# 注意：$ 路径是相对于当前节点的。如果当前节点是场景根节点，
# 那么 $TopBar 就是场景根下的 TopBar 子节点。

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

# ------------------------------------------------------------------ 运行时状态

## TeamManager 实例 — 队伍数据管理者（非 Autoload，手动创建）
var team_manager  # TeamManager 实例

## 当前选中的队伍索引（对应左边高亮的棋盘）
var active_board_index: int = 0

## 所有 BoardGrid 控件实例
var boards: Array = []  # Array[BoardGrid]

## 角色选择器打开时的目标槽位信息
var selecting_slot: int = -1    # 正在选择放置到哪个槽位
var selecting_team: int = -1    # 正在选择放置到哪支队伍

## ---------------------------------------------------------------------------
## 装备数据 — 核心状态
## ---------------------------------------------------------------------------
## 结构：{char_id: {slot_key: eq_id}}
##
## 例如：
##   {
##     "lord_01": {"weapon": "eq_sword_legend_01", "shield": "eq_shield_03"},
##     "mage_05": {"weapon": "eq_staff_02", "acc1": "eq_acc_07"}
##   }
##
## 为什么装备数据存在 MainScreen 而不是 TeamManager 或角色的 JSON 中？
##   1. JSON 数据是静态的"图鉴"，角色的基础属性
##   2. 装备是玩家在游戏中获取的动态资源，需要独立存储
##   3. 放在 MainScreen 中方便装备选择器和 UnitEditor 之间传递数据
## ---------------------------------------------------------------------------
var equipment_data: Dictionary = {}

## 装备选择器打开的上下文：哪个角色的哪个槽位正在等待选择装备
var equip_pending_slot: String = ""   # "weapon" / "shield" / "acc1" / "acc2"
var equip_pending_char: String = ""   # 角色ID


# ==================================================================
#  _ready() — 初始化
# ==================================================================

func _ready() -> void:
	# --- 创建 TeamManager 实例 ---
	team_manager = TeamManagerClass.new()
	add_child(team_manager)
	# 连接信号：队伍数据变更 -> 重建棋盘
	team_manager.team_changed.connect(_on_team_changed)

	# 如果 DataManager 中有保存的队伍数据，恢复到 TeamManager
	if DataManager.saved_teams.size() > 0:
		team_manager.teams = DataManager.saved_teams.duplicate(true)
		print("[MainScreen] 已恢复 %d 支队伍数据" % team_manager.teams.size())
		DataManager.saved_teams.clear()  # 清除备份，避免重复恢复

	# --- 设置顶部标题栏样式 ---
	top_bar.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	top_bar.add_theme_font_size_override("font_size", 14)

	# --- 设置状态栏样式 ---
	act_lab.add_theme_color_override("font_color", UITheme.INK_DIM)
	act_lab.add_theme_font_size_override("font_size", 11)

	# --- 设置底部提示栏 ---
	hint_bar.add_theme_color_override("font_color", UITheme.INK_DIM)
	hint_bar.add_theme_font_size_override("font_size", 11)
	hint_bar.text = "点击棋盘空格放置单位 · 点击已放置单位查看/编辑 · 右键移除单位 · 点击任意队伍的角色切换出战队伍"

	# --- 设置按钮样式 ---
	# Godot 中按钮样式通过 StyleBox 实现，而不是 CSS
	# begin_bulk_theme_override() / end_bulk_theme_override() 是一对优化：
	#   多个主题覆盖在二者之间批量应用，引擎只在 end 后重新计算一次布局
	_style_btn(btn_new_team, "+ 新增队伍")
	_style_btn(btn_disband, "解散队伍")
	_style_battle_btn(btn_battle, "▶ 开始战斗")

	# --- 连接按钮信号 ---
	# pressed 信号在按钮被点击并释放时发出（不是按下时）
	btn_new_team.pressed.connect(_on_new_team)
	btn_disband.pressed.connect(_on_disband_team)
	btn_battle.pressed.connect(_on_start_battle)

	# --- 连接编辑器的装备槽点击信号 ---
	editor.equip_slot_clicked.connect(_on_equip_slot_clicked)

	# --- 构建初始棋盘 ---
	_rebuild_boards()

	# --- 初始化选择器 ---
	_setup_char_picker()   # 角色选择器（在 .tscn 中预定义）
	_setup_equip_picker()  # 装备选择器（完全在代码中动态创建）


# ==================================================================
#  按钮样式工具
# ==================================================================

## 常规按钮样式 — 深色背景+浅色文字
func _style_btn(btn: Button, text: String) -> void:
	btn.text = text
	btn.add_theme_color_override("font_color", UITheme.INK)
	btn.add_theme_font_size_override("font_size", 12)
	btn.begin_bulk_theme_override()
	btn.add_theme_stylebox_override("normal", UITheme.default_button_style())
	btn.end_bulk_theme_override()


## 战斗按钮样式 — 金色背景+深色文字（突出显示，最重要的操作按钮）
func _style_battle_btn(btn: Button, text: String) -> void:
	btn.text = text
	btn.add_theme_color_override("font_color", Color("2c1c0e"))  # 深棕色文字
	btn.add_theme_font_size_override("font_size", 13)
	btn.begin_bulk_theme_override()
	btn.add_theme_stylebox_override("normal", UITheme.gold_button_style())
	btn.end_bulk_theme_override()


# ==================================================================
#  棋盘管理 (Board Management)
# ==================================================================

## ---------------------------------------------------------------------------
## _rebuild_boards() — 完全重建所有棋盘控件
## ---------------------------------------------------------------------------
## 当队伍数量变化时调用。销毁所有旧 BoardGrid，根据 teams 数据创建新的。
## 每个棋盘连接 slot_clicked 和 slot_right_clicked 信号以处理交互。
## ---------------------------------------------------------------------------
func _rebuild_boards() -> void:
	# 先销毁旧棋盘（queue_free 在帧末安全释放）
	for b in boards:
		b.queue_free()
	boards.clear()

	# 为每支队伍创建一个 BoardGrid
	for i in range(team_manager.teams.size()):
		var board := BoardGridClass.new()
		board.team_index = i
		board.is_active = (i == active_board_index)
		# refresh() 传入队伍数据，初始化图标/名称缓存
		board.refresh(i, team_manager.teams[i].units, board.is_active)
		# 连接信号：点击/右键格子 -> MainScreen 处理
		board.slot_clicked.connect(_on_board_slot_clicked)
		board.slot_right_clicked.connect(_on_board_slot_right_clicked)
		board_container.add_child(board)
		boards.append(board)

	# 确保有队伍被选中
	if boards.size() > 0:
		select_board(active_board_index)

	_update_act_lab()
	_update_top_bar()


## ---------------------------------------------------------------------------
## select_board() — 切换当前选中的队伍
## ---------------------------------------------------------------------------
## 更新所有棋盘的 is_active 状态，触发重绘以更新高亮。
## ---------------------------------------------------------------------------
func select_board(idx: int) -> void:
	if idx < 0 or idx >= boards.size():
		return
	active_board_index = idx
	# 更新所有棋盘的活跃状态
	for i in range(boards.size()):
		boards[i].is_active = (i == idx)
		boards[i].refresh(i, team_manager.teams[i].units, boards[i].is_active)
	_update_act_lab()
	_update_top_bar()


## 更新操作栏文字，显示"第X队 · N/6 单位"
func _update_act_lab() -> void:
	var team = team_manager.get_team(active_board_index)
	var count := 0
	for uid in team.units:
		if uid != "":
			count += 1
	act_lab.text = "第%d队 · %d/6 单位" % [active_board_index + 1, count]


func _update_top_bar() -> void:
	# 顶部标题栏显示当前出战队伍
	var team = team_manager.get_team(active_board_index)
	var count := 0
	for uid in team.units:
		if uid != "":
			count += 1
	top_bar.text = "圣兽之王 · 编队战斗  [%s · %d/6人]" % [team.name, count]


## 队伍数据变更回调 -> 重建所有棋盘
func _on_team_changed(_idx: int) -> void:
	_rebuild_boards()
	_update_top_bar()


# ==================================================================
#  棋盘交互处理
# ==================================================================

## ---------------------------------------------------------------------------
## _on_board_slot_clicked() — 左键点击棋盘格子
## ---------------------------------------------------------------------------
## 两种情况：
##   1. 空格子（uid==""）-> 打开角色选择器，让玩家选择一个角色放置
##   2. 已放置角色 -> 在右侧 UnitEditor 中显示该角色的详情
##
## selecting_slot / selecting_team 记录角色选择器的目标位置，
## 当玩家在角色选择器中点击"选择"按钮后，team_manager.set_unit() 完成放置。
## ---------------------------------------------------------------------------
func _on_board_slot_clicked(slot: int, board) -> void:
	var uid = team_manager.get_unit_at(board.team_index, slot)

	if uid == "":
		# 空格子 — 打开角色选择器
		selecting_slot = slot
		selecting_team = board.team_index
		_open_char_picker()
	else:
		# 已放置 — 在编辑器中显示角色详情（含装备）
		var eq = equipment_data.get(uid, {})
		editor.show_unit(uid, board.team_index, slot, eq)
		active_board_index = board.team_index
		_rebuild_boards()


## ---------------------------------------------------------------------------
## _on_board_slot_right_clicked() — 右键点击棋盘格子 -> 移除角色
## ---------------------------------------------------------------------------
func _on_board_slot_right_clicked(slot: int, board) -> void:
	var uid = team_manager.get_unit_at(board.team_index, slot)
	if uid != "":
		team_manager.remove_unit(board.team_index, slot)
		# 同时清理装备数据
		equipment_data.erase(uid)
		editor.clear()


# ==================================================================
#  装备系统 (Equipment System)
# ==================================================================

## ---------------------------------------------------------------------------
## _on_equip_slot_clicked() — 玩家点击了 UnitEditor 中的装备槽
## ---------------------------------------------------------------------------
## 记录上下文信息，然后打开装备选择器弹窗。
## ---------------------------------------------------------------------------
func _on_equip_slot_clicked(char_id: String, slot_key: String) -> void:
	equip_pending_char = char_id
	equip_pending_slot = slot_key
	_open_equip_picker()


## ---------------------------------------------------------------------------
## _setup_equip_picker() — 动态创建装备选择器弹窗
## ---------------------------------------------------------------------------
## 这个弹窗完全由代码创建（不像角色选择器在 .tscn 场景文件中定义）。
## 创建流程：PanelContainer -> VBox -> [标题栏, 筛选行, 装备列表]
##
## Godot 的 UI 创建方式有两种：
##   1. 在 .tscn 场景文件中可视化编辑（所见即所得）
##   2. 纯代码动态创建（如本方法）
##
## 纯代码创建更灵活，但代码量大。适合动态内容（如列表项数量不固定的场景）。
##
## 控件树结构：
##   PanelContainer (EquipPicker)
##   +-- VBoxContainer (VBox)
##       +-- HBoxContainer (Header)
##       |   +-- Label "选择装备"
##       |   +-- Button "✕" (关闭)
## |       +-- HBoxContainer (FilterRow)
##       |   +-- Label "类型:"
##       |   +-- OptionButton (筛选下拉：全部/剑/斧/枪/弓/杖/盾)
##       |   +-- Button "卸下装备"
##       +-- ScrollContainer
##           +-- VBoxContainer (EqList) — 装备行动态填充
## ---------------------------------------------------------------------------
func _setup_equip_picker() -> void:
	var equip_picker := PanelContainer.new()
	equip_picker.name = "EquipPicker"
	equip_picker.visible = false  # 初始隐藏，需要时才显示

	# --- 设置弹窗位置和大小 ---
	# set_anchors_preset(PRESET_CENTER) — 将控件锚定到父容器的中心
	# offset_left/right/top/bottom 定义控件相对于锚点的偏移
	# 这里：居中显示，尺寸约 560x500 像素
	equip_picker.set_anchors_preset(Control.PRESET_CENTER)
	equip_picker.offset_left = -280
	equip_picker.offset_top = -250
	equip_picker.offset_right = 280
	equip_picker.offset_bottom = 250

	# --- 设置面板背景样式 ---
	# 半透明深色背景 + 金色边框，营造中世纪对话框风格
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.114, 0.094, 0.078, 0.95)  # RGBA，0.95 不透明度
	sb.border_width_left = 2; sb.border_width_right = 2
	sb.border_width_top = 2; sb.border_width_bottom = 2
	sb.border_color = UITheme.GOLD
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10; sb.corner_radius_bottom_right = 10
	equip_picker.add_theme_stylebox_override("panel", sb)

	# --- 创建内部布局 ---
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	equip_picker.add_child(vbox)

	# --- 标题栏 ---
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "选择装备"
	title.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 占满水平空间
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	# 点击关闭按钮 -> 隐藏弹窗
	# func(): 是 GDScript 的匿名函数(lambda)语法
	close_btn.pressed.connect(func(): equip_picker.visible = false)
	header.add_child(close_btn)
	vbox.add_child(header)

	# --- 筛选行 ---
	var filter_row := HBoxContainer.new()
	filter_row.name = "FilterRow"
	filter_row.add_theme_constant_override("separation", 8)

	var filter_label := Label.new()
	filter_label.text = "类型:"
	filter_label.add_theme_color_override("font_color", UITheme.INK_DIM)
	filter_label.add_theme_font_size_override("font_size", 11)
	filter_row.add_child(filter_label)

	# OptionButton — Godot 的下拉选择框
	var filter_opt := OptionButton.new()
	filter_opt.name = "FilterOpt"
	filter_opt.add_item("全部", 0)
	filter_opt.add_item("剑 sword", 1); filter_opt.add_item("斧 axe", 2)
	filter_opt.add_item("枪 spear", 3); filter_opt.add_item("弓 bow", 4)
	filter_opt.add_item("杖 staff", 5); filter_opt.add_item("盾 shield", 6)
	# .item_selected.connect(func(idx): ...) — 选择变更时刷新列表
	filter_opt.item_selected.connect(func(idx): _refresh_equip_list(equip_picker))
	filter_row.add_child(filter_opt)

	# --- 卸下装备按钮 ---
	var unequip_btn := Button.new()
	unequip_btn.text = "卸下装备"
	unequip_btn.add_theme_color_override("font_color", UITheme.RED)
	unequip_btn.add_theme_font_size_override("font_size", 11)
	unequip_btn.pressed.connect(func():
		if equip_pending_char != "":
			if not equipment_data.has(equip_pending_char):
				equipment_data[equip_pending_char] = {}
			# .erase() 删除字典中的指定键
			equipment_data[equip_pending_char].erase(equip_pending_slot)
			# 通知编辑器更新显示
			editor.equip_item(equip_pending_slot, "")
			equip_picker.visible = false
	)
	filter_row.add_child(unequip_btn)
	vbox.add_child(filter_row)

	# --- 可滚动装备列表 ---
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL  # 垂直方向填满剩余空间
	var list := VBoxContainer.new()
	list.name = "EqList"
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	vbox.add_child(scroll)

	# 将装备选择器添加到 Overlay 层（覆盖在棋盘上方）
	var overlay = $MainLayout/ZoneLeft/Overlay
	overlay.add_child(equip_picker)


## 打开装备选择器并刷新列表
func _open_equip_picker() -> void:
	var equip_picker = $MainLayout/ZoneLeft/Overlay/EquipPicker
	equip_picker.visible = true
	_refresh_equip_list(equip_picker)


## ---------------------------------------------------------------------------
## _refresh_equip_list() — 刷新装备选择器中的装备列表
## ---------------------------------------------------------------------------
## 根据筛选下拉框的选中值过滤装备，按稀有度和攻击力排序显示。
##
## 排序逻辑：
##   1. 稀有度优先（传说 > 史诗 > 稀有 > 罕见 > 普通）
##   2. 同等稀有度下按攻击力/魔力从高到低
##
## .sort_custom(func(a, b): ...) — 自定义排序
##   回调函数返回 true 表示 a 应该排在 b 前面。
##   类似于 Python 的 list.sort(key=...) 但用的是比较函数而非 key 函数。
## ---------------------------------------------------------------------------
func _refresh_equip_list(equip_picker: PanelContainer) -> void:
	# 清空旧列表
	var list = equip_picker.get_node("VBox/ScrollContainer/EqList")
	for child in list.get_children():
		child.queue_free()

	# 读取筛选条件
	var filter_opt: OptionButton = equip_picker.get_node("VBox/FilterRow/FilterOpt")
	var filter_idx = filter_opt.selected
	var subtype_names := ["", "sword", "axe", "spear", "bow", "staff", "shield"]
	var filter_subtype = subtype_names[filter_idx] if filter_idx < subtype_names.size() else ""

	# 筛选装备
	var all_eq = DataManager.get_all_equipment_ids()
	var filtered: Array = []
	for eq_id in all_eq:
		var eq = DataManager.get_equipment(eq_id)
		var st = eq.get("subtype", "")
		if filter_subtype == "" or st == filter_subtype:
			filtered.append(eq_id)

	# 排序：稀有度优先 -> 攻击力优先
	filtered.sort_custom(func(a, b):
		var ea = DataManager.get_equipment(a); var eb = DataManager.get_equipment(b)
		var ra = ea.get("rarity", "common"); var rb = eb.get("rarity", "common")
		var rarity_order = {"legendary":0, "epic":1, "rare":2, "uncommon":3, "common":4}
		# 比较稀有度（数字越小的越靠前）
		var ro = rarity_order.get(ra, 5) - rarity_order.get(rb, 5)
		if ro != 0:
			return ro < 0  # 返回 true 表示 a 排在 b 前面
		# 同等稀有度，比较攻击力
		var sa = ea.get("stats", {}); var sb = eb.get("stats", {})
		return sa.get("atk", sa.get("mag", 0)) > sb.get("atk", sb.get("mag", 0))
	)

	# 构建列表项（最多 80 条，防止性能问题）
	var count := 0
	for eq_id in filtered:
		if count >= 80:
			break
		var eq = DataManager.get_equipment(eq_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var eq_name = eq.get("name_zh", eq.get("name_en", "???"))
		var rarity = eq.get("rarity", "common")
		var stats = eq.get("stats", {})

		# 装备信息标签：名称 + 稀有度 + 属性
		var info := Label.new()
		var stat_str := ""
		for k in stats:
			stat_str += "%s+%d " % [k, stats[k]]
		info.text = "%s  [%s]  %s" % [eq_name, rarity, stat_str]
		# 文字颜色 = 稀有度对应颜色
		info.add_theme_color_override("font_color", UITheme.rarity_color(rarity))
		info.add_theme_font_size_override("font_size", 12)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		# "装备"按钮 — 点击即装备
		var sel_btn := Button.new()
		sel_btn.text = "装备"
		sel_btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		sel_btn.add_theme_font_size_override("font_size", 11)
		# 注意：必须把 eq_id 复制到局部变量，因为 GDScript 的闭包
		# 捕获的是变量引用而非值。如果直接用 eq_id，所有按钮都会
		# 使用循环结束后的最后一个 eq_id（经典的闭包陷阱，和 Python 一样！）
		var eq_id_copy = eq_id
		sel_btn.pressed.connect(func():
			if equip_pending_char != "":
				if not equipment_data.has(equip_pending_char):
					equipment_data[equip_pending_char] = {}
				equipment_data[equip_pending_char][equip_pending_slot] = eq_id_copy
				# 通知编辑器更新显示
				editor.equip_item(equip_pending_slot, eq_id_copy)
				equip_picker.visible = false
		)
		row.add_child(sel_btn)
		list.add_child(row)
		count += 1


# ==================================================================
#  按钮回调
# ==================================================================

func _on_new_team() -> void:
	team_manager.add_team()
	# 新队伍自动设为活跃队伍
	active_board_index = team_manager.teams.size() - 1


func _on_disband_team() -> void:
	# 至少保留1支队伍
	if team_manager.teams.size() > 1:
		team_manager.remove_team(active_board_index)


## ---------------------------------------------------------------------------
## _on_start_battle() — "开始战斗"按钮回调
## ---------------------------------------------------------------------------
## 流程：
##   1. 校验：确保当前活跃队伍有至少一个角色
##   2. 重置 BattleManager（清空上次战斗数据）
##   3. 调用 start_battle() 初始化战斗状态
##   4. 切换到战斗场景（change_scene_to_file）
##
## GDScript 场景切换说明：
##   get_tree().change_scene_to_file("res://scenes/battle.tscn")
##   这会卸载当前场景（main.tscn），加载并显示战斗场景。
##   当前场景的所有节点（包括 MainScreen 和 TeamManager）都会被销毁。
##   只有 Autoload 节点（BattleManager、DataManager、UITheme）会保留。
## ---------------------------------------------------------------------------
func _on_start_battle() -> void:
	if not team_manager.has_any_units():
		_show_toast("请先在队伍中放置至少一个单位！")
		return

	var active_team_ids = team_manager.get_team_unit_ids(active_board_index)
	if active_team_ids.is_empty():
		_show_toast("当前队伍为空，请先放置单位！")
		return

	# 保存队伍数据到 DataManager（切换场景后恢复编队）
	DataManager.saved_teams = team_manager.teams.duplicate(true)

	# 重置战斗管理器状态
	BattleManager.reset()
	# 初始化战斗：传入玩家队伍的角色ID列表，敌方自动随机生成
	BattleManager.start_battle(active_team_ids)
	# 切换场景到战斗画面
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


# ==================================================================
#  角色选择器 (Character Picker)
# ==================================================================

## ---------------------------------------------------------------------------
## _setup_char_picker() — 初始化角色选择器
## ---------------------------------------------------------------------------
## 角色选择器在 main.tscn 场景文件中预定义（CharPicker 节点），
## 这里只做信号连接。关闭按钮点击时隐藏弹窗。
## ---------------------------------------------------------------------------
func _setup_char_picker() -> void:
	char_picker.visible = false
	var close_btn = char_picker.get_node_or_null("Panel/Header/CloseBtn")
	if close_btn:
		close_btn.pressed.connect(func(): char_picker.visible = false)


## ---------------------------------------------------------------------------
## _open_char_picker() — 打开角色选择器并填充角色列表
## ---------------------------------------------------------------------------
## 流程：
##   1. 显示弹窗
##   2. 清空旧列表项
##   3. 获取所有已编入队伍的角色ID（assigned）
##   4. 遍历所有角色，为每个角色创建一行
##      - 已编入其他队伍的角色显示"已编入"标记（不可选）
##      - 当前槽位原有的角色可以重新选择（cid in assigned 但是是当前槽位的角色）
##      - 未编入的角色显示"选择"按钮
## ---------------------------------------------------------------------------
func _open_char_picker() -> void:
	char_picker.visible = true
	var list = char_picker.get_node_or_null("Panel/ScrollContainer/CharList")
	if not list:
		return

	# 清空旧内容
	for child in list.get_children():
		child.queue_free()

	# 获取所有已编入队伍的角色ID（用于标记"已编入"）
	var assigned = team_manager.get_all_assigned_char_ids()
	var all_ids = DataManager.get_all_character_ids()

	for cid in all_ids:
		var ch = DataManager.get_character(cid)
		# 判断该角色是否已被编入（但允许同一角色在当前槽位被重新选择）
		var in_use = cid in assigned and cid != team_manager.get_unit_at(selecting_team, selecting_slot)

		# --- 创建一行：图标 + 信息 + 操作按钮 ---
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		# 角色图标（emoji）
		var icon := Label.new()
		icon.text = _char_icon(ch)
		icon.add_theme_font_size_override("font_size", 20)
		row.add_child(icon)

		# 角色信息：名称 + 职业 / 地区 + 稀有度
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

		# 弹性间距（把按钮推到右边）
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		# 状态/操作
		if in_use:
			# 已被其他队伍使用 -> 显示"已编入"标记
			var used := Label.new()
			used.text = "已编入"
			used.add_theme_color_override("font_color", UITheme.RED)
			used.add_theme_font_size_override("font_size", 11)
			row.add_child(used)
		else:
			# 空闲角色 -> 显示"选择"按钮
			var sel_btn := Button.new()
			sel_btn.text = "选择"
			sel_btn.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
			sel_btn.add_theme_font_size_override("font_size", 11)
			var cid_copy = cid  # 闭包陷阱！必须复制到局部变量
			sel_btn.pressed.connect(func():
				# 将选中的角色放置到目标槽位
				team_manager.set_unit(selecting_team, selecting_slot, cid_copy)
				char_picker.visible = false
				# 在编辑器中显示新增的角色
				editor.show_unit(cid_copy, selecting_team, selecting_slot)
			)
			row.add_child(sel_btn)

		list.add_child(row)


## 角色职业->emoji图标映射
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


# ==================================================================
#  Toast 提示
# ==================================================================

## ---------------------------------------------------------------------------
## _show_toast() — 显示临时提示消息
## ---------------------------------------------------------------------------
## 创建一个 Label，显示在屏幕底部，1.5秒后开始淡出，淡出结束后自动销毁。
##
## Tween（补间动画）说明：
##   Tween 是 Godot 的动画系统，可以对任何属性做平滑过渡。
##   create_tween() 创建 Tween 实例。
##   tween_property(obj, "property", final_value, duration) — 在 duration 秒内
##     将 obj.property 平滑过渡到 final_value。
##   .set_delay(n) — 延迟 n 秒后开始这个动画。
##   tween_callback(fn) — 动画序列中插入回调函数调用。
##
##   这里：显示 1.5 秒 -> 透明度在 2 秒内从 1 渐变到 0 -> 销毁节点
##
## modulate:a 说明：
##   modulate 是 CanvasItem 的颜色调制属性。
##   modulate:a 访问其 alpha（透明度）通道。
##   类似于 CSS 的 opacity，但可以分别访问 RGBA 四个通道。
## ---------------------------------------------------------------------------
func _show_toast(msg: String) -> void:
	var toast := Label.new()
	toast.text = msg
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", UITheme.INK)
	toast.add_theme_font_size_override("font_size", 13)

	# 定位在屏幕底部居中
	# anchor_left/right = 0.5 表示锚点在父容器水平中心
	# anchor_bottom = 1.0 表示锚点在父容器底部
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_bottom = 1.0
	toast.offset_left = -200
	toast.offset_right = 200
	toast.offset_bottom = -50
	add_child(toast)

	# 创建淡出动画
	var tween := create_tween()
	# 1.5秒后开始，2秒内透明度从当前值渐变到0
	tween.tween_property(toast, "modulate:a", 0.0, 2.0).set_delay(1.5)
	# 动画结束后销毁节点
	tween.tween_callback(toast.queue_free)
