extends Control
## poker-back 主场景:左侧抽牌堆(牌背朝上),右侧开牌堆(牌面朝上)。
## 在抽牌堆按住向右拖 = 顶部牌翻面飞向开牌堆;在开牌堆按住向左拖 = 顶部牌盖回抽牌堆。
## 右下角按钮重新洗牌。

const CardScript = preload("res://card.gd")
const PileScript = preload("res://pile_area.gd")

const CARD_SIZE := Vector2(100, 150)
const DRAW_CENTER := Vector2(330, 375)
const OPEN_CENTER := Vector2(950, 375)
## 拖动多少像素完成整段翻牌(0.5 即翻到侧立)
const FLIP_DIST := 380.0

var draw_pile: PileArea
var open_pile: PileArea
var draw_cards: Array = []
var open_cards: Array = []
var draw_count_label: Label
var open_count_label: Label

var flying: PokerCard = null
var flying_from := Vector2.ZERO
var flying_to := Vector2.ZERO
var flying_dir := 1.0
var flight_progress := 0.0
var dragging := false
var animating := false

func _ready() -> void:
	_build_ui()
	_build_deck()

func _draw() -> void:
	# 深色内框,给绿色绒布一点纵深
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0, 0, 0, 0.22), false, 30.0)
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0, 0, 0, 0.14), false, 18.0)

func _process(_delta: float) -> void:
	# 鼠标在窗口外松开时,GUI 可能收不到 release 事件,这里兜底
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_drag(flight_progress >= 0.5)

# ---------- UI ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color8(23, 84, 41)
	add_child(bg)
	_add_filling(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cjk := SystemFont.new()
	cjk.font_names = PackedStringArray(
			["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "PingFang SC"])

	var title := Label.new()
	title.text = "POKER BACK"
	title.add_theme_font_override("font", cjk)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color8(255, 215, 106))
	title.position = Vector2(0, 26)
	title.size = Vector2(1280, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var sub := Label.new()
	sub.text = "抽牌堆上向右拖动 → 翻牌　·　开牌堆上向左拖动 → 盖回"
	sub.add_theme_font_override("font", cjk)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.81, 0.91, 0.84, 0.9))
	sub.position = Vector2(0, 86)
	sub.size = Vector2(1280, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	draw_pile = PileScript.new()
	draw_pile.position = DRAW_CENTER - CARD_SIZE / 2.0
	draw_pile.size = CARD_SIZE
	draw_pile.interaction.connect(_on_pile_event.bind(draw_pile))
	add_child(draw_pile)

	open_pile = PileScript.new()
	open_pile.position = OPEN_CENTER - CARD_SIZE / 2.0
	open_pile.size = CARD_SIZE
	open_pile.interaction.connect(_on_pile_event.bind(open_pile))
	add_child(open_pile)

	_name_label("抽牌堆", Vector2(230, 226), cjk)
	_name_label("开牌堆", Vector2(850, 226), cjk)
	draw_count_label = _count_label(Vector2(230, 260), cjk)
	open_count_label = _count_label(Vector2(850, 260), cjk)

	var legend := Label.new()
	legend.text = "牌背几何字符 + 副符号 = 点数(资源缺失时回退编织记号牌背)"
	legend.add_theme_font_override("font", cjk)
	legend.add_theme_font_size_override("font_size", 13)
	legend.add_theme_color_override("font_color", Color(0.75, 0.86, 0.78, 0.8))
	legend.position = Vector2(24, 680)
	legend.size = Vector2(500, 22)
	add_child(legend)

	var btn := Button.new()
	btn.text = "重新洗牌"
	btn.position = Vector2(1090, 630)
	btn.size = Vector2(150, 50)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_override("font", cjk)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color8(233, 237, 245))
	btn.add_theme_stylebox_override("normal", _btn_box(Color8(43, 47, 58), Color8(69, 76, 92)))
	btn.add_theme_stylebox_override("hover", _btn_box(Color8(58, 64, 80), Color8(84, 92, 110)))
	btn.add_theme_stylebox_override("pressed", _btn_box(Color8(35, 38, 47), Color8(60, 66, 80)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_reshuffle)
	add_child(btn)

func _add_filling(child: Control) -> void:
	child.anchor_right = 1.0
	child.anchor_bottom = 1.0
	child.offset_right = 0.0
	child.offset_bottom = 0.0

func _name_label(text: String, pos: Vector2, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color8(245, 248, 246))
	l.position = pos
	l.size = Vector2(200, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l

func _count_label(pos: Vector2, font: Font) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color8(190, 220, 198))
	l.position = pos
	l.size = Vector2(200, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l

func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

# ---------- 牌堆 ----------

func _build_deck() -> void:
	for c in draw_cards:
		c.queue_free()
	for c in open_cards:
		c.queue_free()
	draw_cards.clear()
	open_cards.clear()
	var deck: Array = []
	for s in 4:
		for r in 13:
			deck.append({"rank": r + 1, "suit": s})
	for i in range(deck.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp: Dictionary = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	for d in deck:
		var card: PokerCard = CardScript.new()
		var rank_v: int = d["rank"]
		var suit_v: int = d["suit"]
		card.setup(rank_v, suit_v)
		card.flip_progress = 0.0
		draw_pile.add_child(card)
		draw_cards.append(card)
	_relayout()
	_update_counts()

func _relayout() -> void:
	for i in draw_cards.size():
		var c: PokerCard = draw_cards[i]
		c.position = Vector2(i * 0.6, i * 0.6)
	for i in open_cards.size():
		var c: PokerCard = open_cards[i]
		c.position = Vector2(0, minf(i, 8) * 4.0)
	draw_pile.stack_count = draw_cards.size()
	open_pile.stack_count = open_cards.size()

func _update_counts() -> void:
	draw_count_label.text = "剩余 %d 张" % draw_cards.size()
	open_count_label.text = "已开 %d 张" % open_cards.size()

func _top_offset(pile: PileArea, cards: Array) -> Vector2:
	if pile == draw_pile:
		var n := cards.size()
		return Vector2(n * 0.6, n * 0.6)
	return Vector2(0, minf(cards.size(), 8) * 4.0)

# ---------- 拖动交互 ----------

func _on_pile_event(event: InputEvent, pile: PileArea) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if not animating and not dragging:
				_begin_drag(pile)
		else:
			_end_drag(flight_progress >= 0.5)
		return
	var mm := event as InputEventMouseMotion
	if mm != null and dragging:
		_update_flight(mm.global_position)

func _begin_drag(pile: PileArea) -> void:
	var from_cards: Array = draw_cards if pile == draw_pile else open_cards
	if from_cards.is_empty():
		return
	var to_cards: Array = open_cards if pile == draw_pile else draw_cards
	var to_pile: PileArea = open_pile if pile == draw_pile else draw_pile
	flying_dir = 1.0 if pile == draw_pile else -1.0
	var card: PokerCard = from_cards.pop_back()
	flying_from = pile.position + card.position + CARD_SIZE / 2.0
	flying_to = to_pile.position + CARD_SIZE / 2.0 + _top_offset(to_pile, to_cards)
	flying = card
	card.get_parent().remove_child(card)
	add_child(card)
	card.position = flying_from - CARD_SIZE / 2.0
	card.flip_progress = 0.0 if flying_dir > 0.0 else 1.0
	card.show_shadow = true
	flight_progress = 0.0
	dragging = true
	_relayout()
	_update_counts()

func _update_flight(mouse: Vector2) -> void:
	if flying == null:
		return
	var dist := mouse.x - flying_from.x if flying_dir > 0.0 else flying_from.x - mouse.x
	flight_progress = clampf(dist / FLIP_DIST, 0.0, 1.0)
	var p := flight_progress
	var center := flying_from.lerp(flying_to, p)
	center.y -= sin(p * PI) * 46.0
	flying.position = center - CARD_SIZE / 2.0
	flying.flip_progress = p if flying_dir > 0.0 else 1.0 - p
	flying.rotation = flying_dir * 0.14 * p

func _end_drag(commit: bool) -> void:
	if not dragging or flying == null:
		return
	dragging = false
	animating = true
	var target_flip := 1.0 if commit else 0.0
	var target_pos := flying_to - CARD_SIZE / 2.0 if commit else flying_from - CARD_SIZE / 2.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(flying, "flip_progress", target_flip, 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(flying, "position", target_pos, 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(flying, "rotation", 0.0, 0.3)
	await t.finished
	_finalize_flight(commit)

func _finalize_flight(commit: bool) -> void:
	if flying == null:
		return
	var card: PokerCard = flying
	flying = null
	card.show_shadow = false
	var dest_is_open: bool = (flying_dir > 0.0) == commit
	var pile: PileArea = open_pile if dest_is_open else draw_pile
	var cards: Array = open_cards if dest_is_open else draw_cards
	card.get_parent().remove_child(card)
	pile.add_child(card)
	cards.append(card)
	card.flip_progress = 1.0 if dest_is_open else 0.0
	_relayout()
	_update_counts()
	animating = false

func _reshuffle() -> void:
	if dragging or animating:
		return
	_build_deck()
