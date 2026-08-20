## =====================================================================
## UiBuilder — 把"图片优先，缺失则用原生控件"的策略封装成小工厂
## =====================================================================
## 提供几个静态方法：图标、文本、按钮、兵牌、回合结束按钮、顶栏背景。
## 设计思路：每个方法都先尝试用美术资源；若资源缺失，就用 Godot 原生控件
## （Panel/Button/Label）+ StyleBoxFlat 画出风格相近的回退外观。
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## static func            → 类级方法，用 UiBuilder.make_xxx(...) 直接调用，无需实例化
## Color(r,g,b,a)         → 颜色，分量均为 0.0~1.0 浮点（不是 0~255）
## Color.WHITE            → 颜色常量，纯白 (1,1,1,1)
## StyleBoxFlat           → 一块"样式盒"：背景色+边框+圆角+内边距，可贴到 Panel/Button 上
## add_theme_stylebox_override("panel", sb)
##                        → 把样式盒 sb 覆盖到控件的 "panel" 主题槽（类似 CSS 的 style）
## TextureRect            → 显示一张贴图的控件
## TextureButton          → 用贴图当外观的按钮（normal/hover/pressed 各一张）
## BaseButton             → 按钮抽象基类，TextureButton/Button 都是它的子类
## 控件的 expand_mode / stretch_mode → 控制贴图如何伸缩/对齐
## b.signal.connect(callable) → 订阅信号（类似 Python 的 callback 注册）
## func(): ...            → 匿名函数（lambda），connect 常用它做一次性回调
## =====================================================================
class_name UiBuilder
extends RefCounted

## ---- 配色常量（统一风格的金色/暗色系）----
const GOLD := Color(0.788, 0.631, 0.290)            # 烫金色（主点缀色）
const DARK := Color(0.165, 0.125, 0.043)            # 深棕底色
const DARK_PANEL := Color(0.110, 0.080, 0.040, 0.92) # 半透明暗色面板背景

# TextureButton 的悬停/按下颜色反馈（用 modulate 叠乘到贴图上）。
# modulate 是"颜色乘法滤镜"：(1,1,1) 原色不变，>1 提亮，<1 压暗。
const HOVER_MOD := Color(1.18, 1.10, 0.85, 1.0)
const PRESSED_MOD := Color(0.72, 0.66, 0.55, 1.0)

## 给 TextureButton 接上悬停/按下的颜色反馈。
## 通过连接 4 个信号（mouse_entered/exited、button_down/up）改 modulate 实现。
static func _add_hover_press(b: TextureButton) -> void:
	b.modulate = Color.WHITE
	# 鼠标进入：若当前没按下，就提亮（悬停态）。
	b.mouse_entered.connect(func(): if not b.button_pressed: b.modulate = HOVER_MOD)
	# 鼠标离开：恢复原色。
	b.mouse_exited.connect(func(): b.modulate = Color.WHITE)
	# 按下：压暗（按下态）。
	b.button_down.connect(func(): b.modulate = PRESSED_MOD)
	# 抬起：若仍在悬停区就保持提亮，否则恢复原色。
	b.button_up.connect(func(): b.modulate = HOVER_MOD if b.is_hovered() else Color.WHITE)

## 返回图标：有资源用 TextureRect，没有用占位 Panel（金色边框方块）。
static func make_icon(asset_name: String, size: Vector2) -> Control:
	var tex := ResourceManager.load_texture(asset_name)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		# EXPAND_IGNORE_SIZE：忽略贴图原始尺寸，按控件 size 伸缩。
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# KEEP_ASPECT_CENTERED：保持比例、居中显示。
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = size  # 最小尺寸（布局时不会缩到比这更小）
		t.size = size                 # 当前尺寸
		return t
	# 回退：金色边框方块
	var p := Panel.new()
	p.custom_minimum_size = size
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = DARK_PANEL
	sb.border_color = GOLD
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	return p

## 返回文本 Label。默认白色，16 号字。
static func make_text(text: String, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	# 覆盖字体颜色主题（类似 CSS color）。
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 16)
	return l

## 返回按钮：有资源用 TextureButton（带悬停/按下颜色反馈），没有用原生 Button。
## 返回类型用 BaseButton（父类），这样调用方无需区分两种实现。
static func make_button(asset_name: String, label: String, size: Vector2) -> BaseButton:
	var tex := ResourceManager.load_texture(asset_name)
	if tex != null:
		var b := TextureButton.new()
		b.texture_normal = tex        # 默认态贴图
		b.ignore_texture_size = true # 忽略贴图尺寸，按控件 size 伸缩
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = size
		b.size = size
		b.tooltip_text = label       # 鼠标悬停提示（贴图按钮没有文字，靠 tooltip）
		_add_hover_press(b)
		return b
	# 回退：原生按钮（自带主题反馈，文字即 label）
	var bb := Button.new()
	bb.text = label
	bb.custom_minimum_size = size
	bb.size = size
	return bb

## 返回兵牌（可点击）：有资源用 TextureButton，没有用带人名 Label 的原生 Button。
## 与 make_button 的区别：兵牌回退时画的是暗色金边面板样式，更"卡片"感。
static func make_unit_card(asset_name: String, name: String, size: Vector2) -> BaseButton:
	var tex := ResourceManager.load_texture(asset_name)
	if tex != null:
		var b := TextureButton.new()
		b.texture_normal = tex
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = size
		b.size = size
		b.tooltip_text = name
		_add_hover_press(b)
		return b
	# 回退：暗色面板风格的 Button
	var bb := Button.new()
	bb.text = name
	bb.custom_minimum_size = size
	bb.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = DARK_PANEL
	sb.border_color = GOLD
	sb.set_border_width_all(2)  # 四边都是 2px 边框
	bb.add_theme_stylebox_override("normal", sb)
	return bb

## 返回顶部栏背景：有资源用 TextureRect 平铺，没有用 StyleBoxFlat 模拟。
static func make_topbar_bg(size: Vector2) -> Control:
	var tex := ResourceManager.load_texture("topbar_bg")
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# STRETCH_TILE：平铺贴图（类似 CSS background-repeat: repeat）。
		t.stretch_mode = TextureRect.STRETCH_TILE
		t.size = size
		return t
	# 回退：暗色 + 烫金底边
	var p := Panel.new()
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = DARK
	sb.border_color = GOLD
	sb.border_width_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	return p

## 返回回合结束容器：圆角边框 + 圆形按钮（按钮自带悬停/按下颜色反馈）。
## 结构：外层 frame（边框/底） + 内层 btn（居中的圆形按钮）。
static func make_end_turn(frame_asset: String, button_asset: String, frame_size: Vector2, btn_size: Vector2) -> Control:
	# ---- 外层容器（圆角边框）----
	var frame: Control
	var frame_tex := ResourceManager.load_texture(frame_asset)
	if frame_tex != null:
		var t := TextureRect.new()
		t.texture = frame_tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = frame_size
		t.size = frame_size
		frame = t
	else:
		var p := Panel.new()
		p.custom_minimum_size = frame_size
		p.size = frame_size
		var sb := StyleBoxFlat.new()
		sb.bg_color = DARK
		sb.border_color = GOLD
		sb.set_border_width_all(3)
		# 四个角的圆角半径，做出圆角面板。
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		sb.corner_radius_bottom_left = 18
		sb.corner_radius_bottom_right = 18
		p.add_theme_stylebox_override("panel", sb)
		frame = p
	# ---- 内层按钮（make_button 已带颜色反馈）----
	var btn := make_button(button_asset, "End Turn", btn_size)
	# 把按钮在 frame 内居中：(frame_size - btn_size) / 2 作为偏移。
	btn.position = (frame_size - btn_size) * 0.5
	frame.add_child(btn)
	return frame
