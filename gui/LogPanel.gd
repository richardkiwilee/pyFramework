## =====================================================================
## LogPanel — 屏幕右上角（顶部栏下方）的日志弹框
## =====================================================================
## 尺寸：宽 200 高 400；ScrollContainer 支持滚轮翻阅历史；ESC 不关闭；
## 由主场景调用 toggle()/show_panel()/hide_panel() 控制开关。
##
## 结构：本节点是 Panel（自带边框背景） → 标题 Label + ScrollContainer → 内部 VBox。
## 每条日志是一个 Label，append 到 VBox 里。
##
## ---- Python 开发者速查 ----
## extends Panel                → 继承面板控件（默认带主题背景，这里自定义样式）
## class_name LogPanel          → 注册类型名（别处可作类型使用）
## ScrollContainer              → 带滚动条的容器，内容超出时自动出现滚动条
## VBoxContainer                → 垂直排列子控件的容器（类似 Python tkinter 的纵向 pack）
## size_flags_horizontal/vertical
##     → 布局标志：SIZE_EXPAND_FILL 表示"尽可能撑满可用空间"
## autowrap_mode                → 自动换行模式（类似 CSS word-wrap）
## add_theme_constant_override("separation", n)
##     → 覆盖容器的子项间距常量（类似 CSS gap）
## await get_tree().process_frame → 等一帧（让布局算完再滚动到底）
## get_v_scroll_bar().max_value  → 垂直滚动条的最大值（滚到底用）
## is_instance_valid(node)      → 检查节点是否还存活（避免访问已销毁对象）
## =====================================================================
class_name LogPanel
extends Panel

var scroll: ScrollContainer       # 滚动容器（包裹日志列表）
var log_box: VBoxContainer        # 实际装日志 Label 的纵向容器
var _auto_scroll := true           # 是否自动滚到底（新增日志时）

func _ready() -> void:
	# ---- 容器自身外观：暗色半透明 + 金边 + 圆角 + 内边距 ----
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.96)
	sb.border_color = UiBuilder.GOLD
	sb.set_border_width_all(2)
	# 只给左上、左下、右下三个角做圆角（右上贴着顶栏，不圆）。
	sb.corner_radius_top_left = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	# content_margin：内容与边框的内边距（类似 CSS padding）。
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP  # 拦截鼠标（吃掉点击，不传给地图）

	# ---- 标题 ----
	var ttl := Label.new()
	ttl.name = "Title"
	ttl.text = "战记日志"
	ttl.add_theme_color_override("font_color", UiBuilder.GOLD)
	ttl.add_theme_font_size_override("font_size", 14)
	ttl.position = Vector2(8, 6)
	ttl.size = Vector2(184, 20)
	add_child(ttl)

	# ---- 滚动容器 ----
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(4, 30)
	scroll.size = Vector2(192, 366)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # 禁用横向滚动
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO        # 纵向按需出现
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)

	# ---- 日志列表（VBox）----
	log_box = VBoxContainer.new()
	log_box.name = "LogBox"
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 水平撑满
	log_box.add_theme_constant_override("separation", 4)      # 日志条目间距
	scroll.add_child(log_box)

	# ---- 订阅 GameState 的日志信号 ----
	# GameState 是全局单例（Autoload），单例名即类型名，可直接访问。
	if GameState:
		GameState.log_added.connect(_on_log_added)
		# 把已存在的历史日志也补显示出来（切场景回来时仍可见历史）。
		for entry in GameState.log_entries:
			_append_entry(entry)

	visible = false  # 初始隐藏，由主场景按需弹出
	pass

## 收到新日志信号时：追加一行；若面板可见就滚到底。
func _on_log_added(entry: String) -> void:
	_append_entry(entry)
	if visible:
		_keep_bottom()

## 追加一条日志（创建 Label 塞进 log_box）。
func _append_entry(entry: String) -> void:
	var l := Label.new()
	l.text = entry
	l.add_theme_color_override("font_color", Color(0.88, 0.88, 0.82))
	l.add_theme_font_size_override("font_size", 13)
	# AUTOWRAP_WORD_SMART：智能按词换行，避免长日志撑爆宽度。
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(176, 0)   # 最小宽度，保证换行有依据
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_child(l)

## 滚到底部：等一帧布局完成后再设滚动条位置。
func _keep_bottom() -> void:
	# await 协程：等一帧让 VBox 重新算好高度，再去读滚动条 max_value。
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

## 切换显示。返回切换后是否可见。
func toggle() -> bool:
	visible = not visible
	if visible:
		_keep_bottom()
	return visible

func show_panel() -> void:
	visible = true
	_keep_bottom()

func hide_panel() -> void:
	visible = false

## ESC 不关闭日志（需求明确）。但仍消费滚轮，避免滚轮同时缩放地图。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# 交给 ScrollContainer 自己处理，这里不拦截
			pass
	pass
