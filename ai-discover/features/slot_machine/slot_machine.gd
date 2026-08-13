extends Control
## =============================================================================
## 老虎机 —— 三轴滚动 + 依次停止 + 中奖判定（纯 UI 组件）
## =============================================================================
## 玩法：点击【旋转】消耗 100 币；三个转轴以不同时长滚动并依次停下，
## 中间行三个符号相同 → 中奖 +500 币，中奖行亮起金色辉光 shader。
## 实现要点：
##   · 每个转轴 = 裁剪窗口(Control.clip_contents) + 一列符号(VBox)，
##     用 Tween 滚动 position.y；
##   · 滚完后把滚过的符号整体移到列尾、y 归零——可见内容不变，
##     实现"无缝回卷"，下次旋转继续从 y=0 出发；
##   · 中奖辉光 = 每列中间行后的 glow.gdshader（金色呼吸渐变）。
## =============================================================================

const SYMBOLS: Array[String] = ["🍒", "🍋", "🔔", "💎", "⭐", "🍇", "7️⃣"]
const ROW_H := 96.0            # 单行符号高度
const SYM_COUNT := 12          # 每列符号总数（> 3 才能滚动）
const SPIN_COST := 100
const WIN_PAY := 500
const WIN_CHANCE := 0.3

const GlowShader = preload("res://features/slot_machine/glow.gdshader")

var _credits := 1000
var _spinning := false
var _stopped := 0
var _reels: Array = []         # 每列 {win, box, labels, glow}

@onready var reel_box: HBoxContainer = $Center/VBox/Frame/ReelBox
@onready var result_label: Label = $Center/VBox/ResultLabel
@onready var credits_label: Label = $Center/VBox/CreditsLabel
@onready var spin_btn: Button = $Center/VBox/ButtonsRow/SpinBtn


func _ready() -> void:
	# 机器边框样式（深蓝圆角）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.24)
	sb.border_color = Color(0.45, 0.5, 0.85)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16.0
	sb.content_margin_top = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 16.0
	$Center/VBox/Frame.add_theme_stylebox_override("panel", sb)

	for i in 3:
		_reels.append(_make_reel())
	spin_btn.pressed.connect(_spin)
	_refresh_credits()


## 造一个转轴：裁剪窗口 + 12 个符号 + 中奖辉光层
func _make_reel() -> Dictionary:
	var win := Control.new()
	win.custom_minimum_size = Vector2(110, ROW_H * 3)
	win.clip_contents = true
	reel_box.add_child(win)

	# 中奖辉光（先加入 = 画在符号后面）
	var glow := ColorRect.new()
	glow.size = Vector2(110, ROW_H)
	glow.position = Vector2(0, ROW_H)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = GlowShader
	glow.material = gm
	glow.visible = false
	win.add_child(glow)

	var box := VBoxContainer.new()
	win.add_child(box)

	var labels: Array[Label] = []
	for i in SYM_COUNT:
		var l := Label.new()
		l.custom_minimum_size = Vector2(110, ROW_H)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 44)
		l.text = SYMBOLS[i % SYMBOLS.size()]
		box.add_child(l)
		labels.append(l)

	return {"win": win, "box": box, "labels": labels, "glow": glow}


# ============================================================
#  旋转
# ============================================================
func _spin() -> void:
	if _spinning:
		return
	if _credits < SPIN_COST:
		result_label.text = "💰 余额不足！"
		return
	_credits -= SPIN_COST
	_spinning = true
	_stopped = 0
	spin_btn.disabled = true
	result_label.text = "转动中…"
	for reel in _reels:
		reel["glow"].visible = false

	# 30% 概率中奖：三个转轴的中间行最终都停在同一符号
	var win_sym: String = "" if randf() >= WIN_CHANCE else SYMBOLS.pick_random()
	for i in 3:
		var reel: Dictionary = _reels[i]
		var k := 5 + randi() % 4                     # 滚 5~8 行
		var target: String = SYMBOLS.pick_random() if win_sym == "" else win_sym
		reel["labels"][(1 + k) % SYM_COUNT].text = target   # 落点 = 中间行
		var dur := 0.9 + 0.22 * i                    # 左列先停，右列后停
		var tw := create_tween()
		tw.tween_property(reel["box"], "position:y", -k * ROW_H, dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_callback(_on_reel_stop.bind(i, k))
	_refresh_credits()


func _on_reel_stop(i: int, k: int) -> void:
	var reel: Dictionary = _reels[i]
	# 无缝回卷：滚过去的 k 个符号移到列尾，y 归零（可见内容不变）
	for j in k:
		var l: Label = reel["labels"][0]
		reel["box"].move_child(l, reel["box"].get_child_count() - 1)
		reel["labels"].remove_at(0)
		reel["labels"].append(l)
	reel["box"].position.y = 0

	_stopped += 1
	if _stopped >= 3:
		_spinning = false
		spin_btn.disabled = false
		_evaluate()


func _evaluate() -> void:
	var mid: Array = []
	for reel in _reels:
		mid.append(reel["labels"][1].text)
	if mid[0] == mid[1] and mid[1] == mid[2]:
		_credits += WIN_PAY
		result_label.text = "🎉 中奖！%s %s %s  +%d 币" % [mid[0], mid[1], mid[2], WIN_PAY]
		for reel in _reels:
			reel["glow"].visible = true
	else:
		result_label.text = "😢 未中奖，再来一次！"
	_refresh_credits()


func _refresh_credits() -> void:
	credits_label.text = "💰 余额：%d 币（旋转 -%d · 中奖 +%d）" % [_credits, SPIN_COST, WIN_PAY]
