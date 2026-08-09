# unit_card.gd
# 单位卡片组件 — 用于队伍编辑场景
class_name UnitCard extends Panel

signal deploy_toggled(unit_data: Dictionary)
signal equipment_edit_requested(unit_data: Dictionary)

var unit_data: Dictionary = {}
var is_active: bool = true  # true=上场, false=候补
var team_color: Color = Color.WHITE

# UI 节点
var _sprite_rect: ColorRect
var _class_label: Label
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _stats_labels: Dictionary = {}
var _deploy_btn: Button
var _equip_btn: Button


func _init(p_data: Dictionary = {}, p_is_active: bool = true) -> void:
	unit_data = p_data
	is_active = p_is_active


func _ready() -> void:
	team_color = PlaceholderAssets.get_team_color(unit_data.get("team", "blue"))
	custom_minimum_size = Vector2(320, 130)
	size = custom_minimum_size
	_build_ui()
	_refresh_display()


func _build_ui() -> void:
	# Panel 样式
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("#1a1a3e") if unit_data.get("team", "blue") == "blue" else Color("#3e1a1a")
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = team_color
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", panel_style)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# 左侧：角色图像占位符
	_sprite_rect = ColorRect.new()
	_sprite_rect.custom_minimum_size = Vector2(64, 64)
	_sprite_rect.set_size(Vector2(64, 64))
	hbox.add_child(_sprite_rect)

	# 右侧：信息区
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	# 名称行
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	info_vbox.add_child(_name_label)

	# 职业标签
	_class_label = Label.new()
	_class_label.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(_class_label)

	# HP 条
	var hp_hbox = HBoxContainer.new()
	info_vbox.add_child(hp_hbox)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(120, 14)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_hbox.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 11)
	hp_hbox.add_child(_hp_label)

	# 属性网格（2行×3列）
	var stats_grid = GridContainer.new()
	stats_grid.columns = 4
	info_vbox.add_child(stats_grid)

	var stat_names = ["ATK", "DEF", "MATK", "MDEF", "SPD", "HIT", "AP", "PP"]
	for sn in stat_names:
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.text = "%s:--" % sn
		stats_grid.add_child(lbl)
		_stats_labels[sn] = lbl

	# 按钮行
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 6)
	info_vbox.add_child(btn_hbox)

	_equip_btn = Button.new()
	_equip_btn.text = "装备"
	_equip_btn.custom_minimum_size = Vector2(60, 28)
	_equip_btn.add_theme_font_size_override("font_size", 12)
	_equip_btn.pressed.connect(_on_equip_pressed)
	btn_hbox.add_child(_equip_btn)

	_deploy_btn = Button.new()
	_deploy_btn.text = "下阵" if is_active else "上阵"
	_deploy_btn.custom_minimum_size = Vector2(60, 28)
	_deploy_btn.add_theme_font_size_override("font_size", 12)
	_deploy_btn.pressed.connect(_on_deploy_pressed)
	btn_hbox.add_child(_deploy_btn)


func _refresh_display() -> void:
	if unit_data.is_empty():
		return

	var stats = BattleData.calculate_effective_stats(unit_data)

	# 角色图像颜色
	var class_color = PlaceholderAssets.get_class_color(unit_data.get("class_name", "knight"))
	_sprite_rect.color = class_color

	# 文本
	_name_label.text = "%s Lv.%d" % [unit_data.get("name", "???"), unit_data.get("level", 1)]
	_name_label.add_theme_color_override("font_color", team_color)
	_class_label.text = unit_data.get("class_display", "")

	# HP条
	var hp_max = stats.get("hp", 100)
	var hp_cur = unit_data.get("hp_current", hp_max)
	_hp_bar.max_value = hp_max
	_hp_bar.value = hp_cur
	_hp_label.text = "%d/%d" % [hp_cur, hp_max]

	# 属性
	_stats_labels["ATK"].text = "ATK:%d" % stats.get("atk", 0)
	_stats_labels["DEF"].text = "DEF:%d" % stats.get("def", 0)
	_stats_labels["MATK"].text = "MATK:%d" % stats.get("matk", 0)
	_stats_labels["MDEF"].text = "MDEF:%d" % stats.get("mdef", 0)
	_stats_labels["SPD"].text = "SPD:%d" % stats.get("speed", 0)
	_stats_labels["HIT"].text = "HIT:%d" % stats.get("hit", 0)
	_stats_labels["AP"].text = "AP:%d" % stats.get("ap_max", 0)
	_stats_labels["PP"].text = "PP:%d" % stats.get("pp_max", 0)


func update_data(data: Dictionary) -> void:
	unit_data = data
	_refresh_display()


func set_is_active(active: bool) -> void:
	is_active = active
	_deploy_btn.text = "下阵" if active else "上阵"


func _on_equip_pressed() -> void:
	equipment_edit_requested.emit(unit_data)


func _on_deploy_pressed() -> void:
	deploy_toggled.emit(unit_data)
