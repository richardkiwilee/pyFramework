extends Control
## =============================================================================
## Table — 牌桌场景：从统一快照渲染对局，本地/联机共用
## =============================================================================
## 三种模式共用同一渲染管线（state_changed(snapshot)）：
##   - AI：LocalGame（座位1 为玩家，座位0 为 AI）
##   - 本地双人：LocalGame（双人类，底部始终显示当前行动方手牌）
##   - 联机：NetGame（主机座位0 / 客户端座位1，底部显示己方手牌）
## 输入：要牌/停牌按钮（或 H/S 键）、F1 对照表、Esc 返回菜单、悬停牌堆放大镜。
## =============================================================================

const PILE_POS := Vector2(480, 300)      # 牌堆位置（顶牌牌背可见）
const PILE_SIZE := Vector2(100, 140)
const DISCARD_POS := Vector2(320, 300)   # 弃牌堆

var game: LocalGame = null
var net: NetGame = null
var _my_seat: int = 1
var _local_2p := false

var _opp_panel: PanelContainer
var _opp_name: Label
var _opp_status: Label
var _opp_hand: HBoxContainer
var _my_panel: PanelContainer
var _my_name: Label
var _my_status: Label
var _my_hand: HBoxContainer
var _pile: TextureRect
var _discard: TextureRect
var _deck_label: Label
var _pot_label: Label
var _round_label: Label
var _btn_hit: Button
var _btn_stand: Button
var _banner: PanelContainer
var _banner_label: Label
var _banner_btn: Button
var _magnifier: Magnifier
var _sheet: ReferenceSheet
var _empty_tex: ImageTexture
var _active_style: StyleBoxFlat
var _inactive_style: StyleBoxFlat


func _ready() -> void:
	theme = UITheme.app_theme
	_build_layout()
	match GameConfig.mode:
		GameConfig.Mode.LOCAL:
			_local_2p = true
			_my_seat = 1
			_setup_local()
		GameConfig.Mode.HOST:
			_setup_net(NetGame.make_host(GameConfig.port))
		GameConfig.Mode.CLIENT:
			_setup_net(NetGame.make_client(GameConfig.ip, GameConfig.port))
		_:
			_my_seat = 1
			_setup_local()
	_round_label.text = _mode_name() + " · 等待开局……"


func _setup_local() -> void:
	game = LocalGame.new()
	# AI 模式：座位0 是 AI、座位1（玩家）是人；本地双人：双方都是人。
	# ⚠️ 曾写反成 [false, not _local_2p]——玩家被 AI 调度器替打、
	# 真 AI 又不行动（对手永远"行动中"）。
	# ⚠️ 不能用三元表达式给 Array[bool] 属性赋值：三元结果是无类型数组，
	# 运行时被类型校验拒绝；字面量直接赋值才会编译期推断类型。
	if _local_2p:
		game.ai_players = [false, false]
	else:
		game.ai_players = [true, false]
	game.difficulty = GameConfig.difficulty
	add_child(game)
	game.state_changed.connect(_on_state)
	game.start()


func _setup_net(ng: NetGame) -> void:
	net = ng
	_my_seat = net.my_seat
	add_child(net)
	net.state_changed.connect(_on_state)
	net.connected.connect(_on_net_connected)
	net.opponent_left.connect(_on_opponent_left)
	_round_label.text = _mode_name() + " · 等待对方连接……"


func _on_net_connected() -> void:
	_round_label.text = _mode_name() + " · 对局开始"


func _on_opponent_left() -> void:
	_banner_label.text = "对方已离开，你获胜"
	_banner.visible = true
	_banner_btn.visible = true


func _mode_name() -> String:
	match GameConfig.mode:
		GameConfig.Mode.AI:
			return "单机 · 对手 AI（" + ("困难" if GameConfig.difficulty == "hard" else "简单") + "）"
		GameConfig.Mode.LOCAL:
			return "本地双人"
		GameConfig.Mode.HOST:
			return "联机 · 主机（端口 %d）" % GameConfig.port
		GameConfig.Mode.CLIENT:
			return "联机 · 客户端（%s:%d）" % [GameConfig.ip, GameConfig.port]
	return ""


func _on_state(snap: Dictionary) -> void:
	_render(snap)


# ==================================================================
#  布局构建
# ==================================================================

func _build_layout() -> void:
	# 牌桌呢绒底
	var bg := ColorRect.new()
	bg.color = UITheme.FELT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 顶部对手面板
	_opp_panel = _make_side_panel()
	_opp_panel.position = Vector2(190, 16)
	_opp_panel.size = Vector2(900, 250)
	add_child(_opp_panel)
	var opp_box: VBoxContainer = _opp_panel.get_node("VBox")
	_opp_name = UITheme.make_label("对手", 20, UITheme.INK)
	opp_box.add_child(_opp_name)
	_opp_status = UITheme.make_label("", 16, UITheme.INK2)
	opp_box.add_child(_opp_status)
	_opp_hand = _make_hand_row()
	opp_box.add_child(_opp_hand)

	# 底部我方面板（内容含手牌行+按钮行约 274 高，面板给足 280）
	_my_panel = _make_side_panel()
	_my_panel.position = Vector2(190, 440)
	_my_panel.size = Vector2(900, 280)
	add_child(_my_panel)
	var my_box: VBoxContainer = _my_panel.get_node("VBox")
	_my_name = UITheme.make_label("你", 20, UITheme.INK)
	my_box.add_child(_my_name)
	_my_status = UITheme.make_label("", 16, UITheme.INK2)
	my_box.add_child(_my_status)
	_my_hand = _make_hand_row()
	my_box.add_child(_my_hand)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	my_box.add_child(btn_row)
	_btn_hit = UITheme.make_button("要牌 (H)", UITheme.gold_button_style(), 18)
	_btn_hit.custom_minimum_size = Vector2(160, 48)
	_btn_hit.add_theme_stylebox_override("disabled", UITheme.disabled_button_style())
	_btn_hit.pressed.connect(_on_hit)
	btn_row.add_child(_btn_hit)
	_btn_stand = UITheme.make_button("停牌 (S)", UITheme.default_button_style(), 18)
	_btn_stand.custom_minimum_size = Vector2(160, 48)
	_btn_stand.add_theme_stylebox_override("disabled", UITheme.disabled_button_style())
	_btn_stand.pressed.connect(_on_stand)
	btn_row.add_child(_btn_stand)

	# 弃牌堆（顶牌牌背可见，练读背）
	_discard = TextureRect.new()
	_discard.position = DISCARD_POS
	_discard.size = PILE_SIZE  # TextureRect 非容器，须显式设 size（custom_minimum_size 只对容器布局生效）
	_discard.stretch_mode = TextureRect.STRETCH_SCALE
	_discard.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_discard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_discard)

	# 牌堆（顶牌牌背可见——本作核心观察对象）
	_pile = TextureRect.new()
	_pile.position = PILE_POS
	_pile.size = PILE_SIZE
	_pile.stretch_mode = TextureRect.STRETCH_SCALE
	_pile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_pile)
	_pile.mouse_entered.connect(_on_pile_entered)
	_pile.mouse_exited.connect(_on_pile_exited)

	_deck_label = UITheme.make_label("牌堆 52", 15, UITheme.INK2)
	_deck_label.position = Vector2(PILE_POS.x - 20, PILE_POS.y + PILE_SIZE.y + 6)
	_deck_label.size = Vector2(140, 24)
	_deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_deck_label)

	_pot_label = UITheme.make_label("底池 0", 18, UITheme.GOLD_BRIGHT)
	_pot_label.position = Vector2(PILE_POS.x - 70, PILE_POS.y - 34)
	_pot_label.size = Vector2(240, 28)
	_pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pot_label)

	_round_label = UITheme.make_label("", 15, UITheme.INK_DIM)
	_round_label.position = Vector2(1080, 12)
	_round_label.size = Vector2(190, 24)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_round_label)

	# 放大镜（悬停牌堆显示，放在右侧不挡牌桌中央）
	_magnifier = Magnifier.new()
	_magnifier.position = Vector2(660, 60)
	add_child(_magnifier)

	# 结算横幅
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UITheme.panel_style(16))
	_banner.position = Vector2(340, 262)
	_banner.size = Vector2(600, 196)
	_banner.z_index = 50
	_banner.visible = false
	add_child(_banner)
	var banner_box := VBoxContainer.new()
	banner_box.add_theme_constant_override("separation", 12)
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(banner_box)
	_banner_label = UITheme.make_label("", 26, UITheme.GOLD_BRIGHT)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(_banner_label)
	_banner_btn = UITheme.make_button("返回菜单", UITheme.gold_button_style(), 18)
	_banner_btn.custom_minimum_size = Vector2(160, 44)
	_banner_btn.visible = false
	_banner_btn.pressed.connect(_back_to_menu)
	banner_box.add_child(_banner_btn)

	# 对照表（F1，最上层）
	_sheet = ReferenceSheet.new()
	_sheet.z_index = 100
	add_child(_sheet)

	# 返回菜单按钮
	var back := UITheme.make_button("返回菜单 (Esc)", UITheme.default_button_style(), 14)
	back.position = Vector2(12, 12)
	back.pressed.connect(_back_to_menu)
	add_child(back)

	_empty_tex = _make_empty_texture()
	_active_style = UITheme.panel_style(8)
	_active_style.border_color = UITheme.GOLD_BRIGHT
	_active_style.border_width_top = 2
	_active_style.border_width_bottom = 2
	_active_style.border_width_left = 2
	_active_style.border_width_right = 2
	_inactive_style = UITheme.panel_style(8)


func _make_side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(8))
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	return panel


func _make_hand_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 146)
	return row


func _make_empty_texture() -> ImageTexture:
	# 牌堆/弃牌堆为空时的占位
	var img := Image.create(140, 196, false, Image.FORMAT_RGBA8)
	img.fill(Color("0f0b08"))
	Raster.stroke_rect(img, 6, 6, 128, 184, Color("3a2e1e"))
	return ImageTexture.create_from_image(img)


# ==================================================================
#  快照渲染
# ==================================================================

func _render(snap: Dictionary) -> void:
	var round: Dictionary = snap["round"]
	var chips: Array = snap["chips"]
	_pot_label.text = "底池 %d" % int(snap["pot"])
	_round_label.text = _mode_name() + " · 第 %d 回合" % int(snap["round_number"])
	if round.is_empty():
		_update_names(0)
		_update_chips(chips)
		return
	_update_names(int(round["turn"]))
	_update_chips(chips)
	_update_hands(round)
	_update_pile(round)
	_update_discard(round)
	_deck_label.text = "牌堆 %d" % int(round["deck_count"])
	_update_status(round)
	_update_buttons(round, bool(snap["match_over"]))
	_update_banner(snap, round)


## 本地双人模式底部显示当前行动方；其余模式底部固定为己方
func _bottom_seat(turn: int) -> int:
	if _local_2p:
		return turn
	return _my_seat


func _update_names(turn: int) -> void:
	var bottom := _bottom_seat(turn)
	var top := 1 - bottom
	if _local_2p:
		_opp_name.text = "玩家%d" % (top + 1)
		_my_name.text = "玩家%d" % (bottom + 1)
	else:
		_opp_name.text = "你" if top == _my_seat else "对手"
		_my_name.text = "你" if bottom == _my_seat else "对手"


func _update_chips(chips: Array) -> void:
	var top: int = int(chips[1 - _my_seat])
	var mine: int = int(chips[_my_seat])
	_opp_name.text = _opp_name.text + " · 筹码 %d" % top
	_my_name.text = _my_name.text + " · 筹码 %d" % mine


func _update_hands(round: Dictionary) -> void:
	var turn: int = round["turn"]
	var bottom := _bottom_seat(turn)
	var top := 1 - bottom
	var hands: Array = round["hands"]
	_fill_hand(_opp_hand, hands[top])
	_fill_hand(_my_hand, hands[bottom])


func _fill_hand(row: HBoxContainer, cards: Array) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for cdict in cards:
		var c: Dictionary = cdict
		row.add_child(CardView.face(CardData.from_dict(c)))


func _update_pile(round: Dictionary) -> void:
	var top: Dictionary = round["top"]
	if top.is_empty():
		_pile.texture = _empty_tex
	else:
		var card := CardData.from_dict(top)
		_pile.texture = BackDrawer.back_texture(card.suit, card.rank)
		# 放大镜内容随顶牌刷新（显隐由悬停控制）
		if _magnifier.visible:
			_magnifier.show_card(card, GameConfig.observe == GameConfig.Observe.TRAINING)


func _update_discard(round: Dictionary) -> void:
	var discard: Array = round["discard"]
	if discard.is_empty():
		_discard.texture = _empty_tex
	else:
		var last: Dictionary = discard[discard.size() - 1]
		var card := CardData.from_dict(last)
		_discard.texture = BackDrawer.back_texture(card.suit, card.rank)


func _update_status(round: Dictionary) -> void:
	var turn: int = round["turn"]
	var totals: Array = round["totals"]
	var stood: Array = round["stood"]
	var busted: int = round["busted"]
	var bottom := _bottom_seat(turn)
	var top := 1 - bottom
	_opp_status.text = _seat_status(int(totals[top]), bool(stood[top]), busted == top, turn == top)
	_my_status.text = _seat_status(int(totals[bottom]), bool(stood[bottom]), busted == bottom, turn == bottom)
	# 行动方高亮
	_opp_panel.add_theme_stylebox_override("panel", _active_style if turn == top else _inactive_style)
	_my_panel.add_theme_stylebox_override("panel", _active_style if turn == bottom else _inactive_style)


func _seat_status(total: int, is_stood: bool, is_busted: bool, is_turn: bool) -> String:
	if is_busted:
		return "爆牌！"
	var s := "点数 %d" % total
	if is_stood:
		s += " · 已停牌"
	if is_turn:
		s += " · ▶ 行动中"
	return s


func _update_buttons(round: Dictionary, match_over: bool) -> void:
	var phase: int = round["phase"]
	var turn: int = round["turn"]
	var bottom := _bottom_seat(turn)
	var hands: Array = round["hands"]
	var bottom_hand: Array = hands[bottom]
	var can := not match_over and phase == RoundEngine.Phase.TURN and turn == bottom \
		and not bool(round["stood"][turn])
	_btn_hit.disabled = not can
	_btn_stand.disabled = not can or bottom_hand.is_empty()


func _update_banner(snap: Dictionary, round: Dictionary) -> void:
	if bool(snap["match_over"]):
		var winner: int = snap["match_winner"]
		var text := "对局结束！"
		if _local_2p:
			text = "对局结束！玩家%d 获胜" % (winner + 1)
		elif winner == _my_seat:
			text = "对局结束！你赢了"
		else:
			text = "对局结束！你输了"
		_banner_label.text = text
		_banner.visible = true
		_banner_btn.visible = true
		return
	var phase: int = round["phase"]
	if phase != RoundEngine.Phase.OVER:
		_banner.visible = false
		return
	var winner: int = round["winner"]
	var kind: int = round["result_kind"]
	var detail := ""
	match kind:
		RoundEngine.ResultKind.BUST:
			detail = "（对方爆牌）" if winner == _bottom_seat(int(round["turn"])) else "（爆牌）"
		RoundEngine.ResultKind.BLACKJACK:
			detail = " · 黑杰克！"
		RoundEngine.ResultKind.POINTS:
			detail = " · 点数领先"
		RoundEngine.ResultKind.PUSH:
			detail = ""
	var text := ""
	if winner == -1:
		text = "平局（push）"
	elif winner == _bottom_seat(int(round["turn"])):
		text = "本回合获胜" + detail
	else:
		text = "本回合落败" + detail
	_banner_label.text = text
	_banner.visible = true
	_banner_btn.visible = false


# ==================================================================
#  输入
# ==================================================================

func _on_hit() -> void:
	_submit("hit")


func _on_stand() -> void:
	_submit("stand")


func _submit(action: String) -> void:
	if net != null:
		net.submit_action(_my_seat, action)
	elif game != null:
		game.submit_action(_bottom_seat(_current_turn()), action)


func _current_turn() -> int:
	if game != null and game.ms != null and game.ms.round != null:
		return game.ms.round.turn
	return 0


func _on_pile_entered() -> void:
	_refresh_magnifier()


func _on_pile_exited() -> void:
	_magnifier.visible = false


func _refresh_magnifier() -> void:
	var card: CardData = null
	if game != null and game.ms != null:
		card = game.ms.deck.peek_top()
	elif net != null and net.last_snap.has("round"):
		var top: Dictionary = net.last_snap["round"].get("top", {})
		if not top.is_empty():
			card = CardData.from_dict(top)
	_magnifier.show_card(card, GameConfig.observe == GameConfig.Observe.TRAINING)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_H:
					if not _btn_hit.disabled:
						_on_hit()
				KEY_S:
					if not _btn_stand.disabled:
						_on_stand()
				KEY_F1:
					_toggle_sheet()
				KEY_ESCAPE:
					if _sheet.visible:
						_toggle_sheet()
					else:
						_back_to_menu()


func _toggle_sheet() -> void:
	if GameConfig.observe == GameConfig.Observe.HELL:
		return  # 地狱模式没有对照表
	_sheet.visible = not _sheet.visible


func _back_to_menu() -> void:
	if net != null:
		net.shutdown()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
