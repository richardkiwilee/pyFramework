# combatant_node.gd
# 战斗单位节点 — 用于战斗场景
class_name CombatantNode extends Control

var unit_data: Dictionary = {}
var unit_index: int = 0
var team: String = "blue"

# UI 节点
var _sprite_rect: ColorRect
var _class_icon: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _name_label: Label
var _ap_label: Label
var _pp_label: Label
var _status_container: HBoxContainer
var _status_icons: Dictionary = {}
var _damage_label: Label
var _highlight: ColorRect


func _init(p_data: Dictionary = {}, p_index: int = 0) -> void:
	unit_data = p_data
	unit_index = p_index
	team = p_data.get("team", "blue")


func _ready() -> void:
	custom_minimum_size = Vector2(140, 220)
	size = custom_minimum_size
	_build_ui()
	refresh_display()


func _build_ui() -> void:
	var team_color = PlaceholderAssets.get_team_color(team)

	# 背景高亮框（当前行动单位时显示）
	_highlight = ColorRect.new()
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.color = Color(team_color, 0.0)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)

	# 角色图像
	_sprite_rect = ColorRect.new()
	_sprite_rect.position = Vector2(16, 8)
	_sprite_rect.size = Vector2(108, 100)
	_sprite_rect.color = PlaceholderAssets.get_class_color(unit_data.get("class_name", "knight"))
	add_child(_sprite_rect)

	# 职业首字母
	_class_icon = Label.new()
	_class_icon.position = Vector2(50, 30)
	_class_icon.size = Vector2(50, 50)
	_class_icon.add_theme_font_size_override("font_size", 32)
	_class_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_class_icon.text = unit_data.get("class_display", "?")[0]
	add_child(_class_icon)

	# 名称
	_name_label = Label.new()
	_name_label.position = Vector2(6, 112)
	_name_label.size = Vector2(128, 16)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", team_color)
	add_child(_name_label)

	# HP条
	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(10, 130)
	_hp_bar.size = Vector2(120, 10)
	add_child(_hp_bar)

	# HP文字
	_hp_label = Label.new()
	_hp_label.position = Vector2(10, 142)
	_hp_label.size = Vector2(120, 14)
	_hp_label.add_theme_font_size_override("font_size", 10)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hp_label)

	# AP/PP指示器
	_ap_label = Label.new()
	_ap_label.position = Vector2(10, 158)
	_ap_label.size = Vector2(55, 14)
	_ap_label.add_theme_font_size_override("font_size", 10)
	_ap_label.add_theme_color_override("font_color", Color("#ff4444"))
	add_child(_ap_label)

	_pp_label = Label.new()
	_pp_label.position = Vector2(75, 158)
	_pp_label.size = Vector2(55, 14)
	_pp_label.add_theme_font_size_override("font_size", 10)
	_pp_label.add_theme_color_override("font_color", Color("#4488ff"))
	add_child(_pp_label)

	# 状态图标区
	_status_container = HBoxContainer.new()
	_status_container.position = Vector2(10, 175)
	_status_container.size = Vector2(120, 22)
	_status_container.add_theme_constant_override("separation", 2)
	add_child(_status_container)

	# 伤害数字（覆盖层）
	_damage_label = Label.new()
	_damage_label.position = Vector2(15, 50)
	_damage_label.size = Vector2(110, 30)
	_damage_label.add_theme_font_size_override("font_size", 22)
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_label.visible = false
	_damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_label)


func refresh_display() -> void:
	if unit_data.is_empty():
		return

	var stats = BattleData.calculate_effective_stats(unit_data)

	_name_label.text = unit_data.get("name", "???")

	var hp_max = stats.get("hp", 100)
	var hp_cur = unit_data.get("hp_current", hp_max)
	_hp_bar.max_value = hp_max
	_hp_bar.value = hp_cur
	_hp_bar.modulate = Color.GREEN if hp_cur > hp_max * 0.5 else (Color.YELLOW if hp_cur > hp_max * 0.25 else Color.RED)
	_hp_label.text = "%d/%d" % [hp_cur, hp_max]

	_ap_label.text = "AP:%d/%d" % [unit_data.get("ap_current", 0), unit_data.get("ap_max", 3)]
	_pp_label.text = "PP:%d/%d" % [unit_data.get("pp_current", 0), unit_data.get("pp_max", 2)]

	# 状态图标
	_refresh_status_icons()

	# 存活状态
	if not unit_data.get("is_alive", false):
		modulate = Color(1, 1, 1, 0.3)
	else:
		modulate = Color(1, 1, 1, 1.0)


func _refresh_status_icons() -> void:
	for child in _status_container.get_children():
		child.queue_free()
	_status_icons.clear()

	for se in unit_data.get("status_effects", []):
		var status_type = se.get("type", "")
		var icon = ColorRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.size = Vector2(20, 20)
		var colors = {
			"poison": Color("#8844cc"),
			"burn": Color("#ff4422"),
			"freeze": Color("#66aaff"),
			"stun": Color("#ffcc00"),
		}
		icon.color = colors.get(status_type, Color.WHITE)

		var tooltip = Label.new()
		tooltip.text = "%s(%d)" % [status_type, se.get("duration", 0)]
		_status_container.add_child(icon)
		_status_icons[status_type] = icon


func play_damage_number(damage: int, is_crit: bool = false, is_heal: bool = false, is_miss: bool = false) -> void:
	_damage_label.visible = true
	if is_miss:
		_damage_label.text = "MISS"
		_damage_label.add_theme_color_override("font_color", Color("#888888"))
	elif is_heal:
		_damage_label.text = "+%d" % damage
		_damage_label.add_theme_color_override("font_color", Color("#44ff44"))
	elif is_crit:
		_damage_label.text = "%d!" % damage
		_damage_label.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		_damage_label.text = str(damage)
		_damage_label.add_theme_color_override("font_color", Color("#ff6644"))

	# Tween 动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_damage_label, "position:y", _damage_label.position.y - -25, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(_damage_label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.chain().tween_callback(func(): _damage_label.visible = false)
	_damage_label.position = Vector2(15, 50)
	_damage_label.modulate = Color.WHITE


func play_hit_shake() -> void:
	var tween = create_tween()
	tween.tween_property(self, "position:x", position.x - 4, 0.04)
	tween.tween_property(self, "position:x", position.x + 4, 0.04)
	tween.tween_property(self, "position:x", position.x - 2, 0.03)
	tween.tween_property(self, "position:x", position.x, 0.03)


func play_death() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): queue_free())


func set_highlight(active: bool) -> void:
	var team_color = PlaceholderAssets.get_team_color(team)
	_highlight.color = Color(team_color, 0.25 if active else 0.0)


func set_hp_animated(new_hp: int) -> void:
	var tween = create_tween()
	var hp_max = _hp_bar.max_value
	tween.tween_method(func(v): _hp_bar.value = v; _hp_label.text = "%d/%d" % [int(v), int(hp_max)], _hp_bar.value, new_hp, 0.3)
