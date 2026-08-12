extends Control
## =============================================================================
## UnitEditor — 右侧角色详情面板
## =============================================================================
## 作用：显示选中角色的装备槽位、能力数值和技能列表。
##       玩家可以点击装备槽位来更换装备。
##
## 布局结构（从上到下）：
##   Header    — 角色头像图标、名称、职业/地区
##   EquipPanel — 4个装备槽位（武器、盾牌、饰品1、饰品2）
##   StatsPanel — 8项能力数值（HP、物攻、物防、魔攻、魔防、先制、命中、回避）
##   SkillPanel — 技能列表（最多显示8个）
##
## 装备数据流：
##   UnitEditor 发出 equip_slot_clicked 信号
##   → main_screen 收到后弹出装备选择器(EquipPicker)
##   → 玩家选择装备后 main_screen 调用 equip_item() 更新
##   → _refresh_equipment() 重新渲染装备槽
##   → _refresh_stats() 重新计算并显示加成后的数值
## =============================================================================

class_name UnitEditor

# ------------------------------------------------------------------ 当前查看的角色
var current_char_id: String = ""   # 角色ID
var current_team_idx: int = -1     # 所在队伍索引
var current_slot: int = -1         # 所在槽位索引

# ------------------------------------------------------------------ 装备状态
## 当前角色的装备映射：{"weapon": "eq_sword_01", "shield": "eq_shield_03", ...}
## 注意：这个数据由 main_screen 维护（equipment_data），
## UnitEditor 只保存一份副本用于显示。
var equipped: Dictionary = {}

# ------------------------------------------------------------------ @onready 节点引用
## @onready 是 GDScript 的延迟初始化语法。
## 等价于在 _ready() 中写：ed_head_icon = $Header/Icon
## $ 是 get_node() 的语法糖，$Header/Icon 等价于 get_node("Header/Icon")
## 类似于 CSS 选择器路径，但以 / 分隔。

@onready var ed_head_icon: Label = $Header/Icon       # 角色图标（emoji）
@onready var ed_head_name: Label = $Header/VBox/Name  # 角色名
@onready var ed_head_sub: Label = $Header/VBox/Sub    # 职业/地区

@onready var weapon_slot: Button = $EquipPanel/WeaponSlot  # 武器槽按钮
@onready var shield_slot: Button = $EquipPanel/ShieldSlot  # 盾牌槽按钮
@onready var acc1_slot: Button = $EquipPanel/Acc1Slot      # 饰品1槽按钮
@onready var acc2_slot: Button = $EquipPanel/Acc2Slot      # 饰品2槽按钮

@onready var stat_grid: GridContainer = $StatsPanel/StatGrid        # 数值网格
@onready var skill_list: VBoxContainer = $SkillPanel/ScrollContainer/SkillList  # 技能列表

# ------------------------------------------------------------------ 信号
## 玩家点击装备槽时发出，由 main_screen 接收并弹出装备选择器
## 参数：char_id（角色ID）、slot_key（装备槽名称："weapon"/"shield"/"acc1"/"acc2"）
signal equip_slot_clicked(char_id: String, slot_key: String)


func _ready() -> void:
	# 连接4个装备槽按钮的 pressed 信号
	# func(): 创建匿名函数（lambda），捕获当前的 slot_key 值
	# GDScript 的匿名函数可以捕获外部变量（闭包），和 Python lambda 类似
	weapon_slot.pressed.connect(func(): _on_slot_pressed("weapon"))
	shield_slot.pressed.connect(func(): _on_slot_pressed("shield"))
	acc1_slot.pressed.connect(func(): _on_slot_pressed("acc1"))
	acc2_slot.pressed.connect(func(): _on_slot_pressed("acc2"))


func _on_slot_pressed(slot_key: String) -> void:
	if current_char_id != "":
		equip_slot_clicked.emit(current_char_id, slot_key)


## ---------------------------------------------------------------------------
## show_unit() — 显示角色详情
## ---------------------------------------------------------------------------
## 由 main_screen 调用，当玩家点击棋盘上的角色时触发。
##
## 参数：
##   char_id    — 角色ID（用于查询 DataManager）
##   team_idx   — 所在队伍索引
##   slot       — 所在槽位索引
##   equip_data — 该角色的装备数据（从 main_screen.equipment_data 传入）
##
## 流程：
##   1. 保存参数到成员变量
##   2. 复制装备数据（.duplicate() 做浅拷贝，避免外部修改影响内部状态）
##   3. 从 DataManager 查询角色数据
##   4. 刷新三个区域：装备、数值、技能
## ---------------------------------------------------------------------------
func show_unit(char_id: String, team_idx: int, slot: int, equip_data: Dictionary = {}) -> void:
	current_char_id = char_id
	current_team_idx = team_idx
	current_slot = slot
	equipped = equip_data.duplicate()  # .duplicate() = 浅拷贝，类似 Python 的 dict.copy()

	var ch = DataManager.get_character(char_id)
	if ch.is_empty():
		clear()
		return

	# 更新头部信息
	ed_head_icon.text = _char_icon(ch)
	ed_head_name.text = ch.get("name_zh", "???")
	ed_head_sub.text = ch.get("class_zh", "") + " · " + ch.get("region", "")

	_refresh_equipment()  # 刷新装备槽位显示
	_refresh_stats(ch)    # 刷新属性数值（含装备加成）
	_refresh_skills(ch)   # 刷新技能列表


## 清空面板显示（无角色选中时）
func clear() -> void:
	current_char_id = ""
	equipped.clear()
	ed_head_icon.text = "—"
	ed_head_name.text = "尚未选择单位"
	ed_head_sub.text = "—"
	for btn in [weapon_slot, shield_slot, acc1_slot, acc2_slot]:
		btn.text = "—"
		btn.tooltip_text = ""  # tooltip 是鼠标悬停时显示的提示文本


## ---------------------------------------------------------------------------
## equip_item() — 更新装备（由 main_screen 在玩家选择装备后调用）
## ---------------------------------------------------------------------------
## slot_key — "weapon" / "shield" / "acc1" / "acc2"
## eq_id    — 装备ID，"" 表示卸下装备
## ---------------------------------------------------------------------------
func equip_item(slot_key: String, eq_id: String) -> void:
	if eq_id == "":
		equipped.erase(slot_key)  # .erase() 删除字典中的键
	else:
		equipped[slot_key] = eq_id
	_refresh_equipment()
	# 装备变更后需要重新计算属性加成
	var ch = DataManager.get_character(current_char_id)
	if not ch.is_empty():
		_refresh_stats(ch)


## 角色职业→emoji图标映射（与 BoardGrid 中的逻辑相同，但映射表更精简）
func _char_icon(ch: Dictionary) -> String:
	var cls = ch.get("class_zh", "")
	var cls_icons := {
		"领主": "👑", "君主": "👑", "女祭司": "🙏", "斗士": "🛡️",
		"法师": "🔥", "术士": "🔥", "魔女": "❄️", "猎人": "🏹",
		"骑士": "🐴", "重骑士": "🐴", "牧师": "✨", "盗贼": "🗡️",
	}
	return cls_icons.get(cls, "👤")


# ==================================================================
#  装备显示 (Equipment Display)
# ==================================================================

## ---------------------------------------------------------------------------
## _refresh_equipment() — 刷新装备槽位按钮的文本和颜色
## ---------------------------------------------------------------------------
## 4个槽位的定义：
##   weapon — 武器槽（影响物攻/魔攻等）
##   shield — 盾牌槽（影响物防/魔防等）
##   acc1   — 饰品槽1（各种属性加成）
##   acc2   — 饰品槽2
##
## 已装备：显示装备名，文字颜色=稀有度颜色
## 未装备：显示"— 点击装备"，文字为暗色
## ---------------------------------------------------------------------------
func _refresh_equipment() -> void:
	# 槽位定义数组：每个元素包含 key、对应按钮、显示标签
	var slot_defs := [
		{"key": "weapon", "btn": weapon_slot, "label": "⚔️ 武器槽", "default_subtype": "sword"},
		{"key": "shield", "btn": shield_slot, "label": "🛡️ 盾牌槽", "default_subtype": "shield"},
		{"key": "acc1",  "btn": acc1_slot,  "label": "💍 饰品1",  "default_subtype": ""},
		{"key": "acc2",  "btn": acc2_slot,  "label": "💍 饰品2",  "default_subtype": ""},
	]

	for sd in slot_defs:
		if equipped.has(sd.key):
			# 已装备：查询装备数据并显示
			var eq = DataManager.get_equipment(equipped[sd.key])
			var eq_name = eq.get("name_zh", "???")
			var rarity = eq.get("rarity", "common")
			var color = UITheme.rarity_color(rarity)
			sd.btn.text = "%s\n%s" % [sd.label, eq_name]  # \n 换行显示标签和装备名
			sd.btn.add_theme_color_override("font_color", color)
			# tooltip 显示装备描述
			sd.btn.tooltip_text = eq.get("description", eq.get("acquisition", ""))
		else:
			# 未装备：显示占位文字
			sd.btn.text = "%s\n— 点击装备" % sd.label
			sd.btn.add_theme_color_override("font_color", UITheme.INK_DIM)
			sd.btn.tooltip_text = ""


# ==================================================================
#  属性显示 (Stats Display)
# ==================================================================

## ---------------------------------------------------------------------------
## _get_equipment_stat_bonuses() — 计算所有装备的属性加成总和
## ---------------------------------------------------------------------------
## 遍历已装备的所有装备，累加它们的 stats 字段。
## 例如：武器 atk+10 + 饰品 atk+3 = atk 总加成 13
##
## 返回：{"atk": 13, "def": 5, "hp": 20, ...}
## ---------------------------------------------------------------------------
func _get_equipment_stat_bonuses() -> Dictionary:
	var bonuses := {}
	for eq_id in equipped.values():
		var eq = DataManager.get_equipment(eq_id)
		var st = eq.get("stats", {})
		for k in st:
			# bonuses.get(k, 0) — 取已有值，没有则默认为 0
			bonuses[k] = bonuses.get(k, 0) + st[k]
	return bonuses


## ---------------------------------------------------------------------------
## _refresh_stats() — 刷新属性显示
## ---------------------------------------------------------------------------
## 显示8项属性，每项包括：属性名、基础值、装备加成（如果有）。
## 属性数据来源优先级：level_50_stats > base_stats
## （先取 level_50_stats，取不到就回退到 base_stats）
##
## 属性映射说明：
##   显示名       JSON字段(level_50)    JSON字段(base)   装备加成key
##   ❤️ HP       HP                   hp              hp
##   ⚔️ 物攻     Physical Attack      atk             atk
##   🛡️ 物防     Physical Defense     def             def
##   🔮 魔攻     Magic Attack         mag             mag
##   ✨ 魔防     Magic Defense        mdf             mdf
##   ⚡ 先制     Initiative           spd             spd
##   🎯 命中     Accuracy             acc             acc
##   💨 回避     Evasion              eva             eva
##
## GridContainer 说明：
##   GridContainer 是 Godot 的自动网格布局容器。
##   子节点按顺序排列，自动换行。这里用它来做属性表的对齐。
## ---------------------------------------------------------------------------
func _refresh_stats(ch: Dictionary) -> void:
	# 清空旧的属性行
	for child in stat_grid.get_children():
		child.queue_free()  # queue_free() 将节点加入销毁队列，在帧末安全删除

	var lv50 = ch.get("level_50_stats", {})
	var base = ch.get("base_stats", {})
	var bonuses = _get_equipment_stat_bonuses()

	# 属性定义列表：每项包含显示名和对应的 JSON 字段名
	var stat_defs := [
		{"name": "❤️ HP",    "base_key": "HP",              "eq_key": "hp"},
		{"name": "⚔️ 物攻",  "base_key": "Physical Attack", "eq_key": "atk"},
		{"name": "🛡️ 物防",  "base_key": "Physical Defense", "eq_key": "def"},
		{"name": "🔮 魔攻",  "base_key": "Magic Attack",    "eq_key": "mag"},
		{"name": "✨ 魔防",  "base_key": "Magic Defense",   "eq_key": "mdf"},
		{"name": "⚡ 先制",  "base_key": "Initiative",      "eq_key": "spd"},
		{"name": "🎯 命中",  "base_key": "Accuracy",        "eq_key": "acc"},
		{"name": "💨 回避",  "base_key": "Evasion",         "eq_key": "eva"},
	]

	for sd in stat_defs:
		# 取基础值：优先 level_50_stats，回退 base_stats，再回退 0
		var base_val = lv50.get(sd.base_key, base.get(sd.eq_key, 0))
		var bonus = bonuses.get(sd.eq_key, 0)

		# 创建一行 HBox（水平排列：名称 + 弹性间距 + 基础值 + 加成）
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = sd.name
		name_label.add_theme_color_override("font_color", UITheme.INK2)
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		row.add_child(_spacer())

		# 基础数值（金色显示）
		var val_label := Label.new()
		val_label.text = str(base_val)  # str() 类似 Python 的 str()
		val_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		val_label.add_theme_font_size_override("font_size", 13)
		row.add_child(val_label)

		# 装备加成（如果有）：绿色正数，红色负数
		if bonus != 0:
			var bonus_label := Label.new()
			bonus_label.text = " %+d" % bonus  # %+d 强制显示正负号，如 "+5", "-3"
			bonus_label.add_theme_color_override("font_color", UITheme.GREEN if bonus > 0 else UITheme.RED)
			bonus_label.add_theme_font_size_override("font_size", 10)
			row.add_child(bonus_label)

		stat_grid.add_child(row)


# ==================================================================
#  技能显示 (Skills Display)
# ==================================================================

## ---------------------------------------------------------------------------
## _refresh_skills() — 刷新技能列表
## ---------------------------------------------------------------------------
## 从角色数据的 skills 数组读取技能信息，最多显示 8 个。
##
## 技能类型：
##   🔴 active  — 主动技能（需要消耗 AP/PP 使用）
##   🔵 passive — 被动技能（满足条件时自动触发）
##
## 消耗显示：
##   AP（Action Point，行动点）：每回合恢复，用于使用主动技能
##   PP（Passive Point，被动点）：每回合恢复，用于触发被动技能
##
## 当前版本的说明：
##   技能数据在 JSON 中已经非常丰富（包含 target_type、damage_type、
##   power、hits、effects 等字段），但战斗中尚未实现真正的技能系统。
##   UnitEditor 目前只展示技能名称、类型和消耗。
## ---------------------------------------------------------------------------
func _refresh_skills(ch: Dictionary) -> void:
	# 清空旧列表
	for child in skill_list.get_children():
		child.queue_free()

	var skills_arr = ch.get("skills", [])
	if skills_arr.is_empty():
		var noop := Label.new()
		noop.text = "该角色暂无技能数据"
		noop.add_theme_color_override("font_color", UITheme.INK_DIM)
		noop.add_theme_font_size_override("font_size", 11)
		skill_list.add_child(noop)
		return

	# 最多显示 8 个技能
	for i in range(min(skills_arr.size(), 8)):
		var sk = skills_arr[i]
		var sk_name = sk.get("name", sk.get("name_zh", "???"))
		var sk_type = sk.get("type", "")  # "active" 或 "passive"

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)  # 子控件间距

		# 构建消耗文字
		var cost_text := ""
		var ap_cost = sk.get("ap_cost", 0)
		var pp_cost = sk.get("pp_cost", 0)
		if ap_cost > 0:
			cost_text += "AP:%d " % ap_cost
		if pp_cost > 0:
			cost_text += "PP:%d" % pp_cost

		# 🔴=主动技能, 🔵=被动技能
		var type_icon := "🔴" if sk_type == "active" else "🔵"
		var label := Label.new()
		label.text = "%s %s  %s" % [type_icon, sk_name, cost_text]
		label.add_theme_color_override("font_color", UITheme.INK)
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)

		skill_list.add_child(row)


## ---------------------------------------------------------------------------
## _spacer() — 创建弹性间距控件
## ---------------------------------------------------------------------------
## 返回一个设置了 SIZE_EXPAND_FILL 的 Control，用于在 HBox 中填充空白。
## 类似 HTML/CSS 中的 flex-grow: 1 的 spacer 元素。
## ---------------------------------------------------------------------------
func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
