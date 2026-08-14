extends Node
## =============================================================================
## UITheme — 自动加载(Autoload)单例，提供中世纪暗色调 UI 主题
## =============================================================================
## 作用：集中管理整个游戏的配色方案和 UI 样式。
##       其他脚本通过 UITheme.GOLD、UITheme.panel_style() 等方式引用，
##       确保整个游戏的视觉风格一致。
##
## 类比 Python：
##   就像在一个 constants.py 中定义了所有颜色常量和样式工厂函数，
##   其他地方 `from constants import COLORS` 然后使用。
##
## Godot 概念说明 — Color：
##   Color(r, g, b) 或 Color("hex") 创建颜色对象。
##   Color("0c0a08") 等价于 Color(0.047, 0.039, 0.031)（RGB 0-1 范围）。
##   和 Python 的 matplotlib/tkinter 不同，Godot 的颜色分量范围是 0.0~1.0。
##
## Godot 概念说明 — StyleBoxFlat：
##   StyleBox 是 Godot 的"控件皮肤"。StyleBoxFlat 是实心矩形皮肤的基类。
##   可以设置背景色、边框、圆角、内边距等。
##   类似于 CSS 的 border + background + padding + border-radius 的组合。
##   通过 Control.add_theme_stylebox_override("normal", stylebox) 应用到控件。
## =============================================================================

# ==================================================================
#  基础色板 (Color Palette)
# ==================================================================
# 这些颜色构成了游戏的中世纪暗色调风格。
# 命名约定：
#   BG   = 背景色（Background）
#   PANEL = 面板色
#   LINE  = 边框/分隔线色
#   INK   = 前景文字色（高对比度）
#   GOLD  = 强调色（金色，用于标题/按钮）
#
# const 关键字：编译期常量，值不可更改。类似于 Python 中惯例的大写常量名。
# ==================================================================

const BG: Color = Color("0c0a08")        # 最深背景（接近纯黑）
const BG2: Color = Color("14110d")       # 次级背景
const PANEL: Color = Color("241d14")     # 面板底色（深棕）
const PANEL2: Color = Color("2e2519")    # 面板底色2（稍浅）
const LINE: Color = Color("4a3a24")      # 边框线（暗金棕）
const LINE2: Color = Color("6a5436")     # 边框线2（较亮）
const INK: Color = Color("e8dcc4")       # 主文字色（羊皮纸白）
const INK2: Color = Color("c4b596")      # 次级文字色
const INK_DIM: Color = Color("8a7a5c")   # 暗淡文字色（用于次要信息）
const GOLD: Color = Color("d4af37")      # 金色（标题用）
const GOLD_BRIGHT: Color = Color("f0d264") # 亮金色（强调/选中状态）
const GLOW: Color = Color("ffd86b")      # 发光金色（特效用）

# 功能色 — 用于状态指示
const RED: Color = Color("c2553a")       # 红色（敌方/危险/阵亡）
const GREEN: Color = Color("7ab85a")     # 绿色（友方/存活/加成）
const BLUE: Color = Color("4a90c2")      # 蓝色（魔法/信息）

# 棋盘格瓦片色 — 滚轮棋盘 3×3 菱形格的明暗交替色（同网页版 --tile-light/--tile-dark）
const TILE_LIGHT: Color = Color("c9b48f")  # 亮格（浅沙色）
const TILE_DARK: Color = Color("6b5a42")   # 暗格（深棕）

# ==================================================================
#  稀有度颜色 (Rarity Colors)
# ==================================================================
# 游戏中装备/角色有不同的稀有度等级，每种等级有对应颜色。
# 类似一般手游/网游的灰→绿→蓝→紫→金品质分级。
# ==================================================================

const RARITY_COLORS := {
	"common": Color("9a9a9a"),       # 普通 — 灰色
	"uncommon": Color("7ab85a"),     # 罕见 — 绿色
	"rare": Color("4a90c2"),         # 稀有 — 蓝色
	"epic": Color("9b59b6"),         # 史诗 — 紫色
	"legendary": Color("f0d264"),    # 传说 — 金色
}

# ==================================================================
#  Theme 对象
# ==================================================================
# Godot 的 Theme 是样式资源的容器，可以设置全局默认字体等。
# 在 _ready() 中创建并初始化。
# ==================================================================

var app_theme: Theme


func _ready() -> void:
	# 创建 Theme 实例并设置默认字体
	app_theme = Theme.new()

	# SystemFont 是 Godot 中加载系统字体的类
	# font_names 是一个优先级列表：从左到右依次尝试，用第一个找到的字体
	# PackedStringArray 是 GDScript 的紧凑字符串数组类型（类似 Python list[str]）
	var default_font = SystemFont.new()
	default_font.font_names = PackedStringArray([
		"Microsoft YaHei",   # 微软雅黑（Windows 中文首选）
		"SimHei",            # 黑体（备选）
		"Noto Sans SC",      # Noto 简体中文（跨平台备选）
		"sans-serif",        # 系统默认无衬线字体（兜底）
	])
	app_theme.default_font = default_font
	app_theme.default_font_size = 13


## 根据稀有度字符串返回对应颜色。找不到则返回暗淡文字色。
func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, INK_DIM)


# ==================================================================
#  样式工厂 (Style Factories)
# ==================================================================
# 以下每个方法都返回一个配置好的 StyleBoxFlat，可以直接应用到控件上。
#
# 为什么用工厂方法而不是 const？
#   因为 StyleBoxFlat 是引用类型，如果声明为 const，所有地方共享同一个实例，
#   修改一处就会影响全局。每次调用工厂方法返回全新实例，互不干扰。
#
# StyleBoxFlat 的关键属性：
#   bg_color              — 背景填充色
#   border_width_xxx      — 四个方向的边框宽度（像素）
#   border_color          — 边框颜色
#   corner_radius_xxx     — 四个角的圆角半径（像素）
#   content_margin_xxx    — 内容与边框之间的内边距（像素）
# ==================================================================

## panel_style() — 通用面板样式
## 用途：队伍面板、编辑器面板等外层容器
func panel_style(margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	return sb


## panel_header_style() — 面板标题栏样式
## 只有底部边框和上圆角的特殊样式，适合作为面板顶部标题条
func panel_header_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("352a1a")
	sb.border_width_bottom = 1  # 只有底部边框（分隔标题和内容）
	sb.border_color = LINE
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	# 不设置下圆角 — 标题栏下方通常是内容区，不需要圆角
	return sb


## gold_button_style() — 金色主按钮样式（用于"开始战斗"等主要操作）
## 背景为金色，配合深色文字，视觉上很突出
func gold_button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	return sb


## default_button_style() — 默认按钮样式
## 深色背景，用于"新增队伍"、"解散队伍"等常规操作
func default_button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a2114")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	return sb


## slot_dashed_style() — 空格子样式（半透明，提示此处可放置）
func slot_dashed_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	# Color(0, 0, 0, 0.28) — 第四个参数是 alpha（不透明度），范围 0~1
	sb.bg_color = Color(0, 0, 0, 0.28)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	return sb


## slot_filled_style() — 已填充格子样式（较亮的背景）
func slot_filled_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3a2d1a")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = LINE2
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	return sb
