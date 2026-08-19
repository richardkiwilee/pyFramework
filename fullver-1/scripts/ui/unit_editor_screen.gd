class_name UnitEditorScreen
extends Control
## =============================================================================
## UnitEditorScreen — 部队/单位编辑场景（readme 场景结构第 5 项）
## =============================================================================
## 布局：
##   左列  — 玩家军团列表（点击切换当前编辑的军团）
##   中部  — 3×3 编成九宫格（点击选槽位；第 0 行 = 后排 = 战斗 position 6-8）
##   右列  — 单位详情（复刻 demo-1 结构）：
##             · 4 个装备栏：武器 / 盾牌 / 饰品1 / 饰品2（点击槽位 → 下拉选装）
##             · 8 行行动策略栏：[技能 | 条件1 | 条件2]（demo-1 策略面板结构）
##
## 存储：装备 → Unit.equipment（weapon/shield/acc1/acc2）；
##       策略 → Unit.strategy（[{skill, cond1, cond2}]，最多 8 行）。
##       战斗引擎按策略行的技能顺序出战（battle_skill_ids），
##       条件当前只存储展示（引擎暂不消费，文档已声明）。
## =============================================================================

const MAX_STRATEGY_ROWS := 8

## 4 个装备槽定义（demo-1 口径：武器 + 盾牌 + 饰品×2）
const EQUIP_SLOTS := [
	{"key": "weapon", "icon": "⚔️", "label": "武器"},
	{"key": "shield", "icon": "🛡️", "label": "盾牌"},
	{"key": "acc1", "icon": "💍", "label": "饰品1"},
	{"key": "acc2", "icon": "💍", "label": "饰品2"},
]

var _armies_box: VBoxContainer
var _grid_box: GridContainer
var _detail_box: VBoxContainer
var _selected_army: Army = null
var _selected_slot: int = -1
## 当前点击选中的装备槽 key（"" = 未选）
var _selected_equip_slot: String = ""
## 槽位格子：slot → PanelContainer
var _slot_cells: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG
	add_child(bg)

	if GameManager.game_state == null:
		await GameManager.change_scene("res://scenes/world_map.tscn")
		return

	_build_layout()
	_refresh_army_list()
	_refresh_grid()
	_refresh_detail()


func _build_layout() -> void:
	# 顶部：标题 + 返回
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.position = Vector2(0, 8)
	header.add_theme_stylebox_override("panel", UITheme.panel_header_style())
	add_child(header)
	var header_row := HBoxContainer.new()
	header.add_child(header_row)
	header_row.add_child(UITheme.make_label(I18n.t("ui.units.title"), 18, UITheme.GOLD_BRIGHT))
	var back_btn := UITheme.make_button(I18n.t("ui.units.back"), UITheme.default_button_style(), 13)
	back_btn.add_theme_color_override("font_color", UITheme.INK)
	back_btn.pressed.connect(_on_back)
	header_row.add_child(back_btn)

	# 左列：军团列表
	var left := PanelContainer.new()
	left.position = Vector2(16, 70)
	left.size = Vector2(260, get_viewport_rect().size.y - 90)
	left.add_theme_stylebox_override("panel", UITheme.panel_style(10))
	add_child(left)
	_armies_box = VBoxContainer.new()
	_armies_box.add_theme_constant_override("separation", 6)
	left.add_child(_armies_box)

	# 中部：3×3 九宫格
	var mid := PanelContainer.new()
	mid.position = Vector2(290, 70)
	mid.size = Vector2(620, get_viewport_rect().size.y - 90)
	mid.add_theme_stylebox_override("panel", UITheme.panel_style(10))
	add_child(mid)
	_grid_box = GridContainer.new()
	_grid_box.columns = 3
	_grid_box.add_theme_constant_override("h_separation", 8)
	_grid_box.add_theme_constant_override("v_separation", 8)
	mid.add_child(_grid_box)

	# 右列：详情（装备 4 槽 + 策略 8 行，需要 520 宽）
	var right := PanelContainer.new()
	right.position = Vector2(926, 70)
	right.size = Vector2(520, get_viewport_rect().size.y - 90)
	right.add_theme_stylebox_override("panel", UITheme.panel_style(10))
	add_child(right)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 8)
	right.add_child(_detail_box)


# ==================================================================
#  军团列表
# ==================================================================

func _refresh_army_list() -> void:
	for child in _armies_box.get_children():
		child.queue_free()
	var player_id: String = DataManager.get_player_faction_id()
	for army in GameManager.game_state.armies_of(player_id):
		var city: City = GameManager.game_state.get_city(army.current_city_id)
		var city_name: String = city.name_zh if city != null else "?"
		var text := "%s @ %s（%d人）" % [army.id, city_name, army.team.unit_count()]
		var bt := UITheme.make_button(text, UITheme.default_button_style(), 13)
		bt.add_theme_color_override("font_color", UITheme.INK if army != _selected_army else UITheme.GOLD_BRIGHT)
		# ⚠️ 闭包陷阱：循环变量必须复制（demo-1 注释惯例）
		var army_ref: Army = army
		bt.pressed.connect(func() -> void:
			_selected_army = army_ref
			_selected_slot = -1
			_selected_equip_slot = ""
			_refresh_army_list()
			_refresh_grid()
			_refresh_detail())
		_armies_box.add_child(bt)


# ==================================================================
#  3×3 九宫格
# ==================================================================

func _refresh_grid() -> void:
	for child in _grid_box.get_children():
		child.queue_free()
	_slot_cells.clear()
	if _selected_army == null:
		_grid_box.add_child(UITheme.make_label(I18n.t("ui.units.title") + "：请选择左侧军团", 14, UITheme.INK_DIM))
		return
	for slot in range(Team.MAX_UNITS):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(190, 170)
		var unit: Unit = _selected_army.team.get_unit_at(slot)
		var style := UITheme.slot_filled_style() if unit != null else UITheme.slot_dashed_style()
		if slot == _selected_slot:
			style = UITheme.slot_filled_style()
			style.border_color = UITheme.GOLD_BRIGHT
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		cell.add_theme_stylebox_override("panel", style)
		# 点击格子：选中槽位
		var slot_copy := slot
		cell.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_selected_slot = slot_copy
				_selected_equip_slot = ""
				_refresh_grid()
				_refresh_detail())
		# 格子内容
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		cell.add_child(inner)
		if unit == null:
			inner.add_child(UITheme.make_label(I18n.t("ui.units.empty_slot"), 12, UITheme.INK_DIM))
		else:
			var char_data: Dictionary = DataManager.get_character(unit.character_id)
			var emoji_label := UITheme.make_label(
				"👤" if char_data.is_empty() else _class_emoji(char_data.get("class_en", "")), 26, UITheme.INK)
			emoji_label.add_theme_font_override("font", UITheme.emoji_font)
			inner.add_child(emoji_label)
			inner.add_child(UITheme.make_label(char_data.get("name_zh", unit.character_id), 14, UITheme.INK))
			inner.add_child(UITheme.make_label("%s Lv.%d" % [char_data.get("class_zh", "?"), unit.level], 12, UITheme.INK2))
			inner.add_child(UITheme.make_label("策略 %d/%d" % [unit.strategy.size(), MAX_STRATEGY_ROWS], 11, UITheme.INK_DIM))
		_grid_box.add_child(cell)
		_slot_cells.append(cell)


## 职业 emoji 图标（小表 + 默认）
func _class_emoji(class_en: String) -> String:
	var table := {
		"Lord": "👑", "Mage": "🔮", "Cleric": "✨", "Knight": "🛡️",
		"Soldier": "⚔️", "Archer": "🏹", "Thief": "🗡️", "Swordfighter": "⚔️",
	}
	return table.get(class_en, "👤")


# ==================================================================
#  详情面板：装备 4 槽 + 策略 8 行（复刻 demo-1 结构）
# ==================================================================

func _refresh_detail() -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	if _selected_army == null:
		return
	_detail_box.add_child(UITheme.make_label(
		"%s %d/%d" % [I18n.t("ui.units.team_name"), _selected_army.team.unit_count(), Team.MAX_UNITS], 15, UITheme.GOLD_BRIGHT))
	var unit: Unit = _selected_army.team.get_unit_at(_selected_slot) if _selected_slot >= 0 else null
	if unit == null:
		_detail_box.add_child(UITheme.make_label(
			I18n.t("ui.units.empty_slot") if _selected_slot >= 0 else "点击格子选择单位", 13, UITheme.INK_DIM))
		var add_btn := UITheme.make_button("+ " + I18n.t("ui.city.recruit"), UITheme.default_button_style(), 13)
		add_btn.add_theme_color_override("font_color", UITheme.INK)
		add_btn.pressed.connect(_on_add_unit)
		_detail_box.add_child(add_btn)
		return

	# --- 单位头 ---
	var char_data: Dictionary = DataManager.get_character(unit.character_id)
	_detail_box.add_child(UITheme.make_label(char_data.get("name_zh", unit.character_id), 17, UITheme.INK))
	_detail_box.add_child(UITheme.make_label(
		"%s: %s   %s: %d" % [I18n.t("ui.units.class"), char_data.get("class_zh", "?"),
			I18n.t("ui.units.level"), unit.level], 13, UITheme.INK2))

	_build_equipment_section(unit)
	_build_strategy_section(unit)

	# 移除单位
	var remove_btn := UITheme.make_button(I18n.t("ui.units.remove"), UITheme.default_button_style(), 13)
	remove_btn.add_theme_color_override("font_color", UITheme.RED)
	remove_btn.pressed.connect(_on_remove_unit)
	_detail_box.add_child(remove_btn)


## ---------------------------------------------------------------------------
## 装备区：2×2 四槽卡片（demo-1 口径：武器/盾牌/饰品1/饰品2）+ 选装下拉
## ---------------------------------------------------------------------------
func _build_equipment_section(unit: Unit) -> void:
	_detail_box.add_child(UITheme.make_label("装备", 14, UITheme.GOLD))
	var slot_grid := GridContainer.new()
	slot_grid.columns = 2
	slot_grid.add_theme_constant_override("h_separation", 8)
	slot_grid.add_theme_constant_override("v_separation", 8)
	_detail_box.add_child(slot_grid)
	for slot_def in EQUIP_SLOTS:
		var key: String = slot_def.key
		var eq_id: String = unit.equipment.get(key, "")
		var eq_data: Dictionary = DataManager.get_equipment(eq_id)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(220, 64)
		var style := UITheme.slot_filled_style() if not eq_data.is_empty() else UITheme.slot_dashed_style()
		if key == _selected_equip_slot:
			style = UITheme.slot_filled_style()
			style.border_color = UITheme.GOLD_BRIGHT
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		card.add_theme_stylebox_override("panel", style)
		# 卡内容：图标 + 槽名 + 已装装备名（或 +）
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		card.add_child(inner)
		var icon := UITheme.make_label(slot_def.icon, 18, UITheme.INK)
		icon.add_theme_font_override("font", UITheme.emoji_font)
		inner.add_child(icon)
		var name_box := VBoxContainer.new()
		inner.add_child(name_box)
		name_box.add_child(UITheme.make_label(slot_def.label, 12, UITheme.INK2))
		name_box.add_child(UITheme.make_label(
			eq_data.get("name_zh", "+") if not eq_data.is_empty() else "+", 13,
			UITheme.INK if not eq_data.is_empty() else UITheme.INK_DIM))
		# ⚠️ 闭包陷阱：复制循环变量
		var key_copy := key
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_selected_equip_slot = key_copy
				_refresh_detail())
		slot_grid.add_child(card)

	# 选中的槽位 → 下拉选装 + 卸下
	if _selected_equip_slot != "":
		var pool: Array = _equipment_pool_for_slot(unit, _selected_equip_slot)
		var opt := OptionButton.new()
		opt.add_theme_font_size_override("font_size", 12)
		opt.add_item("— 卸下 —")
		for eq_id in pool:
			var eq: Dictionary = DataManager.get_equipment(eq_id)
			opt.add_item("%s (%s)" % [eq.get("name_zh", eq_id), eq.get("rarity", "")])
		var current: String = unit.equipment.get(_selected_equip_slot, "")
		for i in range(pool.size()):
			if pool[i] == current:
				opt.select(i + 1)
		var unit_ref: Unit = unit
		var slot_copy: String = _selected_equip_slot
		var pool_copy: Array = pool
		opt.item_selected.connect(func(index: int) -> void:
			if index <= 0:
				unit_ref.unequip(slot_copy)
			else:
				unit_ref.equip(slot_copy, pool_copy[index - 1])
			_refresh_grid()
			_refresh_detail())
		_detail_box.add_child(opt)


## 该槽位的可选装备池（数据驱动）：
## weapon → 职业武器子类型；shield → 盾牌子类型；acc → accessory
func _equipment_pool_for_slot(unit: Unit, slot_key: String) -> Array:
	var char_data: Dictionary = DataManager.get_character(unit.character_id)
	var class_id := DataManager.get_class_id_by_character(char_data)
	var pool: Array = []
	if slot_key == "weapon":
		for st in DataManager.get_class_weapon_subtypes(class_id):
			pool.append_array(DataManager.get_equipment_by_subtype(st))
	elif slot_key == "shield":
		for st in ["shield", "greatshield"]:
			pool.append_array(DataManager.get_equipment_by_subtype(st))
	else:
		pool = DataManager.get_equipment_by_subtype("accessory")
	return pool


## ---------------------------------------------------------------------------
## 策略区：最多 8 行 [技能 | 条件1 | 条件2]（demo-1 行动策略面板结构）
## ---------------------------------------------------------------------------
func _build_strategy_section(unit: Unit) -> void:
	_detail_box.add_child(UITheme.make_label(
		"行动策略 %d/%d" % [unit.strategy.size(), MAX_STRATEGY_ROWS], 14, UITheme.GOLD))
	# 表头
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(_fixed_cell("技能", 190))
	head.add_child(_fixed_cell("条件1", 120))
	head.add_child(_fixed_cell("条件2", 120))
	_detail_box.add_child(head)

	var unit_ref: Unit = unit
	for i in range(unit.strategy.size()):
		var row: Dictionary = unit.strategy[i]
		_detail_box.add_child(_build_strategy_row(unit_ref, i, row))

	# 新增行
	var add := UITheme.make_button(
		"＋ 新增技能（%d/%d）" % [unit.strategy.size(), MAX_STRATEGY_ROWS], UITheme.default_button_style(), 12)
	add.add_theme_color_override("font_color", UITheme.INK)
	add.disabled = unit.strategy.size() >= MAX_STRATEGY_ROWS
	add.pressed.connect(func() -> void:
		unit_ref.strategy.append({"skill": "", "cond1": "", "cond2": ""})
		_refresh_grid()
		_refresh_detail())
	_detail_box.add_child(add)


## 单行策略：[技能下拉 | 条件1下拉 | 条件2下拉 | ×]
func _build_strategy_row(unit: Unit, row_index: int, row: Dictionary) -> Control:
	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 4)

	var skill_opt := OptionButton.new()
	skill_opt.add_theme_font_size_override("font_size", 12)
	skill_opt.custom_minimum_size = Vector2(190, 0)
	skill_opt.add_item("— 选择技能 —")
	var skill_pool: Array = _skill_pool_for_unit(unit)
	for sk_id in skill_pool:
		var sk: Dictionary = DataManager.get_skill(sk_id)
		skill_opt.add_item(sk.get("name_zh", sk_id))
	for i in range(skill_pool.size()):
		if skill_pool[i] == row.get("skill", ""):
			skill_opt.select(i + 1)
	row_box.add_child(skill_opt)

	row_box.add_child(_build_condition_dropdown(unit, row_index, row, "cond1"))
	row_box.add_child(_build_condition_dropdown(unit, row_index, row, "cond2"))

	var del := UITheme.make_button("×", UITheme.default_button_style(), 12)
	del.add_theme_color_override("font_color", UITheme.RED)
	del.custom_minimum_size = Vector2(36, 0)
	var unit_ref: Unit = unit
	var idx_copy := row_index
	del.pressed.connect(func() -> void:
		unit_ref.strategy.remove_at(idx_copy)
		_refresh_grid()
		_refresh_detail())
	row_box.add_child(del)
	return row_box


## 条件下拉（55 个条件数据，含"— 无 —"）
func _build_condition_dropdown(unit: Unit, row_index: int, row: Dictionary, cond_key: String) -> Control:
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 12)
	opt.custom_minimum_size = Vector2(120, 0)
	opt.add_item("—")
	var cond_pool: Array = DataManager.get_all_condition_ids()
	for cond_id in cond_pool:
		var cd: Dictionary = DataManager.get_condition(cond_id)
		opt.add_item(cd.get("name_zh", cond_id))
	var current: String = row.get(cond_key, "")
	for i in range(cond_pool.size()):
		if cond_pool[i] == current:
			opt.select(i + 1)
	# ⚠️ 闭包陷阱：复制循环变量 + 条件键
	var unit_ref: Unit = unit
	var idx_copy := row_index
	var key_copy := cond_key
	var pool_copy: Array = cond_pool
	opt.item_selected.connect(func(index: int) -> void:
		unit_ref.strategy[idx_copy][key_copy] = pool_copy[index - 1] if index > 0 else ""
		_refresh_detail())
	return opt


## 技能下拉池：角色自带技能（按 name_en 反查 id）+ 职业技能表
func _skill_pool_for_unit(unit: Unit) -> Array:
	var result: Array = []
	var char_data: Dictionary = DataManager.get_character(unit.character_id)
	for embedded in char_data.get("skills", []):
		var sk_id := DataManager.get_skill_id_by_name(embedded.get("name", ""))
		if sk_id != "" and sk_id not in result:
			result.append(sk_id)
	var cls: String = char_data.get("class_zh", "")
	for sk_id in DataManager.get_skills_by_class_name(cls):
		if sk_id not in result:
			result.append(sk_id)
	return result


func _fixed_cell(text: String, width: float) -> Control:
	var lb := UITheme.make_label(text, 12, UITheme.INK_DIM)
	lb.custom_minimum_size = Vector2(width, 0)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	return lb


# ==================================================================
#  操作
# ==================================================================

func _on_add_unit() -> void:
	var used: Array = []
	var player_id: String = DataManager.get_player_faction_id()
	for army in GameManager.game_state.armies_of(player_id):
		for u in army.team.units:
			if u != null:
				used.append(u.character_id)
	var picks: Array = DataManager.get_random_characters(1, used)
	if picks.is_empty():
		Alert.alert(I18n.t("ui.units.no_equipment"), UITheme.INK2)
		return
	var unit: Unit = GameManager.game_state.new_unit(picks[0], 1)
	var target_slot := _selected_slot if _selected_slot >= 0 else _first_empty_slot()
	if target_slot < 0:
		Alert.alert("编队已满", UITheme.RED)
		return
	if not _selected_army.team.set_unit(target_slot, unit):
		Alert.alert("槽位已占用", UITheme.RED)
		return
	_refresh_grid()
	_refresh_army_list()
	_refresh_detail()


func _on_remove_unit() -> void:
	if _selected_slot < 0:
		return
	_selected_army.team.remove_unit_at(_selected_slot)
	_refresh_grid()
	_refresh_army_list()
	_refresh_detail()


func _first_empty_slot() -> int:
	for slot in range(Team.MAX_UNITS):
		if _selected_army.team.get_unit_at(slot) == null:
			return slot
	return -1


func _on_back() -> void:
	await GameManager.change_scene("res://scenes/world_map.tscn")
