extends Control
## =============================================================================
## DiplomacyScreen — 4X 外交系统雏形主界面（纯代码构建 UI）
## =============================================================================
## 布局（左:中:右 = 1:2:1，中间上下 = 3:2）：
##   +-------------+---------------------------+-------------+
##   | 左          | 中上：关系面板              | 右          |
##   |  我方资源    |   状态 / 关系条(-100..+100)|  4 个 AI    |
##   |  军力 SpinBox|   军力对比 / 规则提示       |  选择卡片    |
##   |  行动按钮    | 中下：交易面板              |  (点击切换)  |
##   |  结束回合    |   双方资源 SpinBox + 评估   |             |
##   +-------------+---------------------------+-------------+
##
## 规则口径（原型，与 AIState 注释一致）：
##   · 关系状态由 (交战标记, 关系值) 推导：交战 > 敌视(<0) > 和平(0..40)
##     > 友好(40..60) > 同盟(>=60)
##   · 宣布友谊(+40 可用)/同盟(+60 可用)：一次性 +10 关系
##   · 逼迫：军力 > 对方 3 倍 且 和平或以上 → 按固定量索取，关系 -20
##   · 宣战/和平同一按钮：宣战关系 -60（不足 -40 压到 -40）
##   · 结束回合：所有 AI 关系向 0 靠拢 0.1
## =============================================================================

# ------------------------------------------------------------------ 常量
const RES: Array[String] = ["food", "gold", "wood", "horse"]
const RES_ZH: Dictionary = {"food": "粮食", "gold": "金币", "wood": "木头", "horse": "马"}
const RES_COLOR: Dictionary = {
	"food": Color("7ec96e"),
	"gold": Color("e8c96a"),
	"wood": Color("e09a5b"),
	"horse": Color("c98a6e"),
}
const STATE_COLOR: Dictionary = {
	"交战": Color("e06c5b"), "敌视": Color("e09a5b"),
	"和平": Color("8f8c9e"), "友好": Color("7ec96e"), "同盟": Color("e8c96a"),
}

# 调色板
const BG := Color("14161c")
const PANEL := Color("1e212a")
const PANEL2 := Color("262a36")
const INK := Color("e6e4df")
const DIM := Color("8f8c9e")
const GOLD := Color("e8c96a")
const RED := Color("e06c5b")
const GREEN := Color("7ec96e")

# ------------------------------------------------------------------ 运行时状态
var turn: int = 1
var my_res: Dictionary = {"food": 50, "gold": 50, "wood": 30, "horse": 15}
var my_military: int = 100
var ais: Array[AIState] = []
var sel_idx: int = 0

# ------------------------------------------------------------------ 节点引用
var turn_label: Label
var res_amount_labels: Dictionary = {}   # 资源名 -> Label
var military_spin: SpinBox
var left_hint: Label
var btn_friendship: Button
var btn_alliance: Button
var btn_coerce: Button
var btn_war: Button
var btn_turn: Button

var name_label: Label
var state_label: Label
var rel_label: Label
var rel_bar: RelBar
var mil_info_label: Label

var give_spins: Dictionary = {}        # 资源名 -> SpinBox（我方给出）
var ask_spins: Dictionary = {}         # 资源名 -> SpinBox（对方给出）
var give_stock_labels: Dictionary = {} # 资源名 -> Label
var ask_stock_labels: Dictionary = {}
var eval_label: Label

var cards: Array[PanelContainer] = []
var card_names: Array[Label] = []
var card_states: Array[Label] = []
var card_rels: Array[Label] = []
var card_mils: Array[Label] = []
var card_ress: Array[Label] = []
var card_exps: Array[Label] = []


# ==================================================================
#  _ready() — 构建 UI
# ==================================================================

func _ready() -> void:
	_setup_font()
	ais = AIState.build_default_ais()

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	_build_left(hbox)
	_build_middle(hbox)
	_build_right(hbox)

	select_ai(0)


## 中文渲染：微软雅黑 SystemFont（默认字体不含 CJK 字形）
func _setup_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"])
	add_theme_font_override("font", f)


# ==================================================================
#  样式工具
# ==================================================================

## 面板底色 StyleBox（自带内容边距）
func _panel_style(bg: Color, border: Color = PANEL2, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = bw
	sb.border_width_right = bw
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


## 按钮/输入框底色 StyleBox
func _box_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _mk_button(text: String, on_pressed: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	if accent:
		b.add_theme_color_override("font_color", Color("2c2412"))
		b.add_theme_stylebox_override("normal", _box_style(GOLD))
		b.add_theme_stylebox_override("hover", _box_style(Color("f2d98f")))
		b.add_theme_stylebox_override("pressed", _box_style(Color("d9b95a")))
	else:
		b.add_theme_color_override("font_color", INK)
		b.add_theme_stylebox_override("normal", _box_style(PANEL2))
		b.add_theme_stylebox_override("hover", _box_style(Color("303549")))
		b.add_theme_stylebox_override("pressed", _box_style(Color("1b1e27")))
	b.pressed.connect(on_pressed)
	return b


func _mk_spin(value: int, maxv: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = maxv
	s.step = 1
	s.value = value
	s.custom_minimum_size.x = 76
	s.add_theme_stylebox_override("normal", _box_style(PANEL2))
	s.add_theme_stylebox_override("hover", _box_style(Color("303549")))
	s.add_theme_stylebox_override("focus", _box_style(PANEL2))
	s.add_theme_color_override("font_color", INK)
	s.add_theme_font_size_override("font_size", 13)
	return s


func _hs_line() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _box_style(PANEL2))
	return sep


# ==================================================================
#  左面板：我方资源 + 军力 + 行动
# ==================================================================

func _build_left(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL))
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	panel.add_child(v)

	turn_label = _mk_label("我方 · 第 1 回合", 15, GOLD)
	v.add_child(turn_label)
	v.add_child(_mk_label("资源库存", 11, DIM))

	for res: String in RES:
		var row := HBoxContainer.new()
		var name_l := _mk_label(_res_zh(res), 13, Color(RES_COLOR.get(res, INK)))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var amt := _mk_label("× 0", 13, INK)
		row.add_child(amt)
		res_amount_labels[res] = amt
		v.add_child(row)

	v.add_child(_hs_line())

	# 军力：可编辑数字框（简化的军力模型）
	var mil_row := HBoxContainer.new()
	mil_row.add_theme_constant_override("separation", 8)
	var mil_l := _mk_label("军力（可编辑）", 13, INK)
	mil_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mil_row.add_child(mil_l)
	military_spin = _mk_spin(my_military, 9999)
	military_spin.value_changed.connect(func(v: float): my_military = int(v))
	mil_row.add_child(military_spin)
	v.add_child(mil_row)

	v.add_child(_hs_line())

	v.add_child(_mk_label("行动", 11, DIM))
	btn_friendship = _mk_button("宣布友谊（需关系 +40）", _on_declare_friendship)
	v.add_child(btn_friendship)
	btn_alliance = _mk_button("宣布同盟（需关系 +60）", _on_declare_alliance)
	v.add_child(btn_alliance)
	btn_coerce = _mk_button("逼迫 · 索取物资", _on_coerce)
	v.add_child(btn_coerce)
	btn_war = _mk_button("宣战", _on_war_peace)
	v.add_child(btn_war)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	left_hint = _mk_label("", 10, DIM)
	left_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(left_hint)

	btn_turn = _mk_button("结束回合", _on_end_turn, true)
	v.add_child(btn_turn)


# ==================================================================
#  中面板：上(3/5)关系 + 下(2/5)交易
# ==================================================================

func _build_middle(parent: HBoxContainer) -> void:
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.size_flags_stretch_ratio = 2.0
	mid.add_theme_constant_override("separation", 8)
	parent.add_child(mid)

	var top := PanelContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.size_flags_stretch_ratio = 3.0
	top.add_theme_stylebox_override("panel", _panel_style(PANEL))
	mid.add_child(top)
	_build_mid_top(top)

	var bottom := PanelContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.size_flags_stretch_ratio = 2.0
	bottom.add_theme_stylebox_override("panel", _panel_style(PANEL))
	mid.add_child(bottom)
	_build_mid_bottom(bottom)


## 中上：与选中 AI 的关系展示
func _build_mid_top(panel: PanelContainer) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	v.add_child(_mk_label("外交关系", 11, DIM))

	name_label = _mk_label("—", 20, INK)
	v.add_child(name_label)

	state_label = _mk_label("—", 26, DIM)
	v.add_child(state_label)

	var rel_row := HBoxContainer.new()
	rel_row.add_theme_constant_override("separation", 10)
	rel_label = _mk_label("+0.0", 18, INK)
	rel_row.add_child(rel_label)
	rel_bar = RelBar.new()
	rel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rel_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rel_row.add_child(rel_bar)
	v.add_child(rel_row)

	# -100 / 0 / +100 刻度
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 0)
	var s1 := _mk_label("-100", 10, DIM)
	s1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(s1)
	var s2 := _mk_label("0", 10, DIM)
	s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scale_row.add_child(s2)
	var s3 := _mk_label("+100", 10, DIM)
	s3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_row.add_child(s3)
	v.add_child(scale_row)

	mil_info_label = _mk_label("", 11, DIM)
	v.add_child(mil_info_label)

	var rule := _mk_label(
		"友好 +40 · 同盟 +60 · 逼迫需和平以上且军力超 3 倍 · 宣战 -60（至少 -40）· 每回合关系向 0 靠拢 0.1",
		10, DIM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rule)


## 中下：交易编辑（双方资源 SpinBox + 实时评估 + 确认）
func _build_mid_bottom(panel: PanelContainer) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var title_row := HBoxContainer.new()
	title_row.add_child(_mk_label("交易", 11, DIM))
	var tip := _mk_label("选取双方资源，AI 按其「预期」计分：>=0 接受，<0 拒绝", 10, DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(tip)
	v.add_child(title_row)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# --- 我方给出列 ---
	var give_col := VBoxContainer.new()
	give_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_col.add_theme_constant_override("separation", 4)
	give_col.add_child(_mk_label("我方给出（+分）", 12, GREEN))
	for res: String in RES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _mk_label("", 11, INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		give_stock_labels[res] = info
		var spin := _mk_spin(0, 999)
		spin.value_changed.connect(_on_trade_changed)
		row.add_child(spin)
		give_spins[res] = spin
		give_col.add_child(row)
	cols.add_child(give_col)

	# --- 对方给出列 ---
	var ask_col := VBoxContainer.new()
	ask_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ask_col.add_theme_constant_override("separation", 4)
	ask_col.add_child(_mk_label("对方给出（-分）", 12, RED))
	for res: String in RES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _mk_label("", 11, INK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		ask_stock_labels[res] = info
		var spin := _mk_spin(0, 999)
		spin.value_changed.connect(_on_trade_changed)
		row.add_child(spin)
		ask_spins[res] = spin
		ask_col.add_child(row)
	cols.add_child(ask_col)

	v.add_child(cols)

	var eval_row := HBoxContainer.new()
	eval_row.add_theme_constant_override("separation", 10)
	eval_label = _mk_label("", 12, DIM)
	eval_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eval_row.add_child(eval_label)
	eval_row.add_child(_mk_button("确认交易", _on_trade_confirm, true))
	v.add_child(eval_row)


# ==================================================================
#  右面板：AI 选择卡片
# ==================================================================

func _build_right(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", _panel_style(PANEL))
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_mk_label("外交对象（点击选择）", 15, GOLD))

	for i in range(ais.size()):
		var ai: AIState = ais[i]
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_theme_stylebox_override("panel", _panel_style(PANEL2))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.add_child(cv)

		var name_l := _mk_label(ai.display_name, 14, INK)
		cv.add_child(name_l)
		var state_l := _mk_label("", 12, DIM)
		cv.add_child(state_l)
		var rel_l := _mk_label("", 11, DIM)
		cv.add_child(rel_l)
		var mil_l := _mk_label("", 11, DIM)
		cv.add_child(mil_l)
		var res_l := _mk_label("", 10, DIM)
		cv.add_child(res_l)
		var exp_l := _mk_label("", 10, DIM)
		cv.add_child(exp_l)

		card_names.append(name_l)
		card_states.append(state_l)
		card_rels.append(rel_l)
		card_mils.append(mil_l)
		card_ress.append(res_l)
		card_exps.append(exp_l)
		cards.append(card)

		var idx := i  # 闭包安全：复制循环变量
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				select_ai(idx)
		)
		v.add_child(card)


# ==================================================================
#  工具
# ==================================================================

func _sel() -> AIState:
	return ais[sel_idx]


func _res_zh(res: String) -> String:
	return str(RES_ZH.get(res, res))


func _fmt_res(d: Dictionary) -> String:
	var parts: Array[String] = []
	for res: String in RES:
		parts.append("%s %d" % [_res_zh(res), int(d.get(res, 0))])
	return " · ".join(parts)


func _set_hint(msg: String, err: bool = false) -> void:
	left_hint.text = "上次行动：%s" % msg
	left_hint.add_theme_color_override("font_color", RED if err else DIM)


## 切换外交对象：高亮卡片、重置交易输入
func select_ai(idx: int) -> void:
	sel_idx = idx
	for i in range(cards.size()):
		cards[i].add_theme_stylebox_override("panel",
			_panel_style(PANEL2, GOLD, 2) if i == idx else _panel_style(PANEL2))
	_reset_trade_spins()
	_refresh_all()


func _reset_trade_spins() -> void:
	for res: String in RES:
		var gs: SpinBox = give_spins[res]
		var asb: SpinBox = ask_spins[res]
		gs.set_value_no_signal(0.0)
		asb.set_value_no_signal(0.0)
	_refresh_trade_eval()


# ==================================================================
#  刷新
# ==================================================================

func _refresh_all() -> void:
	# 左：回合 / 资源
	turn_label.text = "我方 · 第 %d 回合" % turn
	for res: String in RES:
		var amt: Label = res_amount_labels[res]
		amt.text = "× %d" % int(my_res[res])

	# 中上：关系
	var ai := _sel()
	name_label.text = "与 %s 的关系" % ai.display_name
	state_label.text = ai.relation_state()
	state_label.add_theme_color_override("font_color", Color(STATE_COLOR.get(ai.relation_state(), DIM)))
	rel_label.text = "%+.1f" % ai.relationship
	rel_label.add_theme_color_override("font_color", RED if ai.relationship < 0.0 else GREEN)
	rel_bar.value = ai.relationship
	var coercible := ai.can_coerce(my_military)
	mil_info_label.text = "军力对比：我方 %d · 对方 %d · 逼迫需 >3 倍（>=%d）· %s" % [
		my_military, ai.military, ai.military * 3 + 1, "可逼迫" if coercible else "不可逼迫"]
	mil_info_label.add_theme_color_override("font_color", GREEN if coercible else DIM)

	# 左：宣战/和平按钮文案
	btn_war.text = "和平" if ai.at_war else "宣战"

	# 中下：交易面板（库存上限 + 预期提示）
	for res: String in RES:
		var gs: SpinBox = give_spins[res]
		var asb: SpinBox = ask_spins[res]
		gs.max_value = int(my_res[res])
		asb.max_value = int(ai.resources[res])
		if gs.value > gs.max_value:
			gs.value = 0.0
		if asb.value > asb.max_value:
			asb.value = 0.0
		var ginfo: Label = give_stock_labels[res]
		ginfo.text = "%s ×%d · AI预期 %d" % [_res_zh(res), int(my_res[res]), int(ai.expectations[res])]
		var ainfo: Label = ask_stock_labels[res]
		ainfo.text = "%s ×%d · 预期 %d" % [_res_zh(res), int(ai.resources[res]), int(ai.expectations[res])]
	_refresh_trade_eval()

	# 右：AI 卡片
	for i in range(ais.size()):
		var card_ai: AIState = ais[i]
		card_states[i].text = card_ai.relation_state()
		card_states[i].add_theme_color_override("font_color",
			Color(STATE_COLOR.get(card_ai.relation_state(), DIM)))
		card_rels[i].text = "关系 %+.1f" % card_ai.relationship
		card_rels[i].add_theme_color_override("font_color",
			RED if card_ai.relationship < 0.0 else GREEN)
		card_mils[i].text = "军力 %d" % card_ai.military
		card_ress[i].text = "持有 " + _fmt_res(card_ai.resources)
		card_exps[i].text = "预期 " + _fmt_res(card_ai.expectations)


## 实时评估当前交易（AI 计分）
func _refresh_trade_eval() -> void:
	var ai := _sel()
	var give: Dictionary = {}
	var ask: Dictionary = {}
	var any := false
	for res: String in RES:
		var g: int = int(give_spins[res].value)
		var a: int = int(ask_spins[res].value)
		give[res] = g
		ask[res] = a
		if g > 0 or a > 0:
			any = true
	if not any:
		eval_label.text = "尚未选取任何资源"
		eval_label.add_theme_color_override("font_color", DIM)
		return
	var score := ai.trade_score(give, ask)
	var ok := score >= 0
	eval_label.text = "AI 评估：%+d 分 → %s" % [score, "接受交易" if ok else "拒绝交易"]
	eval_label.add_theme_color_override("font_color", GREEN if ok else RED)


# ==================================================================
#  行动回调
# ==================================================================

func _on_declare_friendship() -> void:
	var ai := _sel()
	if ai.at_war:
		_set_hint("交战状态下无法宣布友谊。", true)
		return
	if ai.relationship < 40.0:
		_set_hint("关系需达到 +40 才能宣布友谊（当前 %+.1f）。" % ai.relationship, true)
		return
	if ai.friendship_declared or ai.relation_state() == "同盟":
		_set_hint("已宣布过友谊，或已是同盟。", true)
		return
	ai.declare_friendship()
	_set_hint("已向 %s 宣布友谊，关系 +10 → %+.1f。" % [ai.display_name, ai.relationship])
	_refresh_all()


func _on_declare_alliance() -> void:
	var ai := _sel()
	if ai.at_war:
		_set_hint("交战状态下无法宣布同盟。", true)
		return
	if ai.relationship < 60.0:
		_set_hint("关系需达到 +60 才能宣布同盟（当前 %+.1f）。" % ai.relationship, true)
		return
	if ai.alliance_declared or ai.relation_state() == "同盟":
		_set_hint("已宣布过同盟。", true)
		return
	ai.declare_alliance()
	_set_hint("已与 %s 结为同盟，关系 +10 → %+.1f。" % [ai.display_name, ai.relationship])
	_refresh_all()


func _on_coerce() -> void:
	var ai := _sel()
	my_military = int(military_spin.value)
	if not ai.can_coerce(my_military):
		if ai.at_war:
			_set_hint("交战状态下无法逼迫。", true)
		elif my_military <= ai.military * 3:
			_set_hint("军力不足：需超过对方 3 倍（对方军力 %d，需 >=%d）。" % [ai.military, ai.military * 3 + 1], true)
		else:
			_set_hint("关系未达和平或以上（当前 %+.1f）。" % ai.relationship, true)
		return
	var gained := ai.coerce(my_res)
	var parts := ""
	for res: String in RES:
		if gained.has(res):
			parts += "%s %d · " % [_res_zh(res), int(gained[res])]
	_set_hint("逼迫成功！获得 %s关系 -20 → %+.1f" % [parts, ai.relationship])
	_refresh_all()


func _on_war_peace() -> void:
	var ai := _sel()
	if ai.at_war:
		ai.make_peace()
		_set_hint("与 %s 达成和平，关系保持 %+.1f（仍处敌视段）。" % [ai.display_name, ai.relationship])
	else:
		var before := ai.relationship
		ai.declare_war()
		_set_hint("向 %s 宣战！关系 %+.1f → %+.1f，状态变为交战。" % [ai.display_name, before, ai.relationship])
	_refresh_all()


func _on_trade_changed(_value: float) -> void:
	_refresh_trade_eval()


func _on_trade_confirm() -> void:
	var ai := _sel()
	var give: Dictionary = {}
	var ask: Dictionary = {}
	var any := false
	for res: String in RES:
		var g: int = int(give_spins[res].value)
		var a: int = int(ask_spins[res].value)
		if g > int(my_res[res]) or a > int(ai.resources[res]):
			_set_hint("交易数量超出库存，请刷新后重试。", true)
			_refresh_all()
			return
		give[res] = g
		ask[res] = a
		if g > 0 or a > 0:
			any = true
	if not any:
		_set_hint("请先选取要交易的资源。", true)
		return
	var score := ai.trade_score(give, ask)
	if score < 0:
		_set_hint("%s 拒绝了这笔交易（评估 %d 分，低于 0）。" % [ai.display_name, score], true)
		return
	ai.apply_trade(give, ask, my_res, score)
	_reset_trade_spins()
	var rel_msg := "，关系 +%d" % score if score > 0 else ""
	_set_hint("交易达成！%s 评估 %+d 分%s。" % [ai.display_name, score, rel_msg])
	_refresh_all()


func _on_end_turn() -> void:
	turn += 1
	for ai: AIState in ais:
		ai.decay_toward_zero()
	_set_hint("第 %d 回合结束：与所有 AI 的关系向 0 靠拢 0.1。" % turn)
	_refresh_all()
