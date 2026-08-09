# combatant_node.gd
# 战斗单位节点 — 用于战斗场景
class_name CombatantNode extends Control

var unit_data: Dictionary = {}
var unit_index: int = 0
var team: String = "blue"

# UI 节点
var _sprite_rect: ColorRect
var _class_icon: Label
var _hp_bar_bg: ColorRect     # HP条背景（深灰）
var _hp_bar_fill: ColorRect   # HP条填充（绿/黄/红）
var _hp_label: Label
var _name_label: Label
var _ap_label: Label
var _pp_label: Label
var _status_container: HBoxContainer
var _status_icons: Dictionary = {}
var _damage_label: Label
var _damage_tween: Tween   # 追踪当前伤害数字动画
var _highlight: ColorRect


func _init(p_data: Dictionary = {}, p_index: int = 0) -> void:
	unit_data = p_data
	unit_index = p_index
	team = p_data.get("team", "blue")


func _ready() -> void:
	# 保留父级设置的位置(offset_left/top)，只设置宽高
	offset_right = offset_left + 140.0
	offset_bottom = offset_top + 220.0
	_build_ui()
	refresh_display()


func _build_ui() -> void:
	var team_color = PlaceholderAssets.get_team_color(team)

	# 背景高亮框
	_highlight = ColorRect.new()
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.color = Color(team_color, 0.0)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)

	# 角色图像
	_sprite_rect = ColorRect.new()
	_sprite_rect.position = Vector2(16, 8)
	_sprite_rect.set_size(Vector2(108, 100))
	_sprite_rect.color = PlaceholderAssets.get_class_color(unit_data.get("class_name", "knight"))
	add_child(_sprite_rect)

	# 职业首字母
	_class_icon = Label.new()
	_class_icon.position = Vector2(50, 30)
	_class_icon.set_size(Vector2(50, 50))
	_class_icon.add_theme_font_size_override("font_size", 32)
	_class_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_class_icon.text = unit_data.get("class_display", "?")[0]
	add_child(_class_icon)

	# 名称
	_name_label = Label.new()
	_name_label.position = Vector2(6, 112)
	_name_label.set_size(Vector2(128, 16))
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", team_color)
	add_child(_name_label)

	# HP 条 — 用两个 ColorRect 替代 ProgressBar（避免 modulate 染整个条）
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.position = Vector2(10, 130)
	_hp_bar_bg.set_size(Vector2(120, 10))
	_hp_bar_bg.color = Color(0.15, 0.15, 0.15, 1.0)
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.position = Vector2(10, 130)
	_hp_bar_fill.set_size(Vector2(120, 10))
	_hp_bar_fill.color = Color.GREEN
	add_child(_hp_bar_fill)

	# HP 文字
	_hp_label = Label.new()
	_hp_label.position = Vector2(10, 142)
	_hp_label.set_size(Vector2(120, 14))
	_hp_label.add_theme_font_size_override("font_size", 10)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hp_label)

	# AP 指示器
	_ap_label = Label.new()
	_ap_label.position = Vector2(10, 158)
	_ap_label.set_size(Vector2(55, 14))
	_ap_label.add_theme_font_size_override("font_size", 10)
	_ap_label.add_theme_color_override("font_color", Color("#ff4444"))
	add_child(_ap_label)

	# PP 指示器
	_pp_label = Label.new()
	_pp_label.position = Vector2(75, 158)
	_pp_label.set_size(Vector2(55, 14))
	_pp_label.add_theme_font_size_override("font_size", 10)
	_pp_label.add_theme_color_override("font_color", Color("#4488ff"))
	add_child(_pp_label)

	# 状态图标区
	_status_container = HBoxContainer.new()
	_status_container.position = Vector2(10, 175)
	_status_container.set_size(Vector2(120, 22))
	_status_container.add_theme_constant_override("separation", 2)
	add_child(_status_container)

	# 伤害数字覆盖层
	_damage_label = Label.new()
	_damage_label.position = Vector2(15, 50)
	_damage_label.set_size(Vector2(110, 30))
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
	var is_dead: bool = not unit_data.get("is_alive", false)

	var hp_max: int = stats.get("hp", 100)
	var hp_cur: int = unit_data.get("hp_current", 0 if is_dead else hp_max)
	var hp_pct: float = clampf(float(hp_cur) / float(max(1, hp_max)), 0.0, 1.0)

	# HP 填充条 — 宽度按比例缩放，避免 ProgressBar modulate 问题
	_hp_bar_fill.set_size(Vector2(120.0 * hp_pct, 10.0))
	_hp_label.text = "%d/%d" % [hp_cur, hp_max]

	# 存活 / 死亡
	if is_dead:
		modulate = Color(0.4, 0.4, 0.4, 1.0)
		_hp_bar_fill.color = Color(0.3, 0.1, 0.1, 1.0)
		_ap_label.text = "AP:--"
		_pp_label.text = "PP:--"
	else:
		modulate = Color(1, 1, 1, 1.0)
		_hp_bar_fill.color = (
			Color.GREEN if hp_pct > 0.5
			else (Color.YELLOW if hp_pct > 0.25
			else Color.RED)
		)
		_ap_label.text = "AP:%d/%d" % [unit_data.get("ap_current", 0), unit_data.get("ap_max", 3)]
		_pp_label.text = "PP:%d/%d" % [unit_data.get("pp_current", 0), unit_data.get("pp_max", 2)]

	# 状态图标
	_refresh_status_icons()


func _refresh_status_icons() -> void:
	for child in _status_container.get_children():
		child.queue_free()
	_status_icons.clear()

	for se in unit_data.get("status_effects", []):
		var status_type = se.get("type", "")
		var icon = ColorRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.set_size(Vector2(20, 20))
		var status_colors = {
			"poison": Color("#8844cc"),
			"burn": Color("#ff4422"),
			"freeze": Color("#66aaff"),
			"stun": Color("#ffcc00"),
		}
		icon.color = status_colors.get(status_type, Color.WHITE)
		_status_container.add_child(icon)
		_status_icons[status_type] = icon


func play_damage_number(dmg: int, is_crit: bool = false, is_heal: bool = false, is_miss: bool = false) -> void:
	# 先停掉上一个动画，避免重叠
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()

	_damage_label.position = Vector2(15, 35)
	_damage_label.modulate = Color.WHITE
	_damage_label.visible = true

	if is_miss:
		_damage_label.text = "MISS"
		_damage_label.add_theme_color_override("font_color", Color("#888888"))
	elif is_heal:
		_damage_label.text = "+%d" % dmg
		_damage_label.add_theme_color_override("font_color", Color("#44ff44"))
	elif is_crit:
		_damage_label.text = "%d!" % dmg
		_damage_label.add_theme_color_override("font_color", Color("#ffd700"))
	else:
		_damage_label.text = str(dmg)
		_damage_label.add_theme_color_override("font_color", Color("#ff6644"))

	_damage_tween = create_tween()
	_damage_tween.set_parallel(true)
	_damage_tween.tween_property(_damage_label, "position:y", 10.0, 0.7).set_ease(Tween.EASE_OUT)
	_damage_tween.tween_property(_damage_label, "modulate:a", 0.0, 0.5).set_delay(0.15)
	_damage_tween.chain().tween_callback(func(): _damage_label.visible = false)


func play_hit_shake() -> void:
	# 只抖动角色图像，不动血条/文字，避免数字重叠
	var tween = create_tween()
	var orig_x = _sprite_rect.position.x
	tween.tween_property(_sprite_rect, "position:x", orig_x - 4, 0.04)
	tween.tween_property(_sprite_rect, "position:x", orig_x + 4, 0.04)
	tween.tween_property(_sprite_rect, "position:x", orig_x - 2, 0.03)
	tween.tween_property(_sprite_rect, "position:x", orig_x, 0.03)


## 施法闪光 — 角色图像闪白
func play_caster_flash() -> void:
	var tween = create_tween()
	tween.tween_property(_sprite_rect, "modulate", Color.WHITE, 0.08)
	tween.tween_property(_sprite_rect, "modulate", Color.WHITE, 0.12)
	tween.tween_property(_sprite_rect, "modulate", Color(1, 1, 1, 1), 0.15)


## 受击/被治疗闪光
func play_target_flash(damage_type: String, is_heal: bool = false) -> void:
	var flash_color: Color
	if is_heal:
		flash_color = Color.GREEN
	elif damage_type == "magical":
		flash_color = Color("#aa44ff")
	else:
		flash_color = Color.RED

	var original = _sprite_rect.color
	var tween = create_tween()
	tween.tween_property(_sprite_rect, "color", flash_color, 0.06)
	tween.tween_property(_sprite_rect, "color", original, 0.18)


func play_death() -> void:
	# 快速闪红 → 然后 refresh_display 设灰色
	var tween = create_tween()
	tween.tween_property(_sprite_rect, "modulate", Color.RED, 0.1)
	tween.tween_callback(refresh_display)


func set_highlight(active: bool) -> void:
	var tc = PlaceholderAssets.get_team_color(team)
	_highlight.color = Color(tc, 0.25 if active else 0.0)
