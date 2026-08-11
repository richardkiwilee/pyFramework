extends Control
## UnitEditor - Right-side panel for editing selected unit's equipment and skills.
class_name UnitEditor

var current_char_id: String = ""
var current_team_idx: int = -1
var current_slot: int = -1

# Equipped items: {slot_name: equipment_id}
var equipped: Dictionary = {}

# UI references
@onready var ed_head_icon: Label = $Header/Icon
@onready var ed_head_name: Label = $Header/VBox/Name
@onready var ed_head_sub: Label = $Header/VBox/Sub

@onready var weapon_slot: Button = $EquipPanel/WeaponSlot
@onready var shield_slot: Button = $EquipPanel/ShieldSlot
@onready var acc1_slot: Button = $EquipPanel/Acc1Slot
@onready var acc2_slot: Button = $EquipPanel/Acc2Slot

@onready var stat_grid: GridContainer = $StatsPanel/StatGrid
@onready var skill_list: VBoxContainer = $SkillPanel/ScrollContainer/SkillList

signal equip_slot_clicked(char_id: String, slot_key: String)


func _ready() -> void:
	weapon_slot.pressed.connect(func(): _on_slot_pressed("weapon"))
	shield_slot.pressed.connect(func(): _on_slot_pressed("shield"))
	acc1_slot.pressed.connect(func(): _on_slot_pressed("acc1"))
	acc2_slot.pressed.connect(func(): _on_slot_pressed("acc2"))


func _on_slot_pressed(slot_key: String) -> void:
	if current_char_id != "":
		equip_slot_clicked.emit(current_char_id, slot_key)


func show_unit(char_id: String, team_idx: int, slot: int, equip_data: Dictionary = {}) -> void:
	current_char_id = char_id
	current_team_idx = team_idx
	current_slot = slot
	equipped = equip_data.duplicate()

	var ch = DataManager.get_character(char_id)
	if ch.is_empty():
		clear()
		return

	ed_head_icon.text = _char_icon(ch)
	ed_head_name.text = ch.get("name_zh", "???")
	ed_head_sub.text = ch.get("class_zh", "") + " · " + ch.get("region", "")

	_refresh_equipment()
	_refresh_stats(ch)
	_refresh_skills(ch)


func clear() -> void:
	current_char_id = ""
	equipped.clear()
	ed_head_icon.text = "—"
	ed_head_name.text = "尚未选择单位"
	ed_head_sub.text = "—"
	for btn in [weapon_slot, shield_slot, acc1_slot, acc2_slot]:
		btn.text = "—"
		btn.tooltip_text = ""


func equip_item(slot_key: String, eq_id: String) -> void:
	if eq_id == "":
		equipped.erase(slot_key)
	else:
		equipped[slot_key] = eq_id
	_refresh_equipment()
	# Refresh stats too
	var ch = DataManager.get_character(current_char_id)
	if not ch.is_empty():
		_refresh_stats(ch)


func _char_icon(ch: Dictionary) -> String:
	var cls = ch.get("class_zh", "")
	var cls_icons := {
		"领主": "👑", "君主": "👑", "女祭司": "🙏", "斗士": "🛡️",
		"法师": "🔥", "术士": "🔥", "魔女": "❄️", "猎人": "🏹",
		"骑士": "🐴", "重骑士": "🐴", "牧师": "✨", "盗贼": "🗡️",
	}
	return cls_icons.get(cls, "👤")


func _refresh_equipment() -> void:
	var slot_defs := [
		{"key": "weapon", "btn": weapon_slot, "label": "⚔️ 武器槽", "default_subtype": "sword"},
		{"key": "shield", "btn": shield_slot, "label": "🛡️ 盾牌槽", "default_subtype": "shield"},
		{"key": "acc1",  "btn": acc1_slot,  "label": "💍 饰品1",  "default_subtype": ""},
		{"key": "acc2",  "btn": acc2_slot,  "label": "💍 饰品2",  "default_subtype": ""},
	]

	for sd in slot_defs:
		if equipped.has(sd.key):
			var eq = DataManager.get_equipment(equipped[sd.key])
			var eq_name = eq.get("name_zh", "???")
			var rarity = eq.get("rarity", "common")
			var color = UITheme.rarity_color(rarity)
			sd.btn.text = "%s\n%s" % [sd.label, eq_name]
			sd.btn.add_theme_color_override("font_color", color)
			sd.btn.tooltip_text = eq.get("description", eq.get("acquisition", ""))
		else:
			sd.btn.text = "%s\n— 点击装备" % sd.label
			sd.btn.add_theme_color_override("font_color", UITheme.INK_DIM)
			sd.btn.tooltip_text = ""


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
	var bonuses = _get_equipment_stat_bonuses()

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
		var base_val = lv50.get(sd.base_key, base.get(sd.eq_key, 0))
		var bonus = bonuses.get(sd.eq_key, 0)

		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = sd.name
		name_label.add_theme_color_override("font_color", UITheme.INK2)
		name_label.add_theme_font_size_override("font_size", 12)
		row.add_child(name_label)

		row.add_child(_spacer())

		var val_label := Label.new()
		val_label.text = str(base_val)
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


func _refresh_skills(ch: Dictionary) -> void:
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

	for i in range(min(skills_arr.size(), 8)):
		var sk = skills_arr[i]
		var sk_name = sk.get("name", sk.get("name_zh", "???"))
		var sk_type = sk.get("type", "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var cost_text := ""
		var ap_cost = sk.get("ap_cost", 0)
		var pp_cost = sk.get("pp_cost", 0)
		if ap_cost > 0:
			cost_text += "AP:%d " % ap_cost
		if pp_cost > 0:
			cost_text += "PP:%d" % pp_cost

		var type_icon := "🔴" if sk_type == "active" else "🔵"
		var label := Label.new()
		label.text = "%s %s  %s" % [type_icon, sk_name, cost_text]
		label.add_theme_color_override("font_color", UITheme.INK)
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)

		skill_list.add_child(row)


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
