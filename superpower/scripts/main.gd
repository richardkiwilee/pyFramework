extends Control
## =============================================================================
## main.gd — 爆气蓄力特效演示（超级赛亚人风格）
## =============================================================================
## 特效表示角色正在【蓄力爆气】、即将释放必杀技：能量场缠绕在角色
## 身上（不是全屏特效），档位越高能量越强。
##
## 操作：
##   ↑/↓ 方向键   切换档位（1~3 档，档位越高能量场越大越亮，宝石充能越多）
##   点击调色盘   切换特效主题色（左下角 8 色，特效与宝石同步换色）
##
## 特效全部由 shader 生成（shaders/effect.gdshader），角色剪影为 SDF 绘制。
## 三档爆气按顺序快速循环（每 1 秒切换）：
##   1. 🔥 烈焰爆气——火苗从身体升腾，贴着轮廓燃烧
##   2. ⚡ 天雷灌顶——闪电从屏幕顶击落头顶 + 全身电弧
##   3. 🌪 龙卷缠身——能量旋涡环绕身体，头顶冲起旋转能量柱
##
## 底部中央的三颗菱形宝石 = BP 槽（shaders/gems.gdshader），
## 充能数量随档位变化：档位提升 = 消耗更多 BP = 爆气被放大。
## =============================================================================

## 每个特效的展示时长（秒）——爆气快速轮换，1 秒一换
const CYCLE_SECONDS := 1.0

const EFFECT_NAMES := ["🔥 烈焰爆气", "⚡ 天雷灌顶", "🌪 龙卷缠身"]

## 调色盘：8 种主题色（特效与宝石共用）
const PALETTE := [
	{"name": "赤红", "color": Color(1.00, 0.22, 0.15)},
	{"name": "橙金", "color": Color(1.00, 0.55, 0.08)},
	{"name": "金黄", "color": Color(1.00, 0.84, 0.20)},
	{"name": "翠绿", "color": Color(0.25, 0.90, 0.45)},
	{"name": "青蓝", "color": Color(0.20, 0.68, 1.00)},
	{"name": "深蓝", "color": Color(0.28, 0.40, 1.00)},
	{"name": "紫色", "color": Color(0.62, 0.30, 1.00)},
	{"name": "粉红", "color": Color(1.00, 0.32, 0.72)},
]

# ------------------------------------------------------------------ 运行时状态
var level: int = 2            # 档位 1~3（↑/↓ 切换）
var effect_idx: int = 0       # 当前特效（0 烈焰 / 1 闪电 / 2 龙卷风）
var _color_idx: int = 1       # 调色盘选中下标
var _cycle_timer: float = 0.0 # 距下次切换特效的剩余时间

# ------------------------------------------------------------------ 节点引用
@onready var effect_rect: ColorRect = $EffectLayer
@onready var gems_rect: ColorRect = $GemsLayer
@onready var level_label: Label = $CanvasLayer/HUD/InfoPanel/InfoBox/LevelLabel
@onready var effect_label: Label = $CanvasLayer/HUD/InfoPanel/InfoBox/EffectLabel
@onready var cycle_label: Label = $CanvasLayer/HUD/InfoPanel/InfoBox/CycleLabel
@onready var palette_box: HBoxContainer = $CanvasLayer/HUD/PalettePanel/PaletteBox/ColorBox
@onready var hint_label: Label = $CanvasLayer/HUD/HintLabel

## 色块按钮与它们的 StyleBox（选中时描边高亮）
var _swatch_buttons: Array = []
var _swatch_styleboxes: Array = []


func _ready() -> void:
	_build_palette()
	_apply_all()


## 自动循环：按 烈焰 → 闪电 → 龙卷风 的顺序循环播放
func _process(delta: float) -> void:
	_cycle_timer += delta
	if _cycle_timer >= CYCLE_SECONDS:
		_cycle_timer = 0.0
		effect_idx = (effect_idx + 1) % EFFECT_NAMES.size()
		_apply_all()
	cycle_label.text = "%.1f 秒后切换到下一特效" % (CYCLE_SECONDS - _cycle_timer)


## ↑/↓ 切换档位
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		level = mini(3, level + 1)
		_apply_all()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		level = maxi(1, level - 1)
		_apply_all()
		get_viewport().set_input_as_handled()


# ============================================================
#  调色盘
# ============================================================
## 在左下角动态创建 8 个色块按钮；选中项用白色描边高亮
func _build_palette() -> void:
	for i in PALETTE.size():
		var b := Button.new()
		b.tooltip_text = PALETTE[i]["name"]
		b.custom_minimum_size = Vector2(34, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = PALETTE[i]["color"]
		sb.corner_radius_top_left = 7
		sb.corner_radius_top_right = 7
		sb.corner_radius_bottom_left = 7
		sb.corner_radius_bottom_right = 7
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.border_color = Color(0, 0, 0, 0)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_on_swatch_pressed.bind(i))
		palette_box.add_child(b)
		_swatch_buttons.append(b)
		_swatch_styleboxes.append(sb)


func _on_swatch_pressed(i: int) -> void:
	_color_idx = i
	_apply_all()


# ============================================================
#  统一刷新区
# ============================================================
## 把 档位 / 特效模式 / 主题色 一次性推给两个 shader 与全部 UI
func _apply_all() -> void:
	var c: Color = PALETTE[_color_idx]["color"]
	effect_rect.material.set_shader_parameter("mode", effect_idx)
	effect_rect.material.set_shader_parameter("level", level)
	effect_rect.material.set_shader_parameter("effect_color", c)
	gems_rect.material.set_shader_parameter("level", level)
	gems_rect.material.set_shader_parameter("effect_color", c)

	level_label.text = "档位：%d / 3" % level
	effect_label.text = "特效：%s" % EFFECT_NAMES[effect_idx]
	hint_label.text = "↑/↓ 切换档位 · 点击调色盘换色 · 爆气特效每 1 秒循环：烈焰 → 天雷 → 龙卷（当前：%s）" % PALETTE[_color_idx]["name"]
	for i in _swatch_styleboxes.size():
		_swatch_styleboxes[i].border_color = Color(1, 1, 1, 0.95) if i == _color_idx else Color(0, 0, 0, 0)
