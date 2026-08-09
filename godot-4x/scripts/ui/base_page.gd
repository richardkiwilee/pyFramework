## 全屏页面基类（现代 4X：小队管理/招募/科技文化等占满窗口的界面）。
##
## 与 Window 子界面的区别（反馈#2）：
## - 不是独立窗口，而是主场景内的层叠 Control —— 层级可控：
##   地图(底) → 按钮/据点层 → 全屏页面层 → 顶部状态栏(最顶，始终可见)。
## - 动态占满主场景除顶栏外的全部空间（跟随主窗口尺寸变化）。
## - 无标题栏/无关闭按钮，全部通过 ESC 关闭（或页面自管 esc_closes）。
##
## 由 GameScreen 的页面栈管理：_open_page(scene, params) / _close_page(value)；
## 关闭回值经 close_requested 信号 → 页面栈 → 新栈顶 return_page / 主场景。
class_name BasePage
extends Control

signal close_requested(value: Variant)

## 页面标题（仅记录；不显示——顶部状态栏常驻）。
var page_title := ""
## 是否 ESC 关闭页面（stronghold 例外：ESC 回退层，置 false 自管）。
var esc_closes := true

var _built := false
var _vbox: VBoxContainer
var _hint_label: Label

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	if not _built:
		_built = true
		build()

## 背景：页面自带不透明面板底（遮罩地图），保证下层不可见。
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_BG.darkened(0.42))

func _unhandled_input(event: InputEvent) -> void:
	# 页面存在期间 ESC 归页面管：先消费事件（防同一事件冒泡到主场景，
	# 造成"关闭页面后又打开主场景的 ESC 设置窗口"）
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		if esc_closes:
			close_requested.emit(null)
			return
	handle_input(event)

## 子类覆写：构建页面布局（占满全部空间，顶部状态栏在其上层）。
func build() -> void:
	pass

## 子类覆写：页面打开时（params 由打开方传入）。
func enter_page(params: Variant = null) -> void:
	pass

## 子类覆写：上层页面关闭时收到回值。
func return_page(value: Variant = null) -> void:
	pass

func exit_page() -> void:
	pass

## 便捷：在页面内创建统一的内容容器（铺满整个页面——否则内容挤在左上角）。
func make_content() -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 8)
	add_child(mc)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	mc.add_child(_vbox)
	return _vbox

## 便捷：页面底部提示行（键位说明，跟随输入绑定）。
func add_hint_label() -> void:
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", UiTheme.DIM)
	_vbox.add_child(_hint_label)

## 子类覆写：返回 [(键名, 说明)] 提示项。
func get_hints() -> Array:
	return []

func refresh_hints() -> void:
	if _hint_label == null:
		return
	var parts: Array[String] = []
	for pair in get_hints():
		parts.append("%s %s" % [pair[0], Loc.t(pair[1])])
	_hint_label.text = "  ".join(parts)

func handle_input(event: InputEvent) -> void:
	pass

func action_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)

## 页面内打开另一全屏页面（委托主场景页面栈，保证层级）。
func open_page(scene: Control, params: Variant = null) -> void:
	var main: Node = SceneStack.main_scene
	if main != null and main.has_method("_open_page"):
		main.call("_open_page", scene, params)
