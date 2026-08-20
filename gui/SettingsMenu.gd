## =====================================================================
## SettingsMenu — 屏幕中央的设置选单
## =====================================================================
## 菜单项：继续游戏 / 保存 / 读取 / 退出游戏。
## ESC 关闭（=继续游戏）。具体存读档功能暂不实现，只记日志。
##
## 结构：本节点（全屏 Control，默认隐藏）→ 半透明遮罩 ColorRect + 中央面板 Panel
##       → 标题 Label + 按钮 VBox。
##
## ---- Python 开发者速查 ----
## extends Control              → UI 控件基类
## anchors_preset = PRESET_FULL_RECT
##     → 锚点预设"填满父节点"（四边锚点全 0/1，自动随父节点拉伸）。
##       类似 CSS 的 position:absolute; inset:0。
## mouse_filter = MOUSE_FILTER_STOP
##     → 拦截鼠标，点遮罩处可捕获点击 → 关闭菜单。
## ColorRect                    → 纯色矩形控件，这里做半透明黑色遮罩。
## _unhandled_input(event)     → 输入事件未被任何 GUI 消费时才到达这里，
##     → 常用来处理全局快捷键（如 ESC）。设 set_process_unhandled_input(true) 开启。
## get_viewport().set_input_as_handled()
##     → 标记"此输入已处理"，阻止它继续往下传（防止 ESC 同时触发别的逻辑）。
## get_viewport().get_visible_rect().size
##     → 视口可见区域尺寸，用于手动居中布局。
## match label:                 → 类似 Python match/case，按字符串分支。
## =====================================================================
class_name SettingsMenu
extends Control

var _panel: Panel          # 中央面板
var _vbox: VBoxContainer   # 按钮纵向容器

func _ready() -> void:
	# ---- 半透明遮罩：点空白处关闭 ----
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchors_preset = Control.PRESET_FULL_RECT
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)  # 点击遮罩 → 关闭
	add_child(dim)

	# ---- 中央面板 ----
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(260, 300)
	_panel.size = Vector2(260, 300)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.05, 0.98)
	sb.border_color = UiBuilder.GOLD
	sb.set_border_width_all(3)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	# ---- 标题 ----
	var ttl := Label.new()
	ttl.name = "Title"
	ttl.text = "设置"
	ttl.add_theme_color_override("font_color", UiBuilder.GOLD)
	ttl.add_theme_font_size_override("font_size", 24)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(ttl)

	# ---- 按钮容器 ----
	_vbox = VBoxContainer.new()
	_vbox.name = "Buttons"
	# 手动设锚点（用 anchors_preset 会把 offset 重置掉），留出标题与边距。
	# anchor_*：0.0=左/上边，1.0=右/下边（比例锚点）。
	# offset_*：相对锚点的像素偏移（正值往内，负值往内/靠近对边）。
	_vbox.anchor_left = 0.0
	_vbox.anchor_top = 0.0
	_vbox.anchor_right = 1.0
	_vbox.anchor_bottom = 1.0
	_vbox.offset_left = 14
	_vbox.offset_top = 50      # 顶部留 50px 给标题
	_vbox.offset_right = -14
	_vbox.offset_bottom = -14
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER  # 子项整体居中
	_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(_vbox)

	# 生成四个菜单按钮，各自接对应回调。
	for label in ["继续游戏", "保存", "读取", "退出游戏"]:
		_vbox.add_child(_make_menu_button(label))

	# 居中面板（手动算位置，因为没用锚点居中）
	_layout_center()
	# 窗口尺寸变化时重新居中。
	get_viewport().size_changed.connect(_layout_center)

	visible = false                       # 初始隐藏
	set_process_unhandled_input(true)     # 开启全局未处理输入监听（ESC）
	pass

## 生成单个菜单按钮，按 label 绑定对应回调。
func _make_menu_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(220, 44)
	b.size = Vector2(220, 44)
	b.add_theme_font_size_override("font_size", 18)
	# match：按按钮文字分支，接对应信号回调。
	match label:
		"继续游戏":
			b.pressed.connect(_on_continue)
		"保存":
			b.pressed.connect(_on_save)
		"读取":
			b.pressed.connect(_on_load)
		"退出游戏":
			b.pressed.connect(_on_exit)
	return b

## 把面板居中到视口中央（手动算位置）。
func _layout_center() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel.position = (vp - _panel.size) * 0.5
	pass

## 点击遮罩空白处：左键按下时关闭（=继续游戏）。
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_continue()

func _on_continue() -> void:
	GameState.add_log("继续游戏")
	hide_menu()

func _on_save() -> void:
	GameState.add_log("保存游戏（占位）")
	hide_menu()

func _on_load() -> void:
	GameState.add_log("读取存档（占位）")
	hide_menu()

func _on_exit() -> void:
	GameState.add_log("退出游戏")
	get_tree().quit()  # 退出游戏进程

## 全局未处理输入：菜单可见时按 ESC 关闭。
func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_continue()
		# 标记已处理，阻止 ESC 继续触发其他逻辑（如返回上一场景）。
		get_viewport().set_input_as_handled()
	pass

func show_menu() -> void:
	visible = true

func hide_menu() -> void:
	visible = false
