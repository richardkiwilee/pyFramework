extends Node2D
## =============================================================================
## 命中反馈 —— 点击训练木桩，体验完整的"打击感"组件链
## =============================================================================
## 每次命中同时触发五件事（都是可复用的打击感手法）：
##   1. 屏幕震动：World 容器随机偏移、强度随时间衰减；
##   2. 命中白闪：全屏白色 ColorRect 快速淡出；
##   3. 伤害飘字：数字向上飘 + 放大弹出 + 淡出（20% 概率暴击金字）；
##   4. 粒子火花：命中点一次性 CPUParticles2D；
##   5. 连击计数：1.2 秒内连续命中累加，木桩受击变红。
## =============================================================================

const DUMMY_CENTER := Vector2(0, -30)
const DUMMY_RADIUS := 120.0
const COMBO_WINDOW := 1.2

var _shake_time := 0.0
var _shake_strength := 0.0
var _combo := 0
var _combo_timer := 0.0

@onready var world: Node2D = $World
@onready var dummy: Node2D = $World/Dummy
@onready var flash: ColorRect = $CanvasLayer/Flash
@onready var combo_label: Label = $CanvasLayer/ComboLabel
@onready var sparks: CPUParticles2D = $World/Sparks


func _ready() -> void:
	sparks.emitting = false
	combo_label.visible = false


func _process(delta: float) -> void:
	# 屏幕震动衰减
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := _shake_time / 0.3 * _shake_strength
		world.position = Vector2(randf_range(-k, k), randf_range(-k, k))
	else:
		world.position = Vector2.ZERO
	# 连击超时重置
	if _combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
			combo_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 鼠标是屏幕坐标，木桩中心 = World 原点 + 偏移
		if event.position.distance_to(world.position + DUMMY_CENTER) < DUMMY_RADIUS:
			_hit(event.position)
			get_viewport().set_input_as_handled()


## 一次完整命中（逻辑层，便于测试与复用）
func _hit(at: Vector2) -> void:
	# 1. 震动
	_shake_time = 0.3
	_shake_strength = 9.0
	# 2. 白闪
	flash.color.a = 0.28
	var ft := create_tween()
	ft.tween_property(flash, "color:a", 0.0, 0.14)
	# 3. 木桩受击变红
	dummy.modulate = Color(1.0, 0.35, 0.35)
	var dt := create_tween()
	dt.tween_property(dummy, "modulate", Color.WHITE, 0.25)
	# 4. 伤害飘字
	var dmg := 20 + randi() % 60
	var crit := randf() < 0.2
	if crit:
		dmg *= 2
	_spawn_damage_number(at, dmg, crit)
	# 5. 粒子（屏幕坐标 → World 局部坐标）
	sparks.position = world.to_local(at)
	sparks.restart()
	# 6. 连击
	_combo += 1
	_combo_timer = COMBO_WINDOW
	combo_label.visible = true
	combo_label.text = "连击 x%d" % _combo
	combo_label.scale = Vector2(1.25, 1.25)
	var ct := create_tween()
	ct.tween_property(combo_label, "scale", Vector2.ONE, 0.18)


func _spawn_damage_number(at: Vector2, dmg: int, crit: bool) -> void:
	var l := Label.new()
	l.text = str(dmg)
	l.add_theme_font_size_override("font_size", 30 if not crit else 40)
	l.add_theme_color_override("font_color", Color(1, 1, 1) if not crit else Color(1.0, 0.8, 0.2))
	l.position = world.to_local(at) + Vector2(-14, -60)
	world.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 55.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tw.chain().tween_callback(l.queue_free)
