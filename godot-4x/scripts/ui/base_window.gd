## 子窗口基类（Godot 最佳实践：每个子界面 = 独立 Window 场景）。
##
## 继承者：窗口内容在 build() 里构建（用容器组合各功能图形组件），
## 参数经 enter_window(params) 交付，关闭回值经 return_window(value) 接收。
## 键盘与鼠标输入都路由到窗口；窗口关闭（ESC/关闭按钮）自动 pop。
class_name BaseWindow
extends Window

## 窗口标题（显示在标题栏）。
var win_title: String = "":
	set(v):
		win_title = v
		title = v
## 窗口尺寸。
var win_size := Vector2i(900, 560):
	set(v):
		win_size = v
		size = v

var _built := false
var _vbox: VBoxContainer
var _hint_label: Label

## 是否 ESC 关闭窗口（stronghold 例外：ESC 回退层）。
var esc_closes := true

func _init() -> void:
	# Window 基础设置：模态窗口、可调整大小、居中打开
	exclusive = true
	unresizable = false
	wrap_controls = false
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	close_requested.connect(func(): SceneStack.close_window(null))

func _ready() -> void:
	title = win_title
	size = win_size
	if not _built:
		_built = true
		build()
	_place()
	# 输入转发：Window 视口内的未处理输入经 relay 送达 handle_input
	var relay := _InputRelay.new()
	relay.target = self
	relay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	relay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(relay)

## 输入中继：窗口视口内键盘/鼠标未处理事件 → 窗口脚本。
class _InputRelay:
	extends Control
	var target: BaseWindow = null

	func _unhandled_input(event: InputEvent) -> void:
		if target == null:
			return
		# ESC 统一关闭（子类可置 esc_closes=false 自管）
		if target.esc_closes and event.is_action_pressed("ui_cancel"):
			SceneStack.close_window(null)
			return
		target.handle_input(event)

## 子类覆写：构建窗口内容。
func build() -> void:
	pass

## 子类覆写：窗口打开时（params 由打开方传入）。
func enter_window(params: Variant = null) -> void:
	pass

## 窗口定位钩子（_ready 设完尺寸后调用）：默认居中；子类可覆写
## 弹出到右上角等位置（如日志小窗）。屏幕坐标为整个视口。
func _place() -> void:
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN

## 便捷：把窗口挪到主窗口右上角（右上角留 16px 边距；独立调试时退回居中）。
func place_top_right() -> void:
	var ws: Vector2i = DisplayServer.window_get_size()
	if ws == Vector2i.ZERO:
		return
	position = Vector2i(maxi(0, ws.x - size.x - 16), 16)

## 子类覆写：上层窗口关闭时收到回值。
func return_window(value: Variant = null) -> void:
	pass

func exit_window() -> void:
	pass

## 便捷：在窗口内创建统一的内容容器（铺满窗口，否则内容挤在左上角）。
func make_content() -> VBoxContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left", 10)
	mc.add_theme_constant_override("margin_right", 10)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 6)
	add_child(mc)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	mc.add_child(_vbox)
	return _vbox

## 便捷：窗口底部提示行（键位说明，跟随输入绑定）。
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

## 键盘输入路由（子类覆写 handle_input）。
func _unhandled_input(event: InputEvent) -> void:
	handle_input(event)

func handle_input(event: InputEvent) -> void:
	pass

func action_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)
