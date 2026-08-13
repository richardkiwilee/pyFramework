extends Control
## =============================================================================
## 血条组件包 —— RPG 常用 UI 条合集（纯 UI 组件）
## =============================================================================
##   ❤️ 生命条：红色；受伤瞬间扣除，黄色"幽灵条"延迟 0.35s 平滑跟上
##               （经典 JRPG 延迟伤害显示）
##   💧 魔法条：蓝色；施法消耗 30 点
##   ⚡ 耐力条：绿色；按住【冲刺】持续消耗，松开自动回复
##   🔮 施法条：紫色；点击施法后 2 秒读条，完成后提示
## 组件实现：每个条 = 深色底框 + 幽灵层 + 前景层 + 数值文字，
## 用 size.x 直接驱动填充比例，Tween 做平滑过渡。
## =============================================================================

const BAR_W := 420.0
const BAR_H := 26.0
const CAST_TIME := 2.0
const MP_COST := 30.0

var _hp := 100.0
var _mp := 100.0
var _stam := 100.0
var _casting := false
var _cast_elapsed := 0.0

var _hp_bar: Dictionary
var _mp_bar: Dictionary
var _stam_bar: Dictionary
var _cast_bar: Dictionary

@onready var bars_box: VBoxContainer = $Center/VBox/BarsBox
@onready var buttons_row: HBoxContainer = $Center/VBox/ButtonsRow
@onready var status_label: Label = $Center/VBox/StatusLabel
@onready var sprint_btn: Button = $Center/VBox/ButtonsRow/SprintBtn


func _ready() -> void:
	_hp_bar = _make_bar("❤️ 生命", Color(0.82, 0.22, 0.20), Color(0.95, 0.80, 0.30))
	_mp_bar = _make_bar("💧 魔法", Color(0.22, 0.45, 0.90), Color(0.60, 0.80, 1.00))
	_stam_bar = _make_bar("⚡ 耐力", Color(0.25, 0.75, 0.30), Color(0.70, 1.00, 0.60))
	_cast_bar = _make_bar("🔮 施法", Color(0.60, 0.35, 0.90), Color(0.85, 0.70, 1.00))
	_set_frac(_cast_bar, 0.0)

	$Center/VBox/ButtonsRow/HurtBtn.pressed.connect(_take_damage)
	$Center/VBox/ButtonsRow/HealBtn.pressed.connect(_heal)
	$Center/VBox/ButtonsRow/CastBtn.pressed.connect(_start_cast)
	$Center/VBox/ButtonsRow/ReviveBtn.pressed.connect(_revive)
	_refresh_values()


## 造一条血条：标题 + 底框(幽灵层+前景层) + 数值
func _make_bar(title: String, color: Color, ghost_color: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bars_box.add_child(row)

	var t := Label.new()
	t.text = title
	t.custom_minimum_size = Vector2(86, 0)
	t.add_theme_font_size_override("font_size", 16)
	row.add_child(t)

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(BAR_W, BAR_H)
	row.add_child(frame)

	var bg := ColorRect.new()
	bg.size = Vector2(BAR_W, BAR_H)
	bg.color = Color(0.12, 0.13, 0.18)
	frame.add_child(bg)

	var ghost := ColorRect.new()
	ghost.size = Vector2(BAR_W, BAR_H)
	ghost.color = ghost_color
	frame.add_child(ghost)

	var fill := ColorRect.new()
	fill.size = Vector2(BAR_W, BAR_H)
	fill.color = color
	frame.add_child(fill)

	var value := Label.new()
	value.size = Vector2(BAR_W, BAR_H)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 13)
	frame.add_child(value)

	return {"fill": fill, "ghost": ghost, "value": value}


func _set_frac(bar: Dictionary, frac: float) -> void:
	bar["fill"].size.x = BAR_W * clampf(frac, 0.0, 1.0)


## 幽灵条平滑跟随前景条
func _tween_ghost(bar: Dictionary, delay: float) -> void:
	if bar.has("ghost_tween") and is_instance_valid(bar["ghost_tween"]):
		bar["ghost_tween"].kill()
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(bar["ghost"], "size:x", bar["fill"].size.x, 0.5)
	bar["ghost_tween"] = tw


# ============================================================
#  行为
# ============================================================
func _take_damage() -> void:
	if _hp <= 0.0:
		status_label.text = "💀 已经濒死了，先复活吧！"
		return
	var dmg := 15 + randi() % 26
	_hp = maxf(0.0, _hp - dmg)
	_set_frac(_hp_bar, _hp / 100.0)
	_tween_ghost(_hp_bar, 0.35)
	status_label.text = "💥 受到 %d 点伤害！" % dmg
	if _hp <= 0.0:
		status_label.text = "💀 濒死！点击【复活】恢复"
	_refresh_values()


func _heal() -> void:
	if _hp >= 100.0:
		status_label.text = "😊 生命值已满"
		return
	_hp = minf(100.0, _hp + 30.0)
	_set_frac(_hp_bar, _hp / 100.0)
	_hp_bar["ghost"].size.x = _hp_bar["fill"].size.x   # 治疗时幽灵条立刻跟上
	status_label.text = "💚 恢复 30 点生命"
	_refresh_values()


func _start_cast() -> void:
	if _casting:
		status_label.text = "⏳ 正在施法…"
		return
	if _mp < MP_COST:
		status_label.text = "🧪 魔法不足（需要 %d 点）" % MP_COST
		return
	_mp -= MP_COST
	_casting = true
	_cast_elapsed = 0.0
	status_label.text = "🔮 施法中…（2 秒读条）"
	_refresh_values()


func _revive() -> void:
	_hp = 100.0
	_mp = 100.0
	_stam = 100.0
	_set_frac(_hp_bar, 1.0)
	_set_frac(_mp_bar, 1.0)
	_set_frac(_stam_bar, 1.0)
	_hp_bar["ghost"].size.x = BAR_W
	status_label.text = "✨ 满血复活！"
	_refresh_values()


func _process(delta: float) -> void:
	# 耐力：按住冲刺消耗，松开自动回复
	if sprint_btn.button_pressed and _stam > 0.0:
		_stam = maxf(0.0, _stam - 42.0 * delta)
		_set_frac(_stam_bar, _stam / 100.0)
	elif _stam < 100.0:
		_stam = minf(100.0, _stam + 26.0 * delta)
		_set_frac(_stam_bar, _stam / 100.0)

	# 施法读条
	if _casting:
		_cast_elapsed += delta
		_set_frac(_cast_bar, _cast_elapsed / CAST_TIME)
		_cast_bar["value"].text = "%.0f%%" % (_cast_elapsed / CAST_TIME * 100.0)
		if _cast_elapsed >= CAST_TIME:
			_casting = false
			status_label.text = "🎇 法术施放完成！"
			var tw := create_tween()
			tw.tween_interval(0.8)
			tw.tween_callback(func(): _cast_bar["value"].text = "就绪")


func _refresh_values() -> void:
	_hp_bar["value"].text = "%d/%d" % [_hp, 100]
	_mp_bar["value"].text = "%d/%d" % [_mp, 100]
	_stam_bar["value"].text = "%d/%d" % [_stam, 100]
	_cast_bar["value"].text = "就绪" if not _casting else _cast_bar["value"].text
