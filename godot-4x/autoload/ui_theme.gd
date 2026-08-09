## UI 主题：颜色、字体、面板样式集中管理（美术替换接口）。
##
## Python 原型把颜色集中在 pyconsole/io/theme.py；本文件是 Godot 等价物。
## 语义对应（§29.4 颜色语义）：
##   绿=己方/已学习/净变动正；红=敌方/未满足前置/净变动负；白=中立/可学习；
##   黄=可学习但资源不足；金=资源数值；暗灰白=小地点；警告色=非法操作。
##
## 边框/面板目前由 PanelSkin 程序绘制（生成式边框，无美术资源）；日后替换美术
## 资源时只需在 skin() 里把 Frame 的绘制换成 NinePatchRect 贴图（见 frame.gd）。
extends Node

# ---- 颜色（对应 theme.py） ----
const BG := Color("0b0e13")          # 背景
const PANEL_BG := Color("141a23")    # 面板底
const BORDER := Color("3d4a5d")      # 边框
const FG := Color("c9d4e4")          # 前景
const DIM := Color("7c8aa0")         # 暗
const HEADING := Color("9fb4d6")     # 标题
const ACCENT := Color("e6c07b")      # 强调（键名/日志标签）
const ACCENT2 := Color("7bd3e6")     # 强调2（信念）
const GOLD := Color("f5d76e")        # 资源数值

# 语义色（§29.4）
const C_OWN := Color("58c46b")       # 绿：己方
const C_ENEMY := Color("e05a5a")     # 红：敌方
const C_NEUTRAL := Color("d8dee6")   # 白：中立
const C_MINOR := Color("8f9bb0")     # 暗灰白：小地点
const C_GAIN := Color("58c46b")      # 资源净变动 >0 绿
const C_LOSS := Color("e05a5a")      # 资源净变动 <=0 红
const WARN := Color("e8b33c")        # 黄/警告
const OVERLAY_BG := Color(0, 0, 0, 0.86)
const DISABLED := Color("565f6e")    # 置灰

# ---- 字体 ----
# Godot 默认字体不含 CJK 字形，用系统字体兜底（Windows 中文环境命中微软雅黑；
# 其他平台按字体列表逐个尝试）。这是字体替换点：日后可换自定义字体文件。
var default_font: SystemFont
var theme_root: Theme

func _ready() -> void:
	default_font = SystemFont.new()
	default_font.font_names = PackedStringArray([
		"Microsoft YaHei", "Microsoft JhengHei", "PingFang SC",
		"Noto Sans CJK SC", "SimHei", "sans-serif"])
	default_font.font_weight = 400
	var fallbacks: Array[Font] = []
	for size in [14, 15, 16, 18, 20, 24]:
		fallbacks.append(load_fallback(size))
	default_font.set_fallbacks(fallbacks)
	theme_root = Theme.new()
	theme_root.default_font = default_font
	theme_root.default_font_size = 15
	theme_root.set_color("default_color", "Label", FG)
	theme_root.set_color("font_color", "Label", FG)
	theme_root.set_color("font_color", "Button", FG)
	theme_root.set_color("font_hover_color", "Button", FG)
	theme_root.set_color("font_pressed_color", "Button", GOLD)
	theme_root.set_color("font_focus_color", "Button", GOLD)
	theme_root.set_color("font_color", "LineEdit", FG)
	theme_root.set_color("font_hover_color", "LineEdit", FG)
	theme_root.set_color("caret_color", "LineEdit", ACCENT)
	theme_root.set_color("font_color", "RichTextLabel", FG)
	# 应用根主题
	get_tree().root.theme = theme_root

func load_fallback(size: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei", "Microsoft JhengHei", "PingFang SC",
		"Noto Sans CJK SC", "SimHei", "sans-serif"])
	f.multichannel_signed_distance_field = false
	return f

## 资源键色：金币金、科技/文化/信仰强调色，其余前景。
static func resource_key_color(kind: String) -> Color:
	match kind:
		"gold": return GOLD
		"tech", "culture", "faith": return ACCENT
		_ : return FG
