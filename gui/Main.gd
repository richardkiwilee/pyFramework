## =====================================================================
## Main — 主场景脚本
## =====================================================================
## 构造两层结构：
##   下层 = 图片层（MapCamera，可拖拽/缩放的大地图）；
##   上层 = UI 层（CanvasLayer）—— 顶部信息栏 / 左下兵牌 / 右下回合结束
##           / 日志面板 / 设置选单。
## 全程用显式 position/size 布局（不依赖锚点），窗口缩放时统一重算。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## extends Control        → 继承 UI 控件基类（有位置/尺寸）
## CanvasLayer            → 独立 UI 层，不受下层相机/缩放影响（类似"永远在最上层的 HUD"）
## ui.layer = 10          → 层数越大越靠上（盖在地图之上）
## Control / HBoxContainer / VBoxContainer
##     → 控件 / 水平排列容器 / 垂直排列容器（HBox 横排、VBox 纵排，类似 flex row/column）
## size_flags_vertical = SIZE_SHRINK_CENTER
##     → 在容器里垂直居中（不撑满高度）
## HBoxContainer.alignment = ALIGNMENT_BEGIN / END
##     → 子项整体左对齐 / 右对齐
## add_theme_constant_override("separation", n)
##     → 覆盖容器子项间距（类似 CSS gap）
## b.pressed.connect(callable)  → 按钮被按时触发回调
## Callable(self, "_on_x")      → 把本对象的方法包装成可调用对象（类似 functools.partial）
## .bind(i)                     → 给可调用对象预绑参数（回调被调用时会补上 i）
## get_viewport().size_changed → 窗口尺寸变化信号，重算布局用
## for i in n:                  → 遍历（注意 GDScript 的 for 是"遍历迭代器"，不是"步进"）
## _unit_defs[i]                → 数组下标访问（和 Python 一致）
## "字符串 %d" % 值             → 字符串格式化（和 Python 一致）
## pass                        → 空语句占位（和 Python 一样）
## =====================================================================
extends Control

# ---- 下层 / 上层关键节点引用 ----
var image_layer: MapCamera      # 图片层（大地图 + 单位）
var top_bar: Control            # 顶部信息栏
var unit_cards: Control         # 左下角兵牌区容器
var end_turn: Control           # 右下角"回合结束"
var log_panel: LogPanel         # 右上角日志弹框
var settings_menu: SettingsMenu # 中央设置选单
var turn_label: Label           # 顶部"回合 N"文本（单独引用，方便刷新）

# 兵牌 ↔ 地图单位的对应关系（按索引对齐）。
# 每项 = { 贴图逻辑名, 显示名, 地图上的世界坐标 }。
# 索引 i 既是兵牌序号，也是地图单位序号（Main._build_units_on_map 按同顺序添加）。
var _unit_defs: Array[Dictionary] = [
	{ "asset": "card_knight", "label": "Knight", "pos": Vector2(300, 700) },
	{ "asset": "card_archer", "label": "Archer",  "pos": Vector2(520, 640) },
	{ "asset": "card_mage",   "label": "Mage",    "pos": Vector2(820, 560) },
	{ "asset": "card_rogue",   "label": "Rogue",   "pos": Vector2(1120, 720) },
]

func _ready() -> void:
	# 根节点用 FULL_RECT 锚点自动填满窗口；这里只读 size，不手动写，避免锚点冲突警告。
	_build_image_layer()    # 下层：地图
	_build_units_on_map()   # 在地图上放单位标记
	_build_ui_layer()       # 上层：所有 UI
	# 回合文本初始值 + 订阅变化
	_update_turn_text()
	# 连接 GameState 信号：回合变化时刷新顶部文本。
	GameState.turn_changed.connect(_on_turn_changed)
	# 连接视口尺寸变化信号：窗口缩放时重算所有布局。
	get_viewport().size_changed.connect(_on_viewport_changed)
	pass

## 窗口尺寸变化时重算所有布局，并修正地图裁剪位置。
func _on_viewport_changed() -> void:
	_layout_image_layer()
	_layout_top_bar()
	_layout_unit_cards()
	_layout_end_turn()
	_layout_log_panel()
	image_layer._apply_clamp()
	pass

# ======================= 下层：图片层 =======================
func _build_image_layer() -> void:
	image_layer = MapCamera.new()
	image_layer.name = "ImageLayer"
	add_child(image_layer)
	_layout_image_layer()
	image_layer._apply_clamp()
	pass

## 把地图上每个单位定义都加到图片层（add_unit 按顺序返回索引，与兵牌对齐）。
func _build_units_on_map() -> void:
	for d in _unit_defs:
		image_layer.add_unit(d.pos, d.asset, d.label)
	pass

func _layout_image_layer() -> void:
	image_layer.position = Vector2.ZERO
	image_layer.size = size  # 图片层填满整个窗口
	pass

# ======================= 上层：UI 层 =======================
func _build_ui_layer() -> void:
	# CanvasLayer：独立 UI 层，不被下层地图缩放影响，永远盖在地图上。
	var ui := CanvasLayer.new()
	ui.name = "UiLayer"
	ui.layer = 10  # 层数 10，靠上
	add_child(ui)
	_build_top_bar(ui)
	_build_unit_cards(ui)
	_build_end_turn(ui)
	_build_log_panel(ui)
	_build_settings_menu(ui)
	pass

# ---------------- 顶部信息栏 ----------------
func _build_top_bar(parent: Node) -> void:
	top_bar = Control.new()
	top_bar.name = "TopBar"
	parent.add_child(top_bar)

	# 背景（平铺贴图或回退暗色金边）
	var bg := UiBuilder.make_topbar_bg(Vector2(size.x, 40))
	bg.position = Vector2.ZERO
	top_bar.add_child(bg)

	# 左侧组：图标1 文本1 图标2 文本2 图标3 文本3（横排）
	var left := HBoxContainer.new()
	left.name = "LeftGroup"
	left.position = Vector2(8, 0)
	left.alignment = BoxContainer.ALIGNMENT_BEGIN  # 左对齐
	left.add_theme_constant_override("separation", 6)  # 子项间距 6px
	top_bar.add_child(left)

	# 三个图标 + 三段文字，交替塞进左侧 HBox。
	var icon_size := Vector2(28, 28)
	var icons := ["icon_apple", "icon_gear", "icon_coin"]
	var texts := ["苹果 99", "设置", "金币 1024"]
	for i in icons.size():
		var ic := UiBuilder.make_icon(icons[i], icon_size)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # 垂直居中
		left.add_child(ic)
		var t := UiBuilder.make_text(texts[i])
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		left.add_child(t)

	# 右侧组：[回合文本] + 按钮[城市管理, 部队管理, 日志, 设置]（左→右），整体右对齐。
	var right := HBoxContainer.new()
	right.name = "RightGroup"
	right.alignment = BoxContainer.ALIGNMENT_END  # 右对齐
	right.add_theme_constant_override("separation", 8)
	top_bar.add_child(right)

	# 回合文本（按钮左侧）
	turn_label = UiBuilder.make_text("回合 1", UiBuilder.GOLD)
	turn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_label.custom_minimum_size = Vector2(80, 30)
	right.add_child(turn_label)

	# 四个按钮，左→右：城市管理、部队管理、日志、设置
	var btn_defs := [
		{ "label": "城市管理", "act": Callable(self, "_on_city") },
		{ "label": "部队管理", "act": Callable(self, "_on_unit") },
		{ "label": "日志",     "act": Callable(self, "_on_log") },
		{ "label": "设置",     "act": Callable(self, "_on_settings") },
	]
	for d in btn_defs:
		# make_button 返回 BaseButton（TextureButton 或回退 Button）。
		var b := UiBuilder.make_button("", d.label, Vector2(0, 30))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# 连接按下信号到对应回调。
		b.pressed.connect(d.act)
		right.add_child(b)

	_layout_top_bar()
	pass

## 手动布局顶部栏：按子节点索引固定分配位置/尺寸。
## 子节点顺序：0=背景，1=左侧 HBox，2=右侧 HBox。
func _layout_top_bar() -> void:
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(size.x, 40)
	for i in top_bar.get_child_count():
		var c := top_bar.get_child(i)
		match i:
			0:  # 背景：铺满整条顶栏
				c.size = top_bar.size
			1:  # 左侧 HBox：占左半（留 8px 左边距）
				c.position = Vector2(8, 0)
				c.size = Vector2(size.x * 0.5 - 8, 40)
			2:  # 右侧 HBox：占右半（留 8px 右边距）
				c.position = Vector2(size.x * 0.5, 0)
				c.size = Vector2(size.x * 0.5 - 8, 40)
	pass

# ---------------- 左下角兵牌区 ----------------
func _build_unit_cards(parent: Node) -> void:
	var card_w := 60          # 单张兵牌宽
	var card_h := 180          # 单张兵牌高
	var gap := 0               # 兵牌间距（0 = 紧贴排列，中间无空隙）
	var total := card_w * 4 + gap * 3  # 整个兵牌区宽度 = 4 张宽 + 3 个间距
	unit_cards = Control.new()
	unit_cards.name = "UnitCards"
	unit_cards.size = Vector2(total, card_h)
	parent.add_child(unit_cards)

	# 逐个创建兵牌，按 i 横向排列，点击时聚焦对应单位。
	var card_size := Vector2(card_w, card_h)
	for i in _unit_defs.size():
		var d := _unit_defs[i]
		var c := UiBuilder.make_unit_card(d.asset, d.label, card_size)
		# 横向定位：第 i 张 = i * (宽 + 间距)。
		c.position = Vector2(i * (card_w + gap), 0)
		c.size = card_size
		# 点击兵牌 → 镜头聚焦到对应单位。.bind(i) 预绑索引参数。
		c.pressed.connect(_on_card_clicked.bind(i))
		unit_cards.add_child(c)

	_layout_unit_cards()
	pass

## 兵牌点击回调：聚焦到第 index 个地图单位，并记一条日志。
func _on_card_clicked(index: int) -> void:
	image_layer.focus_on(index)
	GameState.add_log("聚焦单位：%s" % _unit_defs[index].label)
	pass

## 把兵牌区放到左下角（留 16px 边距）。
func _layout_unit_cards() -> void:
	var margin := 16
	var card_h := 180
	unit_cards.position = Vector2(margin, size.y - card_h - margin)
	pass

# ---------------- 右下角回合结束 ----------------
func _build_end_turn(parent: Node) -> void:
	var frame_size := Vector2(140, 140)  # 外框尺寸
	var btn_size := Vector2(96, 96)     # 内层按钮尺寸
	end_turn = UiBuilder.make_end_turn("endturn_frame", "endturn_button", frame_size, btn_size)
	end_turn.size = frame_size
	parent.add_child(end_turn)
	# make_end_turn 返回的容器里内层才是按钮，遍历子节点找到它接信号。
	for c in end_turn.get_children():
		if c is BaseButton:
			(c as BaseButton).pressed.connect(_on_end_turn)
			break
	_layout_end_turn()
	pass

func _on_end_turn() -> void:
	GameState.next_turn()
	pass

## 把回合结束按钮放到右下角（留 16px 边距）。
func _layout_end_turn() -> void:
	var margin := 16
	end_turn.position = Vector2(size.x - end_turn.size.x - margin, size.y - end_turn.size.y - margin)
	pass

# ---------------- 回合文本 ----------------
## 把顶部回合文本刷新成 GameState 当前回合。
func _update_turn_text() -> void:
	if turn_label:
		turn_label.text = "回合 %d" % GameState.current_turn
	pass

## GameState.turn_changed 信号回调：回合变化时刷新文本。
func _on_turn_changed(turn: int) -> void:
	_update_turn_text()
	pass

# ---------------- 右上角日志面板 ----------------
func _build_log_panel(parent: Node) -> void:
	log_panel = LogPanel.new()
	log_panel.name = "LogPanel"
	log_panel.size = Vector2(200, 400)
	parent.add_child(log_panel)
	_layout_log_panel()
	pass

## 把日志面板放到右上角（顶部栏正下方，留边距）。
func _layout_log_panel() -> void:
	if not log_panel:
		return
	var margin := 16
	# x = 窗口宽 - 面板宽 - 边距；y = 顶栏高 40 + 8 间距。
	log_panel.position = Vector2(size.x - 200 - margin, 40 + 8)
	pass

func _on_log() -> void:
	# 再次点击日志按钮切换开关；ESC 无效（由 LogPanel 自身不处理 ESC 保证）
	log_panel.toggle()
	pass

# ---------------- 中央设置选单 ----------------
func _build_settings_menu(parent: Node) -> void:
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	# 设置选单自身用 FULL_RECT 锚点填满，内部自己居中面板。
	settings_menu.anchors_preset = Control.PRESET_FULL_RECT
	parent.add_child(settings_menu)
	pass

func _on_settings() -> void:
	settings_menu.show_menu()
	pass

# ---------------- 顶部栏按钮：场景跳转 ----------------
func _on_city() -> void:
	GameState.add_log("打开城市管理")
	# 切换场景到 CityScene.tscn（会销毁当前 Main 场景）。
	get_tree().change_scene_to_file("res://CityScene.tscn")
	pass

func _on_unit() -> void:
	GameState.add_log("打开部队管理")
	get_tree().change_scene_to_file("res://UnitScene.tscn")
	pass
