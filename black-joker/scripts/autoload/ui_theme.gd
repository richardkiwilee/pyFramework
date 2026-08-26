extends Node
## =============================================================================
## UITheme — 自动加载(Autoload)单例，提供全局 UI 主题
## =============================================================================
## 移植自 fullver-1 的 scripts/autoload/ui_theme.gd（已验证方案），
## 删去本作用不到的势力/稀有度/emoji 部分，新增牌桌与牌面所需颜色。
## 样式工厂与 center() 的坑位结论均沿用原版（见该文件注释）。
## =============================================================================

# ==================================================================
#  基础色板 (Color Palette)
# ==================================================================

const BG: Color = Color("0c0a08")            # 最深背景（接近纯黑）
const BG2: Color = Color("14110d")           # 次级背景
const PANEL: Color = Color("241d14")         # 面板底色（深棕）
const PANEL2: Color = Color("2e2519")        # 面板底色2（稍浅）
const LINE: Color = Color("4a3a24")          # 边框线（暗金棕）
const LINE2: Color = Color("6a5436")         # 边框线2（较亮）
const INK: Color = Color("e8dcc4")           # 主文字色（羊皮纸白）
const INK2: Color = Color("c4b596")          # 次级文字色
const INK_DIM: Color = Color("8a7a5c")       # 暗淡文字色（用于次要信息）
const GOLD: Color = Color("d4af37")          # 金色（标题用）
const GOLD_BRIGHT: Color = Color("f0d264")   # 亮金色（强调/选中状态）
const GLOW: Color = Color("ffd86b")          # 发光金色（特效用）

# 功能色 — 用于状态指示
const RED: Color = Color("c2553a")           # 红色（危险/爆牌/失败）
const GREEN: Color = Color("7ab85a")         # 绿色（成功/存活）
const BLUE: Color = Color("4a90c2")          # 蓝色（信息）

# ==================================================================
#  牌桌/牌面专用色（本作新增）
# ==================================================================

const FELT: Color = Color("26130f")          # 牌桌呢绒底色（暗血红，地狱风）
const FELT2: Color = Color("331a12")         # 牌桌次级色
const SUIT_RED: Color = Color("c0392b")      # 红桃/方块的牌面红
const SUIT_BLACK: Color = Color("16120d")    # 黑桃/梅花的牌面黑（偏暖黑）
const CARD_IVORY: Color = Color("f2ead8")    # 牌面象牙白底
const TURN_GLOW: Color = Color("f0d264")     # 当前回合方高亮

# ==================================================================
#  Theme 对象
# ==================================================================

var app_theme: Theme


func _ready() -> void:
	app_theme = Theme.new()

	# SystemFont 的 font_names 是优先级列表：从左到右取第一个可用字体
	var default_font := SystemFont.new()
	default_font.font_names = PackedStringArray([
		"Microsoft YaHei",   # 微软雅黑（Windows 中文首选）
		"SimHei",            # 黑体（备选）
		"Noto Sans SC",      # Noto 简体中文（跨平台备选）
		"sans-serif",        # 系统默认无衬线字体（兜底）
	])
	app_theme.default_font = default_font
	app_theme.default_font_size = 14


# ==================================================================
#  样式工厂 (Style Factories)
# ==================================================================
# 每次调用返回全新 StyleBoxFlat 实例（引用类型，不能 const 共享）。

## panel_style() — 通用面板样式
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


## panel_header_style() — 面板标题栏样式（只有底部边框和上圆角）
func panel_header_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("352a1a")
	sb.border_width_bottom = 1
	sb.border_color = LINE
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	return sb


## gold_button_style() — 金色主按钮（要牌/停牌等主要操作）
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
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## default_button_style() — 默认按钮（常规操作，深底浅字）
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
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## disabled_button_style() — 禁用态按钮（灰色，非己方回合/对方回合用）
func disabled_button_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1f1a12")
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color("3a3222")
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## ---------------------------------------------------------------------------
## center() — 把控件相对父级居中
## ---------------------------------------------------------------------------
## ⚠️ 实测坑：set_anchors_preset(PRESET_CENTER) 只把锚点放到父级中心，
## 控件的 top-left 仍停在中心点（面板会画在右下象限，不是居中）！
## 必须再把 position 设为 -size/2（调用前先设好 size）。
## ---------------------------------------------------------------------------
static func center(ctrl: Control) -> void:
	ctrl.set_anchors_preset(Control.PRESET_CENTER)
	ctrl.position = Vector2(-ctrl.size.x / 2.0, -ctrl.size.y / 2.0)


## 创建一个带主题字号的 Label（羊皮纸色、自动换行）
func make_label(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", font_size)
	lb.add_theme_color_override("font_color", color)
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lb


## 创建一个带主题样式的 Button
## style 为金色时文字用深色，否则用浅色；focus_mode 设 NONE 防止抢键盘路由
func make_button(text: String, style: StyleBoxFlat, font_size: int = 14) -> Button:
	var bt := Button.new()
	bt.text = text
	bt.add_theme_stylebox_override("normal", style)
	bt.add_theme_font_size_override("font_size", font_size)
	var font_color := INK
	if style.bg_color == GOLD:
		font_color = Color("1a1408")  # 金底深字
	bt.add_theme_color_override("font_color", font_color)
	bt.focus_mode = Control.FOCUS_NONE
	return bt
