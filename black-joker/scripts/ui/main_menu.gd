extends Control
## =============================================================================
## MainMenu — 主菜单：模式/难度/观察模式选择，写入 GameConfig 后进牌桌
## =============================================================================

const MODE_LABELS := ["单机 · 对手 AI", "本地双人", "联机 · 建主机", "联机 · 加入"]

var _mode_group := ButtonGroup.new()
var _mode_buttons: Array[Button] = []
var _diff_easy: Button
var _diff_hard: Button
var _obs_training: Button
var _obs_hell: Button
var _ip_row: HBoxContainer
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _hint: Label


func _ready() -> void:
	theme = UITheme.app_theme
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center.position = Vector2(400, 46)
	center.size = Vector2(480, 630)
	add_child(center)

	var title := UITheme.make_label("地狱黑杰克", 46, UITheme.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	var subtitle := UITheme.make_label(
		"HELL BLACKJACK · 每一张牌的牌背都有细微差别——读懂牌背，预知抽牌",
		15, UITheme.INK_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(subtitle)

	var gap := UITheme.make_label("", 8)
	center.add_child(gap)

	# 模式选择
	var mode_title := UITheme.make_label("对局模式", 16, UITheme.INK2)
	center.add_child(mode_title)
	for i in MODE_LABELS.size():
		var bt := Button.new()
		bt.text = MODE_LABELS[i]
		bt.toggle_mode = true
		bt.button_group = _mode_group
		bt.add_theme_stylebox_override("normal", UITheme.default_button_style())
		bt.add_theme_stylebox_override("hover", UITheme.default_button_style())
		bt.add_theme_stylebox_override("pressed", UITheme.gold_button_style())
		bt.add_theme_color_override("font_color", UITheme.INK)
		bt.add_theme_color_override("font_pressed_color", Color("1a1408"))
		bt.add_theme_font_size_override("font_size", 16)
		bt.focus_mode = Control.FOCUS_NONE
		bt.custom_minimum_size = Vector2(0, 40)
		if i == 0:
			bt.button_pressed = true
		bt.toggled.connect(_on_mode_toggled)
		_mode_buttons.append(bt)
		center.add_child(bt)

	# 联机参数
	_ip_row = HBoxContainer.new()
	_ip_row.add_theme_constant_override("separation", 8)
	_ip_row.visible = false
	center.add_child(_ip_row)
	_ip_row.add_child(UITheme.make_label("IP", 14, UITheme.INK2))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(160, 32)
	_ip_row.add_child(_ip_edit)
	_ip_row.add_child(UITheme.make_label("端口", 14, UITheme.INK2))
	_port_edit = LineEdit.new()
	_port_edit.text = "9001"
	_port_edit.custom_minimum_size = Vector2(70, 32)
	_ip_row.add_child(_port_edit)

	# AI 难度
	var diff_title := UITheme.make_label("AI 难度", 16, UITheme.INK2)
	center.add_child(diff_title)
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	center.add_child(diff_row)
	_diff_easy = _make_toggle("简单（不读牌背）", diff_row, true)
	_diff_hard = _make_toggle("困难（会读牌背）", diff_row, false)

	# 观察模式
	var obs_title := UITheme.make_label("观察模式", 16, UITheme.INK2)
	center.add_child(obs_title)
	var obs_row := HBoxContainer.new()
	obs_row.add_theme_constant_override("separation", 8)
	center.add_child(obs_row)
	_obs_training = _make_toggle("新手（放大镜带提示）", obs_row, true)
	_obs_hell = _make_toggle("地狱（纯靠记忆）", obs_row, false)

	_hint = UITheme.make_label("", 13, UITheme.INK_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_hint)

	var gap2 := UITheme.make_label("", 8)
	center.add_child(gap2)

	var start := UITheme.make_button("开始对局", UITheme.gold_button_style(), 22)
	start.custom_minimum_size = Vector2(0, 52)
	start.pressed.connect(_on_start)
	center.add_child(start)

	var tip := UITheme.make_label("牌局内：F1 牌背对照表（新手模式）· Esc 返回", 12, UITheme.INK_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(tip)

	_on_mode_toggled(true)


## 同一组的互斥 Toggle 按钮（未用 ButtonGroup 便于行内复用）
func _make_toggle(text: String, parent: Control, pressed: bool) -> Button:
	var bt := Button.new()
	bt.text = text
	bt.toggle_mode = true
	bt.button_pressed = pressed
	bt.add_theme_stylebox_override("normal", UITheme.default_button_style())
	bt.add_theme_stylebox_override("hover", UITheme.default_button_style())
	bt.add_theme_stylebox_override("pressed", UITheme.gold_button_style())
	bt.add_theme_color_override("font_color", UITheme.INK)
	bt.add_theme_color_override("font_pressed_color", Color("1a1408"))
	bt.add_theme_font_size_override("font_size", 14)
	bt.focus_mode = Control.FOCUS_NONE
	bt.custom_minimum_size = Vector2(220, 36)
	bt.toggled.connect(func(_on: bool) -> void:
		# 同组互斥：本按钮变真时把同组的另一个按钮关掉
		for sibling in parent.get_children():
			if sibling != bt and sibling is Button:
				(sibling as Button).button_pressed = false)
	parent.add_child(bt)
	return bt


func _selected_mode() -> int:
	for i in _mode_buttons.size():
		if _mode_buttons[i].button_pressed:
			return i
	return 0


func _on_mode_toggled(_on: bool) -> void:
	var mode := _selected_mode()
	_ip_row.visible = (mode == GameConfig.Mode.HOST or mode == GameConfig.Mode.CLIENT)
	match mode:
		GameConfig.Mode.AI:
			_hint.text = "与 AI 对战。困难 AI 会读牌背、记弃牌、算你的明手。"
		GameConfig.Mode.LOCAL:
			_hint.text = "同屏轮流操作。牌堆顶的牌背对双方公平公开。"
		GameConfig.Mode.HOST:
			_hint.text = "你当主机：告诉对方你的 IP 和端口（同一局域网，或公网端口转发）。"
		GameConfig.Mode.CLIENT:
			_hint.text = "加入主机：输入对方的 IP 和端口后开始。"
		_:
			_hint.text = ""


func _on_start() -> void:
	GameConfig.mode = _selected_mode()
	GameConfig.difficulty = "hard" if _diff_hard.button_pressed else "easy"
	GameConfig.observe = GameConfig.Observe.HELL if _obs_hell.button_pressed else GameConfig.Observe.TRAINING
	GameConfig.ip = _ip_edit.text.strip_edges()
	if GameConfig.ip == "":
		GameConfig.ip = "127.0.0.1"
	var port_text := _port_edit.text.strip_edges()
	GameConfig.port = int(port_text) if port_text.is_valid_int() else 9001
	get_tree().change_scene_to_file("res://scenes/table.tscn")
