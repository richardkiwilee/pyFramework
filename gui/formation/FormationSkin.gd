## =====================================================================
## FormationSkin — 编队界面的控件工厂（资源锚点 → 控件，缺资源就回退原生控件）
## =====================================================================
## readme 的基本准则第 2 条：
##   「锚点链接资源，如果目标资源没有找到，则使用 GDScript 原生的控件代替。」
## 本文件就是那层「锚点」。每个方法先问 ResourceManager 要图，
## 要不到就用 Panel/Label + StyleBoxFlat 画一个风格相近的替代品。
##
## 配色直接复用 UiBuilder 的 GOLD / DARK / DARK_PANEL，保证和主界面同一套视觉。
##
## 需要的资源锚点名（放进 res://assets/ 即可自动生效，不用改代码）：
##   portrait_<角色id>.svg   单位头像，例 portrait_alain.svg
##   slot_empty.svg          空装备槽底图
##   slot_filled.svg         已装备槽底图
##   grid_cell.svg           九宫格空格底图
##   crown.svg               队长皇冠标记
##
## ---- Python 开发者速查：GDScript / Godot 概念 ----
## static func            → 类级方法，直接 FormationSkin.xxx() 调用，不用实例化
## StyleBoxFlat           → 「样式盒」：背景色+边框+圆角+内边距，贴到 Panel/Button 上
## add_theme_stylebox_override("panel", sb)
##                        → 把样式盒覆盖到控件的主题槽。Panel 用 "panel"，
##                          Button 有 "normal"/"hover"/"pressed"/"disabled" 四个槽。
## add_theme_color_override("font_color", c) → 覆盖字体颜色
## add_theme_font_size_override("font_size", n) → 覆盖字号
## Color.from_hsv(h,s,v)  → 用色相/饱和度/明度造颜色，h/s/v 都是 0.0~1.0
## String.hash()          → 字符串哈希，返回 int（这里拿来给每个角色分配稳定的颜色）
## text.substr(0, 1)      → 取第一个字符，等价于 Python 的 text[0:1]
## Control.MOUSE_FILTER_IGNORE → 该控件不接收鼠标事件（事件穿透到下层）
## =====================================================================
class_name FormationSkin
extends RefCounted

# ---- 配色（复用 UiBuilder 的主色，再补几个编队专用色）----
const GOLD := UiBuilder.GOLD                       # 烫金：焦点/队长/强调
const DARK := UiBuilder.DARK                       # 深棕底
const PANEL_BG := Color(0.110, 0.080, 0.040, 0.92) # 面板底色
const PANEL_DIM := Color(0.075, 0.058, 0.034, 0.55) # 失焦面板底色（更暗更透）
const LINE := Color(0.290, 0.227, 0.141)           # 分隔线/普通边框
const INK := Color(0.910, 0.863, 0.769)            # 主文字
const INK_DIM := Color(0.541, 0.478, 0.361)        # 次要文字
const GREEN := Color(0.478, 0.722, 0.353)          # 合法/正向
const RED := Color(0.761, 0.333, 0.227)            # 非法/危险


## 把 child 挂到 parent 上并让它**填满** parent。
##
## ⚠️ 这个 helper 存在的唯一理由是一个很坑的 Godot 行为：
##   anchors_preset 的 setter 在设置锚点的同时，会**按控件当前尺寸立刻算好 offset**。
##   如果控件还没进场景树（或父节点尺寸还是 0），算出来的 offset 就是错的，
##   而且之后父节点变大也不会自动修正 —— 结果就是控件停在左上角、尺寸为 0。
##   所以顺序必须是「先 add_child，再设 anchors_preset」，不能反过来。
##
## 症状很隐蔽：控件看起来「没画出来」或「跑到左上角去了」，
## 但没有任何报错。本项目里所有需要填满父节点的控件都要走这个函数。
static func add_filling(parent: Node, child: Control) -> void:
	parent.add_child(child)
	# 手写四条锚点 + 清零 offset，效果等同 PRESET_FULL_RECT，
	# 但不依赖「设置时控件已在树里」这个前提，最保险。
	child.anchor_left = 0.0
	child.anchor_top = 0.0
	child.anchor_right = 1.0
	child.anchor_bottom = 1.0
	child.offset_left = 0.0
	child.offset_top = 0.0
	child.offset_right = 0.0
	child.offset_bottom = 0.0


## 通用样式盒。border_col 传 Color(0,0,0,0) 表示不要边框。
static func box(bg: Color, border_col: Color, border_w: int = 1, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border_w > 0 and border_col.a > 0.0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb


## 界面容器（左/右两大区）的外框样式。
## ⚠️ 这里是「失焦即失效」的**视觉**部分，刻意不用 modulate 压暗整个容器 ——
## modulate 是颜色乘法，会把金色文字和图标一起洗白，而且它根本拦不住鼠标。
## 改成只换外框：激活 = 金色 2px 边框 + 较实的底；失焦 = 无边框 + 更暗更透的底。
## 这样文字始终保持满对比度，只有容器 chrome 在变。
static func zone_box(active: bool) -> StyleBoxFlat:
	if active:
		var sb := box(PANEL_BG, GOLD, 2, 10)
		sb.set_content_margin_all(12)
		return sb
	var sb2 := box(PANEL_DIM, LINE, 1, 10)
	sb2.set_content_margin_all(12)
	return sb2


## 标题文字（例：「编队管理」）。
static func make_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_font_size_override("font_size", 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 标题不吃鼠标
	return l


## 普通文本。
static func make_text(text: String, color: Color = INK, size_px: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 普通按钮。所有按钮一律 focus_mode = FOCUS_NONE ——
## 这是 demo-1 踩出来的关键经验：否则按钮会抢走方向键/空格/回车，
## 键盘路由（FormationScreen 里那个统一的 _unhandled_input）就全乱了。
static func make_button(text: String, danger: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var edge := RED if danger else LINE
	b.add_theme_stylebox_override("normal", box(Color(0.165, 0.129, 0.078), edge, 1, 5))
	b.add_theme_stylebox_override("hover", box(Color(0.227, 0.176, 0.102), GOLD, 1, 5))
	b.add_theme_stylebox_override("pressed", box(Color(0.129, 0.098, 0.055), GOLD, 1, 5))
	b.add_theme_stylebox_override("disabled", box(Color(0.110, 0.090, 0.063, 0.5), LINE, 1, 5))
	b.add_theme_color_override("font_color", RED if danger else INK)
	b.add_theme_color_override("font_hover_color", GOLD)
	return b


## 单位头像。有 res://assets/portrait_<角色id>.svg 就用图；
## 没有就回退成「带角色名首字的色块」——色相由角色 id 哈希决定，
## 所以同一个角色每次运行颜色都一样，不会闪。
static func make_portrait(unit: UnitModel, px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if unit == null:
		return holder

	var tex := ResourceManager.load_texture(unit.portrait_asset())
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_filling(holder, t)
		return holder

	# ---- 回退：色块 + 首字 ----
	# abs() 是因为 hash() 可能返回负数；% 1000 / 1000.0 把它压到 0.0~1.0 当色相。
	var hue := float(abs(unit.character_id.hash()) % 1000) / 1000.0
	var bg := Color.from_hsv(hue, 0.45, 0.38)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(bg, LINE, 1, 5))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_filling(holder, p)

	var initial := make_text(unit.display_name().substr(0, 1), INK, int(px * 0.5))
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_filling(holder, initial)
	return holder


## 装备槽小格（仅展示用）。filled 决定用实线还是虚线感的样式。
static func make_equip_slot(label: String, filled: bool) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var asset := "slot_filled" if filled else "slot_empty"
	if ResourceManager.has_asset(asset):
		var tex := ResourceManager.load_texture(asset)
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_filling(p, t)
	else:
		var bg := Color(0.196, 0.153, 0.086) if filled else Color(0, 0, 0, 0.28)
		var edge := LINE if filled else Color(0.227, 0.180, 0.118)
		p.add_theme_stylebox_override("panel", box(bg, edge, 1, 4))

	var l := make_text(label, INK if filled else INK_DIM, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	add_filling(p, l)
	return p


## 队长皇冠标记。没有资源就用文字「长」加金框。
static func make_crown(px: float) -> Control:
	var tex := ResourceManager.load_texture("crown")
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(px, px)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	var p := Panel.new()
	p.custom_minimum_size = Vector2(px, px)
	p.add_theme_stylebox_override("panel", box(Color(0.35, 0.27, 0.08), GOLD, 1, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := make_text("长", GOLD, int(px * 0.62))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_filling(p, l)
	return p


## 造一个「透明拦截层」——「失焦即失效」的**功能**部分。
##
## 为什么必须是它，而不是别的办法：
##   · modulate 压暗：根本不拦输入，点击和悬停照样穿过去。
##   · 给容器设 mouse_filter = IGNORE：**不会**让子控件失效，每个子节点保留
##     自己的 filter；更糟的是 IGNORE 会让点击穿透到下面另一半界面上。
##   · 逐个控件设 disabled：只有 Button 有 disabled，Label/Panel 没有，还得递归遍历。
## 透明 Control + MOUSE_FILTER_STOP 才是标准做法：Godot 的命中检测看的是
## 矩形和 filter，不看有没有画东西，所以它虽然完全透明但照样吃掉所有鼠标事件，
## 连 hover 高亮和 tooltip 都会被挡住。
##
## ⚠️ 用法两个要点：
##   1. 必须是所在容器的**最后一个子节点**（兄弟顺序 = 绘制顺序，最后 = 最上层）。
##   2. 开关只改 mouse_filter，**绝不改 visible** —— visible = false 的节点
##      收不到任何事件，拦截层会直接失效。
##   3. 拦截层必须真的**填满**所在容器，否则它挡不住任何东西。
##      这里只负责造节点，锚点由调用方用 add_filling() 在 add_child 之后设置。
static func make_blocker() -> Control:
	var c := Control.new()
	c.name = "Blocker"
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## 开/关拦截层。active = true 表示这个区**可以操作**（拦截层放行）。
static func set_blocker_active(blocker: Control, zone_active: bool) -> void:
	if blocker == null:
		return
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE if zone_active else Control.MOUSE_FILTER_STOP
