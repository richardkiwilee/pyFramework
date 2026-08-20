## =====================================================================
## SubScene — 城市管理 / 部队管理这类"全新场景"的通用骨架
## =====================================================================
## 纯色背景 + 居中标题 + 右上角关闭按钮。点击关闭或按 ESC 回到主场景。
## 标题与背景色通过导出变量在各自 .tscn 里设置（见 CityScene.tscn / UnitScene.tscn）。
##
## 这是"复用脚本 + 数据驱动"的典型用法：一份脚本，多个场景各自配不同参数。
##
## ---- Python 开发者速查 ----
## @export var title: String = "子场景"
##     → 导出变量：在 Godot 编辑器的属性面板里可改，也可在 .tscn 文件里赋值。
##       相当于给脚本配一组"公开可配置参数"，类似 Python dataclass 的字段。
## grow_horizontal = GROW_DIRECTION_BEGIN
##     → 当控件右锚定（anchor_right=1）时，调整尺寸时向"起点"（左）方向生长，
##       保证按钮右上角始终贴在窗口右上。
## get_tree().change_scene_to_file(path)
##     → 切换到另一个场景文件（类似打开新页面）。注意会销毁当前场景。
## _unhandled_input(event) → 未被 GUI 消费的输入到达这里，用于 ESC 快捷键。
## =====================================================================
class_name SubScene
extends Control

@export var title: String = "子场景"                       # 场景标题（编辑器可改）
@export var bg_color: Color = Color(0.20, 0.24, 0.28)      # 背景色（编辑器可改）
@export var main_scene_path: String = "res://Main.tscn"    # 返回的主场景路径

var close_btn: Button   # 右上角关闭按钮

func _ready() -> void:
	# 全屏铺满（根节点在 .tscn 里已设 FULL_RECT 锚点）
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = bg_color
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# ---- 居中大标题 ----
	var ttl := Label.new()
	ttl.name = "Title"
	ttl.text = title
	ttl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80))
	ttl.add_theme_font_size_override("font_size", 40)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ttl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ttl.anchors_preset = Control.PRESET_FULL_RECT
	ttl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ttl)

	# ---- 右上角关闭按钮 ----
	close_btn = Button.new()
	close_btn.name = "Close"
	close_btn.text = "✕ 关闭"
	# 右锚定：按钮跟随窗口右边，窗口变宽时按钮始终贴右上。
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_bottom = 0.0
	# offset：相对锚点的像素偏移。anchor_right=1 时，offset_right=-16 表示
	# "距右边 16px"；offset_left=-136 表示按钮宽 120px。
	close_btn.offset_left = -136.0
	close_btn.offset_right = -16.0
	close_btn.offset_top = 16.0
	close_btn.offset_bottom = 52.0
	# 向左生长：尺寸变化时按钮左边缘移动，右边缘固定。
	close_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	close_btn.pressed.connect(_on_close)
	add_child(close_btn)

	# 开启全局未处理输入监听（ESC 关闭）。
	set_process_unhandled_input(true)
	pass

## 关闭：记日志并切回主场景。
func _on_close() -> void:
	GameState.add_log("返回主场景")
	get_tree().change_scene_to_file(main_scene_path)
	pass

## 全局未处理输入：按 ESC 等同于点击关闭。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
	pass
