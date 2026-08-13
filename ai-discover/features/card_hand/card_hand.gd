extends Control
## =============================================================================
## 卡牌手牌 —— 卡牌游戏核心 UI：扇形手牌 + 悬停抬升 + 打出补牌
## =============================================================================
## · 手牌扇形排布（弧线 + 微旋转），悬停的卡抬升放大并置于最前；
## · 点击打出：卡飞向战场区变成小卡，同时从牌库补一张新手牌
##   （新卡从右上角牌库滑进手牌，有入手指向动画）；
## · 牌库/弃牌计数 + 【重置】按钮。
## 卡面全部程序化生成（无美术资源）：费用圆徽 + 卡名 + 表情 + 描述。
## =============================================================================

const CARD_W := 128.0
const CARD_H := 176.0
const HAND_CENTER_X := 640.0
const HAND_Y := 600.0
const FAN_SPREAD := 102.0
const MAX_HAND := 7

const CARD_POOL: Array[Dictionary] = [
	{"name": "火球术", "cost": 3, "emoji": "🔥", "color": Color(0.85, 0.30, 0.20), "desc": "造成 6 点伤害"},
	{"name": "寒冰箭", "cost": 2, "emoji": "❄️", "color": Color(0.25, 0.55, 0.95), "desc": "冻结一个敌人"},
	{"name": "治疗术", "cost": 2, "emoji": "💚", "color": Color(0.30, 0.75, 0.40), "desc": "回复 5 点生命"},
	{"name": "召唤狼", "cost": 4, "emoji": "🐺", "color": Color(0.60, 0.45, 0.25), "desc": "召唤 2/2 狼"},
	{"name": "闪电链", "cost": 3, "emoji": "⚡", "color": Color(0.70, 0.60, 0.15), "desc": "弹跳 3 个目标"},
	{"name": "奥术智慧", "cost": 3, "emoji": "🔮", "color": Color(0.55, 0.35, 0.85), "desc": "抽 2 张牌"},
	{"name": "神圣护盾", "cost": 1, "emoji": "🛡️", "color": Color(0.80, 0.75, 0.55), "desc": "抵挡下次攻击"},
	{"name": "疾风步", "cost": 1, "emoji": "💨", "color": Color(0.45, 0.70, 0.80), "desc": "本回合+2 速度"},
]

var _hand: Array = []          # {card: Control, data: Dictionary}
var _played: Array = []        # 战场上的小卡
var _deck := 15
var _hovered := -1

@onready var deck_label: Label = $CanvasLayer/TopBar/DeckLabel
@onready var play_label: Label = $CanvasLayer/TopBar/PlayLabel


func _ready() -> void:
	$CanvasLayer/TopBar/ResetBtn.pressed.connect(_reset)
	# 起手 5 张
	for i in 5:
		_draw_card(true)


## 造一张卡（程序化卡面）
func _make_card(data: Dictionary) -> Control:
	var card := Control.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := ColorRect.new()
	bg.size = Vector2(CARD_W, CARD_H)
	bg.color = Color(0.09, 0.10, 0.15)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	# 彩色边框（类型色）
	var border := ColorRect.new()
	border.size = Vector2(CARD_W, CARD_H)
	border.color = data["color"]
	border.color.a = 0.35
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(border)

	var box := VBoxContainer.new()
	box.position = Vector2(10, 10)
	box.size = Vector2(CARD_W - 20, CARD_H - 20)
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	# 费用圆徽
	var cost := Label.new()
	cost.text = str(data["cost"])
	cost.add_theme_font_size_override("font_size", 20)
	cost.add_theme_color_override("font_color", Color(0.15, 0.15, 0.2))
	var cost_sb := StyleBoxFlat.new()
	cost_sb.bg_color = Color(0.95, 0.9, 0.7)
	cost_sb.set_corner_radius_all(14)
	cost.add_theme_stylebox_override("normal", cost_sb)
	cost.custom_minimum_size = Vector2(30, 30)
	box.add_child(cost)

	# 表情主图
	var art := Label.new()
	art.text = data["emoji"]
	art.add_theme_font_size_override("font_size", 44)
	art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(art)

	# 卡名
	var name_label := Label.new()
	name_label.text = data["name"]
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	# 描述
	var desc := Label.new()
	desc.text = data["desc"]
	desc.add_theme_font_size_override("font_size", 11)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	# 交互
	card.mouse_entered.connect(_on_card_enter.bind(card))
	card.mouse_exited.connect(_on_card_exit.bind(card))
	card.gui_input.connect(_on_card_input.bind(card))
	add_child(card)
	return card


## 抽一张牌加入手牌（instant = 直接落位，否则从牌库滑入）
func _draw_card(instant: bool) -> void:
	if _deck <= 0 or _hand.size() >= MAX_HAND:
		return
	_deck -= 1
	var data: Dictionary = CARD_POOL[randi() % CARD_POOL.size()]
	var card := _make_card(data)
	card.pivot_offset = Vector2(CARD_W / 2.0, CARD_H)
	card.position = Vector2(1150, 40)
	card.scale = Vector2(0.4, 0.4)
	card.rotation = -0.5
	_hand.append({"card": card, "data": data})
	if instant:
		_arrange_hand(true)
	else:
		_arrange_hand(false)
	_update_labels()


## 悬停 / 移出
func _on_card_enter(card: Control) -> void:
	_hovered = _index_of(card)
	_arrange_hand(false)


func _on_card_exit(_card: Control) -> void:
	_hovered = -1
	_arrange_hand(false)


func _on_card_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_card(_index_of(card))


func _index_of(card: Control) -> int:
	for i in _hand.size():
		if _hand[i]["card"] == card:
			return i
	return -1


## 扇形排布（instant = 瞬间到位，否则补间动画）
func _arrange_hand(instant: bool) -> void:
	var n := _hand.size()
	for i in n:
		var entry: Dictionary = _hand[i]
		var card: Control = entry["card"]
		var t := float(i) / float(maxi(1, n - 1)) - 0.5      # -0.5..0.5
		var target := Vector2(HAND_CENTER_X + t * FAN_SPREAD * (n - 1), HAND_Y + absf(t) * 150.0)
		var rot := t * 0.22
		if i == _hovered:
			target.y -= 70.0
			rot = 0.0
		card.z_index = 10 + (100 if i == _hovered else i)
		if instant:
			card.position = target
			card.rotation = rot
			card.scale = Vector2.ONE * (1.18 if i == _hovered else 1.0)
		else:
			var tw := card.create_tween().set_parallel(true)
			tw.tween_property(card, "position", target, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "rotation", rot, 0.22)
			tw.tween_property(card, "scale", Vector2.ONE * (1.18 if i == _hovered else 1.0), 0.22)


## 打出：飞到战场 → 变迷你卡 → 补牌
func _play_card(idx: int) -> void:
	if idx < 0:
		return
	var entry: Dictionary = _hand[idx]
	_hand.remove_at(idx)
	var card: Control = entry["card"]
	card.z_index = 500
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var played_pos := Vector2(340 + _played.size() % 5 * 150, 200 + (_played.size() / 5) * 170)
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "position", played_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "rotation", 0.0, 0.35)
	tw.tween_property(card, "scale", Vector2(0.72, 0.72), 0.35)
	tw.chain().tween_callback(func() -> void:
		_played.append(card)
		_update_labels())

	_hovered = -1
	_arrange_hand(false)
	_draw_card(false)   # 补一张新手牌


func _reset() -> void:
	for e in _hand:
		e["card"].queue_free()
	for c in _played:
		c.queue_free()
	_hand.clear()
	_played.clear()
	_deck = 15
	_hovered = -1
	for i in 5:
		_draw_card(true)
	_update_labels()


func _update_labels() -> void:
	deck_label.text = "🂠 牌库：%d" % _deck
	play_label.text = "🃏 已打出：%d" % _played.size()
