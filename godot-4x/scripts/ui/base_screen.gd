## 场景基类（对应 pyconsole/core/scene.py 的场景语义 + §29 交互契约）。
##
## 每个场景 = 一个全屏 Control，实现：
##   enter_scene(params)     被压栈时调用（构建 UI、聚焦初始项）
##   exit_scene()            被弹栈时清理
##   return_scene(value)     下层场景 POP 时收到回值
##   refresh_hints()         SceneStack 调用，更新顶部提示栏
##   handle_input(event)     未处理输入路由（SceneStack._unhandled_input）
##
## 布局：场景在 build() 里用容器组合各功能图形（Frame/ListWidget/MapView 等），
## 即"多个图形通过布局组成场景"。
class_name BaseScreen
extends Control

## 底部日志栏是否绘制（§6：日志全球化——任何界面都可见）
var show_log_bar := true
## 顶部提示栏（由场景在 build 中创建并赋引用，或由本类懒建）
var hint_bar: HintBar = null
var log_bar: LogBar = null
## 场景标题（显示在提示栏左侧）
var screen_title := ""

var _built := false

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func enter_scene(params: Variant = null) -> void:
	if not _built:
		_built = true
		build()
	_refresh_all()
	on_enter(params)

## 子类覆写：构建布局。
func build() -> void:
	pass

func on_enter(params: Variant = null) -> void:
	pass

func exit_scene() -> void:
	pass

func return_scene(value: Variant = null) -> void:
	on_return(value)

func on_return(value: Variant = null) -> void:
	pass

func refresh_hints() -> void:
	if hint_bar != null:
		hint_bar.refresh(self)

## 子类覆写：返回 [(action, desc)] 提示项。
func get_hints() -> Array:
	return []

func handle_input(event: InputEvent) -> void:
	pass

## 主场景输入路由（未处理输入 → 场景 handle_input）。
func _unhandled_input(event: InputEvent) -> void:
	handle_input(event)

# ---------- 便捷 ----------
func action_pressed(action: String) -> bool:
	return event_is_action_pressed(action)

static func event_is_action_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)

## 统一刷新：提示栏 + 日志栏 + 场景自身。
func _refresh_all() -> void:
	if hint_bar != null:
		hint_bar.refresh(self)
	if log_bar != null:
		log_bar.refresh()
	refresh()

func refresh() -> void:
	pass
