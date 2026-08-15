extends Control
## =============================================================================
## UnitEditor — 右侧单位详情面板（对齐网页版布局）
## =============================================================================
## 作用：显示选中角色的装备槽位卡片、属性数值和行动策略。
##       玩家可以点击装备槽/策略格，弹出覆盖在左侧的选择弹窗。
##
## 布局结构（从上到下，对标网页版右半区）：
##   Header      — 角色头像图标、名称、职业/地区
##   TopRow      — 装备面板(4槽卡片) | 属性面板(8项2列)
##   StratPanel  — 行动策略面板：[技能 | 条件1 | 条件2] 行，最多 8 行
##
## 数据流：
##   UnitEditor 发出信号（equip_slot_clicked / strategy_*_clicked / row_delete）
##   → main_screen 弹出对应选择器
##   → 玩家选择后 main_screen 更新数据并整体重渲（show_unit）
##
## 装备/策略数据由 main_screen 维护（equipment_data / strategy_data），
## UnitEditor 只保存副本用于显示，是纯视图。
## =============================================================================

class_name UnitEditor

# ------------------------------------------------------------------ 当前查看的角色
var current_char_id: String = ""   # 角色ID
var current_team_idx: int = -1     # 所在队伍索引
var current_slot: int = -1         # 所在槽位索引

# ------------------------------------------------------------------ 显示状态（main_screen 传入的副本）
var equipped: Dictionary = {}   # {"weapon": eq_id, "shield": eq_id, ...}
var strat: Array = []           # [{skill: "", cond1: "", cond2: ""}, ...]

# ------------------------------------------------------------------ @onready 节点引用
@onready var ed_head_icon: Label = $Header/Icon       # 角色图标（emoji）
@onready var ed_head_name: Label = $Header/VBox/Name  # 角色名
@onready var ed_head_sub: Label = $Header/VBox/Sub    # 职业/地区

# 槽位定义缓存（_ready 时构建一次；kind/icon/name/rank 子 Label 引用挂在同一批字典上）
var _slots: Array = []

@onready var equip_panel: VBoxContainer = $TopRow/EquipPanel
@onready var weapon_slot: Button = $TopRow/EquipPanel/WeaponSlot
@onready var shield_slot: Button = $TopRow/EquipPanel/ShieldSlot
@onready var acc1_slot: Button = $TopRow/EquipPanel/Acc1Slot
@onready var acc2_slot: Button = $TopRow/EquipPanel/Acc2Slot

@onready var stat_grid: GridContainer = $TopRow/StatsPanel/StatGrid
@onready var strat_list: VBoxContainer = $StratPanel/ScrollContainer/StratList

# ------------------------------------------------------------------ 信号
## 玩家点击装备槽时发出（main_screen 弹出装备选择器）
signal equip_slot_clicked(char_id: String, slot_key: String)
## 点击策略行的技能格：row_idx=-1 + is_new=true 表示"新增一行"
signal strategy_skill_clicked(char_id: String, row_idx: int, is_new: bool)
## 点击策略行的条件格（field = "cond1"/"cond2"）
signal strategy_cond_clicked(char_id: String, row_idx: int, field: String)
## 点击策略行的删除按钮
signal strategy_row_delete(char_id: String, row_idx: int)


func _ready() -> void:
	# 头部图标是 emoji，主题字体不含 emoji 字形，需要专用字体
	ed_head_icon.add_theme_font_override("font", UITheme.emoji_font)
	# 槽位定义只构建一次（_slot_defs() 返回该缓存，供 _build/_refresh/clear 共用）
	_slots = [
		{"key": "weapon", "btn": weapon_slot, "kind_label": "⚔️ 武器"},
		{"key": "shield", "btn": shield_slot, "kind_label": "🛡️ 盾牌"},
		{"key": "acc1",   "btn": acc1_slot,   "kind_label": "💍 饰品1"},
		{"key": "acc2",   "btn": acc2_slot,   "kind_label": "💍 饰品2"},
	]
	_build_equip_slots()
	# 策略面板表头行（只建一次）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(_strat_head_cell("技能名", 2.2))
	head.add_child(_strat_head_cell("条件 1", 1.4))
	head.add_child(_strat_head_cell("条件 2", 1.4))
	head.add_child(_fixed_spacer(24))
	strat_list.add_child(head)


## ---------------------------------------------------------------------------
## show_unit() — 显示角色详情（main_screen 调用）
## ---------------------------------------------------------------------------
func show_unit(char_id: String, team_idx: int, slot: int, equip_data: Dictionary = {}, strat_data: Array = []) -> void:
	current_char_id = char_id
	current_team_idx = team_idx
	current_slot = slot
	equipped = equip_data.duplicate()  # 浅拷贝，类似 Python 的 dict.copy()
	strat.clear()
	for row in strat_data:
		strat.append(row.duplicate())

	var ch = DataManager.get_character(char_id)
	if ch.is_empty():
		clear()
		return

	# 更新头部信息
	ed_head_icon.text = char_icon(ch)
	ed_head_name.text = ch.get("name_zh", "???")
	ed_head_sub.text = ch.get("class_zh", "") + " · " + ch.get("region", "")

	_refresh_equipment()  # 刷新装备槽卡片
	_refresh_stats(ch)    # 刷新属性数值（含装备加成）
	_refresh_strategy()   # 刷新行动策略行


## 清空面板显示（无角色选中时）
func clear() -> void:
	current_char_id = ""
	equipped.clear()
	strat.clear()
	ed_head_icon.text = "—"
	ed_head_name.text = "尚未选择单位"
	ed_head_sub.text = "—"
	for sd in _slot_defs():
		sd.kind.text = sd.kind_label.split(" ")[1]
		sd.icon.text = "+"
		sd.icon.add_theme_color_override("font_color", Color("5a4a30"))
		sd.name.text = "空 槽 位"
		sd.name.add_theme_color_override("font_color", UITheme.INK_DIM)
		sd.rank.text = ""
		sd.btn.tooltip_text = ""
		sd.btn.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		sd.btn.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		sd.btn.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
	_refresh_strategy()


## ---------------------------------------------------------------------------
## equip_item() — 更新装备（main_screen 在玩家选择装备后调用）
## ---------------------------------------------------------------------------
func equip_item(slot_key: String, eq_id: String) -> void:
	if eq_id == "":
		equipped.erase(slot_key)  # .erase() 删除字典中的键
	else:
		equipped[slot_key] = eq_id
	_refresh_equipment()
	var ch = DataManager.get_character(current_char_id)
	if not ch.is_empty():
		_refresh_stats(ch)


# ==================================================================
#  装备槽卡片
# ==================================================================

## 槽位定义缓存（_ready 构建）：key、按钮、显示标签、卡片内的子 Label 引用
func _slot_defs() -> Array:
	return _slots


## 为 4 个槽按钮填充卡片子控件（VBox：种类行 + 图标 + 名称 + 品阶）
func _build_equip_slots() -> void:
	for sd in _slot_defs():
		var btn: Button = sd.btn
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE  # 防止按键被按钮吃掉
		btn.custom_minimum_size = Vector2(0, 64)
		btn.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		btn.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		btn.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())

		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 0)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(vbox)

		# 种类行拆成 emoji + 文字两个 Label（混排无法用单一字体渲染）
		var kind_row := HBoxContainer.new()
		kind_row.alignment = BoxContainer.ALIGNMENT_CENTER
		kind_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kind_icon := Label.new()
		kind_icon.text = sd.kind_label.split(" ")[0]
		kind_icon.add_theme_font_override("font", UITheme.emoji_font)
		kind_icon.add_theme_font_size_override("font_size", 10)
		kind_row.add_child(kind_icon)
		var kind := Label.new()
		kind.text = sd.kind_label.split(" ")[1]
		kind.add_theme_color_override("font_color", UITheme.INK_DIM)
		kind.add_theme_font_size_override("font_size", 10)
		kind_row.add_child(kind)
		vbox.add_child(kind_row)

		var icon := Label.new()
		icon.text = "+"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_theme_color_override("font_color", Color("5a4a30"))
		icon.add_theme_font_size_override("font_size", 26)
		vbox.add_child(icon)

		var nm := Label.new()
		nm.text = "空 槽 位"
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_color_override("font_color", UITheme.INK_DIM)
		nm.add_theme_font_size_override("font_size", 11)
		vbox.add_child(nm)

		var rank := Label.new()
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank.add_theme_color_override("font_color", UITheme.GOLD)
		rank.add_theme_font_size_override("font_size", 9)
		vbox.add_child(rank)

		sd.kind = kind
		sd.icon = icon
		sd.name = nm
		sd.rank = rank
		var key: String = sd.key
		btn.pressed.connect(func(): _on_slot_pressed(key))


func _on_slot_pressed(slot_key: String) -> void:
	if current_char_id != "":
		equip_slot_clicked.emit(current_char_id, slot_key)


## 刷新 4 张装备槽卡片
func _refresh_equipment() -> void:
	for sd in _slot_defs():
		if equipped.has(sd.key):
			var eq = DataManager.get_equipment(equipped[sd.key])
			var rarity = eq.get("rarity", "common")
			sd.kind.text = sd.kind_label
			sd.icon.text = eq_icon(eq)
			sd.icon.add_theme_color_override("font_color", Color.WHITE)
			sd.name.text = eq.get("name_zh", "???")
			sd.name.add_theme_color_override("font_color", UITheme.rarity_color(rarity))
			sd.rank.text = "品阶 %s" % rarity
			sd.btn.tooltip_text = eq.get("description", eq.get("acquisition", ""))
			sd.btn.add_theme_stylebox_override("normal", UITheme.slot_filled_style())
			sd.btn.add_theme_stylebox_override("hover", UITheme.slot_filled_style())
			sd.btn.add_theme_stylebox_override("pressed", UITheme.slot_filled_style())
		else:
			sd.kind.text = sd.kind_label
			sd.icon.text = "+"
			sd.icon.add_theme_color_override("font_color", Color("5a4a30"))
			sd.name.text = "空 槽 位"
			sd.name.add_theme_color_override("font_color", UITheme.INK_DIM)
			sd.rank.text = ""
			sd.btn.tooltip_text = ""
			sd.btn.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
			sd.btn.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
			sd.btn.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())


## 装备图标：按 subtype 映射 emoji（装备数据无图标字段）
func eq_icon(eq: Dictionary) -> String:
	var st = eq.get("subtype", "")
	var icons := {
		"sword": "⚔️", "axe": "🪓", "spear": "🔱", "bow": "🏹", "staff": "🪄",
		"shield": "🛡️", "greatshield": "🛡️", "accessory": "💍",
	}
	return icons.get(st, "💍")


# ==================================================================
#  属性显示（8 项，含装备加成绿/红标注）
# ==================================================================

func _get_equipment_stat_bonuses() -> Dictionary:
	var bonuses := {}
	for eq_id in equipped.values():
		var eq = DataManager.get_equipment(eq_id)
		var st = eq.get("stats", {})
		for k in st:
			bonuses[k] = bonuses.get(k, 0) + st[k]
	return bonuses


func _refresh_stats(ch: Dictionary) -> void:
	for child in stat_grid.get_children():
		child.queue_free()

	var lv50 = ch.get("level_50_stats", {})
	var base = ch.get("base_stats", {})
	if lv50 == null:
		lv50 = {}  # 防御：JSON 中字段值为 null 时 .get() 返回 null 而非默认值
	if base == null:
		base = {}
	var bonuses = _get_equipment_stat_bonuses()

	var stat_defs := [
		{"name": "❤️ HP",   "base_key": "HP",              "eq_key": "hp"},
		{"name": "⚔️ 物攻", "base_key": "Physical Attack", "eq_key": "atk"},
		{"name": "🛡️ 物防", "base_key": "Physical Defense", "eq_key": "def"},
		{"name": "🔮 魔攻", "base_key": "Magic Attack",    "eq_key": "mag"},
		{"name": "✨ 魔防", "base_key": "Magic Defense",   "eq_key": "mdf"},
		{"name": "⚡ 先制", "base_key": "Initiative",      "eq_key": "spd"},
		{"name": "🎯 命中", "base_key": "Accuracy",        "eq_key": "acc"},
		{"name": "💨 回避", "base_key": "Evasion",         "eq_key": "eva"},
	]

	for sd in stat_defs:
		var base_val = lv50.get(sd.base_key, base.get(sd.eq_key, 0))
		if base_val == null:
			base_val = 0  # 防御：某些角色缺少该项属性数据
		var bonus = bonuses.get(sd.eq_key, 0)

		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = sd.name
		name_label.add_theme_color_override("font_color", UITheme.INK2)
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		row.add_child(_spacer())

		var val_label := Label.new()
		val_label.text = str(base_val + bonus)  # 总值（对齐网页版 attrTotals）
		val_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		val_label.add_theme_font_size_override("font_size", 13)
		row.add_child(val_label)

		if bonus != 0:
			var bonus_label := Label.new()
			bonus_label.text = " %+d" % bonus
			bonus_label.add_theme_color_override("font_color", UITheme.GREEN if bonus > 0 else UITheme.RED)
			bonus_label.add_theme_font_size_override("font_size", 10)
			row.add_child(bonus_label)

		stat_grid.add_child(row)


# ==================================================================
#  行动策略面板
# ==================================================================

## 表头单元格（Label + 拉伸比例）
func _strat_head_cell(text: String, ratio: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITheme.INK_DIM)
	l.add_theme_font_size_override("font_size", 10)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = ratio
	return l


func _fixed_spacer(w: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


## 重建策略行（每次 show_unit 调用，整体重建——数据量小，代价可忽略）
func _refresh_strategy() -> void:
	# 清空除表头外的所有行（表头是第一个子节点）
	var children := strat_list.get_children()
	for i in range(1, children.size()):
		children[i].queue_free()

	for i in range(strat.size()):
		var row_data: Dictionary = strat[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(_build_skill_cell(row_data, i))
		row.add_child(_build_cond_cell(row_data, i, "cond1"))
		row.add_child(_build_cond_cell(row_data, i, "cond2"))

		var del := Button.new()
		del.text = "×"
		del.focus_mode = Control.FOCUS_NONE
		del.custom_minimum_size = Vector2(24, 0)
		del.add_theme_color_override("font_color", UITheme.RED)
		del.add_theme_font_size_override("font_size", 10)
		var idx_copy = i  # 闭包陷阱！必须复制到局部变量
		del.pressed.connect(func(): strategy_row_delete.emit(current_char_id, idx_copy))
		row.add_child(del)
		strat_list.add_child(row)

	# 底部：新增行按钮 / 已满提示
	if strat.size() < 8:
		var add := Button.new()
		add.text = "＋ 新增技能（%d/8）" % strat.size()
		add.focus_mode = Control.FOCUS_NONE
		add.add_theme_color_override("font_color", UITheme.INK_DIM)
		add.add_theme_font_size_override("font_size", 11)
		add.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		add.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		add.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
		add.pressed.connect(func(): strategy_skill_clicked.emit(current_char_id, -1, true))
		strat_list.add_child(add)
	else:
		var full := Label.new()
		full.text = "已达上限 8 条策略。"
		full.add_theme_color_override("font_color", UITheme.INK_DIM)
		full.add_theme_font_size_override("font_size", 11)
		strat_list.add_child(full)


## 技能格按钮：满/空两种样式
func _build_skill_cell(row_data: Dictionary, idx: int) -> Button:
	var sk_id: String = row_data.get("skill", "")
	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_NONE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = 2.2
	cell.custom_minimum_size = Vector2(0, 44)
	if sk_id != "":
		var sk = DataManager.get_skill(sk_id)
		var type_icon := "🔴" if sk.get("type", "") == "active" else "🔵"
		cell.text = "%s %s\n%s" % [type_icon, sk.get("name_zh", "???"), sk.get("description_zh", "")]
		cell.add_theme_color_override("font_color", UITheme.INK)
		cell.add_theme_font_size_override("font_size", 12)
		cell.add_theme_stylebox_override("normal", UITheme.slot_filled_style())
		cell.add_theme_stylebox_override("hover", UITheme.slot_filled_style())
		cell.add_theme_stylebox_override("pressed", UITheme.slot_filled_style())
	else:
		cell.text = "＋ 选择技能"
		cell.add_theme_color_override("font_color", UITheme.INK_DIM)
		cell.add_theme_font_size_override("font_size", 12)
		cell.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		cell.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		cell.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
	var idx_copy = idx
	cell.pressed.connect(func(): strategy_skill_clicked.emit(current_char_id, idx_copy, false))
	return cell


## 条件格按钮
func _build_cond_cell(row_data: Dictionary, idx: int, field: String) -> Button:
	var cd_id: String = row_data.get(field, "")
	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_NONE
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = 1.4
	cell.custom_minimum_size = Vector2(0, 44)
	if cd_id != "":
		var cd = DataManager.get_condition(cd_id)
		cell.text = cd.get("name_zh", "???")
		cell.add_theme_color_override("font_color", UITheme.INK2)
		cell.add_theme_font_size_override("font_size", 12)
		cell.add_theme_stylebox_override("normal", UITheme.slot_filled_style())
		cell.add_theme_stylebox_override("hover", UITheme.slot_filled_style())
		cell.add_theme_stylebox_override("pressed", UITheme.slot_filled_style())
	else:
		cell.text = "＋ 条件"
		cell.add_theme_color_override("font_color", Color("5a4a30"))
		cell.add_theme_font_size_override("font_size", 12)
		cell.add_theme_stylebox_override("normal", UITheme.slot_dashed_style())
		cell.add_theme_stylebox_override("hover", UITheme.slot_dashed_style())
		cell.add_theme_stylebox_override("pressed", UITheme.slot_dashed_style())
	var idx_copy = idx
	var field_copy = field
	cell.pressed.connect(func(): strategy_cond_clicked.emit(current_char_id, idx_copy, field_copy))
	return cell


# ==================================================================
#  工具
# ==================================================================

## 角色职业→emoji图标映射
func char_icon(ch: Dictionary) -> String:
	var cls = ch.get("class_zh", "")
	var cls_icons := {
		"领主": "👑", "君主": "👑", "女祭司": "🙏", "斗士": "🛡️",
		"法师": "🔥", "术士": "🔥", "魔女": "❄️", "猎人": "🏹",
		"骑士": "🐴", "重骑士": "🐴", "牧师": "✨", "盗贼": "🗡️",
	}
	return cls_icons.get(cls, "👤")


## 弹性间距控件（类似 CSS flex-grow: 1 的 spacer）
func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
